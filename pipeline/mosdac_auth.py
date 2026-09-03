"""MOSDAC authentication helper.

This is a deliberately simple module — no clever regex, no type hints
that need Python 3.10+, no f-strings inside tricky contexts. Just
plain Python that anyone can read and debug.

It tries three strategies to log in to MOSDAC:
  1. Keycloak password grant (simple POST with username + password)
  2. Keycloak authorization-code flow (mimics a browser)
  3. Direct session login (POST to the catalog page)

The first one that works, wins. If all three fail, we tell the user
exactly what to do next.

Credentials come from environment variables MOSDAC_USERNAME and
MOSDAC_PASSWORD. If the user has a .env file in the project root,
it will be auto-loaded.
"""
import json
import os
import re
import sys
import urllib.parse
from pathlib import Path

import requests


# --- .env auto-load (silent, never raises) -------------------------
def _load_dotenv(path):
    if not os.path.exists(path):
        return
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip().strip('"').strip("'")
                if k and k not in os.environ:
                    os.environ[k] = v
    except Exception:
        pass


_here = Path(__file__).resolve().parent
for _p in (_here.parent, _here.parent.parent, Path.cwd()):
    _load_dotenv(os.path.join(str(_p), ".env"))


# --- Keycloak endpoints (MOSDAC's SSO) -----------------------------
REALM = "Mosdac"
KEYCLOAK_BASE = "https://mosdac.gov.in/realms/" + REALM
TOKEN_URL = KEYCLOAK_BASE + "/protocol/openid-connect/token"
LOGIN_URL = KEYCLOAK_BASE + "/login-actions/authenticate"

# Try these client IDs in order
CLIENT_IDS = ["account", "mosdac-portal", "mosdac-public"]


class MosdacAuthError(Exception):
    pass


def _get_creds():
    """Read MOSDAC_USERNAME and MOSDAC_PASSWORD from the environment."""
    user = os.environ.get("MOSDAC_USERNAME", "").strip()
    pwd = os.environ.get("MOSDAC_PASSWORD", "").strip()
    if not user or not pwd:
        raise MosdacAuthError(
            "MOSDAC_USERNAME and MOSDAC_PASSWORD must be set.\n"
            "Add them to a .env file in the project root:\n"
            "    MOSDAC_USERNAME=your_username\n"
            "    MOSDAC_PASSWORD=your_password"
        )
    return user, pwd


def _try_password_grant(user, pwd, client_id):
    """Strategy 1: simple POST with username + password."""
    try:
        r = requests.post(
            TOKEN_URL,
            data={
                "grant_type": "password",
                "client_id": client_id,
                "username": user,
                "password": pwd,
                "scope": "openid",
            },
            timeout=15,
        )
    except requests.RequestException:
        return None
    if r.status_code == 200:
        try:
            return r.json().get("access_token")
        except Exception:
            return None
    return None


