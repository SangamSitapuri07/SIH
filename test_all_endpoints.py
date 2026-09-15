#!/usr/bin/env python3
"""
Comprehensive API endpoint tester for ORCA Backend.
Tests all endpoints and reports status, response time, and errors.
"""

import requests
import time
import json
from typing import Dict, Any

BASE_URL = "http://localhost:8000"
TIMEOUT = 30  # seconds

def test_endpoint(method: str, path: str, params: Dict = None, json_data: Dict = None, description: str = "") -> Dict[str, Any]:
    """Test a single endpoint and return results."""
    url = f"{BASE_URL}{path}"
    result = {
        "path": path,
        "method": method,
        "description": description,
        "status": None,
        "status_code": None,
        "response_time_ms": None,
        "error": None,
        "response_preview": None
    }
    
    try:
        start = time.time()
        if method == "GET":
            response = requests.get(url, params=params, timeout=TIMEOUT)
        elif method == "POST":
            response = requests.post(url, json=json_data, timeout=TIMEOUT)
        else:
            result["error"] = f"Unsupported method: {method}"
            return result
        
        elapsed_ms = int((time.time() - start) * 1000)
        result["status_code"] = response.status_code
        result["response_time_ms"] = elapsed_ms
        
        if response.status_code == 200:
            result["status"] = "✅ OK"
            try:
                data = response.json()
                # Preview first 200 chars of JSON
                result["response_preview"] = json.dumps(data, indent=2)[:200] + "..."
            except:
                result["response_preview"] = response.text[:200]
        else:
            result["status"] = f"❌ HTTP {response.status_code}"
            result["error"] = response.text[:300]
            
    except requests.exceptions.Timeout:
        result["status"] = "⏱️ TIMEOUT"
        result["error"] = f"Request timed out after {TIMEOUT}s"
    except requests.exceptions.ConnectionError as e:
        result["status"] = "🔌 CONNECTION ERROR"
        result["error"] = str(e)[:200]
    except Exception as e:
        result["status"] = "💥 ERROR"
        result["error"] = f"{type(e).__name__}: {str(e)[:200]}"
    
    return result

def print_result(result: Dict[str, Any]):
    """Print formatted test result."""
    print(f"\n{'='*80}")
    print(f"{result['method']:6s} {result['path']}")
    if result['description']:
        print(f"  {result['description']}")
    print(f"  Status: {result['status']}")
    if result['status_code']:
        print(f"  HTTP Code: {result['status_code']}")
    if result['response_time_ms']:
        print(f"  Response Time: {result['response_time_ms']}ms")
    if result['error']:
        print(f"  Error: {result['error']}")
    if result['response_preview'] and result['status'] == "✅ OK":
        print(f"  Preview: {result['response_preview'][:150]}...")

