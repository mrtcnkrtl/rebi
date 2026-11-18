"""
Aktif madde dosyesi — doz kademeleri + sistem seçim kuralları (tek kaynak).

Konsantrasyon yükselt/indir (`dose_tier` / check-in) buradaki iskeletin üstündedir.
Kullanıcı menü seçmez; `pick_*` fonksiyonları tek madde döner.

Kaynak: CIR/SCCS/FDA + klinik özetler (ürün sahibi onaylı derleme, 2026-11).
Ev leave-on kozmetik; klinik peeling dozları (%15+ AHA wash-off) yazılmaz.
"""

from __future__ import annotations

from typing import Any, Optional

# ── Bilinçli aday değil (tekil leave-on rutin adımı olarak) ─────────────
NOT_MONO_CANDIDATE = frozenset(
    {
        "malic_acid",  # yalnız kombo peeling / pH tampon
        "glycerin",  # formül içi humektan; ayrı adım değil (dar istisna aşağıda)
        "ferulic_acid",  # C olmadan sabah antioksidan yerine geçmez
    }
)

# Seramid yerine geçmez; yanında destek
BARRIER_SUPPORT_ONLY = frozenset({"aloe_vera", "shea_butter", "colloidal_oatmeal"})

# ── Doz kademeleri (NEW_ACTIVE_DOSES ile birleşir) ─────────────────────
# pct + freq; source=user → onaylı bant.
DOSES: dict[str, dict] = {
    "glycolic": {
        "tiers": {
            "hassas": {
                "pct": "%5-8",
                "freq": "haftada 1 gece ile başla; tolere ediliyorsa haftada 2",
                "ph_min": 3.5,
            },
            "standart": {
                "pct": "%8-10",
                "freq": "haftada 2-3 gece",
                "ph_min": 3.5,
            },
            "yogun": {
                "pct": "%10",
                "freq": "haftada 2-3 gece; art arda gece yok",
                "ph_min": 3.5,
                "warning": "Leave-on tavan %10 (CIR/FDA). %15+ klinik peeling; ev gece dozuna yazılmaz.",
            },
        },
        "leave_on_cap": "%10",
        "source": "user",
        "info": "Fotosensitivite artar; sabah SPF zorunlu. 76 Da; en hızlı AHA.",
    },
    "lactic": {
        "tiers": {
            "hassas": {"pct": "%5", "freq": "haftada 1-2 gece"},
            "standart": {"pct": "%5-8", "freq": "haftada 2-3 gece"},
            "yogun": {
                "pct": "%10",
                "freq": "haftada 2-3 gece",
                "warning": "%12+ ilaç düzeyi (ör. amonyum laktat); kozmetik rutine yazılmaz.",
            },
        },
        "leave_on_cap": "%10",
        "source": "user",
        "info": "90 Da; NMF bileşeni; kuru/dehidre/hafif hassasta glikolik yerine.",
    },
    "kojic": {
        "tiers": {
            "hassas": {"pct": "%1", "freq": "günde 1 kez akşam; tahrişte günaşırı"},
            "standart": {"pct": "%1", "freq": "günde 1 kez akşam"},
            "yogun": {
                "pct": "%1",
                "freq": "günde 1 kez akşam",
                "warning": "AB SCCS yüz/el ürünlerinde en fazla %1. Daha yüksek bantlar rutine yazılmaz.",
            },
        },
        "leave_on_cap": "%1",
        "source": "user",
        "info": "Tirozinaz şelasyonu; epidermal PIH / solar lentigo. Kararsız; temas dermatiti riski.",
    },
    "cay_agaci": {
        "tiers": {
            "hassas": {"pct": "%5 jel", "freq": "günde 1; yalnızca noktasal"},
            "standart": {"pct": "%5 jel", "freq": "günde 1; inflamatuar lezyona noktasal"},
            "yogun": {"pct": "%5 jel", "freq": "günde 1-2; noktasal, tüm yüz değil"},
        },
        "source": "user",
        "info": "Terpinen-4-ol; hafif-orta inflamatuar akne. Saf yağ yazılmaz. Okside yağ alerjen olabilir.",
    },
    "aloe": {
        "tiers": {
            "hassas": {"pct": "ekstrakt %1-5 veya saf jel bazı", "freq": "sabah ve/veya akşam"},
            "standart": {"pct": "ekstrakt %5-10 veya jel bazı", "freq": "sabah ve akşam"},
            "yogun": {"pct": "ekstrakt %5-10", "freq": "günde 1-2"},
        },
        "source": "user",
        "info": "Yatıştırıcı/nem; lipid bariyer yerine geçmez. Decolorized (aloinsiz) tercih.",
        "support_only": True,
    },
    "shea": {
        "tiers": {
            "hassas": {"pct": "formül payı %1-3", "freq": "akşam nemlendiricide"},
            "standart": {"pct": "formül payı %3-5 (yüz kremi)", "freq": "akşam"},
            "yogun": {"pct": "balm payı %10-20", "freq": "çok kuru alanlarda"},
        },
        "source": "user",
        "info": "Emoliyan/oklüzif. Yağlı/akneli yüzde %5 üzerine çıkma.",
        "support_only": True,
        "avoid_skin": ("oily",),
    },
    "colloidal_oatmeal": {
        "tiers": {
            "hassas": {"pct": "%0.5-1", "freq": "sabah ve akşam"},
            "standart": {"pct": "%1-2", "freq": "sabah ve akşam"},
            "yogun": {"pct": "%2-5", "freq": "atak/egzama döneminde günde 2-3"},
        },
        "source": "user",
        "info": "FDA cilt koruyucu; avenantramid. Yulaf alerjisinde kullanma. Seramid yerine değil.",
        "support_only": True,
    },
    "glycerin": {
        "tiers": {
            "hassas": {"pct": "nemlendirici içinde %3-5", "freq": "her uygulama"},
            "standart": {"pct": "nemlendirici içinde %3-10", "freq": "her uygulama"},
            "yogun": {"pct": "nemlendirici içinde %5-10", "freq": "her uygulama"},
        },
        "source": "user",
        "info": "Humektan; ayrı mono-adım değil. Üstü emoliyan/oklüzifle kapatılmalı.",
        "mono_step": False,
    },
    "vitamin_e": {
        "tiers": {
            "hassas": {"pct": "%0.1-0.5", "freq": "sabah (CEF veya nemlendiricide)"},
            "standart": {"pct": "%0.5-1", "freq": "sabah; CEF içinde %1"},
            "yogun": {
                "pct": "%1-2",
                "freq": "kuru ciltte nemlendiricide",
                "warning": "%1 üzeri tekil oran yağlı/aknede komedojenite ve kontakt riskini artırır.",
            },
        },
        "cef_pct": "%1",
        "source": "user",
        "info": "En iyi kanıt C+E+ferulik. C yerine tek başına sabah antioksidanı yazılmaz.",
    },
    "ferulic": {
        "tiers": {
            "hassas": {"pct": "%0.2-0.5", "freq": "C vitamini ile sabah"},
            "standart": {"pct": "%0.5", "freq": "CEF içinde sabah"},
            "yogun": {"pct": "%0.5-1", "freq": "CEF içinde; çözünürlük sınırı"},
        },
        "cef_pct": "%0.5",
        "source": "user",
        "info": "Duke/Pinnell: %15 LAA + %1 E + %0.5 ferulik. C yoksa C alternatifi değil.",
        "requires_vitamin_c": True,
    },
}


