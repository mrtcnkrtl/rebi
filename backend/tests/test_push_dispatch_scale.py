"""Push dağıtıcısı ölçekte: sayfalama, toplu sorgular, süre bütçesi, devam etme, hata durumunda susma."""

from __future__ import annotations

import asyncio
import uuid
from datetime import datetime, timedelta, timezone

import pytest

import main
import rate_limit
from tests.fake_supabase import FakeSupabase, FakeTable

DISPATCH_SECRET = "dispatch-secret-abcdefghijklmnop"


def _uid(i: int) -> str:
    """Sıralı, deterministik kullanıcı kimlikleri (kimliğe göre sıralama sayfalamayı sınar)."""
    return str(uuid.UUID(int=i + 1))


def _offset_for(hhmm: str) -> int:
    """Cihazın yerel saatini istenen değere getiren UTC farkı (dakika)."""
    now = datetime.now(timezone.utc)
    target = int(hhmm[:2]) * 60 + int(hhmm[3:])
    delta = (target - (now.hour * 60 + now.minute)) % 1440
    return delta - 1440 if delta > 720 else delta


def _device(i: int, offset: int, token: str | None = None, seen: str = "2026-10-04T10:00:00+00:00") -> dict:
    return {
        "user_id": _uid(i),
        "token": token or f"tok-{i}",
        "platform": "android",
        "utc_offset_minutes": offset,
        "push_enabled": True,
        "last_seen_at": seen,
    }


class _Sender:
    def __init__(self, delay: float = 0.0, fail_tokens: tuple[str, ...] = (), dead_tokens: tuple[str, ...] = ()):
        self.calls: list[dict] = []
        self.delay = delay
        self.fail_tokens = fail_tokens
        self.dead_tokens = dead_tokens
        self.in_flight = 0
        self.max_in_flight = 0

    async def __call__(self, tokens, title, body, data=None):
        self.in_flight += 1
        self.max_in_flight = max(self.max_in_flight, self.in_flight)
        try:
            if self.delay:
                await asyncio.sleep(self.delay)
            self.calls.append({"tokens": list(tokens), "data": dict(data or {})})
            if any(t in self.fail_tokens for t in tokens):
                raise RuntimeError("FCM çöktü")
            dead = [t for t in tokens if t in self.dead_tokens]
            if dead:
                return {"status": "sent", "sent": 0, "invalid_tokens": dead}
            return {"status": "sent", "sent": 1, "invalid_tokens": []}
        finally:
            self.in_flight -= 1


@pytest.fixture
def setup(monkeypatch):
    """Dağıtıcıyı açar, devam imlecini ve önbellekleri sıfırlar; (kur, gönder) çiftini döner."""
    monkeypatch.setenv("PUSH_DISPATCH_SECRET", DISPATCH_SECRET)
    monkeypatch.setattr(main, "push_configured", lambda: True)
    main._PUSH_CURSOR["after"] = None
    main._WEATHER_CACHE.clear()
    main._PUSH_LAST_RUN.clear()
    # Uç IP başına dakikada 30 istekle sınırlı; testlerimiz bu sayacı doldurup diğer dosyaları 429'a sürüklemesin.
    rate_limit.LIMIT_PUSH_DISPATCH._hits.clear()

    def install(devices, sender=None, ledger_unique=True, **tables) -> tuple[FakeSupabase, _Sender]:
        sender = sender or _Sender()
        monkeypatch.setattr(main, "send_push", sender)
        db = FakeSupabase(
            device_tokens=devices,
            push_sends=[],
            daily_events=[],
            daily_logs=[],
            reminder_settings=[],
            **tables,
        )
        if ledger_unique:
            db.tables["push_sends"].unique_on = ("user_id", "reminder_id", "log_date", "slot")
        monkeypatch.setattr(main, "get_supabase", lambda: db)
        return db, sender

    yield install
    main._PUSH_CURSOR["after"] = None
    rate_limit.LIMIT_PUSH_DISPATCH._hits.clear()


def _run(client, **params):
    return client.post("/push/dispatch", params=params, headers={"X-Push-Dispatch-Token": DISPATCH_SECRET})


def _longest_in_filter(table: FakeTable) -> int:
    return max((len(v) for q in table.query_log for op, _c, v in q if op == "in"), default=0)


# ── Sayfa yükleyici ──────────────────────────────────────────────────────────────────────────────

