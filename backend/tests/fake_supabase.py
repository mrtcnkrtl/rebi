"""supabase-py sorgu zincirinin test amaçlı küçük bir taklidi.

Yalnızca backend'in kullandığı zincir parçalarını destekler:
select/insert/upsert/delete + eq/gt/gte/lte/order/limit/execute.
"""

from __future__ import annotations


class Result:
    def __init__(self, data):
        self.data = data


class FakeTable:
    def __init__(self, rows: list[dict] | None = None):
        self.rows: list[dict] = list(rows or [])
        self.inserted: list[dict] = []
        self.upserted: list[dict] = []
        self.deleted_count = 0
        self.last_conflict = ""
        self.last_ignore_duplicates = False
        self.filters: list[tuple[str, str, object]] = []
        self._reset()

    def _reset(self):
        self._op = "select"
        self._payload = None
        self.filters = []
        self._order = None
        self._desc = False
        self._limit = None
        return self

    def select(self, *_args, **_kwargs):
        self._op = "select"
        return self

    def insert(self, payload):
        self._op = "insert"
        self._payload = payload
        return self

    def upsert(self, payload, on_conflict: str = "", ignore_duplicates: bool = False):
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
        self._order = column
        self._desc = desc
        return self

    def limit(self, count):
        self._limit = count
        return self

    def _matches(self, row: dict) -> bool:
        for op, column, value in self.filters:
            cell = row.get(column)
            if op == "eq" and cell != value:
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
                found = [dict(r) for r in self.rows if self._matches(r)]
                if self._order:
                    found.sort(key=lambda r: r.get(self._order), reverse=self._desc)
                if self._limit is not None:
                    found = found[: self._limit]
                return Result(found)

            new_rows = payload if isinstance(payload, list) else [payload]
            if op == "insert":
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


class FakeSupabase:
    def __init__(self, **tables: list[dict]):
        self.tables = {name: FakeTable(rows) for name, rows in tables.items()}

    def table(self, name: str) -> FakeTable:
        return self.tables.setdefault(name, FakeTable())._reset()
