#!/usr/bin/env python3
"""
Clean + structure the "Dermatolojik_Veri_Analizi_Master" Excel into a usable
knowledge inventory.

The source is a PDF-extraction dump with two corruption patterns:
  1. `_x0000_`  : NULL chars left where punctuation used to be (`(`, `-`, `)`).
  2. spaced TR diacritics: "Ya ğ ı" -> "Yağı", "kırı ş ıklık" -> "kırışıklık".

This module exposes pure helpers (fix_encoding / parse_header) plus an
Excel-driven builder that writes knowledge/master_veri_inventory.json and prints
a report (how many ingredient/topic boxes, oils/extracts, sample claims).

Usage:
  cd backend && python3 clean_master_veri.py
  python3 clean_master_veri.py --file documents/Dermatolojik_Veri_Analizi_Master.xlsx
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

DEFAULT_XLSX = (
    Path(__file__).resolve().parent / "documents" / "Dermatolojik_Veri_Analizi_Master.xlsx"
)
OUT_PATH = Path(__file__).resolve().parent / "knowledge" / "master_veri_inventory.json"

_NULL = "_x0000_"
# Only LOWERCASE diacritics get the "spaced letter" repair. Capital TR letters
# (İ, Ç, Ş, Ğ, Ö, Ü) legitimately start words, so we must not eat the space
# before them ("Su İçimi" must stay two words).
_TR_LOWER = "şğçıöü"


def fix_encoding(s: str) -> str:
    """Repair the two corruption patterns; return clean human text."""
    if s is None:
        return ""
    s = str(s)
    # Real NULs sometimes survive as \x00 instead of the literal escape.
    s = s.replace("\x00", _NULL)
    # digit <null> digit  ->  range dash (e.g. "5_x0000_10%" -> "5-10%")
    s = re.sub(r"(\d)\s*" + re.escape(_NULL) + r"\s*(\d)", r"\1-\2", s)
    # Remaining nulls become spaces, collapsed below.
    s = s.replace(_NULL, " ")
    # Spaced lowercase diacritic. Two trailing spaces => a real word break follows
    # ("Güne ş  Filtresi" -> "Güneş Filtresi"); one trailing space => mid-word
    # ("Ya ğ ı" -> "Yağı").
    s = re.sub(r"(?<=\w)\s([" + _TR_LOWER + r"])\s\s", r"\1 ", s)
    s = re.sub(r"(?<=\w)\s([" + _TR_LOWER + r"])\s(?=\w)", r"\1", s)
    s = re.sub(r"(?<=\w)\s([" + _TR_LOWER + r"])\s*$", r"\1", s)
    # Capital diacritic split mid-word: "İ çimi" -> "İçimi", "İ nsülin" -> "İnsülin".
    s = re.sub(r"([İĞŞÇÖÜ])\s([a-zşğçıöü])", r"\1\2", s)
    s = re.sub(r"\s+", " ", s).strip()
    # Drop dangling punctuation left by removed parens.
    s = s.strip(" -)(").strip()
    return s


_NOISE_SYNONYM = re.compile(r"^[\d%\.\,\-\s]*$")


def parse_header(raw: str) -> tuple[str, list[str]]:
    """
    Split an 'Ana Başlık' header into (primary_name, synonyms[]).

    "Retinoidler _x0000_Tretinoin, Retinol)" -> ("Retinoidler", ["Tretinoin","Retinol"])
    "Benzoyl Peroksit _x0000_5_x0000_10%_x0000_" -> ("Benzoyl Peroksit", [])
    """
    if raw is None:
        return "", []
    raw = str(raw)
    # The first " _x0000_" (space + null) marks the opening parenthesis.
    head, _, tail = raw.partition(" " + _NULL)
    name = fix_encoding(head)
    synonyms: list[str] = []
    if tail:
        tail_clean = fix_encoding(tail)
        for part in re.split(r"[,/;]", tail_clean):
            tok = part.strip(" )(%-").strip()
            if not tok or _NOISE_SYNONYM.match(tok):
                continue
            if len(tok) < 2 or len(tok) > 60:
                continue
            synonyms.append(tok)
    return name, synonyms


# Heuristic: which headers are ingredients vs conditions/mechanisms.
_OIL_HINTS = ("yağ", "oil", "butter")
_EXTRACT_HINTS = ("ekstr", "özü", "extract")
# Mechanism / condition / epidemiology headers (NOT ingredients) — keep them as
# 'topic' so the report and downstream resolver don't treat them as actives.
_TOPIC_HINTS = (
    "inflamasyon", "inflamatuar", "mekanizma", "kaskad", "faktör", "patogenez",
    "hiperplazi", "dysbiosis", "dyslipidemi", "sitokin", "melano", "melanin",
    "sebum", "hormonal", "vasküler", "telomer", "glycation", "biofilm",
    "defekt", "reaktivite", "mediator", "senescence", "oksidasyon", "kaybı",
    "üretim", "transfer", "integrasyon", "hidrasyon", "durumu", "ciddiyeti",
    "seviyesi", "etkisi", "su içimi", "suiçimi", "stres", "çevre", "makyaj",
    "kırışıklık", "çizgiler", "lekeler", "hiperpigmentasyon", "sensitivite",
    "kızarıklık", "vulgaris", "torbalanma", "morluk", "anatomik", "yolak",
    "feedback", "biofilm", "mikrobiyal", "mikrobiyom", "androjen", "estrojen",
    "insülin", "gland", "birim", "nokta", "aquaporin", "stratum", "corneum",
    "elastin dejenerasyon", "gag ", "agp", "aqp", "igf",
)


def guess_kind(name: str, category: str) -> str:
    n = (name or "").lower()
    if any(h in n for h in _OIL_HINTS):
        return "oil"
    if any(h in n for h in _EXTRACT_HINTS):
        return "extract"
    if any(h in n for h in _TOPIC_HINTS):
        return "topic"
    if (category or "").strip() == "Tedavi Ajanı":
        return "active"
    return "topic"  # condition / mechanism / epidemiology


def build_inventory(xlsx: Path) -> dict:
    import pandas as pd

    mv = pd.read_excel(xlsx, sheet_name="Master Veri")
    mv = mv.fillna("")

    # Header rows define a "box"; following rows until next header are its claims.
    boxes: dict[str, dict] = {}
    current_key: str | None = None

    for _, row in mv.iterrows():
        raw_icerik = str(row.get("İçerik") or "")
        detay = str(row.get("Detay") or "")
        kategori = str(row.get("Kategori") or "").strip()
        alt = str(row.get("Alt Kategori") or "").strip()
        kaynak = str(row.get("Kaynak") or "").strip()
        dosya = str(row.get("Dosya") or "").strip()

        is_header = detay.strip() == "Ana Başlık"
        if is_header:
            name, synonyms = parse_header(raw_icerik)
            if not name:
                continue
            key = name.lower()
            current_key = key
            box = boxes.setdefault(
                key,
                {
                    "name": name,
                    "synonyms": [],
                    "kind": guess_kind(name, kategori),
                    "category": kategori,
                    "subcategories": {},
                    "claims": [],
                    "sources": set(),
                },
            )
            for s in synonyms:
                if s not in box["synonyms"]:
                    box["synonyms"].append(s)
            if dosya:
                box["sources"].add(dosya)
            continue

        # Claim row -> attach to current box.
        claim = fix_encoding(detay)
        if not claim or current_key is None:
            continue
        box = boxes.get(current_key)
        if not box:
            continue
        box["subcategories"][alt] = box["subcategories"].get(alt, 0) + 1
        if dosya:
            box["sources"].add(dosya)
        if len(box["claims"]) < 25:  # keep representative sample, not all 3343
            box["claims"].append(
                {
                    "alt": alt,
                    "text": claim[:400],
                    "kaynak": fix_encoding(kaynak)[:200] or None,
                }
            )

    # Serialize
    items = []
    for box in boxes.values():
        box["sources"] = sorted(box["sources"])
        box["claim_count"] = sum(box["subcategories"].values())
        items.append(box)
    items.sort(key=lambda b: (b["kind"], -b["claim_count"], b["name"]))

    by_kind: dict[str, int] = {}
    for it in items:
        by_kind[it["kind"]] = by_kind.get(it["kind"], 0) + 1

    return {
        "source_file": xlsx.name,
        "box_count": len(items),
        "by_kind": by_kind,
        "boxes": items,
    }


def print_report(inv: dict) -> None:
    print("\n=== MASTER VERİ — TEMİZLENMİŞ ENVANTER ===\n")
    print(f"Kaynak: {inv['source_file']}")
    print(f"Toplam kutu (başlık): {inv['box_count']}")
    print("Tür dağılımı:", inv["by_kind"])
    for kind in ("active", "oil", "extract", "topic"):
        rows = [b for b in inv["boxes"] if b["kind"] == kind]
        if not rows:
            continue
        print(f"\n📁 {kind}  ({len(rows)})")
        for b in rows[:40]:
            syn = f"  syn={b['synonyms'][:4]}" if b["synonyms"] else ""
            print(f"   └─ {b['name']}  [iddia={b['claim_count']}]{syn}")


def main() -> None:
    ap = argparse.ArgumentParser(description="Clean Master Veri Excel into inventory JSON")
    ap.add_argument("--file", default=str(DEFAULT_XLSX))
    ap.add_argument("--no-write", action="store_true")
    args = ap.parse_args()

    xlsx = Path(args.file)
    if not xlsx.is_file():
        raise SystemExit(f"Excel bulunamadı: {xlsx}")

    inv = build_inventory(xlsx)
    if not args.no_write:
        OUT_PATH.write_text(json.dumps(inv, ensure_ascii=False, indent=2), encoding="utf-8")
    print_report(inv)
    if not args.no_write:
        print(f"\nJSON: {OUT_PATH}")


if __name__ == "__main__":
    main()
