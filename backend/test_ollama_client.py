import os
import time
import unittest
from unittest.mock import patch

import httpx

from ollama_client import OllamaClient


class _Response:
    status_code = 200
    text = ""

    def json(self):
        return {"response": "orchestrator | Evidence-bound result"}


class OllamaClientPolicyTests(unittest.TestCase):
    def client(self):
        with patch.dict(os.environ, {"OLLAMA_NUM_THREADS": ""}):
            client = OllamaClient()
        client._available = True
        client._installed_models = [client.model]
        return client

    def test_default_request_lets_ollama_choose_threads(self):
        client = self.client()
        with patch("ollama_client.httpx.post", return_value=_Response()) as post:
            self.assertIsNotNone(client.generate("/no_think\ntest", max_tokens=20))
        payload = post.call_args.kwargs["json"]
        self.assertFalse(payload["think"])
        self.assertEqual(payload["options"]["num_ctx"], 2048)
        self.assertNotIn("num_thread", payload["options"])

    def test_interactive_timeout_does_not_block_reasoning(self):
        client = self.client()
        with patch(
            "ollama_client.httpx.post",
            side_effect=httpx.TimeoutException("interactive timeout"),
        ):
            self.assertIsNone(client.generate(
                "test", wait_for_slot=False, timeout_s=5,
            ))
        self.assertEqual(client.last_generation_status, "timeout")
        self.assertLessEqual(client._cooldown_until, time.monotonic())

    def test_heavy_timeout_opens_only_brief_cooldown(self):
        client = self.client()
        with patch(
            "ollama_client.httpx.post",
            side_effect=httpx.TimeoutException("reasoning timeout"),
        ):
            self.assertIsNone(client.generate(
                "test", wait_for_slot=True, timeout_s=5,
            ))
        remaining = client._cooldown_until - time.monotonic()
        self.assertGreater(remaining, 14)
        self.assertLessEqual(remaining, 15)


if __name__ == "__main__":
    unittest.main()