def merge_into_new_active_doses(target: dict) -> None:
    """NEW_ACTIVE_DOSES sözlüğüne dosya dozlarını ekler (yerinde). PHA vb. mevcut anahtarlar korunur."""
    key_map = {
        "glycolic": "glycolic",
        "lactic": "lactic",
        "kojic": "kojic",
        "cay_agaci": "cay_agaci",
        "aloe": "aloe",
        "shea": "shea",
        "colloidal_oatmeal": "colloidal_oatmeal",
        "glycerin": "glycerin",
        "vitamin_e": "vitamin_e",
        "ferulic": "ferulic",
    }
    for dossier_key, na_key in key_map.items():
        if na_key not in target:
            target[na_key] = dict(DOSES[dossier_key])


# ── Seçim kuralları ───────────────────────────────────────────────────


def pick_pigment_active(
    *,
    score: int,
    gentle: bool,
    pregnant: bool,
    retinol_ok: bool,
    avoid_retinol: bool = False,
    avoid_txa: bool = False,
) -> str:
    """
    Tek leke çekirdeği.
    Dönüş: nag_niacinamide | retinol | licorice | kojic | niacin_txa
    """
    if pregnant:
        return "nag_niacinamide"
    if (
        score >= 7
        and retinol_ok
        and not avoid_retinol
        and not gentle
    ):
        return "retinol"
    if gentle:
        return "licorice"
    if avoid_txa:
        return "kojic"
    # Hafif epidermal PIH / solar lentigo bandı: TXA ilk sıra değil → kojik.
    if score <= 3:
        return "kojic"
    return "niacin_txa"


