"""
E2E Test: Adaptif Rutin Sistemi
================================
Testler:
1. ingredient_db modül yüklemesi ve veri bütünlüğü
2. Risk skoru hesaplama
3. Flow engine + risk ayarlama entegrasyonu
4. Günlük check-in adaptasyonu (deterministik)
5. Senaryo eşleştirme
"""

import sys
import json

passed = 0
failed = 0
total = 0


def test(name, condition, detail=""):
    global passed, failed, total
    total += 1
    if condition:
        passed += 1
        print(f"  ✅ {name}")
    else:
        failed += 1
        print(f"  ❌ {name} — {detail}")


print("=" * 60)
print("REBI Adaptif Rutin Sistemi — E2E Test")
print("=" * 60)

# ═══ TEST 1: ingredient_db modül yüklemesi ═══
print("\n📦 TEST 1: ingredient_db modül yüklemesi")
try:
    from ingredient_db import (
        INGREDIENT_DB, SCENARIO_PROTOCOLS, compute_risk_score,
        get_ingredient, get_concentration, get_risk_adjustment,
        get_daily_trigger_action, get_skin_type_adjustment,
        match_best_scenario, build_ingredient_context_for_ai,
    )
    test("Modül import başarılı", True)
    test("INGREDIENT_DB yüklendi", len(INGREDIENT_DB) >= 10, f"Beklenen >=10, bulunan {len(INGREDIENT_DB)}")
    test("SCENARIO_PROTOCOLS yüklendi", len(SCENARIO_PROTOCOLS) >= 5, f"Beklenen >=5, bulunan {len(SCENARIO_PROTOCOLS)}")

    retinol = get_ingredient("retinol")
    test("Retinol verisi var", bool(retinol))
    test("Retinol evidence_level doğru", retinol.get("evidence_level") == "Level 1b")
    test("Retinol pregnancy_safe=False", retinol.get("pregnancy_safe") == False)
    test("Retinol photosensitive=True", retinol.get("photosensitive") == True)

    conc = get_concentration("retinol", "acne_hafif")
    test("Retinol acne_hafif konsantrasyon var", bool(conc))
    test("Retinol acne_hafif pct doğru", "Adapalen" in conc.get("pct", ""), f"pct={conc.get('pct')}")

    vc = get_ingredient("vitamin_c")
    test("Vitamin C var", bool(vc))
    test("Vitamin C sabah uygulaması", vc.get("application_time") == "Sabah")

    centella = get_ingredient("centella_panthenol")
    test("Centella akşam uygulaması", "Akşam" in centella.get("application_time", ""))
    test("Centella fotosensitif=True", centella.get("photosensitive") == True)

    spf = get_ingredient("mineral_spf")
    test("SPF kesinlikle kesilmez", spf.get("risk_adjustments", {}).get("crisis", {}).get("freq_multiplier") == 1.0)

except Exception as e:
    test("ingredient_db yükleme", False, str(e))

# ═══ TEST 2: Risk skoru hesaplama ═══
print("\n🎯 TEST 2: Risk skoru hesaplama")
try:
    r1 = compute_risk_score(stress=2, water_intake=2.5, humidity=55, sleep_hours=8)
    test("Düşük risk skoru", r1["level"] == "normal", f"level={r1['level']}, score={r1['score']}")

    r2 = compute_risk_score(stress=7, water_intake=1.2, humidity=35, sleep_hours=5.5)
    test("Yüksek risk skoru", r2["level"] in ("high", "crisis"), f"level={r2['level']}, score={r2['score']}")

    r3 = compute_risk_score(stress=10, water_intake=0.5, humidity=20, sleep_hours=4)
    test("Kriz modu", r3["level"] == "crisis", f"level={r3['level']}, score={r3['score']}")
    test("Kriz skor >=13", r3["score"] >= 13, f"score={r3['score']}")

    r4 = compute_risk_score(stress=4, water_intake=2.0, humidity=55, sleep_hours=7)
    test("Orta risk", r4["level"] in ("moderate", "normal"), f"level={r4['level']}, score={r4['score']}")
