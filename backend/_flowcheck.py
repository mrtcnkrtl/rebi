import config, json
from flow_engine import run_flow
from knowledge.cabinet_router import tag_items_with_canonical_ids, chain_actives_for_concern

BASE = dict(severity_score=6, age=32, gender="female", stress_score=5, sleep_hours=7.0,
            water_intake=2.0, smoking=False, alcohol=False, uv_index=6.0, humidity=45.0,
            temperature=24.0, makeup_frequency=2, makeup_removal="cleanser")

PROFILES = [
 ("Akne / yağlı / deneyimsiz", dict(concern="acne", skin_type_key="oily", actives_experience="none")),
 ("Kuruluk / kuru / deneyimli", dict(concern="dryness", skin_type_key="dry", actives_experience="regular")),
 ("Yaşlanma / normal / deneyimli", dict(concern="aging", skin_type_key="normal", actives_experience="regular")),
 ("Leke / karma / hamile", dict(concern="pigmentation", skin_type_key="combination", actives_experience="occasional", is_pregnant=True)),
 ("Hassasiyet / hassas / batma var", dict(concern="sensitivity", skin_type_key="sensitive", actives_experience="occasional",
                                          special_flags={"stings_with_products": True})),
 ("Yaşlanma / retinol toleransı kötü", dict(concern="aging", skin_type_key="normal", actives_experience="regular",
                                            actives_tolerance={"retinol":"bad"})),
]

for label, over in PROFILES:
    kw = {**BASE, **over}
    r = run_flow(**kw)
    items = r["routine_items"]
    n_tagged = tag_items_with_canonical_ids(items)
    print("="*100); print(f"### {label}   (strength_stage={r.get('personalization',{}).get('strength_stage') or r.get('strength_stage')})")
    for it in items:
        if it.get("category") not in ("Bakım","Koruma"): continue
        fam = it.get("active_families") or []
        pct = it.get("strength_pct"); fpw = it.get("frequency_per_week"); wd = it.get("weekly_days")
        cid = it.get("canonical_ingredient_ids") or []
        print(f"  [{it['time']:6}|{it.get('step_order',0):3}] {it['action'][:62]:64} fam={fam} pct={pct} f/w={fpw} gun={wd} kanonik={cid}")
    ap = r.get("active_plan") or []
    print(f"  --- active_plan ({len(ap)} ogesi): " + ", ".join(f"{a.get('active')}[{a.get('when')}]" for a in ap))
    print(f"  --- rutin adiminda kanonik etiket: {n_tagged}/{sum(1 for i in items if i.get('category') in ('Bakım','Koruma'))}")
