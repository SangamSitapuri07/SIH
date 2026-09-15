#!/usr/bin/env python3
"""
ORCA Backend - Real Data Test Script
Run this on your local computer to test with REAL data from Open-Meteo APIs.
"""

import httpx
import json
import time

BASE_URL = "http://localhost:8000"

def test_endpoint(name, url, params=None):
    """Test a single endpoint and show results."""
    print(f"\n{'='*80}")
    print(f"Testing: {name}")
    print(f"URL: {url}")
    if params:
        print(f"Params: {params}")
    print('='*80)
    
    try:
        with httpx.Client(timeout=30.0) as client:
            start = time.time()
            response = client.get(url, params=params)
            elapsed = round((time.time() - start) * 1000)
            
            print(f"✅ HTTP Status: {response.status_code}")
            print(f"⏱️  Response Time: {elapsed}ms")
            
            data = response.json()
            
            # Check if it's an error response
            if data.get("error"):
                print(f"❌ ERROR in response:")
                print(f"   Reason: {data.get('reason')}")
                if data.get('suggestion'):
                    print(f"   Suggestion: {data.get('suggestion')}")
                return False
            else:
                print(f"✅ SUCCESS - Got real data!")
                
                # Show key data points
                if "verdict" in data:
                    print(f"   Verdict: {data.get('verdict')}")
                if "headline" in data:
                    print(f"   Headline: {data.get('headline')}")
                if "variables" in data:
                    vars = data.get("variables", {})
                    if "wave_height_m" in vars:
                        print(f"   Wave Height: {vars['wave_height_m'].get('value')}m")
                    if "wind_speed_kn" in vars:
                        print(f"   Wind Speed: {vars['wind_speed_kn'].get('value')}kn")
                    if "sst_celsius" in vars:
                        print(f"   Sea Temperature: {vars['sst_celsius'].get('value')}°C")
                if "agents" in data:
                    print(f"   Agents: {len(data.get('agents', []))}")
                if "sources" in data:
                    print(f"   Data Sources: {len(data.get('sources', []))}")
                
                return True
                
    except httpx.ConnectError:
        print("❌ CONNECTION ERROR: Cannot connect to backend")
        print("   Make sure the server is running: python -m uvicorn main:app --port 8000")
        return False
    except Exception as e:
        print(f"❌ ERROR: {type(e).__name__}: {e}")
        return False

def main():
    print("\n" + "="*80)
    print("ORCA BACKEND - REAL DATA TEST")
    print("="*80)
    print("\nThis script tests the ORCA backend with REAL data from Open-Meteo APIs.")
    print("Make sure you have internet connection and the server is running.\n")
    
    # First check if server is running
    print("Checking if server is running...")
    try:
        with httpx.Client(timeout=5.0) as client:
            response = client.get(f"{BASE_URL}/")
            if response.status_code == 200:
                print("✅ Server is running!\n")
            else:
                print(f"❌ Server returned status {response.status_code}")
                return
    except:
        print("❌ Server is not running!")
        print("   Start it with: python -m uvicorn main:app --port 8000")
        return
    
    # Test key endpoints
    results = []
    
    # 1. Health check
    results.append(("Health Check", test_endpoint(
        "Health Check",
        f"{BASE_URL}/api/v1/health"
    )))
    
    # 2. Zone snapshot (basic)
    results.append(("Zone Snapshot", test_endpoint(
        "Zone Snapshot (Veraval Offshore)",
        f"{BASE_URL}/api/v1/zone",
        params={"lat": 20.9, "lon": 70.37}
    )))
    
    # 3. Advisory (main endpoint)
    results.append(("Advisory", test_endpoint(
        "Safety Advisory",
        f"{BASE_URL}/api/v1/advisory",
        params={"lat": 20.9, "lon": 70.37}
    )))
    
    # 4. Reasoning
    results.append(("Reasoning", test_endpoint(
        "11-Agent Reasoning",
        f"{BASE_URL}/api/v1/reason",
        params={"lat": 20.9, "lon": 70.37}
    )))
    
    # 5. Grid
    results.append(("Grid", test_endpoint(
        "4x4 Grid Data",
        f"{BASE_URL}/api/v1/grid",
        params={"lat": 20.9, "lon": 70.37}
    )))
    
    # 6. PFZ
    results.append(("PFZ", test_endpoint(
        "Potential Fishing Zones",
        f"{BASE_URL}/api/v1/pfz"
    )))
    
    # 7. Route check
    results.append(("Route Check", test_endpoint(
        "Route Safety Check",
        f"{BASE_URL}/api/v1/route-check",
        params={"from_lat": 20.9, "from_lon": 70.37, "to_lat": 20.5, "to_lon": 70.0}
    )))
    
    # Summary
    print("\n" + "="*80)
    print("TEST SUMMARY")
    print("="*80)
    
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"{status} - {name}")
    
    print(f"\nTotal: {passed}/{total} tests passed")
    
    if passed == total:
        print("\n🎉 ALL TESTS PASSED! Backend is working perfectly with real data!")
        print("\nYou can now use the ORCA app or access the API at:")
        print(f"  - API Docs: {BASE_URL}/docs")
        print(f"  - Advisory: {BASE_URL}/api/v1/advisory?lat=20.9&lon=70.37")
        print(f"  - Reasoning: {BASE_URL}/api/v1/reason?lat=20.9&lon=70.37")
    else:
        print("\n⚠️  Some tests failed. Check the error messages above.")
        print("\nCommon issues:")
        print("  1. No internet connection")
        print("  2. Open-Meteo APIs are temporarily down")
        print("  3. Firewall blocking HTTPS connections")
        print("\nTry again in a few minutes or check your network connection.")

if __name__ == "__main__":
    main()
