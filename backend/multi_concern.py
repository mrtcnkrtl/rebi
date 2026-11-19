"""
Tek odak kuralı:
- 1 sorun → o sorunun rutini/aktifi.
- 1'den fazla → şiddet sırasıyla kuyruk; rutinde yalnız sıradaki sorun.
- Sonraki soruna geçiş: check-in'de açıkça «sorun çözüldü» + en az FOCUS_MIN_DAYS.
- Yeni odağın ilk FOCUS_STARTER_DAYS günü düşük doz / seyrek (starter) alıştırma.
- Cilt dengesi bozuksa (batma / yüksek hassasiyet-kuruluk) önce bariyer fazı,
  sonra tedavi kuyruğu aynı kurala döner.
Ürün değil etken; doz ve sıklık skora göre değişir.
"""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Any, Optional

ALLOWED_CONCERNS = (
    "acne",
    "pigmentation",
    "dryness",
    "aging",
    "pores",
    "oiliness",
    "sensitivity",
    "undereye",
    "general",
)

# Tedavi kuyruğuna giren sorunlar (general yalnız iskelet; sensitivity guard + bariyer).
TREATMENT_CONCERNS = frozenset(
    {
        "acne",
        "pigmentation",
        "dryness",
        "aging",
        "pores",
        "oiliness",
        "undereye",
    }
)

# Eşit şiddette: inflamatuvar / leke / bariyer, yağ-gözenekten önce.
_TIE_BREAK = {cid: i for i, cid in enumerate(ALLOWED_CONCERNS)}

# Geriye uyum: eski test/metinler; ilerleme artık concern_resolved + min gün.
FOCUS_ADVANCE_GOOD_STREAK = 2
# Odak başına minimum süre (birkaç hafta) — erken «çözüldü» işaretinde geçiş yok.
FOCUS_MIN_DAYS = 14
# Yeni odak / yeni aktif: bu süre boyunca starter doz + seyrek haftalık günler.
FOCUS_STARTER_DAYS = 14
# «Sorun geçti mi?» check-in sorusu aralığı.
CONCERN_RESOLVED_ASK_INTERVAL_DAYS = 7
_CONCERN_LABEL_TR = {
    "barrier": "bariyer onarımı",
    "acne": "akne",
    "pigmentation": "leke",
    "dryness": "kuruluk",
    "aging": "yaşlanma",
    "pores": "gözenek",
    "oiliness": "yağlılık",
    "sensitivity": "hassasiyet",
    "undereye": "göz altı",
    "general": "genel bakım",
}


def score_band(score: int) -> str:
    if score <= 3:
        return "hafif"
    if score <= 6:
        return "orta"
    return "şiddetli"


def normalize_concern_entries(
    *,
    concern: str,
    severity_score: int,
    acne_zones: Optional[list] = None,
    concerns: Optional[list] = None,
) -> list[dict]:
    """İstemci listesi veya eski tek `concern` alanından tek biçim."""
    out: list[dict] = []
    seen: set[str] = set()
    raw = concerns if concerns else None
    if raw:
        for item in raw:
            if not isinstance(item, dict):
                continue
            cid = str(item.get("id") or "").strip().lower()
            if cid not in ALLOWED_CONCERNS or cid in seen:
                continue
            try:
                raw_sc = item.get("severity_score")
                if raw_sc is None:
                    raw_sc = item.get("score")
                sc = int(raw_sc if raw_sc is not None else 5)
            except (TypeError, ValueError):
                sc = 5
            zones = item.get("zones") or []
            if not isinstance(zones, list):
                zones = []
            zones = [str(z).strip() for z in zones if str(z).strip()][:12]
            rec = {"id": cid, "score": max(0, min(10, sc)), "zones": zones}
            from concern_history import attach_timeline_fields

            attach_timeline_fields(rec, item)
            out.append(rec)
            seen.add(cid)
    if not out:
        cid = str(concern or "general").strip().lower()
        if cid not in ALLOWED_CONCERNS:
            cid = "general"
        zones = [str(z).strip() for z in (acne_zones or []) if str(z).strip()][:12]
        rec = {"id": cid, "score": max(0, min(10, int(severity_score or 5))), "zones": zones}
        from concern_history import attach_timeline_fields

        attach_timeline_fields(rec)
        out.append(rec)
    return out


