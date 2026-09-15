#!/usr/bin/env python3
"""
SSL/TLS Diagnostic Tool
Ye script aapke computer pe run karo aur mujhe output bhejo.
Isse pata chalega ki exact kya problem hai.
"""

import sys
import ssl
import socket
import httpx
import requests
import urllib3
from urllib.parse import urlparse

print("="*80)
print("SSL/TLS DIAGNOSTIC TOOL")
print("="*80)

# 1. Python Version
print("\n1. Python Version")
print("-"*80)
print(f"Python: {sys.version}")
print(f"OpenSSL: {ssl.OPENSSL_VERSION}")

# 2. SSL Context Test
print("\n2. SSL Context Configuration")
print("-"*80)
ctx = ssl.create_default_context()
print(f"Protocol: {ctx.protocol}")
print(f"Verify Mode: {ctx.verify_mode}")
print(f"Check Hostname: {ctx.check_hostname}")
print(f"Minimum TLS Version: {ctx.minimum_version}")
print(f"Maximum TLS Version: {ctx.maximum_version}")

# 3. DNS Resolution Test
print("\n3. DNS Resolution Test")
print("-"*80)
hosts = [
    "marine-api.open-meteo.com",
    "api.open-meteo.com",
    "google.com"
]

for host in hosts:
    try:
        ip = socket.gethostbyname(host)
        print(f"✅ {host} -> {ip}")
    except socket.gaierror as e:
        print(f"❌ {host} -> DNS FAILED: {e}")

# 4. Direct Socket Connection Test
print("\n4. Direct Socket Connection (Port 443)")
print("-"*80)
for host in ["marine-api.open-meteo.com", "api.open-meteo.com"]:
    try:
        sock = socket.create_connection((host, 443), timeout=10)
        print(f"✅ TCP Connection to {host}:443 SUCCESS")
        
        # Try SSL wrap
        try:
            context = ssl.create_default_context()
            ssock = context.wrap_socket(sock, server_hostname=host)
            print(f"✅ SSL Handshake SUCCESS")
            print(f"   Protocol: {ssock.version()}")
            print(f"   Cipher: {ssock.cipher()}")
            ssock.close()
        except ssl.SSLError as e:
            print(f"❌ SSL Handshake FAILED: {e}")
        finally:
            sock.close()
            
    except socket.error as e:
        print(f"❌ TCP Connection FAILED: {e}")

# 5. Test with httpx (different configurations)
print("\n5. Testing with httpx (Different Configurations)")
print("-"*80)

url = "https://marine-api.open-meteo.com/v1/marine"
params = {
    "latitude": 20.9,
    "longitude": 70.37,
    "current": "wave_height",
    "timezone": "UTC"
}

# Test 5a: Default
print("\n5a. Default configuration:")
try:
    with httpx.Client(timeout=30.0) as client:
        response = client.get(url, params=params)
        print(f"   ✅ SUCCESS: HTTP {response.status_code}")
except Exception as e:
    print(f"   ❌ FAILED: {type(e).__name__}: {e}")

# Test 5b: With verify=False (skip SSL verification)
print("\n5b. With verify=False (skip SSL check):")
try:
    with httpx.Client(timeout=30.0, verify=False) as client:
        response = client.get(url, params=params)
        print(f"   ✅ SUCCESS: HTTP {response.status_code}")
        if response.status_code == 200:
            data = response.json()
            print(f"   Wave height: {data.get('current', {}).get('wave_height')}")
except Exception as e:
    print(f"   ❌ FAILED: {type(e).__name__}: {e}")

# Test 5c: With custom SSL context
print("\n5c. With custom SSL context (TLS 1.2):")
try:
    ctx = ssl.create_default_context()
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    with httpx.Client(timeout=30.0, verify=ctx) as client:
        response = client.get(url, params=params)
        print(f"   ✅ SUCCESS: HTTP {response.status_code}")
except Exception as e:
    print(f"   ❌ FAILED: {type(e).__name__}: {e}")

# 6. Test with requests library
print("\n6. Testing with requests library")
print("-"*80)
try:
    response = requests.get(url, params=params, timeout=30)
    print(f"✅ SUCCESS: HTTP {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        print(f"   Wave height: {data.get('current', {}).get('wave_height')}")
except Exception as e:
    print(f"❌ FAILED: {type(e).__name__}: {e}")

# 7. Test with verify=False in requests
print("\n7. Testing with requests (verify=False)")
print("-"*80)
try:
    urllib3.disable_warnings()
    response = requests.get(url, params=params, timeout=30, verify=False)
    print(f"✅ SUCCESS: HTTP {response.status_code}")
    if response.status_code == 200:
        data = response.json()
        print(f"   Wave height: {data.get('current', {}).get('wave_height')}")
        print(f"\n🎉 API IS ACCESSIBLE! SSL verification is the issue.")
except Exception as e:
    print(f"❌ FAILED: {type(e).__name__}: {e}")

# 8. Check for proxy
print("\n8. Proxy Configuration")
print("-"*80)
import os
proxy_vars = ['HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy', 'NO_PROXY']
for var in proxy_vars:
    value = os.environ.get(var)
    if value:
        print(f"{var} = {value}")
    else:
        print(f"{var} = (not set)")

# 9. Summary
print("\n" + "="*80)
print("DIAGNOSTIC COMPLETE")
print("="*80)
print("\nPlease share this output so I can identify the exact issue.")
print("\nCommon findings:")
print("  - If test 5b/7 works but 5a fails -> SSL certificate issue")
print("  - If all tests fail -> Network/firewall issue")
print("  - If DNS fails -> DNS configuration issue")
print("  - If TCP fails -> Firewall blocking port 443")
