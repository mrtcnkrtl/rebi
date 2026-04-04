"""
Demo kullanıcılar: auth.users satırı olmadan çalışan istemci id'leri.
Bu id'ler için Supabase tablo yazımları atlanır (FK hatası önlenir).
Check-in mükerreri aynı süreç içinde bellekte tutulur.
"""

from __future__ import annotations

import os
from typing import Set, Tuple

# Frontend src/lib/demoUser.js ile aynı olmalı
_DEFAULT_DEMO_IDS = "00000000-0000-4000-8000-000000000001,demo-user-id,demo"

_MEM_DEMO_CHECKIN_DAYS: Set[Tuple[str, str]] = set()


def demo_user_ids() -> frozenset[str]:
    raw = os.getenv("API_DEMO_USER_IDS", _DEFAULT_DEMO_IDS)
    return frozenset(x.strip() for x in raw.split(",") if x.strip())


def is_demo_user_id(user_id: object) -> bool:
    if user_id is None:
        return False
    return str(user_id).strip() in demo_user_ids()


def should_use_supabase_db(supabase_client, user_id: str) -> bool:
    """Gerçek kullanıcı + yapılandırılmış istemci: uzak DB; demo veya istemci yok: hayır."""
    if not supabase_client:
        return False
    return not is_demo_user_id(user_id)


def demo_checkin_already_today(user_id: str, log_date: str) -> bool:
    return (str(user_id).strip(), str(log_date)) in _MEM_DEMO_CHECKIN_DAYS


def demo_checkin_mark(user_id: str, log_date: str) -> None:
    _MEM_DEMO_CHECKIN_DAYS.add((str(user_id).strip(), str(log_date)))