def _walk(db, page_users: int) -> list[tuple[str, dict]]:
    seen: list[tuple[str, dict]] = []
    after = None
    for _ in range(1000):
        users, last, exhausted = main._load_push_page(db, after, page_users)
        seen.extend(users.items())
        if exhausted:
            return seen
        after = last
    raise AssertionError("sayfalama bitmedi")


def test_page_loader_visits_every_user_once_with_all_their_devices():
    rows = []
    for i in range(250):
        for k in range(1 + i % 3):  # kullanıcı başına 1-3 cihaz
            rows.append(_device(i, 0, token=f"tok-{i}-{k}", seen=f"2026-10-0{k + 1}T10:00:00+00:00"))
    db = FakeSupabase(device_tokens=rows)

    seen = _walk(db, 100)

    assert [uid for uid, _ in seen] == [_uid(i) for i in range(250)], "her kullanıcı bir kez ve kimlik sırasında"
    for i, (uid, entry) in enumerate(seen):
        assert len(entry["tokens"]) == 1 + i % 3, f"{uid}: cihazlar eksik ya da yarım"


def test_page_loader_never_splits_a_user_across_pages_when_a_page_fills_up(monkeypatch):
    # Kullanıcı başına en çok 2 cihaz → satır sınırı 2·N+1: sayfalar sürekli doluyor ve araya kullanıcı giriyor.
    monkeypatch.setattr(main, "_PUSH_MAX_TOKENS_PER_USER", 2)
    rows = [_device(i, 0, token=f"tok-{i}-{k}", seen=f"2026-10-0{k + 1}T10:00:00+00:00") for i in range(150) for k in range(2)]
    db = FakeSupabase(device_tokens=rows)

    seen = _walk(db, 40)

    assert [uid for uid, _ in seen] == [_uid(i) for i in range(150)]
    assert all(len(entry["tokens"]) == 2 for _, entry in seen), "bir kullanıcının cihazı iki sayfaya bölünmemeli"


def test_page_loader_takes_the_offset_from_the_most_recently_seen_device():
    db = FakeSupabase(device_tokens=[
        _device(0, 60, token="eski", seen="2026-10-01T10:00:00+00:00"),
        _device(0, 180, token="yeni", seen="2026-10-04T10:00:00+00:00"),
    ])
    (uid, entry), = _walk(db, 10)
    assert entry["offset"] == 180 and entry["tokens"] == ["yeni", "eski"]


def test_page_loader_skips_devices_with_push_off_and_resumes_after_a_cursor():
    rows = [_device(i, 0) for i in range(10)]
    rows[3]["push_enabled"] = False
    db = FakeSupabase(device_tokens=rows)

    users, last, exhausted = main._load_push_page(db, _uid(4), 100)

    assert list(users) == [_uid(i) for i in range(5, 10)]
    assert exhausted and last == _uid(9)


# ── Ölçek: binlerce kullanıcı, az sorgu ──────────────────────────────────────────────────────────

def test_thousands_of_users_are_all_served_with_a_handful_of_bulk_queries(client, setup):
    offset = _offset_for("09:05")  # su hatırlatıcısının 09:00 penceresi
    db, sender = setup([_device(i, offset) for i in range(2500)], ledger_unique=False)

    body = _run(client, max_users=5000).json()

    # Eskiden ilk 1000 kullanıcıyla sınırlıydı; kalanlar hiç bildirim almazdı.
    assert body["users_considered"] == 2500
    assert body["reminders_sent"] == 2500 and body["notifications_sent"] == 2500
    assert body["truncated"] is False and body["users_skipped"] == 0
    assert len(sender.calls) == 2500 and len({c["tokens"][0] for c in sender.calls}) == 2500
    assert len(db.tables["push_sends"].rows) == 2500

    # 25 sayfa × (≤2 parça) = en çok ~50 toplu sorgu; kullanıcı başına sorgu (2500+) yok.
    assert db.tables["device_tokens"].select_calls <= 26
    for name in ("reminder_settings", "daily_events", "daily_logs"):
        assert db.tables[name].select_calls <= 60, f"{name}: toplu okunmuyor"
        assert _longest_in_filter(db.tables[name]) <= 50, f"{name}: URL'ye çok fazla kimlik yazılıyor"