def rank_concerns(entries: list[dict]) -> list[dict]:
    """En yüksek şiddet önce. Eşitlikte klinik tie-break."""
    return sorted(
        entries,
        key=lambda e: (-int(e.get("score") or 0), _TIE_BREAK.get(e.get("id"), 99)),
    )


def barrier_needs_repair(
    ranked: list[dict],
    *,
    stings_with_products: bool = False,
    skin_type_key: str = "normal",
) -> bool:
    """Cilt dengesi bozulmuşsa tedavi aktiflerinden önce bariyer."""
    by_id = {e["id"]: int(e.get("score") or 0) for e in ranked if e.get("id")}
    if stings_with_products:
        return True
    if by_id.get("sensitivity", 0) >= 5:
        return True
    if by_id.get("dryness", 0) >= 6:
        return True
    if (skin_type_key or "").lower() == "sensitive" and (
        by_id.get("dryness", 0) >= 4 or by_id.get("sensitivity", 0) >= 3
    ):
        return True
    return False


def _barrier_focus_entry(ranked: list[dict], *, stings: bool) -> dict:
    """Bariyer fazında iskelet: baskın hassasiyet veya kuruluk."""
    by_id = {e["id"]: int(e.get("score") or 0) for e in ranked if e.get("id")}
    sens = by_id.get("sensitivity", 0)
    dry = by_id.get("dryness", 0)
    if stings or sens >= dry:
        score = max(sens, 6 if stings else 0, 5)
        return {"id": "sensitivity", "score": score, "zones": [], "_barrier_phase": True}
    return {"id": "dryness", "score": max(dry, 6), "zones": [], "_barrier_phase": True}


def build_focus_queue(
    ranked: list[dict],
    *,
    stings_with_products: bool = False,
    skin_type_key: str = "normal",
    resume_queue: Optional[list] = None,
) -> dict[str, Any]:
    """
    Tek odak + ertelenenler.
    resume_queue: check-in ile ilerlemiş kuyruk [{id, score}, ...] — varsa onu kullan.
    """
    ranked = list(ranked or [])
    needs_barrier = barrier_needs_repair(
        ranked,
        stings_with_products=stings_with_products,
        skin_type_key=skin_type_key,
    )

    if resume_queue:
        raw0 = resume_queue[0] if resume_queue else {}
        head_id = str((raw0 or {}).get("id") or "").strip().lower()
        if head_id == "barrier":
            focus = _barrier_focus_entry(ranked, stings=bool(stings_with_products))
            deferred = []
            for raw in resume_queue[1:]:
                if not isinstance(raw, dict):
                    continue
                cid = str(raw.get("id") or "").strip().lower()
                if cid in ("barrier", "general", "sensitivity"):
                    continue
                if cid not in TREATMENT_CONCERNS:
                    continue
                try:
                    sc = int(raw.get("score") if raw.get("score") is not None else 5)
                except (TypeError, ValueError):
                    sc = 5
                deferred.append({"id": cid, "score": max(0, min(10, sc)), "zones": list(raw.get("zones") or [])})
            return {
                "focus": focus,
                "deferred": deferred,
                "phase": "barrier",
                "queue": [focus] + deferred,
                "advance_rule": "resolved_after_min_days",
                "min_days": FOCUS_MIN_DAYS,
                "needs_barrier": True,
            }
        queue: list[dict] = []
        for raw in resume_queue:
            if not isinstance(raw, dict):
                continue
            cid = str(raw.get("id") or "").strip().lower()
            if cid == "barrier":
                continue
            if cid not in ALLOWED_CONCERNS:
                continue
            try:
                sc = int(raw.get("score") if raw.get("score") is not None else 5)
            except (TypeError, ValueError):
                sc = 5
            queue.append({"id": cid, "score": max(0, min(10, sc)), "zones": list(raw.get("zones") or [])})
        if queue:
            focus = queue[0]
            deferred = queue[1:]
            return {
                "focus": focus,
                "deferred": deferred,
                "phase": "treatment",
                "queue": [focus] + deferred,
                "advance_rule": "resolved_after_min_days",
                "min_days": FOCUS_MIN_DAYS,
                "needs_barrier": needs_barrier,
            }

    treatment = [dict(e) for e in ranked if e.get("id") in TREATMENT_CONCERNS]
    if needs_barrier:
        focus = _barrier_focus_entry(ranked, stings=bool(stings_with_products))
        deferred = [e for e in treatment if e.get("id") != focus.get("id")]
        phase = "barrier"
    else:
        if treatment:
            focus = dict(treatment[0])
            deferred = [dict(e) for e in treatment[1:]]
        else:
            # Yalnız general/sensitivity
            focus = dict(ranked[0]) if ranked else {"id": "general", "score": 5, "zones": []}
            deferred = []
        phase = "treatment"

    return {
        "focus": focus,
        "deferred": deferred,
        "phase": phase,
        "queue": [focus] + list(deferred),
        "advance_rule": "resolved_after_min_days",
        "min_days": FOCUS_MIN_DAYS,
        "needs_barrier": needs_barrier,
    }


