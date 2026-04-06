"""Check-in semptom etiketleri → risk skoruna sınırlı ek (doğruluk / kişiselleştirme)."""

from __future__ import annotations

from typing import Any, Optional

ALLOWED_SYMPTOM_TAGS = frozenset(
    {"redness_diffuse", "burning_stinging", "flaking_peeling", "acne_flare"}
)


def risk_level_from_score(score: int) -> tuple[str, str]:
    if score >= 13:
        return "crisis", "KRİZ MODU"
    if score >= 8:
        return "high", "Yüksek Risk"
    if score >= 4:
        return "moderate", "Orta"
    return "normal", "Normal"


def apply_symptom_tags_risk(risk_info: dict, tags: Optional[list]) -> dict:
    """risk_info kopyası; geçerli semptom etiketlerine göre puan eklenir (üst sınırlı)."""
    out = dict(risk_info)
    if not tags:
        return out

    delta = 0
    notes: list[str] = []
    for raw in tags:
        t = str(raw or "").strip().lower()
        if t not in ALLOWED_SYMPTOM_TAGS:
            continue
        if t == "burning_stinging":
            delta += 2
            notes.append("yanma/batma")
        elif t == "redness_diffuse":
            delta += 1
            notes.append("yaygın kızarıklık")
        elif t == "flaking_peeling":
            delta += 1
            notes.append("pul pul / soyulma")
        elif t == "acne_flare":
            delta += 1
            notes.append("sivilce alevlenmesi")

    delta = min(5, delta)
    if delta <= 0:
        return out

    new_score = min(24, int(out.get("score", 0)) + delta)
    lvl, lab = risk_level_from_score(new_score)
    out["score"] = new_score
    out["level"] = lvl
    out["label"] = lab
    base = out.get("detail") or ""
    suffix = " | Semptomlar: " + "; ".join(notes)
    out["detail"] = (base + suffix).strip()
    return out


def normalize_symptom_tags(tags: Any) -> list[str]:
    if not tags:
        return []
    if not isinstance(tags, list):
        return []
    out: list[str] = []
    for x in tags:
        t = str(x or "").strip().lower()
        if t in ALLOWED_SYMPTOM_TAGS and t not in out:
            out.append(t)
    return out[:8]


def apply_tracking_risk_bonus(risk_info: dict, tracking_today: Optional[dict]) -> dict:
    """Gün içi olumlu sinyaller: SPF yenileme / rutin adım tamamlama → hafif risk düşüşü."""
    out = dict(risk_info)
    tt = tracking_today or {}
    if not isinstance(tt, dict):
        return out
    try:
        spf = int(tt.get("spf_refreshes") or 0)
    except Exception:
        spf = 0
    try:
        steps = int(tt.get("routine_steps_done") or 0)
    except Exception:
        steps = 0
    delta = 0
    notes: list[str] = []
    if spf >= 1:
        delta -= 1
        notes.append("gün içi SPF yenileme")
    if steps >= 1:
        delta -= 1
        notes.append("rutin adımı işaretlendi")
    if delta >= 0:
        return out
    new_score = max(0, int(out.get("score", 0)) + delta)
    lvl, lab = risk_level_from_score(new_score)
    out["score"] = new_score
    out["level"] = lvl
    out["label"] = lab
    base = out.get("detail") or ""
    if notes:
        out["detail"] = (base + " | Takip: " + "; ".join(notes)).strip()
    return out
