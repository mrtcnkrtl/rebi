"""Duplicate-chunk keeper rule: never drop the copy that carries the tags."""

from dedupe_chunks import FOLDER_SOURCE_KIND, SOURCE_PRIORITY, keeper_sort_key


def _row(cid, tags=0, kind=None, created="2026-01-01"):
    return {"id": cid, "tag_count": tags, "source_kind": kind, "created_at": created}


def _keeper(rows):
    return sorted(rows, key=keeper_sort_key)[0]["id"]


def test_most_tagged_copy_wins():
    rows = [_row("a", tags=0), _row("b", tags=3), _row("c", tags=1)]
    assert _keeper(rows) == "b"


def test_source_kind_breaks_tie_when_tags_equal():
    rows = [_row("pdf", tags=2, kind="pdf"), _row("mv", tags=2, kind="master_veri")]
    assert _keeper(rows) == "mv"


def test_unknown_source_kind_ranks_last():
    rows = [_row("none", tags=1, kind=None), _row("pdf", tags=1, kind="pdf")]
    assert _keeper(rows) == "pdf"


def test_oldest_wins_when_tags_and_source_equal():
    rows = [
        _row("new", tags=1, kind="pdf", created="2026-05-01"),
        _row("old", tags=1, kind="pdf", created="2026-01-01"),
    ]
    assert _keeper(rows) == "old"


def test_tie_break_is_stable_by_id():
    rows = [_row("b", tags=1, kind="pdf"), _row("a", tags=1, kind="pdf")]
    assert _keeper(rows) == "a"


def test_tags_outrank_a_better_source():
    # a richly tagged pdf copy beats an untagged master_veri copy
    rows = [_row("pdf", tags=5, kind="pdf"), _row("mv", tags=0, kind="master_veri")]
    assert _keeper(rows) == "pdf"


def test_source_priority_order_is_sane():
    assert SOURCE_PRIORITY["master_veri"] < SOURCE_PRIORITY["graph"] < SOURCE_PRIORITY["pdf"]


def test_folder_source_kind_map_covers_known_folders():
    assert FOLDER_SOURCE_KIND["data-pdfs"] == "pdf"
    assert FOLDER_SOURCE_KIND["chat-guides"] == "chat_guide"