def concern_label_tr(cid: str) -> str:
    return _CONCERN_LABEL_TR.get(cid, cid)


def today_iso(today: Optional[str] = None) -> str:
    if today:
        return str(today).strip()[:10]
    return datetime.now(timezone.utc).date().isoformat()


def parse_iso_date(value: Any) -> Optional[date]:
    raw = str(value or "").strip()[:10]
    if not raw:
        return None
    try:
        return date.fromisoformat(raw)
    except ValueError:
        return None


def focus_days_elapsed(focus_state: dict, *, today: Optional[str] = None) -> int:
    """Odakta geçen tam gün (aynı gün = 0). Tarih yoksa 0 (min süre henüz dolmamış)."""
    started = parse_iso_date((focus_state or {}).get("focus_started_on"))
    if not started:
        return 0
    end = parse_iso_date(today) or datetime.now(timezone.utc).date()
    return max(0, (end - started).days)


def focus_needs_starter_ramp(focus_state: Optional[dict], *, today: Optional[str] = None) -> bool:
    """Yeni odak / yeni aktif: ilk FOCUS_STARTER_DAYS düşük doz + seyrek sıklık."""
    if not focus_state:
        return True
    return focus_days_elapsed(focus_state, today=today) < FOCUS_STARTER_DAYS


def find_focus_state_item(routine_items: Optional[list]) -> Optional[dict]:
    for it in routine_items or []:
        if isinstance(it, dict) and it.get("concern_role") == "focus_state":
            return it
    return None


def build_concern_resolved_prompt(
    routine_items: Optional[list],
    *,
    past_logs: Optional[list] = None,
    today: Optional[str] = None,
) -> dict[str, Any]:
    """
    Check-in UI: «sorun geçti mi?» haftada bir, yalnız sırada sonraki sorun varken.
    past_logs: en yeni önce; adaptation.checkin_extras.concern_resolved anahtarı sorulmuş demektir.
    """
    day = today_iso(today)
    focus = find_focus_state_item(routine_items)
    empty = {
        "ask_concern_resolved": False,
        "has_next_focus": False,
        "focus_id": None,
        "focus_label": None,
        "next_focus_id": None,
        "next_focus_label": None,
        "focus_days_elapsed": 0,
        "focus_min_days": FOCUS_MIN_DAYS,
        "ask_interval_days": CONCERN_RESOLVED_ASK_INTERVAL_DAYS,
    }
    if not focus:
        return empty

    queue = [e for e in (focus.get("focus_queue") or []) if isinstance(e, dict) and e.get("id")]
    focus_id = str(focus.get("focus_id") or (queue[0].get("id") if queue else "") or "")
    next_id = str(queue[1].get("id")) if len(queue) > 1 else None
    has_next = bool(next_id)
    days = focus_days_elapsed(focus, today=day)

    out = {
        **empty,
        "has_next_focus": has_next,
        "focus_id": focus_id or None,
        "focus_label": concern_label_tr(focus_id) if focus_id else None,
        "next_focus_id": next_id,
        "next_focus_label": concern_label_tr(next_id) if next_id else None,
        "focus_days_elapsed": days,
        "focus_min_days": FOCUS_MIN_DAYS,
        "ask_interval_days": CONCERN_RESOLVED_ASK_INTERVAL_DAYS,
    }
    if not has_next:
        return out

    last_asked: Optional[date] = None
    for row in past_logs or []:
        if not isinstance(row, dict):
            continue
        ad = row.get("adaptation") or {}
        extras = ad.get("checkin_extras") if isinstance(ad, dict) else None
        if not isinstance(extras, dict):
            continue
        if "concern_resolved" not in extras:
            continue
        last_asked = parse_iso_date(row.get("log_date"))
        if last_asked:
            break

    if last_asked is None:
        out["ask_concern_resolved"] = True
        return out

    end = parse_iso_date(day) or datetime.now(timezone.utc).date()
    out["ask_concern_resolved"] = (end - last_asked).days >= CONCERN_RESOLVED_ASK_INTERVAL_DAYS
    return out


