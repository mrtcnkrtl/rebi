#!/usr/bin/env python3
"""
Build ingredient folder inventory (offline sources + optional Postgres).

Writes: backend/knowledge/ingredient_catalog_tree.json
Prints: human-readable tree to stdout

Usage:
  cd backend && python3 build_ingredient_catalog_tree.py
  python3 build_ingredient_catalog_tree.py --from-db
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

from knowledge.ingredient_folder_schema import INGREDIENT_INTERNAL_FOLDERS, INGREDIENT_FOLDER_SLUGS

OUT_PATH = Path(__file__).resolve().parent / "knowledge" / "ingredient_catalog_tree.json"
SEEDS_PATH = Path(__file__).resolve().parent / "knowledge" / "data_catalog_seeds.json"
_GRAPH_XLSX_NAME = "rebi_skincare_graph_kb.xlsx"
_GRAPH_XLSX_REPO = Path(__file__).resolve().parent / "documents" / _GRAPH_XLSX_NAME
# The repo copy is authoritative; the Downloads path stays as a fallback only so
# older local setups keep working. Relying on Downloads alone lost the source
# whenever the file was cleaned up or the machine changed.
GRAPH_XLSX = _GRAPH_XLSX_REPO if _GRAPH_XLSX_REPO.is_file() else Path.home() / "Downloads" / _GRAPH_XLSX_NAME


def _slugify(s: str) -> str:
    t = (s or "").strip().lower()
    t = re.sub(r"[^a-z0-9]+", "_", t)
    return t.strip("_")[:80] or "unknown"


def _kind_from_category(cat: str) -> str:
    c = (cat or "").lower()
    if "bariyer" in c or "barrier" in c:
        return "active"
    if "extract" in c or "ekstrakt" in c or "özü" in c or "botanical extract" in c:
        return "extract"
    if "oil" in c or "yağ" in c or "botanical" in c:
        return "oil"
    if "retinoid" in c:
        return "retinoid"
    if "spf" in c or "mineral" in c:
        return "spf"
    if "peptid" in c:
        return "peptide"
    return "active"


def _item(
    *,
    ingredient_id: str,
    name_tr: str,
    name_en: str = "",
    kind: str = "active",
    sources: list[str],
    graph_id: str | None = None,
    ingredient_db_key: str | None = None,
) -> dict:
    folder_slug = INGREDIENT_FOLDER_SLUGS.get(kind, "ingredients/actives")
    return {
        "ingredient_id": ingredient_id,
        "name_tr": name_tr,
        "name_en": name_en or "",
        "kind": kind,
        "folder_slug": folder_slug,
        "graph_ingredient_id": graph_id,
        "ingredient_db_key": ingredient_db_key,
        "sources": sources,
        "internal_folders": dict(INGREDIENT_INTERNAL_FOLDERS),
    }


def load_offline_items() -> list[dict]:
    items: dict[str, dict] = {}

    if GRAPH_XLSX.is_file():
        import pandas as pd

        df = pd.read_excel(GRAPH_XLSX, sheet_name="ingredient_profiles", header=4)
        df = df.drop(columns=[c for c in df.columns if str(c).startswith("Unnamed")], errors="ignore")
        for _, r in df.iterrows():
            gid = str(r.get("ingredient_id") or "").strip()
            tr = str(r.get("ingredient_tr") or "").strip()
            en = str(r.get("ingredient_en") or "").strip()
            cat = str(r.get("category") or "").strip()
            iid = _slugify(en or tr or gid)
            kind = _kind_from_category(cat)
            items[iid] = _item(
                ingredient_id=iid,
                name_tr=tr,
                name_en=en,
                kind=kind,
                sources=["graph_kb"],
                graph_id=gid,
            )

    if SEEDS_PATH.is_file():
        data = json.loads(SEEDS_PATH.read_text(encoding="utf-8"))
        for row in data.get("ingredients") or []:
            iid = row.get("ingredient_id") or row.get("slug")
            if not iid:
                continue
            items[str(iid)] = _item(
                ingredient_id=str(iid),
                name_tr=row.get("name_tr") or str(iid),
                name_en=row.get("name_en") or "",
                kind=row.get("kind") or "oil",
                sources=list(set((items.get(str(iid), {}).get("sources") or []) + ["seed_manual"])),
                graph_id=(items.get(str(iid)) or {}).get("graph_ingredient_id"),
            )

    try:
        from ingredient_db import INGREDIENT_DB

        for key, val in (INGREDIENT_DB or {}).items():
            if not isinstance(val, dict):
                continue
            name = (val.get("name") or key).strip()
            iid = items.get(key, {}).get("ingredient_id") if key in items else key
            if key in items:
                ex = items[key]
                ex["sources"] = list(set(ex.get("sources") or []) + ["ingredient_db"])
                ex["ingredient_db_key"] = key
                if not ex.get("name_tr"):
                    ex["name_tr"] = name
            else:
                items[key] = _item(
                    ingredient_id=key,
                    name_tr=name,
                    name_en=key.replace("_", " "),
                    kind="active",
                    sources=["ingredient_db"],
                    ingredient_db_key=key,
                )
    except Exception:
        pass

    return sorted(items.values(), key=lambda x: (x.get("folder_slug") or "", x.get("name_tr") or ""))


def load_db_items() -> list[dict]:
    from knowledge.db import pg_conn

    rows: list[dict] = []
    with pg_conn(autocommit=True) as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                select ingredient_id, slug, name_tr, name_en, kind, folder_slug,
                       graph_ingredient_id, ingredient_db_key, sources
                from public.canonical_ingredients
                order by folder_slug, name_tr
                """,
                prepare=False,
            )
            cols = [d[0] for d in cur.description]
            for r in cur.fetchall() or []:
                row = dict(zip(cols, r))
                row["internal_folders"] = dict(INGREDIENT_INTERNAL_FOLDERS)
                if isinstance(row.get("sources"), str):
                    try:
                        row["sources"] = json.loads(row["sources"])
                    except Exception:
                        row["sources"] = [row["sources"]]
                rows.append(row)
    return rows


