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
    "c vitamini": "vitamin_c",
    "gunes koruyucu": "mineral_spf",
    "gunes filtresi": "mineral_spf",
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
    # English forms pinned to the single survivor id (db-key), so PDF/graph
    # spellings never split a box across duplicate canonical rows.
    "ceramide": "seramidler",
    "ceramides": "seramidler",
    "niacinamide": "niacinamid",
    "hyaluronic acid": "hyaluronik_asit",
    "hyaluronic": "hyaluronik_asit",
    "hydrolyzed hyaluronic acid": "hyaluronik_asit",
    "salicylic acid": "salisilik_asit",
    "salicylic": "salisilik_asit",
    "tranexamic acid": "traneksamik_asit",
    "benzoyl peroxide": "benzoil_peroksit",
    "ascorbic acid": "vitamin_c",
    "l ascorbic acid": "vitamin_c",
    "ascorbic": "vitamin_c",
    "alpha arbutin": "alfa_arbutin",
    "alfa arbutin": "alfa_arbutin",
    "arbutin": "alfa_arbutin",
}

_OIL_HINTS = ("yag", "oil", "butter", "yağ")
_EXTRACT_HINTS = ("ekstr", "ozu", "özü", "extract", "ferment")

# Curated Turkish concern words -> canonical concern_id (slug of graph condition_en,
# produced by merge_data_catalog._slugify). DB rows (load_from_db) take priority.
_CURATED_CONCERNS: dict[str, str] = {
    "akne": "acne_vulgaris",
    "akne vulgaris": "acne_vulgaris",
    "kistik": "acne_vulgaris",
    "kistik akne": "acne_vulgaris",
    "derece 4 kistik": "acne_vulgaris",
    "komedon": "comedones_open_closed",
    "derece 1 komedon": "comedones_open_closed",
    "siyah nokta": "comedones_open_closed",
    "beyaz nokta": "comedones_open_closed",
    "leke": "hyperpigmentation_melasma",
    "koyu leke": "hyperpigmentation_melasma",
    "koyu lekeler": "hyperpigmentation_melasma",
    "hiperpigmentasyon": "hyperpigmentation_melasma",
    "melazma": "hyperpigmentation_melasma",
    "melasma": "hyperpigmentation_melasma",
    "pih": "post_inflammatory_hyperpigmentation",
    "kirisiklik": "photoaging_premature_aging",
    "kırışıklık": "photoaging_premature_aging",
    "ince cizgiler": "photoaging_premature_aging",
    "ince çizgiler": "photoaging_premature_aging",
    "yaslanma": "photoaging_premature_aging",
    "yaşlanma": "photoaging_premature_aging",
    "fotoyaslanma": "photoaging_premature_aging",
    "kuru cilt": "dry_skin_xerosis",
    "kuruluk": "dry_skin_xerosis",
    "kserozis": "dry_skin_xerosis",
    "yagli cilt": "oily_skin_seborrhea",
    "yağlı cilt": "oily_skin_seborrhea",
    "sebore": "oily_skin_seborrhea",
    "rosacea": "rosacea",
    "kizariklik": "rosacea",
    "kızarıklık": "rosacea",
    "sensitivite": "rosacea",
    "hassasiyet": "rosacea",
    "gozenek": "enlarged_pores",
    "gözenek": "enlarged_pores",
    "sarkma": "skin_laxity",
    "gevsek cilt": "skin_laxity",
    "mor halka": "dark_circles_periorbital_hyperpigmentation",
    "goz alti": "dark_circles_periorbital_hyperpigmentation",
    "göz altı": "dark_circles_periorbital_hyperpigmentation",
    "egzama": "atopic_dermatitis",
    "atopik dermatit": "atopic_dermatitis",
    # hair (seed concerns)
    "kuru sac": "hair_dryness",
    "kuru saç": "hair_dryness",
    "sac kurulugu": "hair_dryness",
    "kuru sac derisi": "scalp_dryness",
}


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
    # normalized phrase -> concern_id
    _cindex: dict[str, str] = field(default_factory=dict)
    _cnames: dict[str, str] = field(default_factory=dict)

    def _add(self, ingredient_id: str, *phrases: str) -> None:
        iid = (ingredient_id or "").strip()
        if not iid:
            return
        for p in phrases:
            np = normalize(p)
            if len(np) >= 3:
                self._index.setdefault(np, iid)

    def _add_concern(self, concern_id: str, *phrases: str) -> None:
        cid = (concern_id or "").strip()
        if not cid:
            return
        for p in phrases:
            np = normalize(p)
            if len(np) >= 3:
                self._cindex.setdefault(np, cid)

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

    def resolve_concern(self, name: str) -> ResolveResult:
        """Map free-text concern text to a canonical concern_id (or candidate)."""
        q = normalize(name)
        if len(q) < 3:
            return ResolveResult(name, None, None, True, slugify(name), "concern", "concerns/skin")
        if q in self._cindex:
            return ResolveResult(name, self._cindex[q], "exact", False, slugify(name), "concern", "concerns/skin")
        cur = _CURATED_CONCERNS.get(q) or _CURATED_CONCERNS.get(normalize(q))
        if cur:
            return ResolveResult(name, cur, "curated", False, slugify(name), "concern", "concerns/skin")
        # substring against curated keys and index (longest first to avoid noise)
        for key in sorted(_CURATED_CONCERNS, key=len, reverse=True):
            kn = normalize(key)
            if len(kn) >= 4 and kn in q:
                return ResolveResult(name, _CURATED_CONCERNS[key], "curated_sub", False, slugify(name), "concern", "concerns/skin")
        for phrase, cid in self._cindex.items():
            if len(phrase) >= 4 and (phrase in q or q in phrase):
                return ResolveResult(name, cid, "substring", False, slugify(name), "concern", "concerns/skin")
        return ResolveResult(name, None, None, True, slugify(name), "concern", "concerns/skin")


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
        for row in data.get("concerns") or []:
            cid = row.get("concern_id") or row.get("slug")
            if not cid:
                continue
            r._cnames[cid] = row.get("name_tr") or cid
            cphrases = [row.get("name_tr"), row.get("name_en"), row.get("slug"), cid]
            cphrases += row.get("aliases") or []
            r._add_concern(cid, *[p for p in cphrases if p])

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
                    cur.execute(
                        "select concern_id, slug, name_tr, name_en, aliases from public.canonical_concerns",
                        prepare=False,
                    )
                    for cid, slug, ntr, nen, aliases in cur.fetchall() or []:
                        r._cnames[cid] = ntr or cid
                        al = aliases if isinstance(aliases, list) else []
                        r._add_concern(cid, slug, ntr, nen, *al)
        except Exception:
            pass

    return r