def test_a_user_with_the_old_thousand_user_cap_in_the_way_still_gets_their_reminder(client, setup):
    offset = _offset_for("09:05")
    db, sender = setup([_device(i, offset) for i in range(1100)], ledger_unique=False)

    _run(client, max_users=2000)

    assert {c["tokens"][0] for c in sender.calls} >= {"tok-1099", "tok-1000", "tok-0"}


# ── Süre bütçesi ve devam etme ───────────────────────────────────────────────────────────────────

def _fake_clock(monkeypatch, per_page: float, budget: float):
    clock = [0.0]
    monkeypatch.setattr(main, "_push_clock", lambda: clock[0])
    monkeypatch.setattr(main, "_push_budget_seconds", lambda: budget)
    original = main._dispatch_page

    def slow(*args, **kwargs):
        original(*args, **kwargs)
        clock[0] += per_page

    monkeypatch.setattr(main, "_dispatch_page", slow)
    return clock


def test_a_round_that_runs_out_of_time_is_resumed_by_the_next_one_without_gaps_or_repeats(client, setup, monkeypatch):
    offset = _offset_for("09:05")
    db, sender = setup([_device(i, offset) for i in range(500)])
    _fake_clock(monkeypatch, per_page=60, budget=100)  # bütçe 2 sayfaya yetiyor

    rounds = [_run(client, max_users=5000).json() for _ in range(3)]

    assert [r["users_considered"] for r in rounds] == [200, 200, 100]
    assert [r["truncated"] for r in rounds] == [True, True, False]
    sent = [c["tokens"][0] for c in sender.calls]
    assert sorted(sent) == sorted(f"tok-{i}" for i in range(500)), "her kullanıcı tam bir kez"
    assert main._PUSH_CURSOR["after"] is None, "tur bitince imleç baştan başlar"

    # Yeni tur baştan başlar; defter aynı hatırlatıcıların tekrar gitmesini engeller.
    again = _run(client, max_users=5000).json()
    assert again["users_considered"] == 200 and again["notifications_sent"] == 0


def test_max_users_truncates_and_an_exact_fit_does_not(client, setup):
    offset = _offset_for("09:05")
    db, sender = setup([_device(i, offset) for i in range(250)])

    first = _run(client, max_users=100).json()
    assert first["users_considered"] == 100 and first["truncated"] is True
    assert main._PUSH_CURSOR["after"] == _uid(99)

    second = _run(client, max_users=100).json()
    third = _run(client, max_users=100).json()
    assert (second["users_considered"], second["truncated"]) == (100, True)
    assert (third["users_considered"], third["truncated"]) == (50, False)
    assert len(sender.calls) == 250

    db2, _ = setup([_device(i, offset) for i in range(100)])
    exact = _run(client, max_users=100).json()
    assert exact["users_considered"] == 100 and exact["truncated"] is False, "tam sığan tur yarım sayılmaz"


def test_the_last_run_summary_in_health_carries_the_new_fields(client, setup):
    setup([_device(0, _offset_for("09:05"))])
    _run(client)
    last = client.get("/health").json()["push_dispatch"]
    assert last["truncated"] is False and last["users_skipped"] == 0 and last["users_considered"] == 1


def test_max_users_has_an_upper_bound(client, setup):
    setup([])
    assert _run(client, max_users=50001).status_code == 422
    assert _run(client, max_users=50000).status_code == 200


# ── Okunamayan veri: yanlış bildirim göndermektense sus ──────────────────────────────────────────

class _FailingTables(FakeSupabase):
    def __init__(self, failing: set[str], **tables):
        super().__init__(**tables)
        self._failing = failing

    def table(self, name):
        if name in self._failing:
            raise RuntimeError(f"{name} okunamadı")
        return super().table(name)


def _use_failing_db(monkeypatch, failing: set[str], devices):
    db = _FailingTables(failing, device_tokens=devices, push_sends=[], daily_events=[], daily_logs=[], reminder_settings=[])
    sender = _Sender()
    monkeypatch.setattr(main, "send_push", sender)
    monkeypatch.setattr(main, "get_supabase", lambda: db)
    return db, sender


def test_users_whose_day_cannot_be_read_are_skipped_not_reminded(client, setup, monkeypatch):
    setup([])
    devices = [_device(i, _offset_for("09:05")) for i in range(3)]
    db, sender = _use_failing_db(monkeypatch, {"daily_events"}, devices)

    body = _run(client).json()

    assert body["users_considered"] == 3 and body["users_skipped"] == 3
    assert sender.calls == [], "yapılmış işi tekrar hatırlatmamak için susulur"


