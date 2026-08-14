"""Evidence scoring must count the canonical catalog, not just vector/entity hits.

Regression guard: when the cabinet returns a priority-ordered chain, the composer
has to run in confident mode. Otherwise it asks the user clarifying questions
while a full answer sits unused in the bundle.
"""

from rag_service import _evidence_metrics


class _Hit:
    def __init__(self, similarity: float, document_id: str = "doc-1"):
        self.similarity = similarity
        self.document_id = document_id
        self.chunk_text = "x" * 300


def _m(**kw):
    base = {"entity_text": "", "vector_hits": [], "used_docs": 0}
    base.update(kw)
    return _evidence_metrics(**base)


def test_cabinet_chain_alone_is_answerable():
    m = _m(cabinet_status="concern_chain", cabinet_link_count=4)
    assert m["ok"] is True
    assert m["score"] > 0.4


def test_ingredient_chain_alone_is_answerable():
    assert _m(cabinet_status="ingredient_chain", cabinet_link_count=1)["ok"] is True


def test_direct_hit_is_answerable():
    assert _m(cabinet_status="hit", cabinet_link_count=2)["ok"] is True


def test_chain_without_links_is_not_strong():
    # status set but no link rows -> nothing concrete to answer from
    assert _m(cabinet_status="concern_chain", cabinet_link_count=0)["ok"] is False


def test_weak_cabinet_states_do_not_pass():
    assert _m(cabinet_status="miss", cabinet_link_count=0)["ok"] is False
    assert _m(cabinet_status="partial_single", cabinet_link_count=0)["ok"] is False


def test_literature_plus_graph_is_answerable():
    assert _m(literature_len=800, graph_len=600)["ok"] is True


def test_literature_alone_is_not_enough():
    assert _m(literature_len=800)["ok"] is False


def test_cabinet_raises_score_over_bare_vector():
    bare = _m(vector_hits=[_Hit(0.70)], used_docs=1)
    with_cab = _m(
        vector_hits=[_Hit(0.70)],
        used_docs=1,
        cabinet_status="concern_chain",
        cabinet_link_count=4,
        literature_len=500,
    )
    assert with_cab["score"] > bare["score"]
    assert with_cab["ok"] is True


def test_legacy_call_without_cabinet_args_still_works():
    # existing behaviour preserved: strong vector similarity alone passes
    assert _m(vector_hits=[_Hit(0.80)], used_docs=1)["ok"] is True
    assert _m(entity_text="y" * 250)["ok"] is True


def test_score_stays_bounded():
    m = _m(
        entity_text="y" * 900,
        vector_hits=[_Hit(0.95), _Hit(0.9, "d2"), _Hit(0.88, "d3")],
        used_docs=3,
        cabinet_status="hit",
        cabinet_link_count=8,
        literature_len=1200,
        graph_len=900,
    )
    assert 0.0 <= m["score"] <= 1.0
