"""
Kırmızı çizgiler (kesinlik kuralları) — kullanıcıya “yapma / dikkat” listesi olarak değil,
yalnızca rutin üretim ve güncelleme motorunda zorunlu kısıt olarak kullanılır.

Kapsam: sabah yasakları, doz üst sınırları, birlikte kullanılmaz çiftler (haftalık gün örtüşmesi dahil).
İhlal → adım kaldırma veya metin/doz düzeltme. Özet `rule_enforcement_report` ile API’de izlenebilir;
ön yüzde gösterilmesi zorunlu değildir.
"""

from __future__ import annotations

import copy
import re
from typing import Any, Optional

# ── Katalog (API / ön yüz için tek kaynak) ─────────────────────────────

KESINLIK_ACIKLAMA_TR = (
    "Kesinlik kuralları (kırmızı çizgi): motor rutin oluştururken ve güncellerken ihlalleri otomatik düzeltir veya "
    "adımı çıkarır. Özet `rule_enforcement_report` alanında döner; kullanıcı eğitimi için değil, denetim/iç API içindir."
)

SABAH_KULLANILMAZ: list[dict[str, Any]] = [
    {
        "id": "am_retinoid",
        "etken_grubu_tr": "Retinol, retinal, tretinoin, adapalen ve benzeri retinoidler",
        "aciklama_tr": "Fotosensitizasyon ve UV hasarı riski nedeniyle sabah kullanılmaz; yalnızca akşam.",
        "kesinlik": True,
    },
    {
        "id": "am_bha",
        "etken_grubu_tr": "Salisilik asit (BHA)",
        "aciklama_tr": "Güneşe duyarlılığı ve tahriş birikimi riski; akşam veya haftalık planda.",
        "kesinlik": True,
    },
    {
        "id": "am_benzoyl",
        "etken_grubu_tr": "Benzoil peroksit",
        "aciklama_tr": "Beyazlatma/ kuruluk ve fotosensitizasyon; sabah rutinde yer almaz.",
        "kesinlik": True,
    },
    {
        "id": "am_aha",
        "etken_grubu_tr": "AHA (glikolik, laktik, mandelik asit vb.)",
        "aciklama_tr": "Yüzey yenileme asitleri sabahda önerilmez; akşam ve takvimde.",
        "kesinlik": True,
    },
    {
        "id": "am_arbutin_txa_kojic",
        "etken_grubu_tr": "Alfa-arbutin, arbutin, traneksamik asit, kojik asit, hidrokinon",
        "aciklama_tr": "Leke aktifleri tipik olarak akşam; sabahda C vitamini + SPF önceliklidir.",
        "kesinlik": True,
    },
    {
        "id": "am_azelaic_high_context",
        "etken_grubu_tr": "Azelaik asit (tedavi konsantrasyonu)",
        "aciklama_tr": "Motor varsayılanında akşam adımıdır; sabah satırına düşerse kaldırılır.",
        "kesinlik": True,
    },
]

DOZ_UST_SINIR: list[dict[str, Any]] = [
    {
        "id": "dose_niacinamide_am",
        "etken_tr": "Niasinamid",
        "ust_yuzde": 10,
        "zaman_tr": "Sabah",
        "aciklama_tr": "Sabah rutininde %10 üzeri önerilmez; üstü sınırda %10’a indirilir.",
        "kesinlik": True,
    },
    {
        "id": "dose_laa_serum",
        "etken_tr": "L-Askorbik asit (C vitamini serumu)",
        "ust_yuzde": 20,
        "zaman_tr": "Her zaman",
        "aciklama_tr": "Ev kullanımında %20 üzeri anlatılmaz; metin üst sınıra çekilir.",
        "kesinlik": True,
    },
    {
        "id": "dose_glycolic_face",
        "etken_tr": "Glikolik asit (yüz, ev kullanımı)",
        "ust_yuzde": 10,
        "zaman_tr": "Akşam",
        "aciklama_tr": "Yüz için ev kullanımında %10 üzeri önerilmez.",
        "kesinlik": True,
    },
    {
        "id": "dose_salicylic_leaveon",
        "etken_tr": "Salisilik asit (BHA leave-on)",
        "ust_yuzde": 2,
        "zaman_tr": "Akşam",
        "aciklama_tr": "Tipik güvenli tavan %2; üzeri metinde düşürülür.",
        "kesinlik": True,
    },
    {
        "id": "dose_retinol_otc",
        "etken_tr": "Serbest retinol",
        "ust_yuzde": 1,
        "zaman_tr": "Akşam",
        "aciklama_tr": "Genel ev kullanımı anlatımında retinol %1 üstü sınırlanır (reçete/doktor ayrı).",
        "kesinlik": True,
    },
]