def build_focus_state_item(
    focus_info: dict,
    *,
    good_streak: int = 0,
    ranked_snapshot: Optional[list] = None,
    rebuild_ctx: Optional[dict] = None,
    focus_started_on: Optional[str] = None,
) -> dict:
    """Rutine gömülen odak meta satırı (check-in ilerletir)."""
    focus = focus_info.get("focus") or {}
    deferred = focus_info.get("deferred") or []
    fid = str(focus.get("id") or "general")
    phase = focus_info.get("phase") or "treatment"
    label = concern_label_tr("barrier" if phase == "barrier" else fid)
    has_next = any(d.get("id") for d in deferred)
    weeks = max(1, FOCUS_MIN_DAYS // 7)
    if has_next:
        detail = (
            f"Şu an tek sorun odaklısın: {label}. "
            f"Bu odakta en az ~{weeks} hafta kalınır; check-in’de «sorun çözüldü» "
            "işaretleyince sıradaki sorunun rutinine ve aktifine geçilir. "
            f"İlk {FOCUS_STARTER_DAYS} gün aktifler düşük doz ve seyrek (alıştırma). "
            "Sonraki maddeler plana yazıldı; şimdiden alma veya kullanma. "
            "Sabah dinlenme/koruma; akşam yalnız bu odağın aktifi."
        )
    else:
        detail = (
            f"Tek sorun odaklısın: {label}. "
            "Rutin ve aktif yalnız buna göre. "
            f"İlk {FOCUS_STARTER_DAYS} gün aktifler düşük doz ve seyrek (alıştırma). "
            "Sabah dinlenme/koruma; akşam bu odağın aktifi."
        )
    queue_payload = []
    if phase == "barrier":
        queue_payload.append({"id": "barrier", "score": int(focus.get("score") or 6)})
    else:
        queue_payload.append({"id": fid, "score": int(focus.get("score") or 5)})
    for d in deferred:
        queue_payload.append({"id": d.get("id"), "score": int(d.get("score") or 5)})

    snap = ranked_snapshot
    if snap is None:
        snap = list(focus_info.get("queue") or queue_payload)

    started = today_iso(focus_started_on)
    out = {
        "time": "Günlük",
        "category": "Yaşam",
        "icon": "🎯",
        "action": f"Odak: {label}",
        "detail": detail,
        "priority": 0,
        "step_order": 1,
        "concern_role": "focus_state",
        "focus_id": fid if phase != "barrier" else "barrier",
        "phase": phase,
        "good_streak": max(0, int(good_streak or 0)),
        "focus_started_on": started,
        "focus_min_days": FOCUS_MIN_DAYS,
        "focus_starter_days": FOCUS_STARTER_DAYS,
        "focus_queue": queue_payload,
        "ranked_snapshot": [
            {"id": e.get("id"), "score": int(e.get("score") or 5)}
            for e in (snap or [])
            if isinstance(e, dict) and e.get("id")
        ],
        "advance_rule": "resolved_after_min_days",
        "deferred_plan": [],
    }
    if rebuild_ctx:
        out["rebuild_ctx"] = dict(rebuild_ctx)
    return out


def attach_deferred_plan(
    focus_item: dict,
    deferred: list[dict],
    guards: dict,
    age_group: dict,
) -> tuple[dict, list[dict]]:
    """focus_state'e deferred_plan yazar; Yaşam önizleme satırlarını döner."""
    plan = build_deferred_plan(deferred, guards, age_group)
    focus_item = dict(focus_item or {})
    focus_item["deferred_plan"] = plan
    return focus_item, build_deferred_preview_items(plan)


def advance_focus_queue_state(
    focus_state: dict,
    *,
    skin_feeling: str,
    ranked: Optional[list] = None,
    stings_with_products: bool = False,
    concern_resolved: bool = False,
    today: Optional[str] = None,
) -> tuple[dict, bool, str]:
    """
    Check-in ile kuyruk ilerlemesi.
    - irritasyon/kırık → bariyer
    - concern_resolved + min gün + sırada başka sorun → sonraki odak
    Dönüş: (yeni_focus_state_fields, advanced?, note)
    """
    feeling = (skin_feeling or "").strip().lower()
    state = dict(focus_state or {})
    queue = list(state.get("focus_queue") or [])
    day = today_iso(today)
    # Eksik başlangıç tarihi: bugünden başlat (eski rutinler için min süre uygulanır)
    if not state.get("focus_started_on"):
        state["focus_started_on"] = day
    note = ""

    if feeling in ("irritasyon", "kirik"):
        ranked = ranked or []
        barrier_q = build_focus_queue(
            ranked,
            stings_with_products=True,
            skin_type_key="sensitive",
        )
        new_item = build_focus_state_item(barrier_q, good_streak=0, focus_started_on=day)
        return new_item, True, "Bariyer önceliğine dönüldü (tahriş/kırık hissi)."

    days = focus_days_elapsed(state, today=day)
    state["good_streak"] = 0

    if concern_resolved and len(queue) > 1:
        if days < FOCUS_MIN_DAYS:
            left = FOCUS_MIN_DAYS - days
            note = (
                f"Sorun çözüldü işaretlendi; bu odakta en az {FOCUS_MIN_DAYS} gün "
                f"gerekir ({days}/{FOCUS_MIN_DAYS}). {left} gün sonra sıradaki soruna geçilebilir."
            )
            return state, False, note
        queue = queue[1:]
        info = build_focus_queue(
            ranked or [],
            stings_with_products=stings_with_products,
            resume_queue=queue,
        )
        new_item = build_focus_state_item(info, good_streak=0, focus_started_on=day)
        label = concern_label_tr(
            "barrier" if info.get("phase") == "barrier" else str((info.get("focus") or {}).get("id"))
        )
        return new_item, True, f"Odak sonraki soruna geçti: {label}."

    if concern_resolved and len(queue) <= 1:
        note = "Odak sorun çözüldü olarak işaretlendi; sırada başka sorun yok, mevcut odakta kalınıyor."
        return state, False, note

    return state, False, note


def build_guards(
    ranked: list[dict],
    *,
    stings_with_products: bool = False,
    skin_type_key: str = "normal",
) -> dict[str, Any]:
    """Seçilen TÜM sorunlar birbirini kötüleştirmesin diye tavan/yasak."""
    by_id = {e["id"]: int(e["score"]) for e in ranked}
    ids = set(by_id)

    avoid_aha = False
    avoid_bpo = False
    avoid_retinol = False
    max_bha_pct = 2.0
    max_bha_nights = 4
    max_retinol = "0.5"
    avoid_heavy_occlusive = False
    force_starter = False
    prefer_azelaic = False
    min_spf = 30
    notes: list[str] = []

    if "sensitivity" in ids:
        s = by_id["sensitivity"]
        avoid_aha = True
        prefer_azelaic = True
        force_starter = True
        max_bha_pct = min(max_bha_pct, 1.0)
        max_bha_nights = min(max_bha_nights, 2)
        max_retinol = "0.1-0.3"
        notes.append("hassasiyet: asit/BPO tavanı düşürüldü")
        if s >= 5 or stings_with_products:
            avoid_bpo = True
            notes.append("hassasiyet: tam yüz BPO yok")
        if s >= 7 or stings_with_products:
            avoid_retinol = True
            notes.append("hassasiyet: retinol bu planda yok")

    if "dryness" in ids:
        d = by_id["dryness"]
        if d >= 5:
            max_bha_pct = min(max_bha_pct, 1.0)
            max_bha_nights = min(max_bha_nights, 2)
            notes.append("kuruluk: BHA seyreltildi")
        if d >= 6:
            avoid_bpo = True
            notes.append("kuruluk: BPO yok (kurutmasın)")

    if ("acne" in ids or "oiliness" in ids or "pores" in ids) and by_id.get("dryness", 0) < 7:
        avoid_heavy_occlusive = True

    if "pigmentation" in ids:
        min_spf = 50
        notes.append("leke: SPF 50 taban")

    if skin_type_key == "sensitive":
        force_starter = True
        max_bha_pct = min(max_bha_pct, 1.0)
        avoid_aha = True

    if stings_with_products:
        force_starter = True
        avoid_bpo = True
        avoid_aha = True

    return {
        "avoid_aha": avoid_aha,
        "avoid_bpo": avoid_bpo,
        "avoid_retinol": avoid_retinol,
        "max_bha_pct": max_bha_pct,
        "max_bha_nights": max_bha_nights,
        "max_retinol": max_retinol,
        "avoid_heavy_occlusive": avoid_heavy_occlusive,
        "force_starter": force_starter,
        "prefer_azelaic": prefer_azelaic,
        "min_spf": min_spf,
        "stings_with_products": bool(stings_with_products),
        "notes": notes,
        "by_id": by_id,
    }


def cap_bha(pct: float, nights: int, guards: dict) -> tuple[float, int]:
    pct = min(float(pct), float(guards.get("max_bha_pct") or 2))
    nights = min(int(nights), int(guards.get("max_bha_nights") or 7))
    nights = max(1, nights)
    if pct < 0.5:
        pct = 0.5
    return pct, nights


def bha_for_acne(score: int, guards: dict) -> tuple[float, int]:
    if score <= 3:
        pct, n = 1.0, 2
    elif score <= 6:
        pct, n = 2.0, 3
    else:
        pct, n = 2.0, 4
    return cap_bha(pct, n, guards)


def bha_for_pores(score: int, guards: dict) -> tuple[float, int]:
    """Komedon tıkacı: hafifte bile BHA çekirdek, akne BPO'suz."""
    if score <= 3:
        pct, n = 0.5, 2
    elif score <= 6:
        pct, n = 1.0, 3
    else:
        pct, n = 2.0, 3
    return cap_bha(pct, n, guards)


def bha_for_oiliness(score: int, guards: dict) -> tuple[Optional[float], int]:
    """Sebum: düşük şiddette BHA yok; yalnızca parlama yüksekse düşük doz."""
    if score < 5:
        return None, 0
    if score <= 7:
        pct, n = 0.5, 2
    else:
        pct, n = 1.0, 2
    return cap_bha(pct, n, guards)


def _blob(items: list[dict]) -> str:
    return " ".join(str(i.get("action") or "") for i in items).lower()


def add_secondary_actives(
    items: list[dict],
    secondaries: list[dict],
    guards: dict,
    age_group: dict,
) -> list[dict]:
    """
    Eski yol: ikincil tedavi serumu yığmaz.
    Sıralı odak modelinde destek katmanları deferred kuyruğunda bekler.
    """
    _ = (secondaries, guards, age_group)
    return items


def preview_deferred_active(
    cid: str,
    score: int,
    guards: dict,
    age_group: dict,
) -> Optional[dict[str, Any]]:
    """
    Sıradaki sorun için planlanan madde (şimdi rutine EKLENMEZ).
    Check-in ilerleyince run_flow yeniden kurar; bu yalnız önizleme.
    """
    from flow_engine import (
        _skin_azelaic,
        _skin_green_tea,
        _skin_salicylic_toner,
        dose_tier,
    )

    g = guards or {}
    sc = int(score or 5)
    # Birincil odak seçimine yakın önizleme (ikincil yığma dozundan bağımsız)
    if cid == "oiliness":
        t = dose_tier(g, score=sc)
        action = _skin_green_tea("hassas" if t == "hassas" or g.get("stings_with_products") else "standart")
        return {"id": cid, "label": concern_label_tr(cid), "score": sc, "action": action, "status": "later"}
    if cid == "acne":
        if g.get("avoid_bpo") or g.get("prefer_azelaic") or g.get("stings_with_products"):
            action = _skin_azelaic("%10-15")
        else:
            action = _skin_azelaic("%10-15") if sc <= 6 else "Benzoil peroksit %2.5-5 kısa temas (plan)"
        return {"id": cid, "label": concern_label_tr(cid), "score": sc, "action": action, "status": "later"}
    if cid == "pores":
        pct, _n = bha_for_pores(sc, g)
        return {
            "id": cid,
            "label": concern_label_tr(cid),
            "score": sc,
            "action": _skin_salicylic_toner(pct),
            "status": "later",
        }

    item = _secondary_item(cid, sc, blob="", guards=g, age_group=age_group or {})
    if not item:
        return None
    action = (item.get("action") or "").strip()
    if not action and item.get("system_pick"):
        sp = item.get("system_pick") or {}
        action = str(sp.get("action") or sp.get("label") or "")
    if not action and item.get("choices"):
        ch0 = (item.get("choices") or [{}])[0]
        action = str(ch0.get("action") or "")
    if not action:
        return None
    return {"id": cid, "label": concern_label_tr(cid), "score": sc, "action": action, "status": "later"}


def build_deferred_plan(
    deferred: list[dict],
    guards: dict,
    age_group: dict,
) -> list[dict[str, Any]]:
    """2./3. (ve sonrası) sorunların planlı maddeleri — status=later."""
    out: list[dict[str, Any]] = []
    for d in deferred or []:
        if not isinstance(d, dict):
            continue
        cid = str(d.get("id") or "").strip().lower()
        if cid not in TREATMENT_CONCERNS:
            continue
        try:
            sc = int(d.get("score") if d.get("score") is not None else 5)
        except (TypeError, ValueError):
            sc = 5
        prev = preview_deferred_active(cid, sc, guards, age_group)
        if prev:
            out.append(prev)
    return out


def build_deferred_preview_items(deferred_plan: list[dict]) -> list[dict]:
    """
    Yaşam satırları: madde yazılı ama Bakım adımı değil — kullanıcı şimdi uygulamaz.
    """
    items: list[dict] = []
    for i, p in enumerate(deferred_plan or [], start=2):
        label = p.get("label") or concern_label_tr(str(p.get("id") or ""))
        action = (p.get("action") or "").strip()
        if not action:
            continue
        items.append({
            "time": "Günlük",
            "category": "Yaşam",
            "icon": "⏳",
            "action": f"Sonra (#{i}): {label} → {action}",
            "detail": (
                f"{label} maddesi şimdilik planlandı; "
                f"mevcut odakta en az ~{max(1, FOCUS_MIN_DAYS // 7)} hafta + check-in’de "
                "«sorun çözüldü» sonrası rutine eklenir. "
                "Şimdi alma veya kullanma."
            ),
            "usage": "Bu satır bilgi amaçlıdır; mevcut odak bitmeden uygulamayın.",
            "priority": 9,
            "step_order": 90 + i,
            "concern_role": "deferred_preview",
            "deferred_id": p.get("id"),
            "deferred_status": "later",
        })
    return items


def _secondary_item(
    cid: str,
    score: int,
    blob: str,
    guards: dict,
    age_group: dict,
) -> Optional[dict]:
    from flow_engine import (
        NEW_ACTIVE_DOSES,
        PREGNANCY_EXCLUDED_OPTIONS,
        UNDEREYE_PM_EXTRA,
        _opt_meta,
        dose_tier,
        _skin_undereye_nag,
        _skin_arbutin,
        _skin_hexylresorcinol,
        _skin_licorice,
        _skin_nag_niacinamide,
        _skin_undereye_arbutin,
        _skin_undereye_licorice,
        _skin_undereye_niacinamide,
        make_equivalence_item,
        _skin_azelaic,
        _skin_bakuchiol,
        _skin_niacin_tranexamic,
        _skin_niacin_zinc,
        _skin_peptide_light,
        _skin_retinol,
        _skin_salicylic_toner,
    )

    if cid == "pigmentation":
        if any(k in blob for k in ("arbutin", "traneksamik", "heksilrezorsinol", "meyan kökü", "glukozamin")):
            return None
        ab = "(%2)" if score <= 4 else "(%2-3)"
        base = {
            "time": "Akşam",
            "category": "Bakım",
            "icon": "💎",
            "detail": (
                f"İkincil leke (şiddet {score}/10): birincil tedaviyi bozmadan akşam leke katmanı. "
                "Güçlü gece aktiflerinin olduğu akşamlarda onlar önce. Haftada 3-4 gece."
            ),
            "step_order": 22,
            "concern_role": "support_pigmentation",
        }
        excl = PREGNANCY_EXCLUDED_OPTIONS if guards.get("_pregnant") else ()
        t = dose_tier(guards, score=score)
        if t == "hassas":
            return make_equivalence_item(
                base,
                "pigment_tyrosinase",
                {"licorice": _skin_licorice("hassas"), "alfa_arbutin": _skin_arbutin(ab)},
                default="licorice",
                option_extra={"licorice": _opt_meta("licorice", "hassas")},
            )
        if score <= 6:
            return make_equivalence_item(
                base,
                "pigment_tyrosinase",
                {
                    "alfa_arbutin": _skin_arbutin(ab),
                    "hexylresorcinol": _skin_hexylresorcinol(t),
                    "licorice": _skin_licorice(t),
                },
                default="hexylresorcinol",
                exclude=excl,
                option_extra={
                    "hexylresorcinol": _opt_meta(
                        "hexylresorcinol", t,
                        NEW_ACTIVE_DOSES["hexylresorcinol"]["rinse_off_note"] if t != "hassas" else "",
                    ),
                    "licorice": _opt_meta("licorice", t),
                },
            )
        return make_equivalence_item(
            base,
            "pigment_niacinamide_partner",
            {"niacinamide_txa": _skin_niacin_tranexamic(), "nag_niacinamide": _skin_nag_niacinamide()},
            exclude=excl,
            option_extra={"nag_niacinamide": {"frequency_note": NEW_ACTIVE_DOSES["nag"]["synergy"]["freq"]}},
        )

    if cid == "undereye":
        if "göz çevresi" in blob:
            return None
        return make_equivalence_item(
            {
                "time": "Akşam",
                "category": "Bakım",
                "icon": "👁️",
                "detail": f"İkincil göz altı koyuluğu (şiddet {score}/10): göz çevresine nazik tek katman.",
                "usage": "Gece kreminden önce, kemik çizgisine pirinç tanesi kadar; yüzük parmağıyla tapla.",
                "step_order": 27,
                "concern_role": "support_undereye",
            },
            "undereye_pm",
            {
                "undereye_niacinamide": _skin_undereye_niacinamide(),
                "undereye_licorice": _skin_undereye_licorice(),
                "undereye_arbutin": _skin_undereye_arbutin(),
                "undereye_nag": _skin_undereye_nag(),
            },
            default=(
                "undereye_licorice"
                if dose_tier(guards, score=score) == "hassas"
                else "undereye_niacinamide"
            ),
            option_extra=UNDEREYE_PM_EXTRA,
        )

    if cid == "dryness":
        if "seramid" in blob or "squalane" in blob or "skualan" in blob:
            return None
        return {
            "time": "Akşam",
            "category": "Bakım",
            "icon": "🧴",
            "action": "Seramid NP/AP/EOP + squalane onarım serumu (INCI: Ceramide NP vb. + skualan)",
            "detail": (
                f"İkincil kuruluk (şiddet {score}/10): aktiflerden sonra bariyer; "
                "asiti artırmadan nem kaybını kes."
            ),
            "step_order": 28,
        }

    if cid == "aging":
        if "retinol" in blob or "bakuchiol" in blob or "peptid" in blob:
            return None
        if guards.get("avoid_retinol") or not age_group.get("retinol_ok"):
            return {
                "time": "Akşam",
                "category": "Bakım",
                "icon": "🌿",
                "action": _skin_peptide_light() if score < 7 else _skin_bakuchiol(),
                "detail": (
                    f"İkincil yaşlanma (şiddet {score}/10): retinol bu planda diğer sorunu "
                    "kötüleştireceği için peptid/bakuchiol. Haftada 3 gece."
                ),
                "step_order": 22,
            }
        cap = guards.get("max_retinol") or "0.3"
        return {
            "time": "Akşam",
            "category": "Bakım",
            "icon": "🔬",
            "action": _skin_retinol(f"%{cap}" if not str(cap).startswith("%") else cap),
            "detail": (
                f"İkincil yaşlanma (şiddet {score}/10): düşük retinol, BHA/AHA ile aynı gece yok. "
                "Haftada 2 gece; günler sistem atar."
            ),
            "step_order": 22,
        }

    if cid == "acne":
        if "azelaik" in blob or "benzoil" in blob:
            return None
        return {
            "time": "Akşam",
            "category": "Bakım",
            "icon": "🎯",
            "action": _skin_azelaic("%10-15"),
            "detail": (
                f"İkincil akne (şiddet {score}/10): BHA yığmadan azelaik (akne+leke dostu). "
                "Haftada 2-3 gece."
            ),
            "step_order": 22,
        }

    if cid == "oiliness":
        if "çinko" in blob or "cinko" in blob or "zinc" in blob:
            return None
        return {
            "time": "Akşam",
            "category": "Bakım",
            "icon": "💧",
            "action": _skin_niacin_zinc(),
            "detail": (
                f"İkincil yağlılık (şiddet {score}/10): sebum için çinko/niasinamid; "
                "ekstra asit yok."
            ),
            "step_order": 25,
        }

    if cid == "pores":
        if "salisilik" in blob:
            return None
        pct, n = bha_for_pores(score, guards)
        return {
            "time": "Akşam",
            "category": "Bakım",
            "icon": "🕳️",
            "action": _skin_salicylic_toner(pct),
            "detail": (
                f"İkincil gözenek (şiddet {score}/10): komedon için BHA %{pct:g}, haftada {n} gece. "
                "İnflamatuvar akne protokolü eklenmedi."
            ),
            "step_order": 20,
        }

    return None