def pick_acne_antibacterial(
    *,
    score: int,
    avoid_bpo: bool,
    prefer_azelaic: bool = False,
    stings: bool = False,
) -> str:
    """
    İnflamatuar akne antibakteriyel çekirdek (tek).
    Dönüş: benzoyl | sulfur | azelaic | tea_tree
    """
    if score <= 3 and (avoid_bpo or stings):
        # Hafif inflamatuar + BPO/tahriş kaçınma → noktasal çay ağacı
        return "tea_tree"
    if avoid_bpo or prefer_azelaic:
        return "azelaic"
    if score >= 7:
        return "benzoyl"
    if score >= 4:
        return "azelaic"
    return "tea_tree"


def pick_aha(
    *,
    skin_key: str = "",
    gentle: bool = False,
    avoid_aha: bool = False,
    wants_renewal: bool = True,
    dark_phototype: bool = False,
    high_uv_season: bool = False,
    on_strong_actives: bool = False,
) -> Optional[str]:
    """
    Yüzey yenileme asidi (tek). Yoksa None.
    Dönüş: glycolic | lactic | mandelic | pha | None
    """
    if not wants_renewal:
        return None
    key = (skin_key or "").lower()
    if avoid_aha or gentle or key in ("sensitive", "dry") or dark_phototype or high_uv_season or on_strong_actives:
        if key == "dry" or gentle or avoid_aha or key == "sensitive":
            # PHA: nazik; laktik: kuru/dehidre nemli eksfoliasyon
            if key == "dry" and not avoid_aha and not dark_phototype and not high_uv_season:
                return "lactic"
            return "pha" if (avoid_aha or key == "sensitive" or dark_phototype or high_uv_season or on_strong_actives) else "mandelic"
        return "mandelic"
    if key in ("oily", "combination") or key == "normal":
        return "glycolic"
    return "lactic"


def wants_pha(
    *,
    skin_key: str = "",
    gentle: bool = False,
    avoid_aha: bool = False,
    oily_sensitive: bool = False,
    sensitivity_score: int = 0,
    dark_phototype: bool = False,
    high_uv_season: bool = False,
    on_retinoid_or_bpo_or_high_c: bool = False,
    aha_intolerance: bool = False,
) -> bool:
    """PHA geniş kapısı — yalnızca nazik yenileme gerektiğinde."""
    if oily_sensitive and gentle:
        return True
    if aha_intolerance or avoid_aha:
        return True
    if (skin_key or "").lower() == "sensitive" or sensitivity_score >= 5:
        return True
    if dark_phototype or high_uv_season:
        return True
    if on_retinoid_or_bpo_or_high_c and gentle:
        return True
    return False


def barrier_supports(
    *,
    skin_key: str = "",
    itching: bool = False,
    high_tewl: bool = False,
    redness: bool = False,
) -> list[str]:
    """
    Seramid çekirdeğinin YANINA eklenebilecek destekler (yerine değil).
    Sıra: yulaf (kaşıntı/kızarıklık) → aloe (sulı yatışma) → shea (yüksek TEWL, yağlı değilse).
    """
    out: list[str] = []
    key = (skin_key or "").lower()
    if itching or redness:
        out.append("colloidal_oatmeal")
    if redness or itching:
        out.append("aloe")
    if high_tewl and key not in ("oily",):
        out.append("shea")
    return out


def cef_stack_ok(*, has_vitamin_c: bool) -> bool:
    """E+ferulik yalnızca C ile CEF olarak yazılır."""
    return bool(has_vitamin_c)


def dossier_snapshot() -> dict[str, Any]:
    """Test / denetim için özet."""
    return {
        "dose_keys": sorted(DOSES),
        "not_mono": sorted(NOT_MONO_CANDIDATE),
        "barrier_support_only": sorted(BARRIER_SUPPORT_ONLY),
    }