BIRLIKTE_KULLANILMAZ: list[dict[str, Any]] = [
    {
        "id": "pair_retinoid_aha",
        "a_tr": "Retinoid (retinol, retinal, adapalen, tretinoin)",
        "b_tr": "AHA (glikolik, laktik vb.)",
        "kapsam_tr": "Aynı gece, örtüşen haftalık günler",
        "cozum_tr": "Retinoid kalır; AHA içeren satır kaldırılır.",
        "aciklama_tr": "Aynı uygulamada bariyer tahrişi ve yanma riski çok yüksek.",
        "kesinlik": True,
    },
    {
        "id": "pair_retinoid_bha",
        "a_tr": "Retinoid",
        "b_tr": "BHA (salisilik asit)",
        "kapsam_tr": "Aynı gece, örtüşen haftalık günler",
        "cozum_tr": "Retinoid kalır; BHA satırı kaldırılır.",
        "aciklama_tr": "İki güçlü keratolitik üst üste önerilmez.",
        "kesinlik": True,
    },
    {
        "id": "pair_retinoid_benzoyl",
        "a_tr": "Retinoid",
        "b_tr": "Benzoil peroksit",
        "kapsam_tr": "Aynı gece, örtüşen haftalık günler",
        "cozum_tr": "Retinoid kalır; benzoil satırı kaldırılır.",
        "aciklama_tr": "BP retinoid stabilitesini bozabilir; aynı seansta birlikte önerilmez.",
        "kesinlik": True,
    },
    {
        "id": "pair_aha_cvit_same_session",
        "a_tr": "AHA / BHA (yüzey asidi)",
        "b_tr": "L-Askorbik asit (düşük pH C)",
        "kapsam_tr": "Aynı zaman dilimi (aynı sabah veya aynı akşam üst üste)",
        "cozum_tr": "Aynı gün diliminde asit içeren satır kaldırılır; C vitamini öncelikli sabahda tutulur.",
        "aciklama_tr": "pH çakışması ve tahriş; pratikte ayrı zaman veya gün.",
        "kesinlik": True,
    },
]


def get_absolute_rules_catalog() -> dict[str, Any]:
    return {
        "kesinlik_aciklama_tr": KESINLIK_ACIKLAMA_TR,
        "sabah_kullanilmaz": SABAH_KULLANILMAZ,
        "doz_ust_sinir": DOZ_UST_SINIR,
        "birlikte_kullanilmaz": BIRLIKTE_KULLANILMAZ,
    }


# ── Uygulama yardımcıları ─────────────────────────────────────────────

def _norm_time(t: Optional[str]) -> str:
    return (t or "").strip().lower()


def _item_text(it: dict) -> str:
    return f"{it.get('action', '')} {it.get('detail', '')}"


def _morning_negation_context(text: str) -> bool:
    t = text.lower()
    return any(
        p in t
        for p in (
            "sabahda yok",
            "sabahda kullanılmaz",
            "sabahda bp yok",
            "sabahda asit",
            "sabaha ek",
            "sabaha başka",
            "sabah kullanılmaz",
            "sabahda güçlü",
        )
    )


# Sabah yasak: action+detail içinde geçer
_MORNING_FORBIDDEN_RES = [
    re.compile(r"tretinoin|adapalen|adapalene|retinal\b|retinoid\b|\bretinol\b", re.I),
    re.compile(r"a\s*vitamini\s*alkol", re.I),
    re.compile(r"salisilik\s*asit|salicylic\s*acid", re.I),
    re.compile(r"\bbha\b", re.I),
    re.compile(r"benzoil|benzoyl", re.I),
    re.compile(r"glikolik|glycolic|laktik\s*asit|lactic\s*acid|mandelik|mandelic", re.I),
    re.compile(r"alfa-?arbutin|\barbutin\b", re.I),
    re.compile(r"traneksamik|tranexamic", re.I),
    re.compile(r"kojik|hidrokinon|hydroquinone", re.I),
    re.compile(r"azelaik|azelaic", re.I),
]


