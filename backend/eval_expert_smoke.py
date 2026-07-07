#!/usr/bin/env python3
"""
Smoke-test the skincare expert evidence bundle against representative questions.

For each question it reports which evidence blocks fire:
  - cabinet: canonical catalog match (concern_chain / ingredient_chain / hit)
  - graph:   Graph KB block (profiles, interactions, safety)
  - lit:     raw literature passages from the matched ingredient box(es)

Use after data changes to catch retrieval regressions (no LLM/server needed).

Usage:
  cd backend && python3 eval_expert_smoke.py
"""

from __future__ import annotations

import config  # noqa: F401  (loads backend/.env)

QUESTIONS = [
    "hamileyken leke için ne kullanabilirim",
    "retinol ve salisilik asit aynı akşam kullanılır mı",
    "gözeneklerim çok büyük ne önerirsin",
    "göz altı morlukları için ne iyi gelir",
    "cildim sarkıyor hangi içerik iyi gelir",
    "akne sonrası kalan koyu lekeler",
    "niasinamid ne işe yarar",
    "c vitamini ve niasinamid birlikte kullanılır mı",
    "kuru saç için yağ önerir misin",
    "rozasea kızarıklık için ne kullanmalıyım",
    "yağlı cildim var ne önerirsin",
    "cildim çok kuru ne yapmalıyım",
    "kırışıklıklar için ne kullanmalıyım",
    "sivilcelerim var ne önerirsin",
]


def run(questions: list[str] | None = None) -> int:
    from knowledge.cabinet_router import format_cabinet_evidence_block, invalidate_catalog_cache
    from knowledge.graph_kb import format_graph_evidence_block
    from knowledge.literature import format_literature_block

    invalidate_catalog_cache()
    qs = questions or QUESTIONS
    fired = 0
    for q in qs:
        cab, meta = format_cabinet_evidence_block(q)
        graph = format_graph_evidence_block(q)
        ids = meta.get("cabinet_ingredient_ids") or []
        lit = format_literature_block(ids) if ids else ""
        status = meta.get("cabinet_status") or "miss"
        hit = status != "miss" or bool(graph)
        fired += hit
        mark = "✓" if hit else "✗"
        print(
            f"{mark} [{status:16s}] links={meta.get('cabinet_link_count'):<2} "
            f"graph={'✓' if graph else '—'} lit={'✓' if lit else '—'}  {q}"
        )
    print(f"\nTetiklenen: {fired}/{len(qs)}")
    return fired


if __name__ == "__main__":
    import sys

    n = run()
    raise SystemExit(0 if n == len(QUESTIONS) else 1)