def build_tree(items: list[dict]) -> dict:
    by_folder: dict[str, list[dict]] = {}
    for it in items:
        fs = it.get("folder_slug") or "ingredients/actives"
        by_folder.setdefault(fs, []).append(it)

    return {
        "root": "ingredients",
        "description_tr": "Maddeler klasörü: her madde kutusunun içinde profile, interactions, concern_links, safety, literature bölümleri vardır.",
        "internal_folder_schema": INGREDIENT_INTERNAL_FOLDERS,
        "subfolders": {
            slug: {
                "path": slug,
                "ingredient_count": len(lst),
                "ingredients": lst,
            }
            for slug, lst in sorted(by_folder.items())
        },
        "total_ingredients": len(items),
    }


def print_tree(tree: dict) -> None:
    print("\n=== MADDELER KLASÖRÜ (ingredients/) ===\n")
    print(tree.get("description_tr", ""))
    print("\nHer maddenin İÇİNDEKİ mantıksal klasörler (tüm maddelerde aynı şema):")
    for key, desc in (tree.get("internal_folder_schema") or {}).items():
        print(f"  • {key}/ — {desc}")
    print()
    for slug, block in (tree.get("subfolders") or {}).items():
        print(f"📁 {slug}/  ({block.get('ingredient_count', 0)} madde)")
        for ing in block.get("ingredients") or []:
            src = ", ".join(ing.get("sources") or [])
            gid = ing.get("graph_ingredient_id") or "-"
            print(f"   └─ {ing.get('name_tr')}  [id={ing.get('ingredient_id')}, graph={gid}, kaynak={src}]")
        print()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--from-db", action="store_true", help="Read canonical_ingredients from Postgres")
    args = ap.parse_args()

    if args.from_db:
        try:
            items = load_db_items()
            source = "postgres"
        except Exception as e:
            print(f"DB failed ({e}), falling back to offline sources.")
            items = load_offline_items()
            source = "offline_fallback"
    else:
        items = load_offline_items()
        source = "offline"

    tree = build_tree(items)
    tree["built_from"] = source
    OUT_PATH.write_text(json.dumps(tree, ensure_ascii=False, indent=2), encoding="utf-8")
    print_tree(tree)
    print(f"JSON: {OUT_PATH}")


if __name__ == "__main__":
    main()
