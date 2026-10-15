"""Compose'taki push-cron yan servisinin saf mantığı."""

from __future__ import annotations

import io
import json
import urllib.error

import push_cron


class _Response(io.BytesIO):
    def __enter__(self):
        return self

    def __exit__(self, *_):
        return False


def _opener(payload=None, error=None, capture=None):
    def open_(request, timeout):
        if capture is not None:
            capture.append({"request": request, "timeout": timeout})
        if error is not None:
            raise error
        return _Response(json.dumps(payload).encode("utf-8"))

    return open_


def test_next_tick_is_aligned_to_the_interval():
    # 12:03:20 → :05'e 100 sn
    assert push_cron.seconds_until_next_tick(12 * 3600 + 3 * 60 + 20, 300) == 100
    # Tam sınırda tam aralık beklenir (aynı turu iki kez koşmasın).
    assert push_cron.seconds_until_next_tick(12 * 3600 + 5 * 60, 300) == 300


def test_dispatch_sends_the_secret_header_with_post():
    seen = []
    result = push_cron.dispatch_once(
        "http://api:8000/push/dispatch", "s3cret", _opener({"reminders_sent": 2}, capture=seen)
    )

    assert result == {"reminders_sent": 2}
    request = seen[0]["request"]
    assert request.get_method() == "POST"
    assert request.get_header("X-push-dispatch-token") == "s3cret"
    assert seen[0]["timeout"] == push_cron.REQUEST_TIMEOUT_SECONDS


def test_a_rejected_or_unreachable_dispatch_returns_none_instead_of_raising():
    http_error = urllib.error.HTTPError("http://x", 401, "Unauthorized", {}, None)

    assert push_cron.dispatch_once("http://x", "bad", _opener(error=http_error)) is None
    assert push_cron.dispatch_once("http://x", "k", _opener(error=OSError("ağ yok"))) is None
    assert push_cron.dispatch_once("http://x", "k", _opener(payload=["liste"])) is None


def test_summary_line_flags_unconfigured_push_and_the_user_cap():
    assert "yapılandırılmamış" in push_cron.describe({"push_configured": False})

    line = push_cron.describe(
        {"users_considered": 3, "reminders_sent": 2, "notifications_sent": 4, "deliveries_failed": 1}
    )
    assert "kullanıcı=3" in line and "bildirim=4" in line and "başarısız=1" in line
    assert "UYARI" not in line

    assert "UYARI" in push_cron.describe({"users_considered": 1000, "push_configured": True})
