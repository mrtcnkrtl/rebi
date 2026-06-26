"""
Canonical entity resolver: map a free-text ingredient name (from Master Veri,
PDF entities, user text) to a stable canonical ingredient_id.

Foundation for the self-organizing cabinet: every raw passage / extracted name
is resolved to ONE box. Unmatched names become "candidate" boxes (with a guessed
folder) instead of silently disappearing.

Offline sources (no DB needed): data_catalog_seeds.json + INGREDIENT_DB +
curated alias map. With load_from_db=True it also pulls canonical_ingredients.
"""

from __future__ import annotations

import json
import re
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

SEEDS_PATH = Path(__file__).resolve().parent / "data_catalog_seeds.json"


def normalize(s: str) -> str:
    """Turkish-aware fold to ASCII lowercase (mirrors cabinet_router._norm)."""
    t = unicodedata.normalize("NFKC", (s or "").strip()).casefold()
    t = "".join(ch for ch in t if unicodedata.category(ch) != "Mn")
    t = re.sub(r"\s+", " ", t)
    tr = str.maketrans("ığüşöç", "igusoc")
    return t.translate(tr).strip()


# Curated aliases for forms that don't auto-match by substring (spelling drift
# between the master headers and the canonical keys/names).
_CURATED_ALIASES: dict[str, str] = {
    "retinoidler": "retinol",
    "tretinoin": "retinol",
    "retinaldeyde": "retinol",
    "retinaldehit": "retinol",
    "vitamin c": "vitamin_c",
    "l askorbik asit": "vitamin_c",
    "l askorbit asit": "vitamin_c",
    "askorbik asit": "vitamin_c",
    "benzoyl peroksit": "benzoil_peroksit",
    "benzoil peroksit": "benzoil_peroksit",
    "azelaikasit": "azelaik_asit",
    "azelaik asit": "azelaik_asit",
    "azelaic acid": "azelaik_asit",
    "niacinamid": "niacinamid",
    "niasinamid": "niacinamid",
    "mineral gunes filtresi": "mineral_spf",
    "cinko oksit": "mineral_spf",
    "titanyum dioksit": "mineral_spf",
    "cay agaci yagi": "cay_agaci",
    "cay agaci": "cay_agaci",
    "kolajen peptidleri": "peptidler",
    "kolajen": "peptidler",
    "peptid": "peptidler",
    "peptidler": "peptidler",
    "hyaluronik asit": "hyaluronik_asit",
    "hiyaluronik asit": "hyaluronik_asit",
    "seramid": "seramidler",
    "seramidler": "seramidler",
}

_OIL_HINTS = ("yag", "oil", "butter", "yağ")
_EXTRACT_HINTS = ("ekstr", "ozu", "özü", "extract", "ferment")


def slugify(s: str) -> str:
    t = normalize(s)
    t = re.sub(r"[^a-z0-9]+", "_", t)
    return t.strip("_")[:80] or "unknown"


def guess_kind_folder(name: str) -> tuple[str, str]:
    n = (name or "").lower()
    if any(h in n for h in _OIL_HINTS):
        return "oil", "ingredients/oils-botanicals"
    if any(h in n for h in _EXTRACT_HINTS):
        return "extract", "ingredients/extracts"
    return "active", "ingredients/actives"


@dataclass
class ResolveResult:
    name: str
    ingredient_id: Optional[str]
    matched_via: Optional[str]  # "exact" | "alias" | "substring" | "curated" | None
    is_candidate: bool
    suggested_slug: str
    kind: str
    folder_slug: str


@dataclass
class EntityResolver:
    # normalized phrase -> ingredient_id
    _index: dict[str, str] = field(default_factory=dict)
    _names: dict[str, str] = field(default_factory=dict)  # ingredient_id -> display name

    def _add(self, ingredient_id: str, *phrases: str) -> None:
        iid = (ingredient_id or "").strip()
        if not iid:
            return
        for p in phrases:
            np = normalize(p)
            if len(np) >= 3:
                self._index.setdefault(np, iid)

    def resolve(self, name: str) -> ResolveResult:
        q = normalize(name)
        kind, folder = guess_kind_folder(name)
        if len(q) < 3:
            return ResolveResult(name, None, None, True, slugify(name), kind, folder)
        # 1) exact
        if q in self._index:
            return ResolveResult(name, self._index[q], "exact", False, slugify(name), kind, folder)
        # 2) curated alias
        if q in _CURATED_ALIASES:
            return ResolveResult(name, _CURATED_ALIASES[q], "curated", False, slugify(name), kind, folder)
        # 3) substring either direction (guard length to avoid noise)
        best: Optional[str] = None
        for phrase, iid in self._index.items():
            if len(phrase) < 4:
                continue
            if phrase in q or (len(q) >= 4 and q in phrase):
                best = iid
                break
        if best:
            return ResolveResult(name, best, "substring", False, slugify(name), kind, folder)
        return ResolveResult(name, None, None, True, slugify(name), kind, folder)


def build_resolver(*, load_from_db: bool = False) -> EntityResolver:
    r = EntityResolver()

    # Seeds (oils + manual rows)
    if SEEDS_PATH.is_file():
        data = json.loads(SEEDS_PATH.read_text(encoding="utf-8"))
        for row in data.get("ingredients") or []:
            iid = row.get("ingredient_id") or row.get("slug")
            if not iid:
                continue
            r._names[iid] = row.get("name_tr") or iid
            phrases = [row.get("name_tr"), row.get("name_en"), row.get("slug"), iid]
            phrases += row.get("aliases") or []
            r._add(iid, *[p for p in phrases if p])

    # INGREDIENT_DB (key + display name)
    try:
        from ingredient_db import INGREDIENT_DB

        for key, val in (INGREDIENT_DB or {}).items():
            if not isinstance(val, dict):
                continue
            r._names.setdefault(key, val.get("name") or key)
            r._add(key, key, key.replace("_", " "), val.get("name") or "")
    except Exception:
        pass

    # Curated alias targets must exist as resolvable ids even if only via curation.
    for target in set(_CURATED_ALIASES.values()):
        r._names.setdefault(target, target)

    if load_from_db:
        try:
            from knowledge.db import pg_conn

            with pg_conn(autocommit=True) as conn:
                with conn.cursor() as cur:
                    cur.execute(
                        "select ingredient_id, slug, name_tr, name_en, aliases from public.canonical_ingredients",
                        prepare=False,
                    )
                    for iid, slug, ntr, nen, aliases in cur.fetchall() or []:
                        r._names[iid] = ntr or iid
                        al = aliases if isinstance(aliases, list) else []
                        r._add(iid, slug, ntr, nen, *al)
        except Exception:
            pass

    return r