def test_unreadable_reminder_settings_skip_the_page_instead_of_ignoring_quiet_hours(client, setup, monkeypatch):
    setup([])
    devices = [_device(i, _offset_for("09:05")) for i in range(3)]
    db, sender = _use_failing_db(monkeypatch, {"reminder_settings"}, devices)

    body = _run(client).json()

    assert body["users_skipped"] == 3 and sender.calls == []


def test_only_the_date_group_that_failed_is_skipped(client, setup, monkeypatch):
    db, sender = setup([_device(0, -840), _device(1, 840)], ledger_unique=False)
    # Her zaman farklı yerel günlerde (28 saat arayla): iki ayrı toplu okuma.
    monkeypatch.setattr(main, "due_reminders", lambda plan, now, tol, **_: [
        {"id": "water_intake", "title": "Su", "body": "İç", "slot": "09:00"}
    ])
    failing_date = (datetime.now(timezone.utc) + timedelta(minutes=840)).date().isoformat()
    original = main._load_daily_events_bulk

    def flaky(supabase, user_ids, log_date):
        if log_date == failing_date:
            raise RuntimeError("okunamadı")
        return original(supabase, user_ids, log_date)

    monkeypatch.setattr(main, "_load_daily_events_bulk", flaky)

    body = _run(client).json()

    assert body["users_considered"] == 2 and body["users_skipped"] == 1
    assert [c["tokens"] for c in sender.calls] == [["tok-0"]]


def test_a_failed_device_list_read_is_a_502_on_the_first_page(client, setup, monkeypatch):
    setup([])
    _use_failing_db(monkeypatch, {"device_tokens"}, [])
    assert _run(client).status_code == 502


def test_a_failure_on_a_later_page_keeps_what_was_done_and_resumes_there(client, setup, monkeypatch):
    offset = _offset_for("09:05")
    db, sender = setup([_device(i, offset) for i in range(250)])
    original = main._load_push_page
    calls = {"n": 0}

    def flaky(supabase, after, max_users):
        calls["n"] += 1
        if calls["n"] == 2:
            raise RuntimeError("bağlantı koptu")
        return original(supabase, after, max_users)

    monkeypatch.setattr(main, "_load_push_page", flaky)

    body = _run(client, max_users=5000).json()

    assert body["users_considered"] == 100 and body["truncated"] is True
    assert main._PUSH_CURSOR["after"] == _uid(99), "kaldığı yerden devam edecek"


# ── Gönderim: eşzamanlı ama sınırlı, biri çökse diğerleri gider ──────────────────────────────────

def test_sends_overlap_but_stay_within_the_concurrency_limit(client, setup):
    offset = _offset_for("09:05")
    sender = _Sender(delay=0.02)
    setup([_device(i, offset) for i in range(60)], sender, ledger_unique=False)

    body = _run(client).json()

    assert body["reminders_sent"] == 60
    assert 2 <= sender.max_in_flight <= main._PUSH_SEND_CONCURRENCY


def test_one_crashing_send_does_not_stop_the_rest_and_frees_its_slot(client, setup):
    offset = _offset_for("09:05")
    sender = _Sender(fail_tokens=("tok-3",))
    db, _ = setup([_device(i, offset) for i in range(8)], sender)

    body = _run(client).json()

    assert body["reminders_sent"] == 7 and body["deliveries_failed"] == 1
    claimed = {r["user_id"] for r in db.tables["push_sends"].rows}
    assert _uid(3) not in claimed and len(claimed) == 7, "başarısız olanın rezervi geri alınır: sonraki tur dener"


def test_dead_tokens_are_removed_in_bulk(client, setup):
    offset = _offset_for("09:05")
    dead = tuple(f"tok-{i}" for i in range(0, 120, 2))
    sender = _Sender(dead_tokens=dead)
    db, _ = setup([_device(i, offset) for i in range(120)], sender, ledger_unique=False)

    body = _run(client).json()

    assert body["invalid_tokens_removed"] == 60
    assert {r["token"] for r in db.tables["device_tokens"].rows} == {f"tok-{i}" for i in range(1, 120, 2)}


# ── Hava: hücre başına tek sağlayıcı çağrısı ─────────────────────────────────────────────────────