except Exception as e:
    test("Risk skoru hesaplama", False, str(e))

# ═══ TEST 3: Risk bazlı doz ayarlama ═══
print("\n💊 TEST 3: Risk bazlı doz ayarlama")
try:
    adj_normal = get_risk_adjustment("retinol", "normal")
    test("Retinol normal: mult=1.0", adj_normal.get("freq_multiplier") == 1.0)

    adj_high = get_risk_adjustment("retinol", "high")
    test("Retinol yüksek risk: mult=0.5", adj_high.get("freq_multiplier") == 0.5)

    adj_crisis = get_risk_adjustment("retinol", "crisis")
    test("Retinol kriz: mult=0 (ara ver)", adj_crisis.get("freq_multiplier") == 0.0)

    adj_nia = get_risk_adjustment("niacinamid", "crisis")
    test("Niasinamid kriz: mult=1.0 (kesilmez)", adj_nia.get("freq_multiplier") == 1.0)

    adj_spf = get_risk_adjustment("mineral_spf", "crisis")
    test("SPF kriz: mult=1.0 (kesilmez)", adj_spf.get("freq_multiplier") == 1.0)
except Exception as e:
    test("Risk doz ayarlama", False, str(e))

# ═══ TEST 4: Günlük tetikleyiciler ═══
print("\n🔔 TEST 4: Günlük tetikleyiciler (daily triggers)")
try:
    t1 = get_daily_trigger_action("retinol", "irritasyon")
    test("Retinol irritasyon: pause", t1.get("action") == "pause")

    t2 = get_daily_trigger_action("niacinamid", "irritasyon")
    test("Niasinamid irritasyon: maintain", t2.get("action") == "maintain")

    t3 = get_daily_trigger_action("hyaluronik_asit", "kuru")
    test("HA kuru: increase", t3.get("action") == "increase")

    t4 = get_daily_trigger_action("seramidler", "kirik")
    test("Seramid kırık: increase", t4.get("action") == "increase")
except Exception as e:
    test("Günlük tetikleyiciler", False, str(e))

# ═══ TEST 5: Cilt tipi ayarlaması ═══
print("\n🧴 TEST 5: Cilt tipi ayarlaması")
try:
    st1 = get_skin_type_adjustment("retinol", "sensitive")
    test("Retinol hassas cilt: mult=0.5", st1.get("freq_multiplier") == 0.5)

    st2 = get_skin_type_adjustment("seramidler", "dry")
    test("Seramid kuru cilt: mult=1.5", st2.get("freq_multiplier") == 1.5)

    st3 = get_skin_type_adjustment("hidrokinon", "sensitive")
    test("Hidrokinon hassas: KULLANMA (mult=0)", st3.get("freq_multiplier") == 0.0)
except Exception as e:
    test("Cilt tipi ayarlama", False, str(e))

# ═══ TEST 6: Senaryo eşleştirme ═══
print("\n🎬 TEST 6: Senaryo eşleştirme")
try:
    s1 = match_best_scenario(concern="acne", skin_type="oily", stress_level="medium", hydration="normal")
    test("Akne senaryosu eşleşti", bool(s1))
    test("Akne senaryosu label var", "label" in s1)

    s2 = match_best_scenario(concern="sensitivity", skin_type="sensitive", stress_level="high", hydration="low")
    test("Sensitivite senaryosu", bool(s2))
    test("Sensitivite: rosacea eşleşti", "rosacea" in s2.get("key", "").lower() or "sensitivite" in s2.get("key", "").lower(),
         f"key={s2.get('key')}")

    s3 = match_best_scenario(concern="pigmentation", skin_type="normal", stress_level="medium", hydration="normal")
    test("Pigmentasyon senaryosu", bool(s3))
except Exception as e:
    test("Senaryo eşleştirme", False, str(e))

