"""
Türkçe ve İngilizce cilt bakımı ifadelerini vektör araması için zenginleştirme.
Embedding tek dize aldığından, tetiklenen kavramlara klinik eş anlamlılar (çoğunlukla İngilizce) eklenir.
"""

from __future__ import annotations

import re
import unicodedata
from typing import Optional

# Tetikleyiciler: normalize (NFD + Mn kaldır + casefold) sonrası alt dizgi eşleşmesi — TR + EN
_SKIN_EXPANSIONS: tuple[tuple[tuple[str, ...], str], ...] = (
    (
        (
            "hassas",
            "hassasiyet",
            "reaktif",
            "intolerans",
            "allerj",
            "fragrans",
            "sensitive",
            "reactiv",
            "intolerant",
            "allerg",
            "fragrance",
        ),
        "sensitive skin skin barrier irritant contact dermatitis stinging",
    ),
    (
        (
            "kizar",
            "kizari",
            "eritem",
            "flush",
            "kizarmis",
            "redness",
            "erythema",
            "flushing",
            "rosacea",
            "blotch",
            "inflamed",
            "red ",
            " red",
        ),
        "facial redness erythema flushing rosacea inflammatory skin",
    ),
    (
        (
            "nemlendir",
            "nemlendirme",
            "kuruluk",
            "kuru cilt",
            "kurumus",
            "nemsiz",
            "moistur",
            "hydrat",
            "dehydrat",
            "dry skin",
            "dryness",
            "xerosis",
        ),
        "moisturizer humectant emollient skin hydration dry skin TEWL barrier repair ceramide",
    ),
    (
        ("bariyer", "microbiom", "mikrobiyom", "barrier", "microbiome", "acid mantle"),
        "skin barrier stratum corneum lipids epidermal barrier function",
    ),
    (
        (
            "tahris",
            "irit",
            "yanma",
            "batma",
            "aciyo",
            "cildim yan",
            "irritat",
            "stinging",
            "burning",
            "tingling",
        ),
        "skin irritation stinging burning compromised barrier",
    ),
    (
        (
            "sivilce",
            "akne",
            "comedo",
            "gozenek",
            "sebum",
            "yagli",
            "acne",
            "pimple",
            "breakout",
            "comedone",
            "blackhead",
            "whitehead",
            "oily skin",
            "large pores",
        ),
        "acne vulgaris sebum comedones pores oily skin",
    ),
    (
        ("gunes", "spf", "uv ", "uvb", "uva", "sunscreen", "sun screen", "photoprotect"),
        "sunscreen photoprotection UV damage SPF",
    ),
    (
        (
            "antioksidan",
            "askorbik",
            "peptid",
            "antioxidant",
            "ascorbic",
            "peptide",
            "vitamin c",
            "niacinamide",
        ),
        "topical antioxidant serum niacinamide ascorbic acid peptides",
    ),
    (
        (
            "retinol",
            "retinoid",
            "tretinoin",
            "adapalen",
            "isotretinoin",
            "bakuchiol",
            "retin-a",
            "tazarotene",
        ),
        "retinol retinoids vitamin A derivatives topical anti-aging collagen remodeling irritation potential",
    ),
    (
        (
            "gece",
            "sabah",
            "rutin",
            "am routine",
            "pm routine",
            "morning routine",
            "night routine",
            "evening routine",
            "skincare routine",
        ),
        "skincare routine AM PM layering",
    ),
)


def _normalize_match(s: str) -> str:
    t = unicodedata.normalize("NFD", (s or "").strip())
    t = "".join(c for c in t if unicodedata.category(c) != "Mn")
    return t.casefold()


def expand_skin_query_for_vector_search(
    user_message: str,
    *,
    cleaned_query: Optional[str] = None,
    max_len: int = 520,
) -> Optional[str]:
    """
    TR veya EN mesajda tanınan terimler varsa embedding için eş anlamlı blok üretir.
    Tetik yoksa None (ikinci vektör araması atlanır).
    """
    raw = (user_message or "").strip()
    if len(raw) < 2:
        return None
    n = _normalize_match(raw)
    if cleaned_query:
        n = n + " " + _normalize_match(cleaned_query)

    extras: list[str] = []
    for triggers, blob in _SKIN_EXPANSIONS:
        if any(tr in n for tr in triggers):
            extras.append(blob)

    if not extras:
        return None

    seen: set[str] = set()
    ordered: list[str] = []
    for e in extras:
        if e not in seen:
            seen.add(e)
            ordered.append(e)

    core = (cleaned_query or raw).strip()
    extra = " ".join(ordered)
    combined = f"{core} | {extra}".strip()
    if len(combined) > max_len:
        combined = combined[:max_len].rsplit(" ", 1)[0]
    return combined


def strip_conversational_fillers(q: str) -> str:
    """TR + EN: embedding öncesi soru kalıbı, zamir ve dolgu sözcükleri."""
    t = (q or "").strip()
    if len(t) < 2:
        return t
    t2 = re.sub(
        r"\b(nedir|ne demek|nelerdir|hakkında|hakkinda|yüzüm|yuzum|yüzümde|yuzumde|"
        r"bana|şunu|sunu|neden|niye|nasıl|nasil|ne yapay|ne öner|ne oner|konuda|"
        r"çok|gibi|biraz|hala|hâlâ|halen|yardim|yardım|lütfen|lutfen)\b",
        " ",
        t,
        flags=re.I,
    )
    t2 = re.sub(
        r"\b(what is|what are|what's|whats|how do i|how can i|how should|why is|why does|"
        r"recommend|recommendation|suggestions?|suggest|advice|please|help me|could you|would you|"
        r"my face|on my face|on my|for my skin|about my|skin is|face is|my skin|"
        r"should i|can i use|can i|could i|may i|is it ok|is it safe|anything else|tell me|"
        r"use it|apply it|put it|"
        r"not enough|doesn't work|does not work|doesnt work|"
        r"too much|a lot|really|pretty|kind of|sort of|so much|still|yet)\b",
        " ",
        t2,
        flags=re.I,
    )
    t2 = re.sub(r"\b(and|or|but|it|is|are|was|were)\b", " ", t2, flags=re.I)
    t2 = re.sub(r"[?¿!…\.]+$", "", t2.strip())
    t2 = " ".join(t2.split()).strip()
    return t2 if len(t2) >= 2 else t


# Geriye dönük import adı
strip_conversational_turkish = strip_conversational_fillers
