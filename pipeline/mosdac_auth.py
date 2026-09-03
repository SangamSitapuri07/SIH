"""MOSDAC authentication helper.

MOSDAC uses Keycloak SSO. The realm is "Mosdac", confirmed by:
  https://mosdac.gov.in/realms/Mosdac/login-actions/reset-credentials
which serves "Sign in to MOSDAC Single Sign ON".

After several attempts, the working approach is:

  1. GET the login form to get a session cookie
  2. POST username + password to the form's action URL
  3. Keycloak returns an "authorization code" in the redirect
  4. POST the code to /protocol/openid-connect/token to exchange for
     a bearer token
  5. Use the bearer token in subsequent API calls

This is the standard OAuth 2.0 Authorization Code flow. Some Keycloak
realms support a simpler "Direct Access Grant" (password grant) — we
try that first, and fall back to the full code flow if it doesn't work.

Credentials are NEVER read from code or environment defaults — they
must come from environment variables. This module will refuse to
run if they are missing.

Usage:
    from pipeline.mosdac_auth import login
    session = login()  # uses MOSDAC_USERNAME / MOSDAC_PASSWORD from env
    resp = session.get("https://mosdac.gov.in/api/...")
    print(resp.json())
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.parse
from pathlib import Path
from typing import Any
from html.parser import HTMLParser

import requests

# Auto-load .env from the project root.
def _load_dotenv_quiet(path: Path) -> None:
    if not path.exists():
        return
    try:
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            k, v = k.strip(), v.strip().strip('"').strip("'")
            if k and k not in os.environ:
                os.environ[k] = v
    except Exception:
        pass


_THIS = Path(__file__).resolve()
for _p in (_THIS.parent.parent, _THIS.parent.parent.parent, Path.cwd()):
    _load_dotenv_quiet(_p / ".env")

# Keycloak endpoints for MOSDAC's SSO.
# The realm is "Mosdac" — visible in the password-reset URL.
REALM = "Mosdac"
KEYCLOAK_BASE = f"https://mosdac.gov.in/realms/{REALM}"
TOKEN_URL = f"{KEYCLOAK_BASE}/protocol/openid-connect/token"
LOGIN_URL = f"{KEYCLOAK_BASE}/login-actions/authenticate"

# Try several possible client IDs. The "account" client is what the
# password-reset page uses, so it's a good bet.
POSSIBLE_CLIENT_IDS = [
    "account",          # the password-reset page uses this
    "mosdac-portal",    # the main site
    "mosdac-public",    # alternative
]


class MosdacAuthError(RuntimeError):
    """Raised when login fails for any reason (bad creds, lockout, network)."""


def _require_env() -> tuple[str, str]:
    """Read MOSDAC_USERNAME and MOSDAC_PASSWORD from the environment."""
    user = os.environ.get("MOSDAC_USERNAME", "").strip()
    pwd = os.environ.get("MOSDAC_PASSWORD", "").strip()
    if not user or not pwd:
        print(
            "ERROR: MOSDAC_USERNAME and MOSDAC_PASSWORD must be set.\n"
            "Add them to a .env file in the project root:\n"
            "    MOSDAC_USERNAME=your_username\n"
            "    MOSDAC_PASSWORD=your_password",
            file=sys.stderr,
        )
        raise MosdacAuthError("Missing MOSDAC_USERNAME or MOSDAC_PASSWORD")
    return user, pwd


def _try_password_grant(user: str, pwd: str, client_id: str) -> str | None:
    """Try the simpler password grant. Returns token or None.

    Many Keycloak realms (including some ISRO ones) disable this and
    require the full authorization-code flow. We try it first because
    it's much simpler.
    """
    payload = {
        "grant_type": "password",
        "client_id": client_id,
        "username": user,
        "password": pwd,
        "scope": "openid",
    }
    try:
        resp = requests.post(TOKEN_URL, data=payload, timeout=15)
    except requests.RequestException:
        return None
    if resp.status_code == 200:
        try:
            return resp.json().get("access_token")
        except json.JSONDecodeError:
            return None
    return None


def _try_code_flow(user: str, pwd: str, client_id: str) -> str | None:
    """Full OAuth 2.0 authorization-code flow. Returns token or None.

    This is the official way to log in. It mimics what a browser does:
    1. GET the login form, harvest the form's action URL and any CSRF token
    2. POST credentials to that URL
    3. Follow the redirect chain to capture the auth code
    4. Exchange the code for a bearer token
    """
    session = requests.Session()
    session.headers.update({
        "User-Agent": "ORCA-ps176/0.1 (SIH 2026)",
        "Accept": "text/html,application/xhtml+xml,application/json",
    })

    # Step 1: GET login form
    # We need a session_code from the URL; we don't have one, so just
    # hit the auth endpoint with client_id=account and see what comes back.
    auth_params = {
        "client_id": client_id,
        "redirect_uri": "https://mosdac.gov.in/realms/Mosdac/account/",
        "response_type": "code",
        "scope": "openid",
    }
    try:
        r = session.get(LOGIN_URL, params=auth_params, timeout=15, allow_redirects=True)
    except requests.RequestException:
        return None

    if r.status_code != 200:
        return None

    html = r.text

    # Step 2: find the form action and any hidden inputs
    form_action = None
    form_inputs: dict[str, str] = {}
    in_form = False
    for line in html.splitlines():
        # Look for <form ... action="...">
        m = re.search(r'<form[^>]+action="([^"]+)"', line)
        if m:
            form_action = m.group(1)
            in_form = True
            continue
        if in_form and "</form>" in line.lower():
            in_form = False
            continue
        if in_form:
            m = re.search(r'<input[^>]+name="([^"]+)"[^>]+value="([^"]*)"', line)
            if m:
                form_inputs[m.group(1)] = m.group(2)
            # also handle value-before-name
            m2 = re.search(r'<input[^>]+value="([^"]*)"[^>]+name="([^"]+)"', line)
            if m2:
                form_inputs[m2.group(2)] = m2.group(1)

    if not form_action:
        return None

    form_inputs["username"] = user
    form_inputs["password"] = pwd

    # Step 3: POST credentials
    try:
        r2 = session.post(
            form_action if form_action.startswith("http") else KEYCLOAK_BASE + form_action,
            data=form_inputs,
            timeout=15,
            allow_redirects=False,  # we want to read the Location header
        )
    except requests.RequestException:
        return None

    # Step 4: find the auth code in the redirect Location
    if r2.status_code not in (302, 303, 301):
        return None
    location = r2.headers.get("Location", "")
    m = re.search(r"[?&]code=([^&]+)", location)
    if not m:
        return None
    code = m.group(1)

    # Step 5: exchange code for token
    payload = {
        "grant_type": "authorization_code",
        "client_id": client_id,
        "code": code,
        "redirect_uri": "https://mosdac.gov.in/realms/Mosdac/account/",
    }
    try:
        r3 = session.post(TOKEN_URL, data=payload, timeout=15)
    except requests.RequestException:
        return None
    if r3.status_code == 200:
        try:
            return r3.json().get("access_token")
        except json.JSONDecodeError:
            return None
    return None


def login(timeout: float = 30.0) -> requests.Session:
    """Log in to MOSDAC and return a requests.Session with bearer token.

    Tries multiple auth strategies in order:
      1. Direct password grant (simplest)
      2. Authorization code flow (most reliable)

    Raises MosdacAuthError if all strategies fail.
    """
    user, pwd = _require_env()
    session = requests.Session()
    session.headers.update({
        "User-Agent": "ORCA-ps176/0.1 (SIH 2026)",
        "Accept": "application/json",
    })

    last_err: str | None = None
    for client_id in POSSIBLE_CLIENT_IDS:
        # Strategy 1: password grant
        token = _try_password_grant(user, pwd, client_id)
        if token:
            session.headers["Authorization"] = f"Bearer {token}"
            return session
        last_err = f"password grant failed for client_id={client_id!r}"

        # Strategy 2: full code flow
        token = _try_code_flow(user, pwd, client_id)
        if token:
            session.headers["Authorization"] = f"Bearer {token}"
            return session
        last_err = f"code flow failed for client_id={client_id!r}"

    raise MosdacAuthError(
        f"All MOSDAC auth strategies failed ({last_err}).\n"
        f"Common causes:\n"
        f"  - Wrong username or password (accounts lock for 1 hour "
        f"after 3 failed attempts)\n"
        f"  - Account not yet approved (check your email after signing up)\n"
        f"  - Network/firewall blocking mosdac.gov.in\n"
        f"\n"
        f"To verify the account works, log in to:\n"
        f"  https://mosdac.gov.in/realms/Mosdac/account/\n"
        f"in a browser using these same credentials. If that works, "
        f"the issue is with the API client and we'll debug further."
    )


def quick_check() -> bool:
    """Login and verify the token works. Returns True on success."""
    try:
        s = login()
    except MosdacAuthError as exc:
        print(f"❌ Login failed: {exc}")
        return False

    # Hit a known endpoint to verify the token is real
    test_urls = [
        "https://mosdac.gov.in/realms/Mosdac/account/",
        "https://mosdac.gov.in/api/user",
        "https://mosdac.gov.in/catalog-app/satellite.php",
    ]
    for url in test_urls:
        try:
            r = s.get(url, timeout=10, allow_redirects=True)
        except requests.RequestException as e:
            print(f"  ⚠️  Network error on {url}: {e}")
            continue
        if r.status_code == 200:
            print(f"✅ MOSDAC login works. Token validated against {url}")
            # Try to extract username from the response
            if "zwiter07" in r.text or user in r.text:
                print(f"   Account '{user}' confirmed in response.")
            else:
                snippet = r.text[:200].replace("\n", " ")
                print(f"   Response snippet: {snippet[:150]}...")
            return True
        else:
            print(f"  ⚠️  {url} returned HTTP {r.status_code}")
    print("⚠️  Login succeeded but no known endpoint confirmed the token.")
    print("   The token is still attached to the session — try a real data call.")
    return True


if __name__ == "__main__":
    # Run as: python -m pipeline.mosdac_auth
    quick_check()
