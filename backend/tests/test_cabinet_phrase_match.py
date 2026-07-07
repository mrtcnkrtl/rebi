"""Cabinet phrase matching: substring + token-subset (robust to inflection)."""

from knowledge.cabinet_router import _norm, _phrase_matches


def _match(phrase: str, query: str, min_token: int = 3) -> bool:
    qn = _norm(query)
    return _phrase_matches(_norm(phrase), qn, {t for t in qn.split(" ") if t}, min_token)


def test_contiguous_substring_matches():
    assert _match("gozenek", "gozeneklerim cok buyuk", min_token=4)


def test_token_subset_matches_with_inserted_word_and_order():
    # tokens present regardless of order / inserted words
    assert _match("cildim yagli", "yagli cildim var ne onerirsin", min_token=4)
    assert _match("cildim kuru", "cildim cok kuru ne yapmaliyim", min_token=4)


def test_single_short_word_below_min_token_rejected():
    assert not _match("pih", "akne sonrasi pih", min_token=4)


def test_unrelated_query_does_not_match():
    assert not _match("gozenek", "sac boyasi hakkinda soru", min_token=4)


def test_multiword_requires_all_tokens():
    # only one of the two tokens present -> no match
    assert not _match("mor halka", "yesil cay hakkinda", min_token=4)
