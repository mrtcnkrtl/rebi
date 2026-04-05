"""
Günlük check-in: daily_logs geçmişi + bugünkü cevaplarla uyku, stres, makyaj carryover.
Su ayrıca hydration_window ile; burada tamamlayıcı faktörler.
"""

from __future__ import annotations

from datetime import date
from typing import Any, Optional

# Su modülü ile aynı harman oranları
W_TODAY = 0.5
W_YESTERDAY = 0.35
W_WEEK = 0.15

MAKEUP_CARRY_CONCERNS = frozenset({"acne", "pigmentation", "sensitivity", "aging"})


def get_checkin_extras_from_log_row(row: dict) -> dict:
    """daily_logs satırından checkin_extras (yoksa {})."""
    return _extras_from_row(row)


def fetch_past_daily_logs(
    supabase: Any,
    user_id: str,
    before_log_date: str,
    limit: int = 14,
) -> list[dict]:
    """before_log_date (YYYY-MM-DD) — bu tarihten önceki kayıtlar, en yeni önce."""
    if not supabase:
        return []
    try:
        r = (
            supabase.table("daily_logs")
            .select("log_date,sleep_hours,stress_level,adaptation")
            .eq("user_id", user_id)
            .lt("log_date", before_log_date)
            .order("log_date", desc=True)
            .limit(limit)
            .execute()
        )
        return r.data or []
    except Exception:
        return []


def _extras_from_row(row: dict) -> dict:
    ad = row.get("adaptation") or {}
    if not isinstance(ad, dict):
        return {}
    ex = ad.get("checkin_extras")
    return ex if isinstance(ex, dict) else {}


def blend_sleep_hours(
    today_sleep: float,
    past_rows: list[dict],
) -> tuple[float, str]:
    vals: list[float] = []
    for row in past_rows:
        s = row.get("sleep_hours")
        if s is None:
            continue
        try:
            vals.append(float(s))
        except (TypeError, ValueError):
            pass
    if not vals:
        return float(today_sleep), "uyku: yalnız bugün"

    y = vals[0]
    rest = vals[1:6]
    mean_rest = sum(rest) / len(rest) if rest else y
    eff = W_TODAY * float(today_sleep) + W_YESTERDAY * y + W_WEEK * mean_rest
    return max(0.0, float(eff)), f"uyku efektif {eff:.1f}s (bugün {today_sleep}, dün {y})"


def blend_stress_mapped(
    stress_today_1_5: int,
    past_rows: list[dict],
) -> tuple[int, str]:
    """Risk skoruna giren stres 2–10 aralığı (mevcut API ile uyumlu)."""
    today_m = max(2, min(10, int(stress_today_1_5) * 2))
    hist_m: list[int] = []
    for row in past_rows:
        sl = row.get("stress_level")
        if sl is None:
            continue
        try:
            v = int(sl)
            hist_m.append(max(2, min(10, v * 2)))
        except (TypeError, ValueError):
            pass
    if not hist_m:
        return today_m, "stres: yalnız bugün"

    y = hist_m[0]
    rest = hist_m[1:6]
    mean_rest = sum(rest) / len(rest) if rest else y
    eff = W_TODAY * today_m + W_YESTERDAY * y + W_WEEK * mean_rest
    eff_i = max(2, min(10, int(round(eff))))
    return eff_i, f"stres efektif {eff_i}/10 (bugün×2={today_m}, dün×2={y})"


def effective_makeup_with_history(
    concern: str,
    profile_mf: int,
    profile_mr: str,
    makeup_used_today: Optional[bool],
    makeup_removal_today: Optional[str],
    past_rows: list[dict],
) -> tuple[int, str, Optional[str]]:
    """
    Bugünkü cevap + geçmiş checkin_extras ile makyaj risk girdileri.
    Dönüş: (makeup_frequency, makeup_removal, not)
    """
    mf = int(profile_mf or 0)
    mr = str(profile_mr or "cleanser").lower().strip()
    if mr not in ("none", "water", "cleanser", "double"):
        mr = "cleanser"

    if makeup_used_today is not None:
        if not makeup_used_today:
            return 0, "cleanser", None
        if makeup_removal_today:
            m = (makeup_removal_today or "").lower().strip()
            if m in ("none", "water", "cleanser", "double"):
                mr = m
        return mf, mr, None

    recent_bad = False
    any_recent_makeup = False
    for row in past_rows[:7]:
        ex = _extras_from_row(row)
        if ex.get("makeup_used_today") is True:
            any_recent_makeup = True
            rmr = (ex.get("makeup_removal_today") or "").lower()
            if rmr in ("none", "water"):
                recent_bad = True

    note = None
    c = (concern or "").lower().strip()
    if c in MAKEUP_CARRY_CONCERNS and any_recent_makeup and recent_bad and mf > 0:
        mr = "water"
        note = (
            "Son kayıtlarda makyaj sonrası zayıf temizlik izi var; bugün cevap verilmediği için "
            "risk hesabında geçici olarak daha temkinli temizlik varsayımı kullanıldı."
        )

    return mf, mr, note


def build_carryover_notes(
    sleep_note: str,
    stress_note: str,
    makeup_note: Optional[str],
    hydration_note: Optional[str],
) -> str:
    parts = [sleep_note, stress_note]
    if makeup_note:
        parts.append(makeup_note)
    if hydration_note:
        parts.append(f"Hydrasyon: {hydration_note}")
    return " | ".join(p for p in parts if p)
