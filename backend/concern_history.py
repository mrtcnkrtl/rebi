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
    "undereye": "göz altı koyuluğu",
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


_PASSING_CYCLE_PHASES = frozenset({"menstrual", "luteal"})
_PHASE_WAIT_TR = {
    "menstrual": "Adet günleri",
    "luteal": "Adet öncesi günler",
}


def passing_cycle_window(
    *,
    gender: str = "",
    cycle_phase: str = "",
    triggers: Optional[list] = None,
    is_pregnant: bool = False,
) -> str:
    """Adet kaynaklı sorunda, luteal veya adet penceresi bitene kadar yeni tedavi bekler.

    Menopoz ve gebelik tıbbi hormonal durumdur; bekleme uygulanmaz.
    Foliküler ve ovülasyon penceresi geçmiştir; tedavi o planda başlar.
    """
    if (gender or "").lower() not in ("female", "kadın", "kadin"):
        return ""
    if is_pregnant:
        return ""
    phase = (cycle_phase or "").strip().lower()
    if phase not in _PASSING_CYCLE_PHASES:
        return ""
    if "period" not in {str(t) for t in (triggers or [])}:
        return ""
    return phase


def _treatment_label(it: dict) -> str:
    choices = it.get("choices") or []
    action = ""
    if choices:
        default = it.get("default_choice_id")
        chosen = next((c for c in choices if c.get("id") == default), choices[0])
        action = str(chosen.get("action") or "")
    if not action:
        action = str(it.get("action") or "")
    action = action.split("(INCI")[0].strip(" —-")
    return action[:160]


def _hold_treatment_item(it: dict) -> bool:
    """İskelet (temizlik, nem, SPF) ve yaşam notu kalır; tedavi adımı bekler."""
    if it.get("category") == "Koruma":
        return False
    role = str(it.get("concern_role") or "")
    if role in ("environment", "undereye_lifestyle", "deferred_cycle"):
        return False
    so = it.get("step_order")
    if so in (10, 30, 40):
        return False
    action = (it.get("action") or "").lower()
    if action.startswith(("temizleme", "çift aşama", "gece", "nemlendirici")):
        return False
    if role.startswith(("primary", "support_", "zone")):
        return True
    if so in (18, 20, 25, 26) and it.get("category") == "Bakım":
        return True
    if it.get("choice_group") and it.get("category") == "Bakım":
        return True
    if "pms akne" in action or "hormonal akne" in action:
        return True
    return False


def defer_treatment_until_window_passes(items: list[dict], phase: str) -> list[dict]:
    """Pencere bitene kadar tedavi adımını rutin dışı bırak; madde adını sakla."""
    phase = (phase or "").strip().lower()
    if phase not in _PHASE_WAIT_TR:
        return items
    held = [it for it in items if _hold_treatment_item(it)]
    if not held:
        return items
    primary = next(
        (
            it
            for it in held
            if it.get("step_order") == 20
            and not str(it.get("concern_role") or "").startswith(("support_", "zone"))
        ),
        held[0],
    )
    label = _treatment_label(primary) or "seçilen dermokozmetik"
    note = {
        "time": "Akşam",
        "category": "Bakım",
        "icon": "⏸️",
        "action": f"Bu dönem bitince: {label}",
        "detail": (
            f"{_PHASE_WAIT_TR[phase]} içindesin ve sorun adet döngüsüne bağlı. "
            f"Bu pencere bitince başlanacak dermokozmetik: {label}. "
            "Bugün temizlik, nemlendirici ve güneş koruyucu yeterli. "
            "Menopoz ve gebelik bu beklemeye girmez."
        ),
        "usage": "Yeni asit, retinol veya leke maddesine bu pencerede başlama.",
        "priority": 2,
        "step_order": 20,
        "concern_role": "deferred_cycle",
        "deferred_until": phase,
        "deferred_action": label,
    }
    held_ids = {id(it) for it in held}
    out: list[dict] = []
    inserted = False
    for it in items:
        if id(it) in held_ids:
            if not inserted:
                out.append(note)
                inserted = True
            continue
        out.append(it)
    return out


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
    if "period" in trig and (gender or "").lower() in ("female", "kadın", "kadin"):
        lines.append(
            "Adet tetikleyicisi: luteal ve adet günlerinde yeni dermokozmetik maddeye başlanmaz; "
            "bu pencere bitince başlanır. Menopoz ve gebelik bu beklemeye girmez."
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
