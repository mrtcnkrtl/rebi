"""
Son N günlük su takibinden risk için efektif litre türetir.
Dün / hafta ortalaması bugünkü anlık değerle harmanlanır (carryover).
"""

from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta
from typing import Any, Optional

# Pencere uzunluğu (takvim günü)
WINDOW_DAYS = 7

# Bugün ağırlığı; kalanı dün + hafta ortalamasına bölünür
WEIGHT_TODAY = 0.5
WEIGHT_YESTERDAY = 0.35
WEIGHT_WEEK_MEAN = 0.15


def dates_in_window(end: date, n: int = WINDOW_DAYS) -> list[str]:
    """En yeni gün önce: [bugün, dün, ..., n-1 gün önce] ISO string."""
    out = []
    for i in range(n):
        out.append((end - timedelta(days=i)).isoformat())
    return out


def water_liters_from_day_events(events: list[dict]) -> Optional[float]:
    """En az bir water_intake olayı varsa toplam ml -> L; yoksa None."""
    if not events:
        return None
    total_ml = 0
    seen = 0
    for ev in events:
        if (ev.get("type") or "").lower() != "water_intake":
            continue
        seen += 1
        payload = ev.get("payload") or {}
        try:
            total_ml += int(payload.get("ml", 0) or 0)
        except (TypeError, ValueError):
            pass
    if seen == 0:
        return None
    return max(0.0, total_ml / 1000.0)


def load_water_series_7d(
    user_id: str,
    end: date,
    supabase: Any,
    mem_daily_events: dict,
    use_remote: bool,
) -> list[tuple[str, Optional[float]]]:
    """
    [bugün..] sırasıyla (ISO tarih, litre | None).
    Uzak tablo + bellek birleşimi: gün başına önce DB, yoksa mem.
    """
    date_strs = dates_in_window(end)
    by_date: dict[str, list[dict]] = defaultdict(list)

    if use_remote and supabase:
        try:
            r = (
                supabase.table("daily_events")
                .select("log_date,event_time,type,payload,source")
                .eq("user_id", user_id)
                .in_("log_date", date_strs)
                .order("event_time", desc=False)
                .execute()
            )
            for row in r.data or []:
                ld = row.get("log_date")
                if ld:
                    by_date[str(ld)].append(row)
        except Exception:
            pass

    out: list[tuple[str, Optional[float]]] = []
    for d in date_strs:
        remote = by_date.get(d) or []
        local = mem_daily_events.get((user_id, d), []) if mem_daily_events else []
        merged = remote if remote else local
        out.append((d, water_liters_from_day_events(merged)))
    return out


def compute_effective_water_liters(
    profile_liters: float,
    series_newest_first: list[tuple[str, Optional[float]]],
) -> tuple[float, str]:
    """
    series_newest_first: [(log_date, litres | None), ...]
    None = o gün hiç water_intake olayı yok (bilinmiyor).

    Takip yoksa veya tek gün veri: mevcut davranışa yakın (profil / bugün).
    """
    profile_liters = max(0.0, float(profile_liters or 0.0))

    if not series_newest_first:
        return profile_liters, "profil su hedefi (takip verisi yok)"

    # Bilinen günler: sadece su olayı olanlar
    known: list[float] = []
    for _, litres in series_newest_first:
        if litres is not None:
            known.append(max(0.0, float(litres)))

    today_l = series_newest_first[0][1]
    yesterday_l = series_newest_first[1][1] if len(series_newest_first) > 1 else None

    # Bugün için baz: takip varsa bugünkü L, yoksa profil
    base_today = today_l if today_l is not None else profile_liters

    if not known:
        return profile_liters, "profil su hedefi (son 7 günde su takibi yok)"

    # Tek gün veri: hafif carryover yok, bugünkü veya profil
    if len(known) == 1:
        eff = base_today
        return eff, "yalnızca bir gün su takibi; anlık değer kullanıldı"

    week_mean = sum(known) / len(known)
    y_comp = yesterday_l if yesterday_l is not None else week_mean

    effective = (
        WEIGHT_TODAY * base_today
        + WEIGHT_YESTERDAY * y_comp
        + WEIGHT_WEEK_MEAN * week_mean
    )
    effective = max(0.0, float(effective))

    note = (
        f"efektif su {effective:.2f}L (bugün {base_today:.2f}L, dün {y_comp:.2f}L, "
        f"{len(known)} gün takip ort. {week_mean:.2f}L)"
    )
    return effective, note
