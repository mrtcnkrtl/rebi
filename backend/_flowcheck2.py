import config, json
from flow_engine import run_flow
from knowledge.cabinet_router import chain_actives_for_concern, tag_items_with_canonical_ids

BASE = dict(severity_score=6, age=32, gender="female", stress_score=5, sleep_hours=7.0,
            water_intake=2.0, smoking=False, alcohol=False, uv_index=6.0, humidity=45.0,
            temperature=24.0, makeup_frequency=2, makeup_removal="cleanser")

print("=== KANONIK ZINCIR vs MOTORUN SECIMI ===")
for concern in ("acne","dryness","aging","pigmentation","sensitivity","oiliness","pores"):
    r = run_flow(**{**BASE, "concern":concern, "skin_type_key":"normal", "actives_experience":"regular"})
    items = r["routine_items"]; tag_items_with_canonical_ids(items)
    used = set()
    for it in items: used |= set(it.get("canonical_ingredient_ids") or [])
    chain = chain_actives_for_concern(concern, limit=10)
    cids = [c.get("ingredient_id") for c in chain]
    hit = [c for c in cids if c in used]; miss = [c for c in cids if c not in used]
    print(f"\n[{concern}] zincir={len(cids)} kullanilan={len(hit)}")
    print(f"   ISABET : {hit}")
    print(f"   ATLANAN: {miss[:8]}")

print("\n\n=== TOLERANS 'KOTU' DURUMU: yerine bir sey konuyor mu? ===")
for tol in ({}, {"retinol":"bad"}, {"retinol":"bad","aha":"bad"}):
    r = run_flow(**{**BASE, "concern":"aging","skin_type_key":"normal","actives_experience":"regular",
                    "actives_tolerance":tol})
    ev = [i["action"][:58] for i in r["routine_items"] if i["time"]=="Akşam" and i.get("step_order")==20]
    ap = [a.get("active") for a in (r.get("active_plan") or [])]
    print(f"  tol={tol or 'yok'}")
    print(f"    aksam tedavi adimi: {ev or '(YOK)'}")
    print(f"    active_plan: {ap}")

print("\n\n=== strength_stage nerede? ===")
r = run_flow(**{**BASE, "concern":"aging","skin_type_key":"normal","actives_experience":"none"})
print("  ust seviye anahtarlar:", sorted(r.keys()))
p = r.get("personalization") or {}
print("  personalization:", json.dumps(p, ensure_ascii=False)[:400])

print("\n\n=== YANLIS ETIKET KONTROLU ===")
from knowledge.cabinet_router import tag_items_with_canonical_ids as tg
probe=[{"action":"Niasinamid %10 serum (INCI: Niacinamide; niasin ile karıştırma)","detail":"","time":"Akşam","category":"Bakım"}]
tg(probe); print("  niasin uyarisi olan satir ->", probe[0].get("canonical_ingredient_ids"))
