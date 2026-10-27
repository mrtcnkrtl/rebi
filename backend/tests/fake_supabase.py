"""supabase-py sorgu zincirinin test amaçlı küçük bir taklidi.

Yalnızca backend'in kullandığı zincir parçalarını destekler:
select/insert/upsert/delete + eq/in_/gt/gte/lte/order (çoklu)/limit/range/execute.

`max_rows` verilirse PostgREST'in `db-max-rows` sınırı taklit edilir: bir select, istenen `limit`/`range`
ne olursa olsun en fazla bu kadar satır döndürür (Supabase varsayılanı 1000). Sayfalamayı sınamak için.
"""

from __future__ import annotations


class Result:
    def __init__(self, data):
        self.data = data


class FakeTable:
    def __init__(self, rows: list[dict] | None = None):
        self.rows: list[dict] = list(rows or [])
        # Postgres unique kısıtını taklit eder: çakışan insert hata yükseltir.
        self.unique_on: tuple[str, ...] = ()
        self.inserted: list[dict] = []
        self.upserted: list[dict] = []
        self.deleted_count = 0
        self.max_rows: int | None = None
        self.select_calls = 0
        self.upsert_calls = 0
        # Her select'in süzgeçleri: toplu sorguların URL'ye kaç kimlik yazdığını sınamak için.
        self.query_log: list[list[tuple[str, str, object]]] = []
        self.last_conflict = ""
        self.last_ignore_duplicates = False
        self.filters: list[tuple[str, str, object]] = []
        self._reset()

    def _reset(self):
        self._op = "select"
        self._payload = None
        self.filters = []
        self._orders: list[tuple[str, bool]] = []
        self._limit = None
        self._range: tuple[int, int] | None = None
        return self

    def select(self, *_args, **_kwargs):
        self._op = "select"
        return self

    def insert(self, payload):
        self._op = "insert"
        self._payload = payload
        return self

    def upsert(self, payload, on_conflict: str = "", ignore_duplicates: bool = False):
        self.upsert_calls += 1
        self._op = "upsert"
        self._payload = payload
        self.last_conflict = on_conflict
        self.last_ignore_duplicates = ignore_duplicates
        return self

    def delete(self):
        self._op = "delete"
        return self

    def eq(self, column, value):
        self.filters.append(("eq", column, value))
        return self

    def in_(self, column, values):
        self.filters.append(("in", column, list(values)))
        return self

    def gt(self, column, value):
        self.filters.append(("gt", column, value))
        return self

    def gte(self, column, value):
        self.filters.append(("gte", column, value))
        return self

    def lte(self, column, value):
        self.filters.append(("lte", column, value))
        return self

    def order(self, column, desc: bool = False):
        self._orders.append((column, desc))
        return self

    def limit(self, count):
        self._limit = count
        return self

    def range(self, start, end):
        self._range = (int(start), int(end))
        return self

    def _matches(self, row: dict) -> bool:
        for op, column, value in self.filters:
            cell = row.get(column)
            if op == "eq" and cell != value:
                return False
            if op == "in" and cell not in value:
                return False
            if op == "gt" and not (cell is not None and cell > value):
                return False
            if op == "gte" and not (cell is not None and cell >= value):
                return False
            if op == "lte" and not (cell is not None and cell <= value):
                return False
        return True

    def _conflict_key(self, row: dict):
        return tuple(row.get(c.strip()) for c in self.last_conflict.split(","))

    def execute(self) -> Result:
        op = self._op
        payload = self._payload
        try:
            if op == "select":
                self.select_calls += 1
                self.query_log.append(list(self.filters))
                found = [dict(r) for r in self.rows if self._matches(r)]
                # Çoklu sıralama: son anahtardan başlayarak kararlı sıralamalar (Postgres'in ORDER BY a, b'si gibi).
                for column, desc in reversed(self._orders):
                    found.sort(key=lambda r, c=column: (r.get(c) is None, r.get(c)), reverse=desc)
                if self._range is not None:
                    start, end = self._range
                    found = found[start : end + 1]
                if self._limit is not None:
                    found = found[: self._limit]
                if self.max_rows is not None:
                    found = found[: self.max_rows]
                return Result(found)

            new_rows = payload if isinstance(payload, list) else [payload]
            if op == "insert":
                for row in new_rows:
                    if self.unique_on and any(
                        all(r.get(c) == row.get(c) for c in self.unique_on) for r in self.rows
                    ):
                        raise RuntimeError("duplicate key value violates unique constraint")
                self.inserted.extend(new_rows)
                self.rows.extend(dict(r) for r in new_rows)
                return Result([dict(r) for r in new_rows])

            if op == "upsert":
                self.upserted.extend(new_rows)
                written = []
                for row in new_rows:
                    existing = next(
                        (r for r in self.rows if self._conflict_key(r) == self._conflict_key(row)),
                        None,
                    )
                    if existing is not None and self.last_ignore_duplicates:
                        continue
                    if existing is not None:
                        existing.update(row)
                        written.append(dict(existing))
                    else:
                        self.rows.append(dict(row))
                        written.append(dict(row))
                return Result(written)

            if op == "delete":
                kept = [r for r in self.rows if not self._matches(r)]
                self.deleted_count += len(self.rows) - len(kept)
                self.rows = kept
                return Result([])

            raise AssertionError(f"Desteklenmeyen işlem: {op}")
        finally:
            self._reset()


class _Rpc:
    def __init__(self, handler, params):
        self._handler, self._params = handler, params

    def execute(self):
        return Result(self._handler(self._params))


class FakeSupabase:
    def __init__(self, **tables: list[dict]):
        self.tables = {name: FakeTable(rows) for name, rows in tables.items()}
        # RPC işlevleri: ad -> çağrılabilir(params) -> dönüş verisi. Çağrılar `rpc_calls`ta tutulur.
        self.rpc_handlers: dict = {}
        self.rpc_calls: list = []

    def rpc(self, name: str, params=None):
        self.rpc_calls.append(name)
        handler = self.rpc_handlers.get(name)
        if handler is None:
            raise RuntimeError(f"rpc tanımlı değil: {name}")
        return _Rpc(handler, params)

    def table(self, name: str) -> FakeTable:
        return self.tables.setdefault(name, FakeTable())._reset()
