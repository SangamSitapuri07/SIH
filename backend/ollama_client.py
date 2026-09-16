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
     configurable via OLLAMA_TIMEOUT_S (default 75 s, minimum 15 s).
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
_DEFAULT_TIMEOUT = 75.0  # CPU-only Qwen3:8b commonly needs about 45 seconds
_MIN_TIMEOUT = 15.0
_INTEGRATION_VERSION = "role-lines-v5-cpu-bounded"

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
        # Keep operator configuration but enforce a small floor so transient
        # model loading is not misreported as immediate disconnection.
        self.configured_timeout = configured_timeout
        self.timeout = max(_MIN_TIMEOUT, configured_timeout)
        self._available: Optional[bool] = None  # lazily determined
        self._installed_models: list[str] = []
        # Ollama already chooses a hardware-appropriate physical-core count.
        # Forcing os.cpu_count()-1 is harmful in containers and on SMT hosts:
        # it can report dozens of logical CPUs and severely oversubscribe the
        # model. Only override Ollama when an operator explicitly requests it.
        configured_threads = os.getenv("OLLAMA_NUM_THREADS", "").strip()
        try:
            self.num_threads = max(1, int(configured_threads)) if configured_threads else None
        except (TypeError, ValueError):
            logger.warning("[Ollama] Ignoring invalid OLLAMA_NUM_THREADS=%r", configured_threads)
            self.num_threads = None
        self._thread_state = threading.local()
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

    def _record_generation(self, detail: dict) -> None:
        """Record status globally for health and per caller for attribution.

        Chat may probe the non-blocking lock while a reasoning call is active.
        Thread-local attribution prevents that BUSY probe from overwriting the
        reasoning caller's eventual SUCCESS/TIMEOUT state.
        """
        value = dict(detail)
        self._last_generation = value
        self._thread_state.last_generation = value

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
        wait_for_slot: bool = True,
        timeout_s: Optional[float] = None,
    ) -> Optional[str]:
        """
        Call Ollama /api/generate (non-streaming).

        Returns the model's response text, or None if unavailable / timed out.
        Callers MUST handle None and fall back to deterministic logic.
        """
        if not self.is_available():
            self._record_generation({"status": "unreachable"})
            logger.warning("[Ollama] Server not reachable at %s — using deterministic fallback.", self.host)
            return None
        if self._installed_models and self.model not in self._installed_models:
            self._record_generation({"status": "model_missing", "model": self.model})
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
                "num_ctx": 2048,
            },
        }
        if self.num_threads is not None:
            payload["options"]["num_thread"] = self.num_threads
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
            self._record_generation({"status": "cooldown", "remaining_s": remaining})
            logger.info(
                "[Ollama] Generation cooldown active for %ss — using deterministic fallback.",
                remaining,
            )
            return None

        # Interactive chat must not queue behind a long specialist reasoning
        # pass. Callers can request a non-blocking slot and immediately use
        # deterministic evidence when Ollama is busy.
        acquired = self._generation_lock.acquire(blocking=wait_for_slot)
        if not acquired:
            self._record_generation({"status": "busy"})
            return None
        try:
            now = time.monotonic()
            if now < self._cooldown_until:
                self._record_generation({
                    "status": "cooldown",
                    "remaining_s": int(self._cooldown_until - now),
                })
                return None
            try:
                t0 = time.monotonic()
                effective_timeout = self.timeout if timeout_s is None else max(5.0, timeout_s)
                resp = httpx.post(
                    f"{self.host}/api/generate",
                    json=payload,
                    timeout=effective_timeout,
                )
                elapsed_ms = int((time.monotonic() - t0) * 1000)

                if resp.status_code != 200:
                    self._record_generation({
                        "status": "http_error",
                        "http_status": resp.status_code,
                        "duration_ms": elapsed_ms,
                    })
                    logger.error("[Ollama] HTTP %s: %s", resp.status_code, resp.text[:200])
                    return None

                data = resp.json()
                response_text = data.get("response", "").strip()
                self._record_generation({
                    "status": "success" if response_text else "empty_response",
                    "duration_ms": elapsed_ms,
                    "response_chars": len(response_text),
                })
                logger.info(
                    "[Ollama] %s responded in %s ms (%s chars)",
                    self.model,
                    elapsed_ms,
                    len(response_text),
                )
                return response_text if response_text else None

            except httpx.TimeoutException:
                # A short interactive chat timeout must never poison the next
                # explicit reasoning pass. Only a queued/heavy reasoning call
                # opens a brief breaker; non-blocking chat remains independent.
                cooldown_s = 15 if wait_for_slot else 0
                if cooldown_s:
                    self._cooldown_until = time.monotonic() + cooldown_s
                self._record_generation({
                    "status": "timeout",
                    "timeout_s": effective_timeout,
                    "cooldown_s": cooldown_s,
                })
                logger.warning(
                    "[Ollama] Generation timed out after %.1fs at %s. The server is reachable; "
                    "use a smaller OLLAMA_MODEL or raise the caller timeout. Cooldown=%ss.",
                    effective_timeout,
                    self.host,
                    cooldown_s,
                )
                # A generation timeout does not mean the server disconnected.
                return None
            except Exception as e:
                self._record_generation({"status": "error", "detail": str(e)})
                logger.exception("[Ollama] Unexpected generation error")
                return None
        finally:
            self._generation_lock.release()

    @property
    def last_generation_status(self) -> str:
        detail = getattr(self._thread_state, "last_generation", self._last_generation)
        return str(detail.get("status", "unknown"))

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