def test_weather_is_fetched_once_per_cell_and_only_for_users_who_allowed_location(client, setup, monkeypatch):
    cells = [(41.01, 28.97), (41.04, 29.01), (39.93, 32.86), (38.42, 27.14)]  # ilk ikisi aynı 0,1° hücresi
    offset = _offset_for("11:05")  # SPF/balsam saatleri: hava gün ortasında aranır
    devices, profiles, consents = [], [], []
    for i in range(40):
        lat, lon = cells[i % 4]
        devices.append(_device(i, offset))
        profiles.append({"id": _uid(i), "location_lat": lat, "location_lon": lon})
        if i % 10 != 0:  # her onuncu kullanıcı konum izni vermedi
            consents.append({"user_id": _uid(i), "location_processing_allowed": True})
    db, sender = setup(devices, profiles=profiles, privacy_preferences=consents)

    fetched: list[tuple] = []

    async def provider(lat, lon):
        fetched.append((round(lat, 1), round(lon, 1)))
        return {"temperature": 25, "humidity": 40, "uv_index": 7, "description": "Açık"}

    monkeypatch.setattr(main, "fetch_weather_live", provider)

    body = _run(client).json()

    assert body["users_considered"] == 40 and body["users_skipped"] == 0
    assert sorted(fetched) == [(38.4, 27.1), (39.9, 32.9), (41.0, 29.0)], "kullanıcı başına değil, hücre başına"


def test_a_weather_provider_outage_does_not_break_the_round(client, setup, monkeypatch):
    offset = _offset_for("11:05")
    db, sender = setup(
        [_device(0, offset)],
        profiles=[{"id": _uid(0), "location_lat": 41.0, "location_lon": 29.0}],
        privacy_preferences=[{"user_id": _uid(0), "location_processing_allowed": True}],
    )

    async def down(lat, lon):
        raise RuntimeError("sağlayıcı kapalı")

    monkeypatch.setattr(main, "fetch_weather_live", down)

    body = _run(client).json()

    assert body["users_considered"] == 1 and body["users_skipped"] == 0


# ── Toplu okuma yardımcıları ─────────────────────────────────────────────────────────────────────

def _events_table(n: int, same_time: bool = False) -> FakeTable:
    table = FakeTable([
        {"id": f"{i:06d}", "user_id": "u", "event_time": "2026-10-04T10:00:00+00:00" if same_time else f"2026-10-04T10:{i // 60:02d}:{i % 60:02d}+00:00"}
        for i in range(n)
    ])
    table.max_rows = 1000
    return table


def test_a_single_unpaged_query_silently_loses_rows_beyond_the_server_cap():
    table = _events_table(2350)
    assert len(table.select().execute().data) == 1000, "PostgREST sınırı: fazlası sessizce kesilir"


def test_fetch_paged_returns_every_row_once_past_the_server_cap():
    table = _events_table(2350)

    rows = main._fetch_paged(lambda: table.select().order("event_time").order("id"))

    assert len(rows) == 2350
    assert len({r["id"] for r in rows}) == 2350
    assert [r["id"] for r in rows] == sorted(r["id"] for r in rows)


def test_fetch_paged_is_exact_when_every_row_has_the_same_sort_key():
    table = _events_table(2100, same_time=True)

    rows = main._fetch_paged(lambda: table.select().order("event_time").order("id"))

    assert len({r["id"] for r in rows}) == 2100, "eşit event_time: benzersiz id ikinci anahtarı kayıp/tekrarı önler"


def test_fetch_paged_stops_after_one_query_for_small_results():
    table = _events_table(30)
    rows = main._fetch_paged(lambda: table.select().order("id"))
    assert len(rows) == 30 and table.select_calls == 1


def test_fetch_paged_follows_a_smaller_server_cap_when_configured(monkeypatch):
    monkeypatch.setenv("POSTGREST_MAX_ROWS", "100")
    table = _events_table(450)
    table.max_rows = 100
    rows = main._fetch_paged(lambda: table.select().order("id"))
    assert len(rows) == 450


