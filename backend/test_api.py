"""
REBI API Test Scripti
=====================
Backend API endpoint'lerini test eder.

Kullanım:
    cd backend
    source venv/bin/activate
    python test_api.py
"""

import requests
import json
import sys
from datetime import datetime

BASE_URL = "http://localhost:8000"

def test_health():
    """Health endpoint testi"""
    print("\n🔍 Health Check Testi...")
    try:
        resp = requests.get(f"{BASE_URL}/health", timeout=5)
        if resp.status_code == 200:
            data = resp.json()
            print(f"   ✅ Status: {data.get('status')}")
            print(f"   ✅ Supabase: {data.get('supabase')}")
            print(f"   ✅ Concerns: {data.get('concerns')}")
            return True
        else:
            print(f"   ❌ Status code: {resp.status_code}")
            return False
    except requests.exceptions.ConnectionError:
        print(f"   ❌ Backend çalışmıyor! Önce 'uvicorn main:app' çalıştırın.")
        return False
    except Exception as e:
        print(f"   ❌ Hata: {e}")
        return False

def test_generate_routine():
    """Rutin üretme endpoint testi"""
    print("\n🔍 Generate Routine Testi...")
    
    test_data = {
        "user_id": "test-user-123",
        "full_name": "Test User",
        "age": 25,
        "gender": "female",
        "concern": "acne",
        "skin_type": "oily",
        "severity_score": 7,
        "water_intake": 2.0,
        "sleep_hours": 7.0,
        "stress_score": 5,
        "smoking": False,
        "alcohol": False,
        "location_lat": 41.0082,  # İstanbul
        "location_lon": 28.9784,
    }
    
    try:
        resp = requests.post(
            f"{BASE_URL}/generate_routine",
            json=test_data,
            timeout=30
        )
        
        if resp.status_code == 200:
            data = resp.json()
            routine = data.get("routine", [])
            print(f"   ✅ Rutin üretildi: {len(routine)} öğe")
            print(f"   ✅ Assessment ID: {data.get('assessment_id')}")
            print(f"   ✅ Weather: {data.get('weather', {}).get('description', 'N/A')}")
            print(f"   ✅ Insights: {len(data.get('holistic_insights', []))} adet")
            return True
        else:
            print(f"   ❌ Status code: {resp.status_code}")
            print(f"   ❌ Response: {resp.text[:200]}")
            return False
    except Exception as e:
        print(f"   ❌ Hata: {e}")
        return False

def test_chat():
    """Chat endpoint testi"""
    print("\n🔍 Chat Testi...")
    
    test_data = {
        "user_id": "test-user-123",
        "message": "Akne için hangi ürünleri kullanmalıyım?",
        "concern": "acne"
    }
    
    try:
        resp = requests.post(
            f"{BASE_URL}/chat",
            json=test_data,
            timeout=30
        )
        
        if resp.status_code == 200:
            data = resp.json()
            reply = data.get("reply", "")
            sources = data.get("sources", [])
            print(f"   ✅ Cevap alındı: {len(reply)} karakter")
            print(f"   ✅ Kaynaklar: {len(sources)} adet")
            print(f"   📝 Cevap önizleme: {reply[:100]}...")
            return True
        else:
            print(f"   ❌ Status code: {resp.status_code}")
            print(f"   ❌ Response: {resp.text[:200]}")
            return False
    except Exception as e:
        print(f"   ❌ Hata: {e}")
        return False

def main():
    print("=" * 60)
    print("REBI API Test Suite")
    print("=" * 60)
    print(f"Base URL: {BASE_URL}")
    print(f"Tarih: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    
    results = []
    
    # Test 1: Health check
    results.append(("Health Check", test_health()))
    
    # Test 2: Generate routine (sadece health check başarılıysa)
    if results[0][1]:
        results.append(("Generate Routine", test_generate_routine()))
        results.append(("Chat", test_chat()))
    else:
        print("\n⚠️  Backend çalışmıyor, diğer testler atlandı.")
        print("   Önce backend'i başlatın: cd backend && uvicorn main:app")
    
    # Özet
    print("\n" + "=" * 60)
    print("Test Özeti")
    print("=" * 60)
    passed = sum(1 for _, result in results if result)
    total = len(results)
    
    for name, result in results:
        status = "✅ PASS" if result else "❌ FAIL"
        print(f"   {status} - {name}")
    
    print(f"\nToplam: {passed}/{total} test başarılı")
    
    if passed == total:
        print("\n🎉 Tüm testler başarılı!")
        sys.exit(0)
    else:
        print("\n⚠️  Bazı testler başarısız oldu.")
        sys.exit(1)

if __name__ == "__main__":
    main()
