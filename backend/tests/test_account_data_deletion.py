from __future__ import annotations

import pytest
from fastapi import HTTPException

from main import (
    _delete_skin_photos_for_user,
    _delete_user_application_data,
    _photo_content_matches_extension,
)


USER_ID = "11111111-1111-4111-8111-111111111111"


class _DeleteQuery:
    def __init__(self, table: str, calls: list[tuple[str, str, str]]):
        self.table = table
        self.calls = calls
        self.column = ""
        self.value = ""

    def delete(self):
        return self

    def eq(self, column, value):
        self.column = column
        self.value = value
        return self

    def execute(self):
        self.calls.append((self.table, self.column, self.value))
        return object()


class _Bucket:
    def __init__(self):
        self.removed = []

    def list(self, prefix):
        assert prefix == USER_ID
        return [{"name": "one.jpg"}, {"name": "two.webp"}]

    def remove(self, paths):
        self.removed.extend(paths)


class _Supabase:
    def __init__(self):
        self.calls = []
        self.bucket = _Bucket()

    def table(self, name):
        return _DeleteQuery(name, self.calls)

    class _Storage:
        def __init__(self, bucket):
            self.bucket = bucket

        def from_(self, name):
            assert name == "skin-photos"
            return self.bucket

    @property
    def storage(self):
        return self._Storage(self.bucket)


def test_account_deletion_explicitly_covers_personal_data_tables():
    db = _Supabase()

    _delete_user_application_data(db, USER_ID)

    assert db.calls == [
        ("privacy_preferences", "user_id", USER_ID),
        ("legal_consents", "user_id", USER_ID),
        ("daily_events", "user_id", USER_ID),
        ("daily_logs", "user_id", USER_ID),
        ("routines", "user_id", USER_ID),
        ("assessments", "user_id", USER_ID),
        ("profiles", "id", USER_ID),
    ]


def test_account_deletion_removes_all_user_photo_paths():
    db = _Supabase()

    _delete_skin_photos_for_user(db, USER_ID)

    assert db.bucket.removed == [
        f"{USER_ID}/one.jpg",
        f"{USER_ID}/two.webp",
    ]


def test_photo_magic_bytes_are_validated():
    assert _photo_content_matches_extension(b"\xff\xd8\xffrest", "jpg")
    assert _photo_content_matches_extension(b"\x89PNG\r\n\x1a\nrest", "png")
    assert _photo_content_matches_extension(b"RIFFxxxxWEBPrest", "webp")
    assert not _photo_content_matches_extension(b"<script>alert(1)</script>", "jpg")


def test_photo_listing_failure_blocks_account_deletion():
    db = _Supabase()

    def fail(_prefix):
        raise RuntimeError("storage unavailable")

    db.bucket.list = fail

    with pytest.raises(HTTPException) as exc:
        _delete_skin_photos_for_user(db, USER_ID)

    assert exc.value.status_code == 502
