"""
ORCA Box — Ollama Local LLM Client
====================================
Thin HTTP client for the locally-running Ollama server (default: http://localhost:11434).

Architecture note:
  • Flutter APK  →  ORCA Box FastAPI  →  Ollama (Qwen3:8b)
  Flutter is completely unaware of Ollama.

Design rules:
  1. NEVER block the safety verdict path — if Ollama is unreachable or slow,
     the LLM/Analytical agents fall back to deterministic analysis immediately.
  2. Marine Risk Agent (Agent 10) is ALWAYS deterministic; Ollama NEVER touches safety thresholds.
  3. All prompts are structured and bounded — no open-ended generation.
  4. One bounded request may include model cold-start time. The timeout is
     configurable via OLLAMA_TIMEOUT_S (default/minimum 120 s).
"""

import os
import json
import logging
import time
import threading
from typing import Optional

import httpx

logger = logging.getLogger("orca.ollama")

_DEFAULT_HOST = "http://localhost:11434"
_DEFAULT_MODEL = "qwen3:8b"
_DEFAULT_TIMEOUT = 120.0  # includes first-run model loading on CPU-only devices
_MIN_TIMEOUT = 120.0
_INTEGRATION_VERSION = "batched-v2"

class OllamaClient:
    """
    Lightweight synchronous wrapper around the Ollama /api/generate endpoint.
    Uses httpx for sync HTTP — safe to call from FastAPI route handlers
    (agents run in a thread pool, not the async event loop).
    """

    def __init__(self):
        self.host = os.getenv("OLLAMA_HOST", _DEFAULT_HOST).rstrip("/")
        self.model = os.getenv("OLLAMA_MODEL", _DEFAULT_MODEL).strip()
        try:
            configured_timeout = float(os.getenv("OLLAMA_TIMEOUT_S", str(_DEFAULT_TIMEOUT)))
        except (TypeError, ValueError):
            configured_timeout = _DEFAULT_TIMEOUT
        # Older ORCA .env files used 25s. That is shorter than a Qwen3:8b cold
        # start on CPU and caused a false "not connected" result.
        self.configured_timeout = configured_timeout
        self.timeout = max(_MIN_TIMEOUT, configured_timeout)
        self._available: Optional[bool] = None  # lazily determined
        self._installed_models: list[str] = []
        # Keep capacity for FastAPI routing/weather while local inference runs.
        # Operators can override this for GPU-backed or dedicated Ollama hosts.
        default_threads = max(1, (os.cpu_count() or 4) - 2)
        try:
            self.num_threads = max(1, int(os.getenv("OLLAMA_NUM_THREADS", str(default_threads))))
        except (TypeError, ValueError):
            self.num_threads = default_threads
        # Ollama generally executes one heavyweight local model efficiently at
        # a time. Serialize generation even when advisory, reasoning and the
        # ingestion daemon arrive together.
        self._generation_lock = threading.Lock()
        self._cooldown_until = 0.0
        self._last_generation: dict = {"status": "not_attempted"}
        if configured_timeout < _MIN_TIMEOUT:
            logger.warning(
                "[Ollama] Ignoring legacy OLLAMA_TIMEOUT_S=%.1f; effective timeout is %.1fs.",
                configured_timeout,
                self.timeout,
            )

    def is_available(self) -> bool:
        """Check whether Ollama is reachable. Cached after first successful probe."""
        if self._available is True:
            return True
        try:
            resp = httpx.get(f"{self.host}/api/tags", timeout=5.0)
            self._available = resp.status_code == 200
            if self._available:
                payload = resp.json()
                self._installed_models = [
                    str(item.get("name"))
                    for item in payload.get("models", [])
                    if item.get("name")
                ]
        except Exception:
            self._available = False
            self._installed_models = []
        return self._available

    def generate(
        self,
        prompt: str,
        system: Optional[str] = None,
        temperature: float = 0.3,
        max_tokens: int = 512,
        json_mode: bool = False,
        json_schema: Optional[dict] = None,
    ) -> Optional[str]:
        """
        Call Ollama /api/generate (non-streaming).

        Returns the model's response text, or None if unavailable / timed out.
        Callers MUST handle None and fall back to deterministic logic.
        """
        if not self.is_available():
            logger.warning("[Ollama] Server not reachable at %s — using deterministic fallback.", self.host)
            return None
        if self._installed_models and self.model not in self._installed_models:
            logger.error(
                "[Ollama] Model '%s' is not installed. Available models: %s. Run: ollama pull %s",
                self.model,
                ", ".join(self._installed_models),
                self.model,
            )
            return None

        payload: dict = {
            "model": self.model,
            "prompt": prompt,
            "stream": False,
            # Qwen3 thinking mode exceeds the 25s CPU timeout on this hardware
            # and caused every analytical agent to fall back. Disable thinking
            # so bounded interpretations complete inside OLLAMA_TIMEOUT_S.
            "think": False,
            "keep_alive": "30m",
            "options": {
                "temperature": temperature,
                "num_predict": max_tokens,
                "num_thread": self.num_threads,
                "stop": ["</analysis>", "---END---"],
            },
        }
        if json_schema is not None:
            # Ollama accepts a JSON Schema as `format`; constrained decoding is
            # substantially more reliable than merely asking an 8B model for
            # JSON in prose.
            payload["format"] = json_schema
        elif json_mode:
            payload["format"] = "json"
        if system:
            payload["system"] = system

        now = time.monotonic()
        if now < self._cooldown_until:
            remaining = int(self._cooldown_until - now)
            logger.info(
                "[Ollama] Generation cooldown active for %ss — using deterministic fallback.",
                remaining,
            )
            return None

        # Re-check cooldown after acquiring the lock: another request may have
        # timed out while this request was waiting.
        with self._generation_lock:
            now = time.monotonic()
            if now < self._cooldown_until:
                return None
            try:
                t0 = time.monotonic()
                resp = httpx.post(
                    f"{self.host}/api/generate",
                    json=payload,
                    timeout=self.timeout,
                )
                elapsed_ms = int((time.monotonic() - t0) * 1000)

                if resp.status_code != 200:
                    self._last_generation = {
                        "status": "http_error",
                        "http_status": resp.status_code,
                        "duration_ms": elapsed_ms,
                    }
                    logger.error("[Ollama] HTTP %s: %s", resp.status_code, resp.text[:200])
                    return None

                data = resp.json()
                response_text = data.get("response", "").strip()
                self._last_generation = {
                    "status": "success" if response_text else "empty_response",
                    "duration_ms": elapsed_ms,
                    "response_chars": len(response_text),
                }
                logger.info(
                    "[Ollama] %s responded in %s ms (%s chars)",
                    self.model,
                    elapsed_ms,
                    len(response_text),
                )
                return response_text if response_text else None

            except httpx.TimeoutException:
                # Do not let several queued requests each consume a full cold-
                # start timeout. One timeout opens a short circuit-breaker;
                # deterministic safety output remains immediately available.
                self._cooldown_until = time.monotonic() + 60.0
                self._last_generation = {
                    "status": "timeout",
                    "timeout_s": self.timeout,
                    "cooldown_s": 60,
                }
                logger.warning(
                    "[Ollama] Generation timed out after %.1fs at %s. The server is reachable; "
                    "use a smaller OLLAMA_MODEL or raise OLLAMA_TIMEOUT_S. A 60s cooldown is active.",
                    self.timeout,
                    self.host,
                )
                # A generation timeout does not mean the server disconnected.
                return None
            except Exception as e:
                self._last_generation = {"status": "error", "detail": str(e)}
                logger.exception("[Ollama] Unexpected generation error")
                return None

    def log_configuration(self) -> None:
        """Emit an unmistakable startup signature for stale-server diagnosis."""
        available = self.is_available()
        logger.warning(
            "[Ollama] ORCA integration %s | mode=single-batched | host=%s | "
            "model=%s | timeout=%.1fs | reachable=%s | installed=%s",
            _INTEGRATION_VERSION,
            self.host,
            self.model,
            self.timeout,
            available,
            ", ".join(self._installed_models) or "none",
        )

    def health(self) -> dict:
        """Return Ollama health info for the /api/v1/health endpoint."""
        available = self.is_available()
        info: dict = {
            "available": available,
            "host": self.host,
            "model": self.model,
            "integration_version": _INTEGRATION_VERSION,
            "inference_mode": "single_batched_request",
            "configured_timeout_s": self.configured_timeout,
            "effective_timeout_s": self.timeout,
            "generation_serialized": True,
            "num_threads": self.num_threads,
            "cooldown_remaining_s": max(0, int(self._cooldown_until - time.monotonic())),
            "last_generation": dict(self._last_generation),
        }
        if available:
            try:
                resp = httpx.get(f"{self.host}/api/tags", timeout=3.0)
                tags_data = resp.json()
                models = [m.get("name") for m in tags_data.get("models", [])]
                info["installed_models"] = models
                info["target_model_present"] = self.model in models
            except Exception:
                info["installed_models"] = []
                info["target_model_present"] = False
        return info


# Module-level singleton — instantiated once at server startup.
ollama = OllamaClient()
