"""
Sohbet turu için kota rezervasyonu: ücretsiz günlük ve Plus aylık kotayı tek arayüzde toplar.

Kullanım (uç noktada):

    reservation = reserve_chat_turn(user_id, plus=plus, plus_capped=capped)
    if reservation.exceeded:            # "free_daily" | "plus_monthly": hak yok, hiçbir şey harcanmadı
        return <kota doldu yanıtı>
    hold = reservation.hold             # None: sınırsız Plus, kota yok
    with hold or nullcontext():         # istisna çıkarsa hak otomatik iade edilir
        reply = <model çağrısı>
        if hold and <yanıt hata gibi>:
            hold.release()              # başarısız tur kullanıcının hakkından düşmez

Hak, model çağrısından ÖNCE atomik olarak alınır; kontrol ile artırma arasında boşluk yoktur.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Callable, Optional

from config import get_logger
from free_chat_quota import free_chat_release, free_chat_reserve
from plus_chat_quota import plus_chat_release, plus_chat_reserve

log = get_logger("chat_quota")


class QuotaHold:
    """Rezerve edilmiş tek bir sohbet hakkı. `release()` birden çok kez çağrılsa da hak bir kez iade edilir."""

    def __init__(self, release_fn: Callable[[], None]) -> None:
        self._release_fn = release_fn
        self._released = False

    @property
    def released(self) -> bool:
        return self._released

    def release(self) -> None:
        if self._released:
            return
        self._released = True
        try:
            self._release_fn()
        except Exception as e:
            # İade başarısızsa kullanıcı bir hak kaybeder (güvenli yön); asıl hatayı gizlemeyelim.
            log.error("Kota iadesi yapılamadı: %s", type(e).__name__)

    def __enter__(self) -> "QuotaHold":
        return self

    def __exit__(self, exc_type, exc, tb) -> bool:
        if exc_type is not None:
            self.release()
        return False


@dataclass(frozen=True)
class QuotaReservation:
    hold: Optional[QuotaHold] = None
    # None: hak alındı (ya da kota yok). "free_daily" / "plus_monthly": kota doldu, hiçbir şey harcanmadı.
    exceeded: Optional[str] = None


def reserve_chat_turn(user_id: str, *, plus: bool, plus_capped: bool) -> QuotaReservation:
    """Kullanıcının planına göre bir sohbet hakkı rezerve eder."""
    uid = (user_id or "").strip()
    if not plus:
        ticket = free_chat_reserve(uid)
        if ticket is None:
            return QuotaReservation(exceeded="free_daily")
        return QuotaReservation(hold=QuotaHold(lambda: free_chat_release(uid, ticket)))
    if plus_capped:
        ticket = plus_chat_reserve(uid)
        if ticket is None:
            return QuotaReservation(exceeded="plus_monthly")
        return QuotaReservation(hold=QuotaHold(lambda: plus_chat_release(uid, ticket)))
    return QuotaReservation()
