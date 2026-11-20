"""Kullanıcının kendi rutin düzenlemeleri.

Rebi'nin ürettiği rutin motorun kararıdır; istemci onu yeniden yazamaz. Kullanıcı yalnızca iki şey yapar:

  * **çıkarma** — yapmayacağı adımı planından kaldırır (silinmez, `skipped_by_user` işaretlenir; geri alınabilir),
  * **ekleme** — kendi adımını yazar (`source: "user"`), Rebi'nin önerisi gibi gösterilmez.

İkisi de aynı `routines.active_routine` dizisinde durur: şema değişmez, eski istemciler diziyi okumaya devam eder
(bilmedikleri alanları yok sayarlar) ve kullanıcının çıkardığı adımın özgün metni kaybolmaz.
"""

from __future__ import annotations

from typing import Any

# Kullanıcı en çok bu kadar kendi adımını ekleyebilir (plan okunabilir kalsın, satır sınırsız büyümesin).
MAX_USER_STEPS = 10
MAX_ACTION_CHARS = 90
MAX_DETAIL_CHARS = 240

# Kullanıcı adımının yazabileceği alanlar; gerisi (kanonik id, haftalık günler, seçenekler) motora aittir.
_USER_TIMES = ("Sabah", "Akşam", "Günlük")


def step_key(item: dict) -> str:
    """Bir rutin adımının kalıcı kimliği. İstemci de aynı kuralı kullanır (mobil `routineStepKey`)."""
    if not isinstance(item, dict):
        return ""
    time = str(item.get("time") or "").strip()
    order = item.get("step_order")
    order_text = "" if order is None else str(order)
    action = str(item.get("action") or "").strip()
    return f"{time}|{order_text}|{action}"


def is_user_step(item: Any) -> bool:
    return isinstance(item, dict) and str(item.get("source") or "") == "user"


def is_skipped(item: Any) -> bool:
    return isinstance(item, dict) and item.get("skipped_by_user") is True


def split_user_edits(items: Any) -> tuple[list[dict], list[dict]]:
    """(yürürlükteki adımlar, kullanıcının çıkardığı adımlar). Çıkarılanlar plana ve hatırlatıcılara girmez."""
    rows = [i for i in (items or []) if isinstance(i, dict)]
    effective = [i for i in rows if not is_skipped(i)]
    skipped = [i for i in rows if is_skipped(i)]
    return effective, skipped


def _clean_user_step(raw: Any) -> dict | None:
    if not isinstance(raw, dict):
        return None
    action = str(raw.get("action") or "").strip()[:MAX_ACTION_CHARS]
    if not action:
        return None
    time = str(raw.get("time") or "").strip()
    if time not in _USER_TIMES:
        time = "Sabah"
    detail = str(raw.get("detail") or "").strip()[:MAX_DETAIL_CHARS]
    # Kullanıcı adımı motorun sıralamasının sonuna gelir; kendi arasında eklenme sırasını korur.
    return {
        "time": time,
        "category": "Bakım",
        "icon": "✍️",
        "step_order": 95,
        "action": action,
        "detail": detail,
        "source": "user",
    }


def apply_routine_edits(items: Any, *, hidden: Any = None, added: Any = None) -> list[dict]:
    """
    Motorun rutinine kullanıcının düzenlemelerini uygular ve kaydedilecek yeni diziyi döndürür.

    `hidden`: çıkarılacak adımların `step_key` listesi — listede olmayan adımların işareti kalkar, yani
    aynı çağrı hem çıkarmayı hem geri almayı anlatır (istemci her zaman tam listeyi gönderir).
    `added`: kullanıcının kendi adımları; motorun adımlarının yerini almaz, yanına eklenir.
    """
    hidden_keys = {str(k) for k in (hidden or []) if str(k).strip()}
    engine_items: list[dict] = []
    for item in (items or []):
        if not isinstance(item, dict) or is_user_step(item):
            continue
        row = dict(item)
        if step_key(row) in hidden_keys:
            row["skipped_by_user"] = True
        else:
            row.pop("skipped_by_user", None)
        engine_items.append(row)

    user_items: list[dict] = []
    for raw in (added or []):
        step = _clean_user_step(raw)
        if step is None:
            continue
        user_items.append(step)
        if len(user_items) >= MAX_USER_STEPS:
            break

    return engine_items + user_items
