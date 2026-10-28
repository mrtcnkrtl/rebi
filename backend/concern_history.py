"""
Sorun başı süre + sıklık, tetikleyici, beslenme, geçmiş, beklenti.
Şiddet skorundan ayrı: ne kadar zamandır ve ne sıklıkla olduğunu rutine bağlar.
"""

from __future__ import annotations

from typing import Any, Optional

DURATION_IDS = ("lt1", "1-3", "3-6", "6-12", "1y+")
FREQUENCY_IDS = ("daily", "several_week", "weekly", "monthly", "flare", "constant")
TRIGGER_IDS = ("stress", "period", "sun", "food", "season", "cold", "heat", "other")
PAST_IDS = ("none", "cleanser", "moisturizer", "rx", "derm", "otc")
EXPECT_IDS = ("acne_less", "spots_less", "clean_skin", "hydration", "aging_slow", "comfort")

_DURATION_TR = {
    "lt1": "1 aydan kısa",
    "1-3": "1–3 ay",
    "3-6": "3–6 ay",
    "6-12": "6–12 ay",
    "1y+": "1 yıldan uzun",
}
_FREQ_TR = {
    "daily": "neredeyse her gün",
    "several_week": "haftada birkaç kez",
    "weekly": "haftada bir",
    "monthly": "ayda birkaç kez",
    "flare": "ataklar halinde",
    "constant": "sürekli / hiç geçmiyor",
}
_TRIGGER_TR = {
    "stress": "stres",
    "period": "adet dönemi",
    "sun": "güneş",
    "food": "beslenme",
    "season": "mevsim",
    "cold": "soğuk",
    "heat": "sıcak",
    "other": "diğer",
}

_CONCERN_TR = {
    "acne": "akne",
    "pigmentation": "leke",
    "dryness": "kuruluk",
    "aging": "kırışıklık",
    "pores": "gözenek",
    "oiliness": "yağlılık",
    "sensitivity": "hassasiyet",
    "general": "genel bakım",
}


def _clip_note(raw: Any, n: int = 240) -> str:
    s = str(raw or "").strip()
    if not s:
        return ""
    s = " ".join(s.split())
    return s[:n]


def attach_timeline_fields(entry: dict, raw_item: Optional[dict] = None) -> dict:
    src = raw_item or entry
    dur = str(src.get("duration") or "").strip()
    freq = str(src.get("frequency") or "").strip()
    if dur not in DURATION_IDS:
        dur = ""
    if freq not in FREQUENCY_IDS:
        freq = ""
    entry["duration"] = dur
    entry["frequency"] = freq
    entry["note"] = _clip_note(src.get("note"))
    return entry


def normalize_history_lists(
    *,
    triggers: Optional[list] = None,
    past_treatments: Optional[list] = None,
    expectations: Optional[list] = None,
    nutrition: Optional[dict] = None,
) -> dict:
    trig = [str(x) for x in (triggers or []) if str(x) in TRIGGER_IDS][:8]
    past = [str(x) for x in (past_treatments or []) if str(x) in PAST_IDS][:6]
    exp = [str(x) for x in (expectations or []) if str(x) in EXPECT_IDS][:6]
    nut = {}
    if isinstance(nutrition, dict):
        for k in ("fastfood", "sugar", "dairy", "veggies"):
            try:
                nut[k] = max(0, min(7, int(nutrition.get(k, 0))))
            except (TypeError, ValueError):
                nut[k] = 0
    return {
        "triggers": trig,
        "past_treatments": past,
        "expectations": exp,
        "nutrition": nut,
    }


def apply_history_to_guards(guards: dict, ranked: list[dict], history: dict) -> dict:
    """Tetikleyici / beklenti / kısa süre → mevcut tavanları sıkılaştır veya SPF yükselt."""
    g = dict(guards or {})
    notes = list(g.get("notes") or [])
    trig = set(history.get("triggers") or [])
    exp = set(history.get("expectations") or [])

    if "sun" in trig:
        g["min_spf"] = max(int(g.get("min_spf") or 30), 50)
        notes.append("güneş tetikleyici: SPF 50")
    if "comfort" in exp:
        g["force_starter"] = True
        g["max_bha_nights"] = min(int(g.get("max_bha_nights") or 4), 2)
        notes.append("rahatlık hedefi: asit tavanı")

    primary = ranked[0] if ranked else {}
    dur = primary.get("duration") or ""
    freq = primary.get("frequency") or ""
    if dur in ("lt1", "1-3") or freq in ("flare", "monthly"):
        g["max_bha_nights"] = min(int(g.get("max_bha_nights") or 4), 2)
        notes.append("kısa süre veya atak sıklığı: gece sayısı düşük")
    if freq in ("daily", "constant") and dur in ("6-12", "1y+"):
        notes.append("kronik/sürekli: protokol tam şiddette")

    g["notes"] = notes
    return g


