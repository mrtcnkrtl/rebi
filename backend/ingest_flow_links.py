#!/usr/bin/env python3
"""
Generate ingredient_concern_links from the Master Veri "Akış Şeması" (concept
flow) graph. Each edge like "Kırışıklık -> Retinoidler (Level 1b Kanıt)" becomes
a concern->ingredient support link, so the cabinet can answer "X for Y?" instead
of "eşleme yok".

Requires migrations + populated canonical_ingredients/concerns (run
merge_data_catalog.py first). Resolution uses curated aliases + DB rows.

Usage:
  cd backend && python3 ingest_flow_links.py --dry-run
  python3 ingest_flow_links.py --from-db            # resolve against DB catalog
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from config import get_logger

log = get_logger("ingest_flow_links")

DEFAULT_XLSX = (
    Path(__file__).resolve().parent / "documents" / "Dermatolojik_Veri_Analizi_Master.xlsx"
)

# Nodes that are abstract concepts, never an ingredient or a concern box.
_SKIP_NODES = {"cilt sagligi", "genetik", "diyet"}


def _confidence_from_label(label: str) -> tuple[str, float]:
    lab = (label or "").lower()
    if "kaçın" in lab or "kacin" in lab or "avoid" in lab:
        return "avoid", 0.8
    if "level 1" in lab:
        return "supports", 0.9
    if "tedavi" in lab or "önleme" in lab or "onleme" in lab:
        return "supports", 0.8
    return "supports", 0.6


def build_links_from_flow(rows: list[dict], resolver) -> tuple[list[dict], list[dict]]:
    """
    rows: [{"source":..,"target":..,"label":..}]
    Returns (links, skipped). Pure function (resolver may be offline/db).
    """
    from knowledge.entity_resolver import normalize

    links: list[dict] = []
    skipped: list[dict] = []
    seen: set[tuple[str, str]] = set()

    for row in rows:
        src = str(row.get("source") or "").strip()
        tgt = str(row.get("target") or "").strip()
        label = str(row.get("label") or "").strip()
        if not src or not tgt:
            continue
        if normalize(src) in _SKIP_NODES or normalize(tgt) in _SKIP_NODES:
            skipped.append({"source": src, "target": tgt, "reason": "skip_node"})
            continue

        # Primary orientation: concern (source) -> ingredient (target).
        ing = resolver.resolve(tgt)
        cnd = resolver.resolve_concern(src)
        if ing.is_candidate or cnd.is_candidate:
            # Reverse orientation: ingredient (source) -> concern (target).
            ing2 = resolver.resolve(src)
            cnd2 = resolver.resolve_concern(tgt)
            if not ing2.is_candidate and not cnd2.is_candidate:
                ing, cnd = ing2, cnd2

        if ing.is_candidate or cnd.is_candidate:
            skipped.append(
                {
                    "source": src,
                    "target": tgt,
                    "reason": "unresolved",
                    "ingredient": ing.ingredient_id,
                    "concern": cnd.ingredient_id,
                }
            )
            continue

        effect, conf = _confidence_from_label(label)
        key = (ing.ingredient_id, cnd.ingredient_id)
        if key in seen:
            continue
        seen.add(key)
        links.append(
            {
                "link_id": f"{ing.ingredient_id}__{cnd.ingredient_id}",
                "ingredient_id": ing.ingredient_id,
                "concern_id": cnd.ingredient_id,  # ResolveResult reuses .ingredient_id
                "effect_status": effect,
                "notes_tr": f"Akış grafiği: {src} → {tgt} ({label})",
                "source": "master_flow",
                "confidence": conf,
            }
        )
    return links, skipped


def _load_flow_rows(xlsx: Path) -> list[dict]:
    import pandas as pd

    fs = pd.read_excel(xlsx, sheet_name="Akış Şeması Verisi").fillna("")
    out = []
    for _, r in fs.iterrows():
        out.append(
            {
                "source": str(r.get("Source") or ""),
                "target": str(r.get("Target") or ""),
                "label": str(r.get("Label") or ""),
            }
        )
    return out


def _write_links(links: list[dict]) -> int:
    from knowledge.db import pg_conn
    from merge_data_catalog import _upsert_link

    written = 0
    with pg_conn(autocommit=False) as conn:
        with conn.cursor() as cur:
            for row in links:
                # Skip links whose endpoints are not present in the catalog (FK safety).
                cur.execute(
                    "select 1 from public.canonical_ingredients where ingredient_id=%s",
                    (row["ingredient_id"],),
                    prepare=False,
                )
                if not cur.fetchone():
                    log.warning("ingredient yok, link atlandı: %s", row["ingredient_id"])
                    continue
                cur.execute(
                    "select 1 from public.canonical_concerns where concern_id=%s",
                    (row["concern_id"],),
                    prepare=False,
                )
                if not cur.fetchone():
                    log.warning("concern yok, link atlandı: %s", row["concern_id"])
                    continue
                _upsert_link(cur, row)
                written += 1
        conn.commit()
    return written


def main() -> None:
    ap = argparse.ArgumentParser(description="Generate ingredient_concern_links from Master flow graph")
    ap.add_argument("--file", default=str(DEFAULT_XLSX))
    ap.add_argument("--from-db", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    from knowledge.entity_resolver import build_resolver

    rows = _load_flow_rows(Path(args.file))
    resolver = build_resolver(load_from_db=args.from_db)
    links, skipped = build_links_from_flow(rows, resolver)

    print(json.dumps({"edges": len(rows), "links": len(links), "skipped": len(skipped)}, ensure_ascii=False, indent=2))
    print("\nÜretilen linkler:")
    for l in links:
        print(f"  ✓ {l['ingredient_id']} → {l['concern_id']}  [{l['effect_status']}, conf={l['confidence']}]  ({l['notes_tr']})")
    if skipped:
        print("\nAtlananlar:")
        for s in skipped:
            print(f"  - {s['source']} → {s['target']}  ({s['reason']})")

    if args.dry_run:
        print("\n[dry-run] DB'ye yazılmadı.")
        return
    written = _write_links(links)
    print(f"\nYazılan link: {written}")


if __name__ == "__main__":
    main()
