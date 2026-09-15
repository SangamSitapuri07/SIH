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
from typing import Optional

import httpx

logger = logging.getLogger("orca.ollama")

_DEFAULT_HOST = "http://localhost:11434"
_DEFAULT_MODEL = "qwen3:8b"
_DEFAULT_TIMEOUT = 120.0  # includes first-run model loading on CPU-only devices
_MIN_TIMEOUT = 120.0

class OllamaClient:
    """
    Lightweight synchronous wrapper around the Ollama /api/generate endpoint.
    Uses httpx for sync HTTP — safe to call from FastAPI route handlers
    (agents run in a thread pool, not the async event loop).
    """

    def __init__(self):
        self.host = os.getenv("OLLAMA_HOST", _DEFAULT_HOST).rstrip("/")
        self.model = os.getenv("OLLAMA_MODEL", _DEFAULT_MODEL).strip()
        configured_timeout = float(os.getenv("OLLAMA_TIMEOUT_S", str(_DEFAULT_TIMEOUT)))
        # Older ORCA .env files used 25s. That is shorter than a Qwen3:8b cold
        # start on CPU and caused a false "not connected" result.
        self.timeout = max(_MIN_TIMEOUT, configured_timeout)
        self._available: Optional[bool] = None  # lazily determined
        self._installed_models: list[str] = []

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
                "stop": ["</analysis>", "---END---"],
            },
        }
        if json_mode:
            payload["format"] = "json"
        if system:
            payload["system"] = system

        try:
            t0 = time.monotonic()
            resp = httpx.post(
                f"{self.host}/api/generate",
                json=payload,
                timeout=self.timeout,
            )
            elapsed_ms = int((time.monotonic() - t0) * 1000)

            if resp.status_code != 200:
                logger.error(f"[Ollama] HTTP {resp.status_code}: {resp.text[:200]}")
                return None

            data = resp.json()
            response_text = data.get("response", "").strip()
            logger.info(f"[Ollama] {self.model} responded in {elapsed_ms} ms ({len(response_text)} chars)")
            return response_text if response_text else None

        except httpx.TimeoutException:
            logger.warning(
                "[Ollama] Generation timed out after %.1fs at %s. The server is reachable; "
                "use a smaller OLLAMA_MODEL or raise OLLAMA_TIMEOUT_S.",
                self.timeout,
                self.host,
            )
            # A generation timeout does not mean the Ollama server disconnected.
            # Keep reachability true so a later warm-model request can succeed.
            return None
        except Exception as e:
            logger.error(f"[Ollama] Unexpected error: {e}")
            return None

    def health(self) -> dict:
        """Return Ollama health info for the /api/v1/health endpoint."""
        available = self.is_available()
        info: dict = {
            "available": available,
            "host": self.host,
            "model": self.model,
            "timeout_s": self.timeout,
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