def _morning_violation(it: dict) -> bool:
    """Yalnızca `action` satırına bakılır; açıklamada geçen 'gece retinol' vb. yanlış pozitif çıkmaz."""
    if _norm_time(it.get("time")) != "sabah":
        return False
    if it.get("category") not in ("Bakım", "Koruma"):
        return False
    act = it.get("action") or ""
    if _morning_negation_context(act.lower()):
        return False
    return any(rx.search(act) for rx in _MORNING_FORBIDDEN_RES)


def _families_for_combo(it: dict) -> set[str]:
    t = _item_text(it).lower()
    s: set[str] = set()
    if any(k in t for k in ("retinol", "retinal", "tretinoin", "adapalen", "adapalen", "retinoid")):
        s.add("retinoid")
    if "a vitamini alkol" in t or "vitamin a alcohol" in t:
        s.add("retinoid")
    if "bakuchiol" in t:
        s.add("retinoid")
    if "glikolik" in t or "glycolic" in t or "laktik asit" in t or "lactic acid" in t or "mandelik" in t:
        s.add("aha")
    if "salisilik" in t or "salicylic" in t or re.search(r"\bbha\b", t):
        s.add("bha")
    if "benzoil" in t or "benzoyl" in t:
        s.add("benzoyl")
    if any(
        k in t
        for k in ("askorbik", "ascorbic", "l-askorbik", "c vitamini", "vitamin c", "l-aa")
    ):
        s.add("laa_c")
    return s


def _weekly_overlap(a: dict, b: dict) -> bool:
    wa = a.get("weekly_days")
    wb = b.get("weekly_days")
    if not isinstance(wa, list) or len(wa) == 0:
        return True
    if not isinstance(wb, list) or len(wb) == 0:
        return True
    return bool(set(wa) & set(wb))


def _same_time_slot(a: dict, b: dict) -> bool:
    return _norm_time(a.get("time")) == _norm_time(b.get("time"))


def _enforce_morning_ban(items: list[dict]) -> tuple[list[dict], list[dict]]:
    out: list[dict] = []
    removed: list[dict] = []
    for it in items:
        if _morning_violation(it):
            removed.append(
                {
                    "kural_id": "sabah_kullanilmaz",
                    "action": it.get("action"),
                    "time": it.get("time"),
                    "aciklama_tr": "Sabah kullanılmayacak etken içerdiği için adım çıkarıldı.",
                }
            )
            continue
        out.append(it)
    return out, removed


def _replace_pct_after_keyword(text: str, keywords: tuple[str, ...], max_pct: float) -> tuple[str, bool]:
    if not text:
        return text, False
    changed = False
    lower = text.lower()

    for kw in keywords:
        pos = 0
        while True:
            idx = lower.find(kw, pos)
            if idx == -1:
                break
            window = text[idx : idx + 80]
            new_window, _ = _replace_pct_in_window(window, max_pct)
            if new_window != window:
                text = text[:idx] + new_window + text[idx + len(window) :]
                lower = text.lower()
                changed = True
            pos = idx + len(kw)
    return text, changed


def _replace_pct_in_window(window: str, max_pct: float) -> tuple[str, bool]:
    changed = False

    def cap_num(m: re.Match) -> str:
        nonlocal changed
        try:
            v = float(m.group(1).replace(",", "."))
        except ValueError:
            return m.group(0)
        if v > max_pct:
            changed = True
            s = str(int(max_pct)) if max_pct == int(max_pct) else str(max_pct)
            return m.group(0).replace(m.group(1), s)
        return m.group(0)

    w = re.sub(r"(\d+(?:[.,]\d+)?)\s*%", cap_num, window)
    return w, changed


def _enforce_dose_caps(items: list[dict]) -> tuple[list[dict], list[dict]]:
    report: list[dict] = []
    out: list[dict] = []
    for it in items:
        if it.get("category") != "Bakım":
            out.append(it)
            continue
        nit = copy.deepcopy(it)
        combined_changed = False
        for field in ("action", "detail"):
            val = nit.get(field) or ""
            new_val = val
            t = _norm_time(nit.get("time"))
            if t == "sabah":
                new_val, ch = _replace_pct_after_keyword(
                    new_val,
                    ("niasinamid", "niacinamide", "niacinamid"),
                    10.0,
                )
                combined_changed = combined_changed or ch
            new_val, ch2 = _replace_pct_after_keyword(
                new_val,
                ("askorbik", "ascorbic", "l-askorbik"),
                20.0,
            )
            combined_changed = combined_changed or ch2
            new_val, ch3 = _replace_pct_after_keyword(
                new_val,
                ("glikolik", "glycolic"),
                10.0,
            )
            combined_changed = combined_changed or ch3
            new_val, ch4 = _replace_pct_after_keyword(
                new_val,
                ("salisilik", "salicylic"),
                2.0,
            )
            combined_changed = combined_changed or ch4
            new_val, ch5 = _replace_pct_after_keyword(
                new_val,
                ("retinol",),
                1.0,
            )
            combined_changed = combined_changed or ch5
            nit[field] = new_val
        if combined_changed:
            report.append(
                {
                    "kural_id": "doz_ust_sinir",
                    "action": it.get("action"),
                    "aciklama_tr": "İzin verilen üst doz aşıldığı için metin sınırlandı.",
                }
            )
        out.append(nit)
    return out, report


