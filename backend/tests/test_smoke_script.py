"""`scripts/smoke_mobile_api.py` gerçek bir HTTP sunucusuna karşı çalışır (sahte Supabase ile).

Duman testi canlı sunucuda tek seferlik çalıştırılacağı için kendisi de çürümemeli: burada yerel
bir uvicorn'a karşı hem okuma hem yazma yolu uçtan uca denenir.
"""

from __future__ import annotations

import importlib.util
import socket
import threading
import time
from pathlib import Path

import jwt
import pytest
import uvicorn

import main
from tests.test_contract import SECRET, USER_ID, _seed

SCRIPT = Path(__file__).resolve().parents[2] / "scripts" / "smoke_mobile_api.py"


def _load_script():
    spec = importlib.util.spec_from_file_location("smoke_mobile_api", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@pytest.fixture
def server(monkeypatch):
    monkeypatch.setenv("SUPABASE_JWT_SECRET", SECRET)
    monkeypatch.delenv("API_ALLOW_INSECURE_AUTH", raising=False)
    _seed(monkeypatch)

    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()

    config = uvicorn.Config(main.app, host="127.0.0.1", port=port, log_level="warning")
    instance = uvicorn.Server(config)
    thread = threading.Thread(target=instance.run, daemon=True)
    thread.start()
    deadline = time.monotonic() + 10
    while not instance.started and time.monotonic() < deadline:
        time.sleep(0.05)
    assert instance.started, "yerel sunucu açılmadı"
    yield f"http://127.0.0.1:{port}"
    instance.should_exit = True
    thread.join(timeout=10)


def _token() -> str:
    return jwt.encode({"sub": USER_ID, "aud": "authenticated"}, SECRET, algorithm="HS256")


def test_smoke_script_passes_end_to_end_including_the_write_path(server, capsys):
    script = _load_script()

    code = script.run(server, _token(), write=True)
    out = capsys.readouterr().out

    assert code == 0, out
    assert "KALDI" not in out
    assert "GET /today/plan" in out and "PUT /me/reminder-settings" in out
    assert "aynı olay tekrar gönderilince çift sayılmaz" in out


def test_smoke_script_reports_a_broken_contract(server, monkeypatch, capsys):
    script = _load_script()
    original = main._aggregate_daily_events

    def renamed(events):
        agg = original(events)
        agg["water_total"] = agg.pop("water_ml_total")  # mobilin okuduğu alan yeniden adlandırıldı
        return agg

    monkeypatch.setattr(main, "_aggregate_daily_events", renamed)

    code = script.run(server, _token(), write=False)
    out = capsys.readouterr().out

    assert code == 1
    assert "water_ml_total: alan yok" in out


def test_user_id_is_read_from_the_token():
    assert _load_script().user_id_from_token(_token()) == USER_ID