def main():
    print("\n" + "="*80)
    print("ORCA BACKEND API ENDPOINT TEST SUITE")
    print("="*80)
    
    results = []
    
    # 1. Root endpoint
    results.append(test_endpoint("GET", "/", description="Server root"))
    
    # 2. Health check
    results.append(test_endpoint("GET", "/api/v1/health", description="System health and data sources"))
    
    # 3. Zone snapshot (primary endpoint)
    results.append(test_endpoint("GET", "/api/v1/zone", 
                                params={"lat": 20.9, "lon": 70.37},
                                description="Zone snapshot (Veraval offshore)"))
    
    # 4. Zone snapshot with GFW
    results.append(test_endpoint("GET", "/api/v1/zone",
                                params={"lat": 20.9, "lon": 70.37, "include_gfw": True},
                                description="Zone snapshot with GFW data"))
    
    # 5. Grid endpoint (16 concurrent fetches)
    results.append(test_endpoint("GET", "/api/v1/grid",
                                params={"lat": 20.9, "lon": 70.37, "span": 0.5},
                                description="4x4 grid for map rendering"))
    
    # 6. PFZ (Potential Fishing Zones)
    results.append(test_endpoint("GET", "/api/v1/pfz",
                                description="INCOIS official fishing zones"))
    
    # 7. Layers catalog
    results.append(test_endpoint("GET", "/api/v1/layers",
                                description="Map layer catalog"))
    
    # 8. Reasoning (11-agent analysis)
    results.append(test_endpoint("GET", "/api/v1/reason",
                                params={"lat": 20.9, "lon": 70.37},
                                description="Multi-agent reasoning trace"))
    
    # 9. Advisory (primary safety verdict)
    results.append(test_endpoint("GET", "/api/v1/advisory",
                                params={"lat": 20.9, "lon": 70.37},
                                description="Primary safety advisory"))
    
    # 10. Route check
    results.append(test_endpoint("GET", "/api/v1/route-check",
                                params={"from_lat": 20.9, "from_lon": 70.37, 
                                       "to_lat": 20.75, "to_lon": 70.2},
                                description="Route verification against land mask"))
    
    # 11. Route advisory
    results.append(test_endpoint("GET", "/api/v1/route-advisory",
                                params={"from_lat": 20.9, "from_lon": 70.37,
                                       "to_lat": 20.75, "to_lon": 70.2},
                                description="Transit verdict along route"))
    
    # 12. Alerts
    results.append(test_endpoint("GET", "/api/v1/alerts",
                                description="IMD/GDACS/JTWC warnings"))
    
    # 13. Agents list
    results.append(test_endpoint("GET", "/api/v1/agents",
                                description="11-agent registry"))
    
    # 14. Ingestion status
    results.append(test_endpoint("GET", "/api/v1/ingestion/status",
                                description="Daemon watchlist and verdicts"))
    
    # 15. Recent events
    results.append(test_endpoint("GET", "/api/v1/events/recent",
                                params={"limit": 5},
                                description="Recent SSE events"))
    
    # 16. Profile GET
    results.append(test_endpoint("GET", "/api/v1/profile",
                                params={"user_id": "demo-fisher-01"},
                                description="Get user profile"))
    
    # 17. Profile POST
    results.append(test_endpoint("POST", "/api/v1/profile",
                                json_data={"display_name": "Test User", "preferred_language": "hi"},
                                description="Update user profile"))
    
    # 18. Saved locations GET
    results.append(test_endpoint("GET", "/api/v1/locations",
                                description="Get saved fishing locations"))
    
    # 19. Saved locations POST
    results.append(test_endpoint("POST", "/api/v1/locations",
                                json_data={"name": "Test Spot", "latitude": 20.5, "longitude": 70.0},
                                description="Create saved location"))
    
    # 20. Advisory history
    results.append(test_endpoint("GET", "/api/v1/history",
                                description="Advisory history log"))
    
    # 21. Catch reports GET
    results.append(test_endpoint("GET", "/api/v1/catch-reports",
                                description="Get catch reports"))
    
    # 22. Catch reports POST
    results.append(test_endpoint("POST", "/api/v1/catch-reports",
                                json_data={"location_name": "Test Area", "latitude": 20.5, 
                                          "longitude": 70.0, "species": "Mackerel", 
                                          "quantity_kg": 15.5},
                                description="Submit catch report"))
    
    # 23. Feedback POST
    results.append(test_endpoint("POST", "/api/v1/feedback",
                                json_data={"rating": 5, "comment": "Accurate advisory"},
                                description="Submit skipper feedback"))
    
    # 24. Sync POST
    results.append(test_endpoint("POST", "/api/v1/sync",
                                json_data={"operations": [{"type": "CREATE", "entity": "test"}]},
                                description="Offline outbox sync"))
    
    # 25. Voice TTS
    results.append(test_endpoint("POST", "/api/v1/voice/tts",
                                json_data={"advisory_id": "test", "lang": "en"},
                                description="Text-to-speech generation"))
    
    # 26. Official overview
    results.append(test_endpoint("GET", "/api/v1/official/overview",
                                description="Fisheries dashboard telemetry"))
    
    # 27. Test alert (demo endpoint)
    results.append(test_endpoint("POST", "/api/v1/ingestion/test-alert",
                                description="Push test alert (demo)"))
    
    # Print all results
    for result in results:
        print_result(result)
    
    # Summary
    print("\n" + "="*80)
    print("TEST SUMMARY")
    print("="*80)
    total = len(results)
    ok = sum(1 for r in results if r['status'] == "✅ OK")
    failed = total - ok
    
    print(f"Total endpoints tested: {total}")
    print(f"✅ Passed: {ok} ({100*ok/total:.1f}%)")
    print(f"❌ Failed: {failed} ({100*failed/total:.1f}%)")
    
    if failed > 0:
        print("\n❌ FAILED ENDPOINTS:")
        for r in results:
            if r['status'] != "✅ OK":
                print(f"  - {r['method']:6s} {r['path']}")
                print(f"    Status: {r['status']}")
                if r['error']:
                    print(f"    Error: {r['error'][:150]}")
    
    print("\n" + "="*80)

if __name__ == "__main__":
    main()