def _enforce_combo_rules_fixed(items: list[dict]) -> tuple[list[dict], list[dict]]:
    skincare_indices = [i for i, x in enumerate(items) if x.get("category") == "Bakım"]
    drop: set[int] = set()
    removed_log: list[dict] = []

    for ii, i in enumerate(skincare_indices):
        if i in drop:
            continue
        a = items[i]
        fa = _families_for_combo(a)
        if not fa:
            continue
        for jj in range(ii + 1, len(skincare_indices)):
            j = skincare_indices[jj]
            if j in drop:
                continue
            b = items[j]
            fb = _families_for_combo(b)
            if not fb:
                continue
            if not _same_time_slot(a, b):
                continue
            if not _weekly_overlap(a, b):
                continue

            if "retinoid" in fa and ("aha" in fb or "bha" in fb or "benzoyl" in fb):
                drop.add(j)
                removed_log.append(
                    {
                        "kural_id": "pair_retinoid_acid_bp",
                        "cikarilan_action": b.get("action"),
                        "tutan_action": a.get("action"),
                        "aciklama_tr": "Retinoid ile aynı gece örtüşen satır kesinlik kuralıyla kaldırıldı.",
                    }
                )
                continue
            if "retinoid" in fb and ("aha" in fa or "bha" in fa or "benzoyl" in fa):
                drop.add(i)
                removed_log.append(
                    {
                        "kural_id": "pair_retinoid_acid_bp",
                        "cikarilan_action": a.get("action"),
                        "tutan_action": b.get("action"),
                        "aciklama_tr": "Retinoid ile aynı gece örtüşen satır kesinlik kuralıyla kaldırıldı.",
                    }
                )
                break

            if ("laa_c" in fa and (fb & {"aha", "bha"})) or ("laa_c" in fb and (fa & {"aha", "bha"})):
                if "laa_c" in fa and (fb & {"aha", "bha"}):
                    drop.add(j)
                    removed_log.append(
                        {
                            "kural_id": "pair_c_acid",
                            "cikarilan_action": b.get("action"),
                            "tutan_action": a.get("action"),
                            "aciklama_tr": "Aynı zaman diliminde C vitamini ile yüzey asidi birlikte bırakılmadı.",
                        }
                    )
                else:
                    drop.add(i)
                    removed_log.append(
                        {
                            "kural_id": "pair_c_acid",
                            "cikarilan_action": a.get("action"),
                            "tutan_action": b.get("action"),
                            "aciklama_tr": "Aynı zaman diliminde C vitamini ile yüzey asidi birlikte bırakılmadı.",
                        }
                    )
                    break

    out = [copy.deepcopy(x) for k, x in enumerate(items) if k not in drop]
    return out, removed_log


def enforce_absolute_rules_on_routine(items: list[dict]) -> tuple[list[dict], dict[str, Any]]:
    """
    Kırmızı çizgileri rutin satırlarına uygular (Flow sonrası, AI polish sonrası, check-in sonrası).
    Liste kopyalanır; dönüş değeri yeni liste + uygulama raporu.
    """
    base = [copy.deepcopy(x) for x in items]
    rapor: dict[str, Any] = {"kesinlik": True, "sabah_kaldirilan": [], "doz_sinirlanan": [], "birlikte_cozulen": []}

    step1, r1 = _enforce_morning_ban(base)
    rapor["sabah_kaldirilan"].extend(r1)

    step2, r2 = _enforce_dose_caps(step1)
    rapor["doz_sinirlanan"].extend(r2)

    step3, r3 = _enforce_combo_rules_fixed(step2)
    rapor["birlikte_cozulen"].extend(r3)

    return step3, rapor