# ═══ TEST 7: Flow Engine entegrasyonu ═══
print("\n⚙️ TEST 7: Flow Engine + INGREDIENT_DB entegrasyonu")
try:
    from flow_engine import run_flow, adapt_existing_routine

    result = run_flow(
        concern="acne",
        severity_score=6,
        age=28,
        gender="female",
        skin_type_key="oily",
        stress_score=8,
        sleep_hours=6,
        water_intake=1.5,
        smoking=False,
        alcohol=False,
        uv_index=5,
        humidity=45,
        temperature=22,
    )

    test("run_flow başarılı", bool(result))
    test("routine_items var", len(result.get("routine_items", [])) > 0, f"items={len(result.get('routine_items', []))}")
    test("risk_info dönüyor", "risk_info" in result)
    test("risk_info level var", "level" in result.get("risk_info", {}))

    risk_level = result["risk_info"]["level"]
    test("Risk seviyesi hesaplandı", risk_level in ("normal", "moderate", "high", "crisis"), f"level={risk_level}")

    items = result["routine_items"]
    has_morning = any(i["time"] == "Sabah" for i in items)
    has_evening = any(i["time"] == "Akşam" for i in items)
    test("Sabah rutini var", has_morning)
    test("Akşam rutini var", has_evening)

except Exception as e:
    test("Flow engine entegrasyonu", False, str(e))
    import traceback
    traceback.print_exc()

# ═══ TEST 8: adapt_existing_routine ═══
print("\n🔄 TEST 8: adapt_existing_routine (deterministik adaptasyon)")
try:
    mock_routine = [
        {"time": "Sabah", "category": "Bakım", "icon": "🎯", "action": "Salisilik Asit (%2) Tonik", "detail": "BHA tonik", "priority": 2},
        {"time": "Akşam", "category": "Bakım", "icon": "🔬", "action": "Retinol (%0.3) Serum", "detail": "Retinol serum", "priority": 2},
        {"time": "Sabah", "category": "Bakım", "icon": "✨", "action": "Niasinamid (%5) Serum", "detail": "Niasinamid", "priority": 2},
    ]

    risk_normal = compute_risk_score(stress=3, water_intake=2.5, humidity=50, sleep_hours=8)
    adapt_normal = adapt_existing_routine(mock_routine, {"skin_feeling": "iyi"}, risk_normal)
    test("Normal adaptasyon: minor", adapt_normal["adaptation_type"] == "minor")
    test("Normal: az değişiklik", len(adapt_normal["changes"]) <= 1)

    risk_irritasyon = compute_risk_score(stress=8, water_intake=1.0, humidity=30, sleep_hours=5)
    adapt_irr = adapt_existing_routine(mock_routine, {"skin_feeling": "irritasyon"}, risk_irritasyon)
    test("İrritasyon adaptasyonu var", len(adapt_irr["changes"]) > 0, f"changes={len(adapt_irr['changes'])}")

    retinol_change = [c for c in adapt_irr["changes"] if "retinol" in c["item"].lower()]
    test("Retinol irritasyonda değişti", len(retinol_change) > 0)

    nia_change = [c for c in adapt_irr["changes"] if "niasinamid" in c["item"].lower()]
    test("Niasinamid irritasyonda devam", len(nia_change) == 0 or
         all("maintain" in str(c) for c in nia_change))

except Exception as e:
    test("adapt_existing_routine", False, str(e))
    import traceback
    traceback.print_exc()

# ═══ TEST 9: AI context builder ═══
print("\n📝 TEST 9: AI context builder")
try:
    ctx = build_ingredient_context_for_ai(["retinol", "vitamin_c", "niacinamid"])
    test("Context text oluşturuldu", len(ctx) > 50, f"len={len(ctx)}")
    test("Retinol bilgisi içeriyor", "Retinoid" in ctx)
    test("Vitamin C bilgisi içeriyor", "Vitamin C" in ctx)
    test("Niasinamid bilgisi içeriyor", "Niasinamid" in ctx or "Vitamin B3" in ctx)
except Exception as e:
    test("AI context builder", False, str(e))


# ═══ SONUÇ ═══
print("\n" + "=" * 60)
print(f"SONUÇ: {passed}/{total} test başarılı", end="")
if failed > 0:
    print(f" — {failed} BAŞARISIZ")
else:
    print(" — TÜM TESTLER GEÇTİ ✅")
print("=" * 60)

sys.exit(0 if failed == 0 else 1)