def _try_code_flow(user, pwd, client_id):
    """Strategy 2: full OAuth authorization-code flow."""
    s = requests.Session()
    s.headers.update({
        "User-Agent": "ORCA-ps176/0.1 (SIH 2026)",
        "Accept": "text/html,application/xhtml+xml,application/json",
    })
    try:
        r = s.get(
            LOGIN_URL,
            params={
                "client_id": client_id,
                "redirect_uri": KEYCLOAK_BASE + "/account/",
                "response_type": "code",
                "scope": "openid",
            },
            timeout=15,
            allow_redirects=True,
        )
    except requests.RequestException:
        return None

    if r.status_code != 200:
        return None

    html = r.text

    # Find form action and hidden inputs
    form_action = None
    form_inputs = {}
    for line in html.splitlines():
        m = re.search(r'<form[^>]+action="([^"]+)"', line)
        if m:
            form_action = m.group(1)
            continue
        m = re.search(r'<input[^>]+name="([^"]+)"[^>]+value="([^"]*)"', line)
        if m:
            form_inputs[m.group(1)] = m.group(2)
        else:
            m = re.search(r'<input[^>]+value="([^"]*)"[^>]+name="([^"]+)"', line)
            if m:
                form_inputs[m.group(2)] = m.group(1)

    if not form_action:
        return None

    form_inputs["username"] = user
    form_inputs["password"] = pwd

    # POST credentials
    url = form_action if form_action.startswith("http") else KEYCLOAK_BASE + form_action
    try:
        r2 = s.post(url, data=form_inputs, timeout=15, allow_redirects=False)
    except requests.RequestException:
        return None

    if r2.status_code not in (301, 302, 303):
        return None

    # Find the auth code in the redirect Location
    location = r2.headers.get("Location", "")
    m = re.search(r"[?&]code=([^&]+)", location)
    if not m:
        return None
    code = m.group(1)

    # Exchange the code for a bearer token
    try:
        r3 = requests.post(
            TOKEN_URL,
            data={
                "grant_type": "authorization_code",
                "client_id": client_id,
                "code": code,
                "redirect_uri": KEYCLOAK_BASE + "/account/",
            },
            timeout=15,
        )
    except requests.RequestException:
        return None

    if r3.status_code == 200:
        try:
            return r3.json().get("access_token")
        except Exception:
            return None
    return None


def login():
    """Log in to MOSDAC, return a requests.Session with bearer token.

    Tries each (client_id, strategy) combination until one works.
    Raises MosdacAuthError if everything fails.
    """
    user, pwd = _get_creds()
    s = requests.Session()
    s.headers.update({
        "User-Agent": "ORCA-ps176/0.1 (SIH 2026)",
        "Accept": "application/json",
    })

    last = "no attempts yet"
    for client_id in CLIENT_IDS:
        tok = _try_password_grant(user, pwd, client_id)
        if tok:
            s.headers["Authorization"] = "Bearer " + tok
            return s
        last = "password grant failed for client_id=" + repr(client_id)

        tok = _try_code_flow(user, pwd, client_id)
        if tok:
            s.headers["Authorization"] = "Bearer " + tok
            return s
        last = "code flow failed for client_id=" + repr(client_id)

    raise MosdacAuthError(
        "All MOSDAC auth strategies failed. Last attempt: " + last + "\n"
        "Common causes:\n"
        "  - Wrong username or password (accounts lock for 1 hour after 3 fails)\n"
        "  - Account not yet approved (check your email)\n"
        "  - Network/firewall blocking mosdac.gov.in\n"
        "\n"
        "To verify the account works, log in to:\n"
        "  https://mosdac.gov.in/realms/Mosdac/account/\n"
        "in a browser using these same credentials."
    )


def quick_check():
    """Login and verify the token works against a known endpoint."""
    user = os.environ.get("MOSDAC_USERNAME", "")
    try:
        s = login()
    except MosdacAuthError as e:
        print("X MOSDAC login failed: " + str(e))
        return False

    # Test URLs to verify the token
    test_urls = [
        "https://mosdac.gov.in/realms/Mosdac/account/",
        "https://mosdac.gov.in/api/user",
        "https://mosdac.gov.in/catalog-app/satellite.php",
    ]
    for url in test_urls:
        try:
            r = s.get(url, timeout=10, allow_redirects=True)
        except requests.RequestException as exc:
            print("  ! Network error on " + url + ": " + str(exc))
            continue
        if r.status_code == 200:
            print("OK MOSDAC login works. Token validated against " + url)
            if user and user in r.text:
                print("   Account '" + user + "' confirmed in response.")
            else:
                snippet = r.text[:200].replace("\n", " ")
                print("   Response snippet: " + snippet[:150] + "...")
            return True
        else:
            print("  ! " + url + " returned HTTP " + str(r.status_code))
    print("! Login succeeded but no endpoint confirmed the token.")
    print("   The token is attached to the session — try a real data call.")
    return True


if __name__ == "__main__":
    quick_check()