def cap_weekly_days_from_timeline(items: list[dict], ranked: list[dict]) -> None:
    """Atak/aylık veya yeni başlangıç: güçlü bakım günlerini 2'ye indir."""
    if not ranked:
        return
    p = ranked[0]
    dur = p.get("duration") or ""
    freq = p.get("frequency") or ""
    cap = None
    if freq in ("flare", "monthly") or dur in ("lt1", "1-3"):
        cap = 2
    if cap is None:
        return
    for it in items:
        if it.get("category") != "Bakım":
            continue
        wd = it.get("weekly_days")
        if isinstance(wd, list) and len(wd) > cap:
            it["weekly_days"] = wd[:cap]


def build_history_routine_items(
    ranked: list[dict],
    history: dict,
    *,
    gender: str = "",
) -> list[dict]:
    """Tek yüksek öncelikli yaşam satırı: süre/sıklık + tetik + beslenme + geçmiş."""
    lines = []
    for e in ranked:
        lab = _CONCERN_TR.get(e["id"], e["id"])
        bits = [f"{lab} şiddet {e.get('score', '?')}/10"]
        if e.get("duration"):
            bits.append(_DURATION_TR.get(e["duration"], e["duration"]))
        if e.get("frequency"):
            bits.append(_FREQ_TR.get(e["frequency"], e["frequency"]))
        if e.get("note"):
            bits.append(f"not: «{e['note']}»")
        lines.append(" — ".join(bits))
    trig = history.get("triggers") or []
    if trig:
        lines.append("Tetikleyici: " + ", ".join(_TRIGGER_TR.get(t, t) for t in trig) + ".")
    nut = history.get("nutrition") or {}
    diet_bits = []
    if int(nut.get("sugar") or 0) >= 3:
        diet_bits.append("sık şeker")
    if int(nut.get("dairy") or 0) >= 3:
        diet_bits.append("günlük süt ürünü")
    if int(nut.get("fastfood") or 0) >= 3:
        diet_bits.append("sık fast-food")
    if int(nut.get("veggies") or 0) <= 1:
        diet_bits.append("az sebze-meyve")
    ids = {e["id"] for e in ranked}
    if diet_bits and (ids & {"acne", "oiliness", "pigmentation"}):
        lines.append(
            "Beslenme notu (" + ", ".join(diet_bits) + "): yüksek glisemik yük ve sık süt "
            "akne/sebumu azdırabilir; rutin asidi artırmak yerine bunları seyreltmek daha güvenli."
        )
    past = history.get("past_treatments") or []
    if "derm" in past or "rx" in past:
        lines.append(
            "Daha önce dermatolog veya reçeteli tedavi var: bu plan destekleyicidir, "
            "reçeteyi kesmez; yeni güçlü aktifi hekimin bilgisi olmadan katlama."
        )
    elif "none" in past:
        lines.append("Daha önce tedavi denememişsin: sıklık düşük tutuldu, doz yığılmaz.")
    if "period" in trig and (gender or "").lower() == "female":
        lines.append(
            "Adet tetikleyicisi: luteal/adet haftasında yeni asit ekleme; "
            "mevcut azelaik/niasinamidi çene odaklı sürdürmek yeterli."
        )
    if not lines:
        return []
    return [
        {
            "time": "Günlük",
            "category": "Yaşam",
            "icon": "🗓️",
            "action": "Sorunların süre ve sıklığı — senin tarifin",
            "detail": " ".join(lines),
            "usage": (
                "Şiddet skoru ne kadar yoğun olduğunu, süre ne kadar zamandır sürdüğünü, "
                "sıklık da haftada kaç kez çıktığını söyler. Motor gece sayısını buna göre kısıtlar."
            ),
            "priority": 0,
            "step_order": 1,
        }
    ]
