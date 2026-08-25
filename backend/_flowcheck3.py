import config, json
from flow_engine import run_flow
from knowledge.cabinet_router import tag_items_with_canonical_ids, concern_ids_for_slug, _fetch_links_by_concern, chain_actives_for_concern

BASE = dict(severity_score=6, age=32, gender="female", stress_score=5, sleep_hours=7.0,
            water_intake=2.0, smoking=False, alcohol=False, uv_index=6.0, humidity=45.0,
            temperature=24.0, makeup_frequency=2, makeup_removal="cleanser")

print("=== 1) chain_actives_for_concern sadece 'supports' mu donduruyor? ===")
for slug in ("sensitivity","acne"):
    ch = chain_actives_for_concern(slug, limit=12)
    print(f"  [{slug}] " + ", ".join(f"{c.get('ingredient_id')}({c.get('effect_status')})" for c in ch))

print("\n=== 2) RUTIN, KANONIK 'AVOID' LISTESIYLE CELISIYOR MU? ===")
for slug in ("acne","dryness","aging","pigmentation","sensitivity","oiliness","pores"):
    r = run_flow(**{**BASE, "concern":slug, "skin_type_key":"normal", "actives_experience":"regular"})
    items = r["routine_items"]; tag_items_with_canonical_ids(items)
    used=set()
    for it in items: used |= set(it.get("canonical_ingredient_ids") or [])
    cids = concern_ids_for_slug(slug)
    avoid = _fetch_links_by_concern(cids, limit=50, effect_statuses=["avoid"]) if cids else []
    aid = {a.get("ingredient_id") for a in avoid}
    clash = sorted(used & aid)
    print(f"  [{slug:12}] avoid kayitli={len(aid):2} celisme={clash or 'yok'}")

print("\n=== 3) ZAMANLAMA ALANLARI HANGI ADIMLARDA DOLU? ===")
for slug in ("acne","aging","dryness"):
    r = run_flow(**{**BASE, "concern":slug, "skin_type_key":"normal", "actives_experience":"regular"})
    print(f"  [{slug}]")
    for it in r["routine_items"]:
        if it.get("category") not in ("Bakım","Koruma"): continue
        print(f"    {it['time']:6}|{it.get('step_order',0):3}| f/w={str(it.get('frequency_per_week')):5} gun={str(it.get('weekly_days')):12} ramp={str(it.get('ramp_stage')):10} {it['action'][:44]}")
