"""
Endişe tipine göre check-in ek alanları: bugünkü cevaplar + geçmiş kayıtlarda tekrar eden örüntüler.
compute_risk_score sonrası puana sınırlı ekler; seviye yeniden hesaplanır.
"""

from __future__ import annotations

from typing import Any, List, Tuple

from checkin_carryover import get_checkin_extras_from_log_row


def _level_from_score(score: int) -> tuple[str, str]:
    if score >= 13:
        return "crisis", "KRİZ MODU"
    if score >= 8:
        return "high", "Yüksek Risk"
    if score >= 4:
        return "moderate", "Orta"
    return "normal", "Normal"


def _today_extra_delta(concern: str, req: Any) -> Tuple[int, List[str]]:
    c = (concern or "").lower().strip()
    delta = 0
    notes: List[str] = []

    if c == "acne":
        if getattr(req, "picked_skin_today", None) is True:
            delta += 1
            notes.append("sivilce/komedon kurcalama")
        if getattr(req, "high_glycemic_intake_today", None) is True:
            delta += 1
            notes.append("yüksek glisemik öğün")
        if getattr(req, "heavy_dairy_today", None) is True:
            delta += 1
            notes.append("belirgin süt ürünü")

    if c in ("aging", "pigmentation"):
        sun = getattr(req, "long_sun_exposure_today", None) is True
        spf = getattr(req, "spf_applied_today", None)
        if sun:
            delta += 1
            notes.append("uzun güneş maruziyeti")
        if spf is False:
            delta += 1
            notes.append("SPF uygulanmadı")
        if sun and spf is False:
            delta += 1
            notes.append("güneş + SPF yok kombinasyonu")

    if c == "dryness":
        if getattr(req, "very_dry_environment_today", None) is True:
            delta += 1
            notes.append("çok kuru ortam (ısıtma/klima)")
        if getattr(req, "long_hot_shower_today", None) is True:
            delta += 1
            notes.append("uzun sıcak duş")

    if c == "sensitivity":
        if getattr(req, "fragrance_new_product_today", None) is True:
            delta += 1
            notes.append("yeni parfüm/kokulu ürün")
        if getattr(req, "long_hot_shower_today", None) is True:
            delta += 1
            notes.append("uzun sıcak duş")

    return delta, notes


def _carryover_extra_delta(concern: str, past_logs: list, req: Any) -> Tuple[int, List[str]]:
    """Bugün ilgili soru atlandıysa (None) son kayıtlardaki tekrar."""
    c = (concern or "").lower().strip()
    delta = 0
    notes: List[str] = []
    exs = [get_checkin_extras_from_log_row(r) for r in past_logs[:7]]

    def _count_true(key: str) -> int:
        return sum(1 for e in exs if e.get(key) is True)

    def _count_false(key: str) -> int:
        return sum(1 for e in exs if e.get(key) is False)

    if c == "acne":
        if getattr(req, "high_glycemic_intake_today", None) is None and _count_true("high_glycemic_intake_today") >= 2:
            delta += 1
            notes.append("son günlerde sık yüksek glisemik kaydı")
        if getattr(req, "heavy_dairy_today", None) is None and _count_true("heavy_dairy_today") >= 2:
            delta += 1
            notes.append("son günlerde sık süt ürünü kaydı")
        if getattr(req, "picked_skin_today", None) is None and _count_true("picked_skin_today") >= 2:
            delta += 1
            notes.append("son günlerde tekrarlayan kurcalama kaydı")

    if c in ("aging", "pigmentation"):
        if getattr(req, "spf_applied_today", None) is None and _count_false("spf_applied_today") >= 2:
            delta += 1
            notes.append("son check-in'lerde SPF genelde hayır")
        if getattr(req, "long_sun_exposure_today", None) is None and _count_true("long_sun_exposure_today") >= 2:
            delta += 1
            notes.append("son günlerde sık uzun güneş kaydı")

    if c == "dryness":
        if getattr(req, "very_dry_environment_today", None) is None and _count_true("very_dry_environment_today") >= 2:
            delta += 1
            notes.append("son günlerde sık kuru ortam kaydı")
        if getattr(req, "long_hot_shower_today", None) is None and _count_true("long_hot_shower_today") >= 2:
            delta += 1
            notes.append("son günlerde sık uzun sıcak duş")

    if c == "sensitivity":
        if getattr(req, "fragrance_new_product_today", None) is None and _count_true("fragrance_new_product_today") >= 2:
            delta += 1
            notes.append("son günlerde sık yeni kokulu ürün")
        if getattr(req, "long_hot_shower_today", None) is None and _count_true("long_hot_shower_today") >= 2:
            delta += 1
            notes.append("son günlerde sık sıcak duş")

    return delta, notes


def apply_concern_extra_risk(concern: str, req: Any, past_logs: list, risk_info: dict) -> dict:
    """risk_info kopyası; puan ve seviye güncellenir."""
    out = dict(risk_info)
    d1, n1 = _today_extra_delta(concern, req)
    d2, n2 = _carryover_extra_delta(concern, past_logs, req)
    delta = d1 + d2
    all_notes = [x for x in n1 + n2 if x]
    if delta <= 0 and not all_notes:
        return out

    new_score = min(24, int(out.get("score", 0)) + delta)
    lvl, lab = _level_from_score(new_score)
    out["score"] = new_score
    out["level"] = lvl
    out["label"] = lab
    base_detail = out.get("detail") or ""
    if all_notes:
        out["detail"] = base_detail + " | Endişe ekleri: " + "; ".join(all_notes)
    else:
        out["detail"] = base_detail
    return out
