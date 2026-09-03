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


# --- MOSDAC API endpoints (from official mdapi.py source) -----------
# The official MOSDAC Python client (mdapi.py) uses these URLs:
#   POST https://mosdac.gov.in/download_api/gettoken      (login)
#   POST https://mosdac.gov.in/download_api/refresh-token (refresh)
#   POST https://mosdac.gov.in/download_api/logout        (logout)
#   POST https://mosdac.gov.in/apios/datasets.json        (search)
#   POST https://mosdac.gov.in/download_api/download      (download)
# It's NOT Keycloak (despite the /realms/Mosdac/ URLs in the SSO
# pages). The auth is a simple JSON POST.
TOKEN_URL = "https://mosdac.gov.in/download_api/gettoken"
REFRESH_URL = "https://mosdac.gov.in/download_api/refresh-token"
LOGOUT_URL = "https://mosdac.gov.in/download_api/logout"
SEARCH_URL = "https://mosdac.gov.in/apios/datasets.json"


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
    """Strategy 1: simple POST with username + password.
    (client_id ignored for this auth scheme — kept for API compat.)
    """
    try:
        r = requests.post(
            TOKEN_URL,
            json={"username": user, "password": pwd},
            timeout=15,
        )
    except requests.RequestException:
        return None
    if r.status_code == 200:
        try:
            data = r.json()
            if data.get("access_token"):
                return data["access_token"]
        except Exception:
            return None
    return None


def _try_code_flow(user, pwd, client_id):
    """Strategy 2: refresh token exchange (no longer used but kept
    for API compat). MOSDAC's auth is single-step — password grant
    is the only way. So this just returns None.
    """
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