def test_settings_are_read_in_url_safe_chunks_and_errors_are_not_swallowed():
    ids = [_uid(i) for i in range(130)]
    db = FakeSupabase(reminder_settings=[{"user_id": ids[5], "settings": {"water_target_ml": 2500}}])

    out = main._load_reminder_settings_bulk(db, ids)

    assert len(out) == 130 and out[ids[5]]["water_target_ml"] == 2500
    assert _longest_in_filter(db.tables["reminder_settings"]) <= 50
    assert db.tables["reminder_settings"].select_calls == 3

    with pytest.raises(RuntimeError):
        main._load_reminder_settings_bulk(_FailingTables({"reminder_settings"}), ids)


# ── Gönderim defteri: sayfa başına toplu yazım ───────────────────────────────────────────────────

def test_the_ledger_is_written_in_bulk_not_one_insert_per_reminder(client, setup):
    offset = _offset_for("09:05")
    db, sender = setup([_device(i, offset) for i in range(1000)])

    body = _run(client, max_users=5000).json()

    assert body["reminders_sent"] == 1000 and len(db.tables["push_sends"].rows) == 1000
    # 10 sayfa → en çok ~10 toplu yazım (eskiden 1000 ayrı ekleme).
    assert db.tables["push_sends"].upsert_calls <= 12
    assert db.tables["push_sends"].inserted == [], "satır satır ekleme yapılmamalı"


def test_already_claimed_slots_in_a_batch_are_skipped_and_the_rest_are_sent(client, setup):
    offset = _offset_for("09:05")
    db, sender = setup([_device(i, offset) for i in range(10)])
    log_date = (datetime.now(timezone.utc) + timedelta(minutes=offset)).date().isoformat()
    for i in (1, 3, 5, 7):  # bu dört kullanıcıya bu pencerede zaten gönderilmiş
        db.tables["push_sends"].rows.append(
            {"user_id": _uid(i), "reminder_id": "water_intake", "log_date": log_date, "slot": "09:00"}
        )

    body = _run(client).json()

    assert body["reminders_sent"] == 6
    assert sorted(c["tokens"][0] for c in sender.calls) == sorted(f"tok-{i}" for i in (0, 2, 4, 6, 8, 9))
    assert len(db.tables["push_sends"].rows) == 10


def test_an_unwritable_ledger_sends_nothing_instead_of_risking_duplicates(client, setup, caplog):
    offset = _offset_for("09:05")
    db, sender = setup([_device(i, offset) for i in range(5)])

    def down(*_a, **_k):
        raise RuntimeError("bağlantı koptu")

    original = db.table
    db.table = lambda name: _with(original(name), upsert=down) if name == "push_sends" else original(name)

    with caplog.at_level("ERROR"):
        body = _run(client).json()

    assert sender.calls == [] and body["reminders_sent"] == 0
    assert any("Gönderim defterine yazılamadı" in r.getMessage() for r in caplog.records)


def test_a_database_without_the_unique_index_falls_back_to_row_by_row_claims(client, setup, caplog):
    offset = _offset_for("09:05")
    db, sender = setup([_device(i, offset) for i in range(4)])

    def no_index(*_a, **_k):
        raise RuntimeError("42P10: there is no unique or exclusion constraint matching the ON CONFLICT specification")

    original = db.table
    db.table = lambda name: _with(original(name), upsert=no_index) if name == "push_sends" else original(name)

    with caplog.at_level("WARNING"):
        body = _run(client).json()

    assert body["reminders_sent"] == 4, "toplu yazım desteklenmiyorsa satır satır yazılır, hatırlatıcılar gider"
    assert len(db.tables["push_sends"].inserted) == 4
    assert any("satır satır" in r.getMessage() for r in caplog.records)


def test_the_row_by_row_fallback_still_refuses_duplicates(client, setup):
    offset = _offset_for("09:05")
    db, sender = setup([_device(i, offset) for i in range(3)])
    log_date = (datetime.now(timezone.utc) + timedelta(minutes=offset)).date().isoformat()
    db.tables["push_sends"].rows.append(
        {"user_id": _uid(1), "reminder_id": "water_intake", "log_date": log_date, "slot": "09:00"}
    )

    def no_index(*_a, **_k):
        raise RuntimeError("42P10")

    original = db.table
    db.table = lambda name: _with(original(name), upsert=no_index) if name == "push_sends" else original(name)

    body = _run(client).json()

    assert body["reminders_sent"] == 2 and sorted(c["tokens"][0] for c in sender.calls) == ["tok-0", "tok-2"]


def _with(table, **overrides):
    for name, fn in overrides.items():
        setattr(table, name, fn)
    return table
