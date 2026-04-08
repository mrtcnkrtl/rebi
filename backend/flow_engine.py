"""
REBI AI - Akış Motoru v5.0 (Flow Engine)
==========================================
Deterministik karar ağacı + Adaptif Rutin Sistemi.

v5 Yenilikler:
- INGREDIENT_DB entegrasyonu (bilimsel veri-driven konsantrasyonlar)
- Risk skoru sistemi (stres + su + nem + uyku)
- Günlük check-in adaptasyonu (adapt_existing_routine)
- Senaryo eşleştirme (6 klinik senaryo)
- Her madde için frequency, evidence_level, expected_result, ingredient_key

v4 Devam:
- Hamilelik güvenlik filtresi (kontrendike madde otomatik değişimi)
- Hormonal döngü modifiyeleri (adet fazına göre rutin adaptasyonu)
- Akne bölge analizi (yüz haritası → neden analizi → hedefli tedavi)
- Yaş grubu x Concern x Cilt Tipi matrisi
- Madde uyumluluk kontrolü (ingredient conflict check)
- Holistic yaşam motoru (beslenme, egzersiz, supplement)
- Stres testi TÜM concern'ler için aktif

Kırmızı çizgiler (sabah yasağı, doz tavanı, çakışmalar) `skincare_absolute_rules` ile run_flow içinde
ve API’de AI polish sonrası tekrar uygulanır; kullanıcıya liste olarak gösterilmesi gerekmez.

Mimari:
    Kullanıcı Girişi
         │
    ┌────▼─────┐
    │ CONCERN   │── Akne / Yaşlanma / Leke / Kuruluk / Hassasiyet
    │ ROUTER    │
    └────┬─────┘
         │
    ┌────▼──────────┐
    │ AGE GROUP      │── Genç(15-19) / Yetişkin(20-29) / Orta(30-39) /
    │ CLASSIFIER     │   Olgun(40-49) / İleri(50+)
    └────┬──────────┘
         │
    ┌────▼──────────┐
    │ HORMONAL       │── Hamilelik? / Döngü Fazı / Menopoz
    │ MODIFIER       │   (sadece kadın kullanıcılar)
    └────┬──────────┘
         │
    ┌────▼──────────┐
    │ SKIN TYPE      │── Yağlı / Kuru / Karma / Normal / Hassas
    │ MODIFIER       │
    └────┬──────────┘
         │
    ┌────▼──────────┐
    │ SEVERITY       │── Hafif(1-3) / Orta(4-6) / Şiddetli(7-10)
    │ CLASSIFIER     │
    └────┬──────────┘
         │
    ┌────▼──────────┐
    │ ACNE ZONE      │── Alın / Burun / Yanak / Çene / Şakak
    │ ANALYZER       │   (sadece akne concern'ünde)
    └────┬──────────┘
         │
    ┌────▼──────────┐
    │ INGREDIENT     │── Uyumluluk kontrolü + Sabah/Akşam ayrımı
    │ COMPATIBILITY  │
    └────┬──────────┘
         │
    ┌────▼──────────┐
    │ PREGNANCY      │── Güvensiz madde → Güvenli alternatif
    │ SAFETY FILTER  │   (hamile ise son katman)
    └────┬──────────┘
         │
    ┌────▼──────────┐
    │ LIFESTYLE +    │── Stres / Uyku / Su / Sigara / Alkol
    │ HOLISTIC       │── Beslenme / Egzersiz / Supplement
    └────┬──────────┘
         │
    ┌────▼──────────┐
    │ ENVIRONMENT    │── UV / Nem / Sıcaklık
    │ MODIFIERS      │
    └────┬──────────┘
         │
    ┌────▼──────────┐
    │ ROUTINE        │── Sabah + Akşam + Yaşamsal öneriler
    │ ASSEMBLER      │
    └───────────────┘
"""

import re
from typing import Optional


def sanitize_routine_detail_system_voice(detail: str) -> str:
    """
    Kullanıcıya sıklığı/kararı bırakan veya AI'nin eklediği kalıpları temizle.
    Sıklık ve uyarlama weekly_days + check-in motorunda tanımlanır.
    """
    if not detail or not str(detail).strip():
        return detail
    d = str(detail)
    strip_patterns = (
        r"Gerekirse ilk haftalar[^.]*\.\s*",
        r"(?:\s|;)+tolere edince[^.]*\.\s*",
        r"check-in ile sıkılık[^.]*\.\s*",
        r"Gerekirse check-in ile[^.]*\.\s*",
        r"Tahrişte check-in ile[^.]*\.\s*",
        r"check-in ile yumuşatılır[^.]*\.\s*",
        r"İlk kullanım:\s*düşük sıklıkla başla[^.]*\.\s*",
    )
    for p in strip_patterns:
        d = re.sub(p, "", d, flags=re.IGNORECASE)
    d = re.sub(r"\s{2,}", " ", d).strip()
    d = re.sub(r"\s+\.", ".", d)
    return d


def sanitize_routine_items_details(items: list) -> None:
    for it in items or []:
        if it.get("detail"):
            it["detail"] = sanitize_routine_detail_system_voice(it["detail"])


def _niacinamide_start_pct(exp_norm: str, merged_tol: dict) -> str:
    """İlk rutinde %5’e sıçramayı önle: deneyim + B3 toleransına göre başlangıç %."""
    tol = merged_tol or {}
    nia = (tol.get("niacinamide") or tol.get("niacinamid") or "").lower()
    if nia in ("never", "mild"):
        return "2.5"
    if exp_norm == "none":
        return "2.5"
    if exp_norm == "occasional":
        return "4"
    return "5"


def _apply_niacinamide_pct_to_routine_items(items: list, pct: str) -> None:
    if pct == "5":
        return
    for it in items or []:
        for k in ("action", "detail"):
            v = it.get(k)
            if not isinstance(v, str):
                continue
            v2 = re.sub(r"(?i)\bNiacinamide\s*%5\b", f"Niacinamide %{pct}", v)
            it[k] = re.sub(r"(?i)\bNiasinamid\s*%5\b", f"Niasinamid %{pct}", v2)


def _apply_niacinamide_pct_to_skin_profile(skin_type: dict, pct: str) -> None:
    if pct == "5" or not skin_type:
        return
    for k in ("moisturizer_type", "night_cream", "sunscreen"):
        v = skin_type.get(k)
        if isinstance(v, str):
            v2 = re.sub(r"(?i)\bNiacinamide %5\b", f"Niacinamide %{pct}", v)
            skin_type[k] = re.sub(r"(?i)\bNiasinamid %5\b", f"Niasinamid %{pct}", v2)


def _active_strength_stage(exp_norm: str, merged_tol: dict, risk_level: str) -> str:
    """
    'starter': ilk kez/never/mild veya risk yüksek → daha düşük güç etiketleri
    'standard': diğer
    """
    tol = merged_tol or {}
    if risk_level in ("high", "crisis"):
        return "starter"
    if exp_norm == "none":
        return "starter"
    if any(v in ("never", "mild") for v in tol.values()):
        return "starter"
    return "standard"


def _apply_active_strength_ramp(items: list, stage: str) -> None:
    """
    Metin tabanlı, geriye uyumlu güç azaltma:
    - Retinol: %0.5-1 / %0.5 -> %0.25-0.3
    - C vitamini: %15-20 -> %10-15; CEF %20 -> %10-15 (LAA)
    - BHA: %2 -> %1
    - Azelaik: %15-20 -> %10-15
    - AHA glikolik: %8+ -> %5
    """
    if stage != "starter":
        return

    def _ramp_text(s: str, families: set) -> str:
        if not isinstance(s, str) or not s:
            return s
        out = s
        # Retinol
        if "retinol" in families:
            out = out.replace("Serbest retinol %0.5-1", "Serbest retinol %0.25-0.3")
            out = out.replace("Serbest retinol %0.5", "Serbest retinol %0.25-0.3")
        # Vitamin C
        if "vitamin_c" in families:
            out = out.replace("L-Askorbik asit %15-20", "L-Askorbik asit %10-15")
            out = out.replace("L-Askorbik asit %12-15", "L-Askorbik asit %10-15")
            out = out.replace(
                "L-Askorbik asit %20 + tokoferol + ferulik asit (CEF; C vitamini stabil üçlü)",
                "L-Askorbik asit %10-15 — C vitamini serumu (INCI: Ascorbic Acid)",
            )
        # BHA
        if "bha" in families:
            out = out.replace("Salisilik asit %2 tonik", "Salisilik asit %1 tonik")
        # Azelaik
        if "azelaic" in families:
            out = out.replace("Azelaik asit %15-20", "Azelaik asit %10-15")

        # AHA glikolik: %8+ -> %5
        def _aha_repl(m):
            try:
                v = float(m.group(1))
            except Exception:
                return m.group(0)
            if v >= 8:
                return "Glikolik asit %5 (AHA, INCI: Glycolic Acid)"
            return m.group(0)

        if "aha" in families:
            out = re.sub(
                r"Glikolik asit %(\d+(?:\.\d+)?) \(AHA, INCI: Glycolic Acid\)",
                _aha_repl,
                out,
            )
        return out

    for it in items or []:
        if it.get("category") != "Bakım":
            continue
        families = _strong_actives_families_for_item(it)
        if not families:
            continue
        for k in ("action", "detail"):
            it[k] = _ramp_text(it.get(k), families)
        it.setdefault("ramp_stage", stage)


# ══════════════════════════════════════════════════════════════════════
# 1. CONCERN KNOWLEDGE MAP - Supabase metadata filtreleri
# ══════════════════════════════════════════════════════════════════════

CONCERN_KNOWLEDGE_MAP = {
    "general": {
        "label_tr": "Genel Bakım",
        "primary_kategori": "Tedavi Ajanı",
        "primary_alt_kategoriler": ["Genel"],
        "treatment_kategori": "Tedavi Ajanı",
        "treatment_alt_kategoriler": ["Mekanizma"],
        "flow_nodes": [],
    },
    "oiliness": {
        "label_tr": "Yağlılık / Sebum",
        "primary_kategori": "Tedavi Ajanı",
        "primary_alt_kategoriler": ["Mekanizma", "Klinik Etkinlik"],
        "treatment_kategori": "Tedavi Ajanı",
        "treatment_alt_kategoriler": ["Kanıt Seviyesi"],
        "flow_nodes": ["Sebum", "Genişlemiş gözenek"],
    },
    "pores": {
        "label_tr": "Siyah Nokta / Gözenek",
        "primary_kategori": "Tedavi Ajanı",
        "primary_alt_kategoriler": ["Mekanizma", "Klinik Etkinlik"],
        "treatment_kategori": "Tedavi Ajanı",
        "treatment_alt_kategoriler": ["Kanıt Seviyesi"],
        "flow_nodes": ["Komedon", "Gözenek", "Sebum"],
    },
    "acne": {
        "label_tr": "Akne / Sivilce",
        "primary_kategori": "Akne Vulgaris",
        "primary_alt_kategoriler": ["Sınıflandırma", "Tedavi", "Nedenler"],
        "treatment_kategori": "Tedavi Ajanı",
        "treatment_alt_kategoriler": ["Mekanizma", "Klinik Etkinlik", "Kanıt Seviyesi"],
        "flow_nodes": ["Akne", "Genetik", "Diyet"],
    },
    "aging": {
        "label_tr": "Yaşlanma Karşıtı",
        "primary_kategori": "Tedavi Ajanı",
        "primary_alt_kategoriler": ["Mekanizma", "Klinik Etkinlik", "Kanıt Seviyesi"],
        "treatment_kategori": "Tedavi Ajanı",
        "treatment_alt_kategoriler": ["Etki Mekanizması", "Kanıt Seviyesi"],
        "flow_nodes": ["Yaşlanma", "Kırışıklık"],
    },
    "pigmentation": {
        "label_tr": "Lekelenme",
        "primary_kategori": "Tedavi Ajanı",
        "primary_alt_kategoriler": ["Mekanizma", "Etki Mekanizması"],
        "treatment_kategori": "Tedavi Ajanı",
        "treatment_alt_kategoriler": ["Klinik Etkinlik", "Kanıt Seviyesi"],
        "flow_nodes": ["Leke", "C Vitamini", "Güneş Koruyucu"],
    },
    "dryness": {
        "label_tr": "Kuruluk",
        "primary_kategori": "Tedavi Ajanı",
        "primary_alt_kategoriler": ["Mekanizma", "Etki Mekanizması"],
        "treatment_kategori": "Tedavi Ajanı",
        "treatment_alt_kategoriler": ["Genel"],
        "flow_nodes": [],
    },
    "sensitivity": {
        "label_tr": "Hassasiyet",
        "primary_kategori": "Tedavi Ajanı",
        "primary_alt_kategoriler": ["Mekanizma", "Genel"],
        "treatment_kategori": "Tedavi Ajanı",
        "treatment_alt_kategoriler": ["Uzman Görüşü"],
        "flow_nodes": [],
    },
}


# ══════════════════════════════════════════════════════════════════════
# 2. YAŞ GRUBU SINIFLANDIRMA
# ══════════════════════════════════════════════════════════════════════

def classify_age_group(age: int) -> dict:
    """Yaş grubunu sınıflandır ve uygun stratejileri belirle."""
    if age < 20:
        return {
            "group": "adolescent",
            "label_tr": "Genç (15-19)",
            "retinol_ok": False,
            "aha_max_pct": 5,
            "focus": "nazik_temizlik",
            "collagen_support": False,
            "notes": "Nazik formüller, agresif tedavilerden kaçın",
            "daily_water_min": 2.0,
            "sleep_target": 9,
        }
    elif age < 30:
        return {
            "group": "young_adult",
            "label_tr": "Genç Yetişkin (20-29)",
            "retinol_ok": True,
            "aha_max_pct": 10,
            "focus": "önleme",
            "collagen_support": False,
            "notes": "Antioksidan koruma, erken önleme başlat",
            "daily_water_min": 2.0,
            "sleep_target": 8,
        }
    elif age < 40:
        return {
            "group": "adult",
            "label_tr": "Yetişkin (30-39)",
            "retinol_ok": True,
            "aha_max_pct": 15,
            "focus": "erken_müdahale",
            "collagen_support": True,
            "notes": "Retinol başla, peptid ekle, kolajen desteği",
            "daily_water_min": 2.5,
            "sleep_target": 8,
        }
    elif age < 50:
        return {
            "group": "mature",
            "label_tr": "Olgun (40-49)",
            "retinol_ok": True,
            "aha_max_pct": 20,
            "focus": "aktif_tedavi",
            "collagen_support": True,
            "notes": "Güçlü retinoid, peptid, büyüme faktörleri",
            "daily_water_min": 2.5,
            "sleep_target": 7.5,
        }
    else:
        return {
            "group": "senior",
            "label_tr": "İleri Yaş (50+)",
            "retinol_ok": True,
            "aha_max_pct": 10,
            "focus": "onarım_koruma",
            "collagen_support": True,
            "notes": "Bariyer onarım, derin nemlendirme, nazik aktifler",
            "daily_water_min": 2.5,
            "sleep_target": 7.5,
        }


# ══════════════════════════════════════════════════════════════════════
# 3. CİLT TİPİ MODİFİYERLERİ
# ══════════════════════════════════════════════════════════════════════

# Cilt tipine göre: etken madde + konsantrasyon/formül (ürün adı yok)
SKIN_TYPE_PROFILES = {
    "oily": {
        "label_tr": "Yağlı",
        "moisturizer_type": "Niasinamid %5 + Hyaluronik asit (hafif jel)",
        "cleanser_type": "Yüzey aktif (SLES-free) köpük temizleyici",
        "avoid_ingredients": ["ağır yağlar", "vazelin", "mineral yağ"],
        "prefer_ingredients": ["niasinamid", "salisilik asit", "çay ağacı"],
        "spf_type": "mat bitişli, yağsız SPF",
        "night_cream": "Niasinamid %5 + HA (hafif jel, gece)",
    },
    "dry": {
        "label_tr": "Kuru",
        "moisturizer_type": "Seramid %2-5 + Squalane + Kolesterol (bariyer kremi)",
        "cleanser_type": "Krem bazlı nazik temizleyici (sülfat-free)",
        "avoid_ingredients": ["alkol bazlı tonikler", "sodyum lauril sülfat"],
        "prefer_ingredients": ["hyaluronik asit", "seramid", "squalane", "shea yağı"],
        "spf_type": "nemlendirici özellikli SPF",
        "night_cream": "Seramid %2-5 + Kolesterol + Yağ asidi (3:1:1 oran, gece onarım)",
    },
    "combination": {
        "label_tr": "Karma",
        "moisturizer_type": "Niasinamid %5 + Hyaluronik asit (hafif losiyon/jel-krem)",
        "cleanser_type": "Dengeli pH (5.5) jel temizleyici",
        "avoid_ingredients": ["çok ağır kremler"],
        "prefer_ingredients": ["niasinamid", "hyaluronik asit"],
        "spf_type": "hafif SPF",
        "night_cream": "Seramid %1-2 + HA (orta yoğunluk, gece)",
    },
    "normal": {
        "label_tr": "Normal",
        "moisturizer_type": "Peptid (Matrixyl/Argireline) + Hyaluronik asit",
        "cleanser_type": "Nazik jel temizleyici (sülfat-free)",
        "avoid_ingredients": [],
        "prefer_ingredients": ["antioksidanlar", "peptidler"],
        "spf_type": "geniş spektrumlu SPF",
        "night_cream": "Peptid kompleks + Seramid %1-2 (gece)",
    },
    "sensitive": {
        "label_tr": "Hassas",
        "moisturizer_type": "Centella (Cica) %1 + Seramid %2 + Panthenol %5 (bariyer)",
        "cleanser_type": "Misel su veya süt bazlı temizleyici",
        "avoid_ingredients": ["parfüm", "alkol", "esansiyel yağlar", "retinol (yüksek doz)"],
        "prefer_ingredients": ["centella", "allantoin", "panthenol", "bisabolol"],
        "spf_type": "Mineral SPF (çinko oksit)",
        "night_cream": "Centella (Cica) + Seramid %2-5 + Bisabolol (onarım)",
    },
}


# ══════════════════════════════════════════════════════════════════════
# 4. MADDE UYUMLULUK MATRİSİ
# ══════════════════════════════════════════════════════════════════════

INGREDIENT_CONFLICTS = [
    {"a": "Retinol", "b": "AHA", "reason": "Aynı anda kullanım cilt bariyerini bozar", "solution": "Retinol akşam, AHA sabah veya alternatif gece"},
    {"a": "Retinol", "b": "BHA", "reason": "Birlikte tahriş riski yüksek", "solution": "Farklı gecelerde kullan"},
    {"a": "Retinol", "b": "Benzoil Peroksit", "reason": "BP retinolü inaktive eder", "solution": "BP sabah, Retinol akşam"},
    {"a": "Retinol", "b": "C Vitamini", "reason": "pH uyumsuzluğu etkinliği düşürür", "solution": "C Vitamini sabah, Retinol akşam"},
    {"a": "AHA", "b": "C Vitamini", "reason": "Birlikte tahriş yapabilir", "solution": "AHA akşam, C Vitamini sabah"},
    {"a": "Niasinamid", "b": "AHA", "reason": "Niasinamid flushing yapabilir düşük pH'da", "solution": "Araya 10 dk bekle veya farklı zaman"},
]

# Retinal, güçlü asitler vb. için aynı matris mantığı (UI + API tek kaynak)
INGREDIENT_CONFLICTS.append(
    {"a": "Retinal", "b": "AHA", "reason": "Retinal ve AHA aynı seansta bariyer ve tahriş riski yüksek", "solution": "Retinal akşam; AHA yoksa o gece veya haftada ayrı geceler"},
)
INGREDIENT_CONFLICTS.append(
    {"a": "Retinal", "b": "BHA", "reason": "İki güçlü aktif aynı rutinde tahriş birikir", "solution": "Farklı geceler; bir gece retinal, bir gece BHA"},
)

# Kullanıcıya gösterilecek genel ilkeler (çift/isim yok; sıra + takvim + güvenlik)
ROUTINE_USAGE_PRINCIPLES = [
    "Kesinlik kuralları: sabah kullanılmayacak etkenler, üst doz sınırları ve birlikte kullanılmaz çiftler motor tarafından zorunlu uygulanır; liste ve rapor API’de `absolute_rules_catalog` / `rule_enforcement_report` ile döner.",
    "Uygulama sırası: temizlik → serum/aktif → nemlendirici; sabahda en son geniş spektrumlu güneş koruyucu.",
    "Kişiselleştirme katmanı: stres/su/uyku/nem risk skoru + şiddet puanı + cilt tipi + aktif tolerans anketi tek bir “tier” üretir; akne, yaşlanma, leke ve kurulukta akşam aktifleri ve gerektiğinde kurulukta sabah HA bu tipe göre sıkıştırılır veya tek satırda birleştirilir.",
    "Bir rutin satırındaki maddeler tek üründe olmak zorunda değil; aynı adımda hedeflenen etkenler ayrı serum + krem gibi ürünlerle de sağlanır (sıra: sulu/aktif önce, krem/yağ sonra).",
    "Konsantrasyon etikette birebir olmayabilir; yakın ve daha düşük % ile başlamak çoğu zaman uygundur, güçlü formüle geçmeden tolere kontrolü yap.",
    "İnce/küvöz kıvamlı ürünler önce, daha koyu krem veya yağ bazlı nemlendirici sonra gelir.",
    "Sabah genelde hafif (temizlik, gerekirse tek hafif serum, nem, SPF); güçlü ve yoğun serumlar akşama planlanır.",
    "Haftalık planda işaretli günler sistem tarafından atanır; güçlü gece adımlarını sadece o günlere yay.",
    "Yeni konsantrasyon veya ürün öncesi 24–48 saat yama testi; kızarıklıkta o adımı durdur.",
    "Hamilelik veya emzirmede yeni aktif eklemeden önce sağlık uzmanına danış.",
]


def _normalize_actives_experience(raw: str) -> str:
    x = (raw or "occasional").strip().lower()
    if x in ("none", "never", "hiç", "yok"):
        return "none"
    if x in ("regular", "sık", "düzenli"):
        return "regular"
    return "occasional"


def _strong_actives_families_for_item(item: dict) -> set:
    """Rutin satırındaki güçlü aktif aileleri (API'deki actives_unused id'leriyle uyumlu)."""
    act_l = (item.get("action") or "").lower()
    dl = (item.get("detail") or "").lower()
    t = f"{act_l} {dl}"
    out = set()
    if any(k in t for k in ("retinol", "retinal")):
        out.add("retinol")
    if any(k in t for k in ("salisilik", "salicylic", "bha")):
        out.add("bha")
    if any(k in t for k in ("glikolik", "glycolic", "laktik asit", "lactic acid", " aha", "aha %")):
        out.add("aha")
    if "benzoil" in t or "benzoyl" in t:
        out.add("benzoyl")
    if "azelaik" in t or "azelaic" in t:
        out.add("azelaic")
    if any(k in t for k in ("askorbik", "ascorbic", "c vitamini", "vitamin c")):
        out.add("vitamin_c")
    if "bakuchiol" in t:
        out.add("bakuchiol")
    if any(k in t for k in ("arbutin", "traneksamik", "tranexamic")):
        out.add("pigment")
    if "niasinamid" in t or "niacinamide" in t:
        out.add("niacinamide")
    return out


def merge_actives_tolerance(
    actives_tolerance: Optional[dict],
    actives_unused: Optional[list],
) -> dict:
    """actives_unused (eski API): her id -> 'never'. Yeni: actives_tolerance { family: never|good|mild|bad }."""
    tol: dict = {}
    if isinstance(actives_tolerance, dict):
        for k, v in actives_tolerance.items():
            ks = str(k).lower().strip()
            if v in ("never", "good", "mild", "bad"):
                tol[ks] = v
    for x in actives_unused or []:
        ks = str(x).lower().strip()
        if ks:
            tol.setdefault(ks, "never")
    return tol


def avoided_families_from_tolerance(tol: dict) -> set:
    return {k for k, v in tol.items() if v == "bad"}


def _extract_strength_pct_from_text(text: str) -> Optional[str]:
    """
    Basit % yakalama (geriye uyumlu). Örn:
    - "L-Askorbik asit %10-15" -> "10-15"
    - "Serbest retinol %0.25-0.3" -> "0.25-0.3"
    - "Salisilik asit %1 tonik" -> "1"
    """
    if not isinstance(text, str) or not text:
        return None
    m = re.search(r"%\s*(\d+(?:\.\d+)?(?:\s*-\s*\d+(?:\.\d+)?)?)", text)
    if not m:
        return None
    return m.group(1).replace(" ", "")


def attach_structured_fields_to_routine_items(items: list) -> None:
    """
    Frontend'i bozmadan, rutin satırlarına makine-okunur ek alanlar ekle.
    - active_families: ["bha","retinol",...]
    - strength_pct: "10-15" / "0.25-0.3" / "1"
    - frequency_per_week: weekly_days sayısı
    """
    for it in items or []:
        cat = it.get("category")
        if cat not in ("Bakım", "Koruma"):
            continue
        fam = sorted(_strong_actives_families_for_item(it))
        if fam:
            it.setdefault("active_families", fam)
        # strength: action öncelikli
        sp = _extract_strength_pct_from_text(it.get("action") or "") or _extract_strength_pct_from_text(it.get("detail") or "")
        if sp:
            it.setdefault("strength_pct", sp)
        wd = it.get("weekly_days")
        if isinstance(wd, list) and wd:
            it.setdefault("frequency_per_week", len(wd))


def _remove_routine_items_by_avoided_families(items: list, avoid: set) -> list:
    """Kullanıcı ciddi tepki bildirdiği aktif ailelerine denk gelen Bakım satırlarını çıkarır."""
    if not avoid:
        return items
    out = []
    for it in items:
        if it.get("category") != "Bakım":
            out.append(it)
            continue
        fam = _strong_actives_families_for_item(it)
        if fam & avoid:
            continue
        out.append(it)
    return out


def compute_personalization_profile(
    risk_info: dict,
    severity_score: int,
    skin_type_key: str,
    actives_tolerance: Optional[dict] = None,
    concern: str = "",
) -> dict:
    """
    Tüm concern'ler için ortak kişiselleştirme katmanı.
    Girdi: INGREDIENT_DB risk skoru (stres/su/nem/uyku) + şiddet puanı + cilt tipi + aktif tolerans anketi.
    Çıktı: tier (0–3) ve bariyer katmanlarını birleştirme bayrağı — rutin yoğunluğu buna göre tek yerden ayarlanır.
    """
    tol = actives_tolerance or {}
    bad_c = sum(1 for v in tol.values() if v == "bad")
    never_c = sum(1 for v in tol.values() if v == "never")

    rl = risk_info.get("level", "normal")
    if rl == "crisis":
        tier = 0
    elif rl == "high":
        tier = 1
    elif rl == "moderate":
        tier = 2
    else:
        tier = 3

    if severity_score >= 8:
        tier = min(tier, 1)
    elif severity_score >= 5:
        tier = min(tier, 2)

    if skin_type_key == "sensitive":
        tier = min(tier, 2)

    if bad_c >= 2:
        tier = min(tier, 1)
    elif bad_c == 1:
        tier = min(tier, 2)

    if never_c >= 5:
        tier = min(tier, 2)

    if concern == "sensitivity":
        tier = min(tier, 2)

    tier = max(0, min(3, tier))

    labels = {
        0: "Bariyer öncelikli",
        1: "Temkinli",
        2: "Dengeli",
        3: "Standart yoğunluk",
    }
    merge_barrier = tier <= 1
    rs = int(risk_info.get("score", 0))
    composite = max(
        0,
        min(
            100,
            72
            - rs * 2
            - bad_c * 14
            - max(0, severity_score - 3) * 3
            + (3 - tier) * 8,
        ),
    )

    return {
        "tier": tier,
        "label_tr": labels[tier],
        "composite_score": composite,
        "merge_barrier_layers": merge_barrier,
        "risk_level": rl,
        "risk_score": rs,
        "inputs_summary": {
            "bad_reactions": bad_c,
            "never_used_actives": never_c,
            "severity_score": severity_score,
            "skin_type_key": skin_type_key,
        },
    }


def _personalization_compress_evening(personalization: Optional[dict]) -> bool:
    """
    Tüm concern'lerde: yüksek yaşam riski veya düşük tier → akşamda üst üste çok aktif/nem katmanı açma.
    (merge_barrier_layers veya tier≤1)
    """
    if not personalization:
        return False
    return bool(personalization.get("merge_barrier_layers")) or int(personalization.get("tier", 3)) <= 1


def _personalization_detail_suffix(personalization: Optional[dict]) -> str:
    if not personalization:
        return ""
    tier = personalization.get("tier", 3)
    if tier <= 1:
        return " Plan sade: aynı iş için ekstra serum/nem katmanı yok. Sıklık check-in ile güncellenir."
    if tier == 2:
        return " Ekstra katman açılmadı; sıklık check-in ile ayarlanır."
    return ""


def build_morning_moisturizer_item(
    concern: str,
    severity: dict,
    skin_type: dict,
    personalization: Optional[dict] = None,
) -> dict:
    """Sabah nemlendirici — tüm concern'ler; kişisel puana göre detay notu."""
    pers = personalization or {}
    sfx = _personalization_detail_suffix(personalization)
    dry_fold = concern == "dryness" and _personalization_compress_evening(pers)
    if dry_fold:
        return {
            "time": "Sabah", "category": "Bakım", "icon": "🧊",
            "action": f"Nemlendirici (HA + nem tek taban): {skin_type['moisturizer_type']}",
            "detail": f"Ayrı HA serumu yok; nem hedefini bu tek adımda topla.{sfx}",
            "usage": "Temiz cilde; ayrı serum adımı yoksa doğrudan nem veya önce damla HA sonra krem.",
            "priority": 3, "step_order": 30,
        }
    detail = f"Serumdan sonra.{sfx}"
    return {
        "time": "Sabah", "category": "Bakım", "icon": "🧊",
        "action": f"Nemlendirici: {skin_type['moisturizer_type']}",
        "detail": detail,
        "usage": "Temiz cilde, serumdan sonra. Tüm yüze ince katman (göz çevresi ince).",
        "priority": 3, "step_order": 30,
    }


def _detail_ramp_none(d: str) -> str:
    dl = d.lower()
    for suf in ("gece", "kez", "kere", "gün"):
        d = re.sub(rf"haftada\s*3\s*[-–]\s*4\s*{suf}\b", "Haftada 2-3 " + suf, d, flags=re.IGNORECASE)
        d = re.sub(rf"haftada\s*3\s*{suf}\b", "Haftada 2 " + suf, d, flags=re.IGNORECASE)
        d = re.sub(rf"haftada\s*2\s*[-–]?\s*3\s*{suf}\b", "Haftada 1-2 " + suf, d, flags=re.IGNORECASE)
        d = re.sub(rf"haftada\s*2\s*{suf}\b", "Haftada 1 " + suf, d, count=1, flags=re.IGNORECASE)
    # Kullanıcıya karar bırakmayalım: sıklık metni varsa zaten haftalık plana çevrilir (weekly_days).
    # Metinde sıklık yoksa burada serbest metin eklemeyiz.
    return d


def _detail_ramp_occasional(d: str) -> str:
    dl = d.lower()
    for suf in ("gece", "kez", "kere", "gün"):
        d = re.sub(rf"haftada\s*3\s*{suf}\b", "Haftada 2 " + suf, d, count=1, flags=re.IGNORECASE)
    # Kullanıcıya “gerekirse/sonra artır” gibi belirsiz yönlendirme vermeyelim.
    # Sıklık metni varsa haftalık gün planı otomatik atanır (weekly_days).
    return d


def _apply_actives_experience_ramp(
    routine_items: list,
    experience: str,
    actives_unused: Optional[list] = None,
    actives_tolerance: Optional[dict] = None,
) -> None:
    """
    Haftalık sıklık / alıştırma metinleri.
    - never / hiç kullanmadım: güçlü none-ramp
    - mild / hafif tepki: occasional-ramp
    - bad satırlar zaten rutinden düşürülmüştür
    """
    tol = merge_actives_tolerance(actives_tolerance, actives_unused)
    never_f = {k for k, v in tol.items() if v == "never"}
    mild_f = {k for k, v in tol.items() if v == "mild"}
    exp = _normalize_actives_experience(experience)

    for it in routine_items:
        if it.get("category") != "Bakım":
            continue
        families = _strong_actives_families_for_item(it)
        if not families:
            continue
        touches_never = bool(families & never_f)
        touches_mild = bool(families & mild_f)
        if exp == "regular" and not touches_never and not touches_mild:
            continue
        d = it.get("detail") or ""
        if exp == "none" or touches_never:
            it["detail"] = _detail_ramp_none(d)
        elif exp == "occasional" or touches_mild:
            it["detail"] = _detail_ramp_occasional(d)


def get_routine_care_guide(is_pregnant: bool = False) -> dict:
    """
    API ve ön yüz: uygulama sırası + haftalık plan (çakışan molekül listesi yok; motor arka planda ayarlar).
    """
    notes = list(ROUTINE_USAGE_PRINCIPLES)
    if is_pregnant:
        notes.insert(
            0,
            "Hamilelik bilgisi işlendi; güvensiz adımlar motor tarafından süzülür. Yine de yeni ürün için uzmana danış.",
        )
    return {
        "title": "Uygulama sırası ve haftalık plan",
        "usage_notes": notes,
        "weekly_routine_explanation": (
            "Haftalık kullanım kartındaki günler, güçlü gece adımlarının hangi akşamlarda uygulanacağını gösterir. "
            "Gün gün rutinde sabah ve akşam adımları bu takvime göre listelenir; aynı günde iki güçlü adım önerilmez. "
            "Check-in ile sıklık güncellenebilir."
        ),
    }


def check_ingredient_compatibility(routine_items: list) -> list:
    """Rutin öğelerindeki madde uyumsuzluklarını kontrol et ve uyarı ekle."""
    warnings = []
    morning_items = [i for i in routine_items if i.get("time") == "Sabah"]
    evening_items = [i for i in routine_items if i.get("time") == "Akşam"]

    for conflict in INGREDIENT_CONFLICTS:
        for time_group, label in [(morning_items, "Sabah"), (evening_items, "Akşam")]:
            actions = " ".join([i.get("action", "") for i in time_group]).lower()
            a_found = conflict["a"].lower() in actions
            b_found = conflict["b"].lower() in actions
            if a_found and b_found:
                warnings.append({
                    "time": label,
                    "category": "Koruma",
                    "icon": "⚠️",
                    "action": f"Dikkat: {conflict['a']} + {conflict['b']}",
                    "detail": f"{conflict['reason']}. Öneri: {conflict['solution']}",
                    "priority": 0,
                })
    return warnings


# ══════════════════════════════════════════════════════════════════════
# 5. SEVERITY CLASSIFIER - Şiddet sınıflandırma (yaş uyumlu)
# ══════════════════════════════════════════════════════════════════════

def classify_severity(score: int, concern: str, age_group: dict) -> dict:
    """Şiddet puanını concern ve yaş grubuna göre sınıflandır."""
    if score <= 3:
        level = "hafif"
        label_tr = "Hafif"
        treatment_intensity = "topikal_nazik"
    elif score <= 6:
        level = "orta"
        label_tr = "Orta"
        treatment_intensity = "kombine_topikal"
    else:
        level = "şiddetli"
        label_tr = "Şiddetli"
        treatment_intensity = "yoğun"

    agents = _get_preferred_agents(concern, level, age_group)

    return {
        "level": level,
        "label_tr": label_tr,
        "treatment_intensity": treatment_intensity,
        "preferred_agents": agents["prefer"],
        "avoid": agents["avoid"],
    }


def _get_preferred_agents(concern: str, level: str, age_group: dict) -> dict:
    """Concern + Şiddet + Yaş grubuna göre tercih edilen aktif maddeleri belirle.
    INGREDIENT_DB referansıyla bilimsel konsantrasyonlar kullanılır."""
    from ingredient_db import INGREDIENT_DB, get_concentration

    def _fmt(key, ctx):
        c = get_concentration(key, ctx)
        return c.get("pct", key) if c else key

    if concern == "acne":
        if level == "hafif":
            prefer = [_fmt("salisilik_asit", "acne_hafif"), _fmt("niacinamid", "acne_genel"), _fmt("cay_agaci", "acne_hafif")]
            avoid = ["Retinol (gereksiz)", "Agresif peeling"]
        elif level == "orta":
            prefer = [_fmt("benzoil_peroksit", "acne_orta"), _fmt("niacinamid", "acne_genel"), _fmt("azelaik_asit", "akne_standart")]
            avoid = ["Agresif fiziksel peeling"]
            if age_group["retinol_ok"]:
                prefer.append(_fmt("retinol", "acne_hafif"))
        else:
            prefer = [_fmt("benzoil_peroksit", "acne_siddetli"), _fmt("retinol", "acne_siddetli")]
            avoid = ["Sadece topikal (dermatolog öner)"]
            if age_group["retinol_ok"]:
                prefer.append(_fmt("retinol", "acne_siddetli"))

    elif concern == "aging":
        if age_group["group"] == "adolescent":
            prefer = ["Antioksidan serum", _fmt("mineral_spf", "genel")]
            avoid = ["Retinol", "Güçlü asitler"]
        elif age_group["group"] == "young_adult":
            prefer = [_fmt("vitamin_c", "aging_20_29"), _fmt("niacinamid", "acne_genel"), "Peptid serum"]
            avoid = ["Yüksek doz retinol"]
        elif age_group["group"] == "adult":
            prefer = [_fmt("retinol", "aging_30_39"), _fmt("vitamin_c", "aging_30_39"), "Peptid kompleks"]
            avoid = []
        elif age_group["group"] == "mature":
            prefer = [_fmt("retinol", "aging_40_49"), _fmt("vitamin_c", "aging_40_plus"), "Bakuchiol %1", "EGF peptid"]
            avoid = []
        else:
            prefer = [_fmt("retinol", "aging_50_plus"), "Peptid kompleks", _fmt("hyaluronik_asit", "genel"), _fmt("seramidler", "standart")]
            avoid = ["Yüksek konsantrasyon retinol (bariyer hassas)"]

    elif concern == "pigmentation":
        prefer = [_fmt("alfa_arbutin", "pigmentation_hafif"), _fmt("traneksamik_asit", "melasma_first_line"), _fmt("niacinamid", "pigmentation_destek")]
        avoid = []
        if age_group["retinol_ok"] and level != "hafif":
            prefer.append(_fmt("retinol", "aging_30_39"))
        if level in ("orta", "şiddetli"):
            prefer.append(f"AHA %{min(age_group['aha_max_pct'], 10)}")
        if age_group["group"] != "adolescent":
            prefer.insert(0, _fmt("vitamin_c", "pigmentation_genel"))

    elif concern == "dryness":
        prefer = [_fmt("hyaluronik_asit", "kuruluk"), _fmt("seramidler", "standart"), "Squalane"]
        avoid = ["Alkol bazlı formüller", "Sert temizleyiciler"]
        if age_group["collagen_support"]:
            prefer.append("Peptid nemlendirici")
        if level == "şiddetli":
            prefer.append(_fmt("petrolatum", "standart"))

    elif concern == "sensitivity":
        prefer = [_fmt("centella_panthenol", "sensitivity_aksam"), _fmt("niacinamid", "sensitivity_bariyer"), "Allantoin"]
        avoid = ["Parfüm", "Esansiyel yağlar", "Alkol", "Yüksek doz aktifler"]
        if level == "şiddetli":
            prefer.append("Bisabolol")
            prefer.append(_fmt("petrolatum", "standart"))

    else:
        prefer = [_fmt("niacinamid", "acne_genel"), _fmt("hyaluronik_asit", "genel")]
        avoid = []

    return {"prefer": prefer, "avoid": avoid}


# ══════════════════════════════════════════════════════════════════════
# 6. SKINCARE ROUTINE BUILDER - Yaş + Cilt Tipi + Concern uyumlu
# ══════════════════════════════════════════════════════════════════════

def _skin_retinol(pct_range: str) -> str:
    """Serbest retinol (haftalık rutinde hangi gün varsa o günlerde bu satır görünür)."""
    return (
        f"Serbest retinol {pct_range} (INCI: Retinol; A vitamini alkolü — retinyl palmitat/ester türleri değil)"
    )


def _skin_vitc_laa(pct_range: str) -> str:
    """L-askorbik asit; detail/c vitamini eşleşmeleri için metinde 'C vitamini' tutulur."""
    return f"L-Askorbik asit {pct_range} — C vitamini serumu (INCI: Ascorbic Acid)"


def _skin_vitc_cef() -> str:
    return "L-Askorbik asit %20 + tokoferol + ferulik asit (CEF; C vitamini stabil üçlü)"


def _skin_ha(kind: str = "multi") -> str:
    if kind == "hafif":
        return "Sodyum hyalüronat — hyaluronik asit serum (çoklu molekül ağırlığı, INCI: Sodium Hyaluronate)"
    return "Sodyum hyalüronat — hyaluronik asit (çoklu MW, INCI: Sodium Hyaluronate)"


def _skin_salicylic_toner() -> str:
    return "Salisilik asit %2 tonik (BHA, INCI: Salicylic Acid)"


def _skin_niacin_zinc() -> str:
    return "Niasinamid %5 (INCI: Niacinamide, B3) + çinko destekli serum"


def _skin_niacinamide(pct: str) -> str:
    return f"Niasinamid {pct} serum (INCI: Niacinamide; niasin ile karıştırma)"


def _skin_azelaic() -> str:
    return "Azelaik asit %15-20 (INCI: Azelaic Acid; dikarboksilli asit)"


def _skin_benzoyl() -> str:
    return "Benzoil peroksit %5 kısa temas (INCI: Benzoyl Peroxide)"


def _skin_glycolic(pct: float) -> str:
    return f"Glikolik asit %{pct:g} (AHA, INCI: Glycolic Acid)"


def _skin_arbutin(pct_label: str) -> str:
    return f"Alfa-arbutin {pct_label} serum (INCI: Alpha-Arbutin; hidrokinon türevi, stabil leke aktifi)"


def _skin_niacin_tranexamic() -> str:
    return (
        "Niasinamid %10 (INCI: Niacinamide) + traneksamik asit (INCI: Tranexamic Acid; topikal TXA)"
    )


def _skin_bakuchiol() -> str:
    return "Bakuchiol serum (INCI: Bakuchiol; fitoretinol — serbest retinol değil)"


def _skin_peptide_light() -> str:
    return "Sinyal peptid serum (Matrixyl/Argireline sınıfı; INCI: Palmitoyl pentapeptide vb.)"


def _skin_peptide_ha() -> str:
    return "Sinyal peptid + sodyum hyalüronat (peptid kompleksi + HA)"


def _skin_panthenol() -> str:
    return "D-Pantenol %5 yatıştırıcı serum (INCI: Panthenol; B5 provitamini)"


def _skin_toco_ferulic() -> str:
    return "Tokoferol (E vitamini) + ferulik asit antioksidan serum"


def build_evening_moisturizer_item(
    concern: str,
    severity: dict,
    skin_type: dict,
    personalization: Optional[dict] = None,
) -> dict:
    """
    Gece nemlendirici / bariyer satırının tek çıkış noktası (tüm concern'ler).
    Kişisel puan (risk + şiddet + tolerans) yüksekse ekstra bariyer adımları burada birleştirilir.
    """
    base = skin_type["night_cream"]
    sev = severity.get("level", "")
    pers = personalization or {}
    sfx = _personalization_detail_suffix(personalization)

    if concern == "sensitivity" and sev == "şiddetli":
        return {
            "time": "Akşam", "category": "Bakım", "icon": "🌙",
            "action": (
                f"Gece (tek yoğun katman): {base} + panthenol %5; "
                "gerekirse son adım ince vazelin bariyer kilidi"
            ),
            "detail": (
                "Tek gece katmanında toplandı; ayrı panthenol/vazelin şişesi şart değil. "
                "Çok kuruysa en son ince vazelin filmi; tıkanıklıkta vazelini seyrelt veya azalt."
                + sfx
            ),
            "usage": "Temiz cilde önce onarım katmanı; vazelin varsa en son, ince film.",
            "priority": 3,
            "step_order": 30,
        }

    if concern == "dryness" and sev == "şiddetli" and pers.get("merge_barrier_layers"):
        return {
            "time": "Akşam", "category": "Bakım", "icon": "🌙",
            "action": f"Gece (yoğun tek katman): {base} + HA nem çekimi; çok kuruda kalınlık artır",
            "detail": (f"Ayrı maske satırı yok; tek blokta bariyer + nem yoğunluğu ({base})." + sfx),
            "usage": "Serum/aktif sonrası tek kalın nem tabanı; gerekirse ıslak cilde uygula.",
            "priority": 3,
            "step_order": 30,
        }

    # Hafif/orta kuruluk + tier≤1: akşam seramid serumu kaldırıldı; bariyer amacı gece kremde toplanır
    if concern == "dryness" and _personalization_compress_evening(pers):
        if not (sev == "şiddetli" and pers.get("merge_barrier_layers")):
            return {
                "time": "Akşam", "category": "Bakım", "icon": "🌙",
                "action": (
                    f"Gece (tek katman): {base} + seramid NP/skualan onarım içeriği "
                    "(bir ürün veya nemlendiricide birleşik)"
                ),
                "detail": ("Ayrı gece serum yok; seramid/skualan hedefini bu nemlendiricide topla." + sfx),
                "usage": "Temiz cilde veya hafif tonik sonrası tek kalın taban.",
                "priority": 3,
                "step_order": 30,
            }

    return {
        "time": "Akşam", "category": "Bakım", "icon": "🌙",
        "action": f"Gece: {base}",
        "detail": f"Bariyer onarımı.{sfx}",
        "usage": "Aktif tedaviden sonra. Tüm yüze ince katman, gece bırak.",
        "priority": 3,
        "step_order": 30,
    }


def get_base_skincare_routine(
    concern: str,
    severity: dict,
    age_group: dict,
    skin_type: dict,
    actives_experience: str = "occasional",
    personalization: Optional[dict] = None,
    makeup_frequency: int = 0,
    makeup_removal: str = "cleanser",
) -> list:
    """Concern + Şiddet + Yaş + Cilt tipine göre temel bakım rutini; kişisel puan tek kaynaktan."""
    _ = _normalize_actives_experience(actives_experience)
    items = []

    # step_order: Sabah 10=temizlik, 20=serum/aktif, 30=nemlendirici, 40=SPF
    #             Akşam 10=temizlik, 20=serum/aktif, 30=nemlendirici

    # ── SABAH TEMİZLİK (madde/formül, ürün adı yok) ──
    items.append({
        "time": "Sabah", "category": "Bakım", "icon": "🧴",
        "action": f"Temizleme: {skin_type['cleanser_type']}",
        "detail": f"{skin_type['label_tr']} cilt için bu formül uygun. Sabah ilk adım.",
        "usage": "Yüzü ıslat, köpürt, 30 sn masaj yap, ılık su ile durula, kurula.",
        "priority": 1, "step_order": 10,
    })

    # ── SABAH AKTİF SERUM (minimal; güçlü aktifler çoğunlukla akşam) ──
    _add_morning_actives(items, concern, severity, age_group, skin_type, personalization)

    # ── SABAH NEMLENDİRİCİ (tek kaynak: build_morning_moisturizer_item) ──
    items.append(build_morning_moisturizer_item(concern, severity, skin_type, personalization))

    # ── AKŞAM TEMİZLİK ──
    # Kullanıcı makyaj yapmıyorsa misel/double-cleanse önermeyelim.
    mf = max(0, int(makeup_frequency or 0))
    mr = (makeup_removal or "cleanser").strip().lower()
    needs_double = mf >= 3 or mr == "double"
    if needs_double:
        items.append({
            "time": "Akşam", "category": "Bakım", "icon": "🫧",
            "action": "Çift aşama temizlik: yağ/balm bazlı temizleyici + nazik temizleyici",
            "detail": "Makyaj/SPF ve biriken kirlilik çözülür; ardından cilt nazikçe yıkanır.",
            "usage": "1) Yağ/balm bazlı temizleyiciyi kuru cilde masajla uygula, emülsiye et, durula. 2) Nazik temizleyici ile yıka, durula.",
            "priority": 1, "step_order": 10,
        })
    else:
        items.append({
            "time": "Akşam", "category": "Bakım", "icon": "🫧",
            "action": "Nazik temizleyici (tek adım, sülfat-free)",
            "detail": "Makyaj yoksa tek adım temizlik yeterli; bariyeri yormadan günü temizle.",
            "usage": "Yüzü ıslat, 30 sn masajla temizle, ılık suyla durula.",
            "priority": 1, "step_order": 10,
        })

    # ── AKŞAM AKTİF TEDAVİ (yoğun serum / tedavi burada) ──
    _add_evening_actives(items, concern, severity, age_group, skin_type, personalization)

    # ── AKŞAM NEMLENDİRİCİ (tek kaynak: build_evening_moisturizer_item) ──
    items.append(build_evening_moisturizer_item(concern, severity, skin_type, personalization))

    return items


def _add_morning_actives(
    items,
    concern,
    severity,
    age_group,
    skin_type,
    personalization: Optional[dict] = None,
):
    """
    Sabah: yalnızca güneş/SPF ile uyumlu ve hafif katmanlar.
    Asit, yüksek % niasinamid, BP, arbutin vb. akşama taşınır.
    """

    if concern == "acne":
        # Sabahda güçlü aktif yok; BHA/niasinamid/BP akşam rutininde
        pass

    elif concern == "oiliness":
        # Yağlılık: sabah minimal, SPF ile uyumlu sebum dengeleme
        items.append({
            "time": "Sabah", "category": "Bakım", "icon": "💧",
            "action": _skin_niacinamide("%5"),
            "detail": "Sebumu dengelemeye yardımcı, sabah SPF altında hafif katman.",
            "priority": 2, "step_order": 20,
        })

    elif concern == "pores":
        # Gözenek/siyah nokta: sabah nazik, bariyeri yormadan
        items.append({
            "time": "Sabah", "category": "Bakım", "icon": "🕳️",
            "action": _skin_niacinamide("%5"),
            "detail": "Gözenek görünümü ve sebum dengesi için sabah hafif katman.",
            "priority": 2, "step_order": 20,
        })

    elif concern == "general":
        # Genel bakım: sabah aktif şart değil; rutin temeli temizlik + nem + SPF
        pass

    elif concern == "aging":
        if age_group["group"] == "adolescent":
            items.append({
                "time": "Sabah", "category": "Bakım", "icon": "🛡️",
                "action": _skin_toco_ferulic(),
                "detail": "Genç yaşta agresif anti-aging gereksiz. Antioksidan koruma yeterli.",
                "priority": 2, "step_order": 20,
            })
        elif age_group["group"] == "young_adult":
            items.append({
                "time": "Sabah", "category": "Bakım", "icon": "✨",
                "action": _skin_vitc_laa("%10-15"),
                "detail": (
                    "Temiz cilde ince katman; tam emilince nemlendirici ve SPF. "
                    "Hassasiyet olursa daha seyrek başla ve toleransa göre artır."
                ),
                "priority": 2, "step_order": 20,
            })
        elif age_group["group"] == "adult":
            items.append({
                "time": "Sabah", "category": "Bakım", "icon": "✨",
                "action": _skin_vitc_laa("%15-20"),
                "detail": (
                    "İnce katman, göz çevresinden kaçın; kuruyunca nemlendirici ve SPF. "
                    "Hassasiyet olursa daha düşük konsantrasyon veya daha seyrek kullanım tercih et."
                ),
                "priority": 2, "step_order": 20,
            })
        elif age_group["group"] == "mature":
            items.append({
                "time": "Sabah", "category": "Bakım", "icon": "✨",
                "action": _skin_vitc_cef(),
                "detail": (
                    "Kuru veya hafif nemli cilde uygula; kuruyunca nemlendirici ve SPF. "
                    "Tahriş olursa daha seyrek başla veya daha düşük güçte C vitamini seç."
                ),
                "priority": 2, "step_order": 20,
            })
        else:
            items.append({
                "time": "Sabah", "category": "Bakım", "icon": "💧",
                "action": _skin_ha("hafif"),
                "detail": "Sabah sadece hafif nem tabakası; peptid ve güçlü onarım akşam rutininde.",
                "priority": 2, "step_order": 20,
            })

    elif concern == "pigmentation":
        if age_group["group"] == "adolescent":
            items.append({
                "time": "Sabah", "category": "Bakım", "icon": "💧",
                "action": _skin_ha("hafif"),
                "detail": "Sabah minimal; alfa arbutin ve leke tedavisi akşamda.",
                "priority": 2, "step_order": 20,
            })
        else:
            items.append({
                "time": "Sabah", "category": "Bakım", "icon": "💎",
                "action": _skin_vitc_laa("%12-15"),
                "detail": (
                    "İnce katman; SPF öncesi tam kurumasını bekle. Leke hedefli arbutin ve yüzey yenileme akşam rutininde."
                ),
                "priority": 2, "step_order": 20,
            })

    elif concern == "dryness":
        if not _personalization_compress_evening(personalization):
            items.append({
                "time": "Sabah", "category": "Bakım", "icon": "💧",
                "action": _skin_ha("multi"),
                "detail": "Düşük + yüksek mol. ağırlık HA birlikte: yüzeyde ve derinde nemlendirme. Nemli cilde uygula.",
                "priority": 2, "step_order": 20,
            })

    elif concern == "sensitivity":
        # Sabah ek panthenol serumu ekleme: nemlendiricide zaten yatıştırıcı/bariyer katmanı var (çift ürün önlenir).
        pass


def _add_evening_actives(
    items,
    concern,
    severity,
    age_group,
    skin_type,
    personalization: Optional[dict] = None,
):
    """Akşam aktif tedavilerini ekle - yaş ve cilt tipine uygun."""
    pers = personalization or {}
    compress = _personalization_compress_evening(pers)

    if concern == "acne":
        if severity["level"] == "hafif":
            if compress:
                items.append({
                    "time": "Akşam", "category": "Bakım", "icon": "🎯",
                    "action": f"{_skin_salicylic_toner()} → ardından {_skin_niacin_zinc()}",
                    "detail": (
                        "Kişisel puan (yüksek risk veya düşük tolerans): iki ayrı serum yerine aynı akşam sırayla "
                        "veya tek üründe BHA+niasinamid+çinko aranan içerik. Pamukla BHA, kuruduktan sonra ince katman. "
                        "Haftada 3-4 gece."
                    ),
                    "priority": 2, "step_order": 20,
                })
            else:
                items.append({
                    "time": "Akşam", "category": "Bakım", "icon": "🎯",
                    "action": _skin_salicylic_toner(),
                    "detail": "BHA akşamda; sabahda asit kullanılmaz. Pamukla sür, göz çevresinden kaçın. Haftada 3-4 gece ile başla.",
                    "priority": 2, "step_order": 20,
                })
                items.append({
                    "time": "Akşam", "category": "Bakım", "icon": "🍯",
                    "action": _skin_niacin_zinc(),
                    "detail": "BHA sonrası veya BHA olmayan gecelerde. Çinko sebumu dengeler.",
                    "priority": 2, "step_order": 25,
                })
        elif severity["level"] == "orta":
            if compress:
                items.append({
                    "time": "Akşam", "category": "Bakım", "icon": "🎯",
                    "action": f"{_skin_niacinamide('%10')} + {_skin_azelaic()} (sırayla veya tek formül)",
                    "detail": (
                        "Kişisel puan: katman sayısını azalt. Önce niasinamid, kuruduktan sonra azelaik ince katman; "
                        "mümkünse tek üründe ikisi. Haftada 3 gece azelaik ile başla."
                    ),
                    "priority": 2, "step_order": 20,
                })
            else:
                items.append({
                    "time": "Akşam", "category": "Bakım", "icon": "🎯",
                    "action": _skin_niacinamide("%10"),
                    "detail": "Akşam sebum ve bariyer desteği; sabahda yüksek % niasinamid yok.",
                    "priority": 2, "step_order": 20,
                })
                items.append({
                    "time": "Akşam", "category": "Bakım", "icon": "🎯",
                    "action": _skin_azelaic(),
                    "detail": "Niasinamidden sonra ince katman. Haftada 3 gece başla.",
                    "priority": 2, "step_order": 25,
                })
        else:
            if compress:
                items.append({
                    "time": "Akşam", "category": "Bakım", "icon": "⚡",
                    "action": f"{_skin_benzoyl()} → ardından/alternatif geceler {_skin_azelaic()}",
                    "detail": (
                        "Kişisel puan: BP kısa temas (5-10 dk, yıka); aynı gece azelaik istemiyorsan alternatif geceler. "
                        "Sabahda BP yok."
                    ),
                    "priority": 2, "step_order": 20,
                })
            else:
                items.append({
                    "time": "Akşam", "category": "Bakım", "icon": "⚡",
                    "action": _skin_benzoyl(),
                    "detail": "Akşam kısa temas; sabahda BP yok. Yüze sür, 5-10 dk bekle, yıka.",
                    "priority": 2, "step_order": 20,
                })
                items.append({
                    "time": "Akşam", "category": "Bakım", "icon": "🎯",
                    "action": _skin_azelaic(),
                    "detail": "BP sonrası veya alternatif gecelerde. Haftada 2-3 gece başla.",
                    "priority": 3, "step_order": 25,
                })

    elif concern == "aging":
        if age_group["group"] == "adolescent":
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "🌿",
                "action": _skin_peptide_light(),
                "detail": "Genç yaşta retinol gereksiz. Peptid ile cildin doğal yenilenme kapasitesini destekle.",
                "priority": 2, "step_order": 20,
            })
        elif age_group["group"] == "young_adult":
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "🔬",
                "action": _skin_retinol("%0.25-0.3"),
                "detail": "Gece yaşlanma aktifi; yalnızca haftalık plandaki akşamlarda. Haftada 2 gece ile başla. Aynı gece ek asit ekleme.",
                "priority": 2, "step_order": 20,
            })
        elif age_group["group"] == "adult":
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "🔬",
                "action": _skin_retinol("%0.5"),
                "detail": "Gece tek güçlü aktif. Haftada 3 gece ile başla; günler sistem tarafından atanır. Aynı gece ek asit yok.",
                "priority": 2, "step_order": 20,
            })
        elif age_group["group"] == "mature":
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "🔬",
                "action": _skin_retinol("%0.5-1"),
                "detail": "Gece retinol. Haftada 2-3 gece; günler sistem tarafından atanır. Tahriş sinyalinde sıklık motor tarafından düşürülür.",
                "priority": 2, "step_order": 20,
            })
        else:
            if compress:
                items.append({
                    "time": "Akşam", "category": "Bakım", "icon": "💎",
                    "action": (
                        f"Gece (tek yoğun blok): {_skin_peptide_ha()} + {_skin_bakuchiol()} + "
                        "seramid NP/AP/EOP 3:1:1 (tek serum veya sıralı ince katmanlar)"
                    ),
                    "detail": (
                        "Kişisel puan: üç ayrı rutin satırı yerine aynı akşam peptid+HA → bakuchiol → seramid sırası; "
                        "mümkünse çoklu içerikli tek gece ürünü. Sabahda sadece hafif HA kullanıldı."
                    ),
                    "priority": 2, "step_order": 20,
                })
            else:
                items.append({
                    "time": "Akşam", "category": "Bakım", "icon": "💎",
                    "action": _skin_peptide_ha(),
                    "detail": "Akşam yoğun onarım; sabahda sadece hafif HA kullanıldı.",
                    "priority": 2, "step_order": 20,
                })
                items.append({
                    "time": "Akşam", "category": "Bakım", "icon": "🌿",
                    "action": _skin_bakuchiol(),
                    "detail": "Peptid tabanından sonra. Retinol etkisine yakın, daha nazik.",
                    "priority": 2, "step_order": 22,
                })
                items.append({
                    "time": "Akşam", "category": "Bakım", "icon": "🧬",
                    "action": "Seramid NP/AP/EOP + kolesterol + yağ asitleri (3:1:1 bariyer onarım, INCI: Ceramide NP vb.)",
                    "detail": "Yaşla azalan bariyer lipidlerini geri kazandır. 3:1:1 oranı bilimsel altın standarttır.",
                    "priority": 2, "step_order": 25,
                })

    elif concern == "pigmentation":
        aha_pct = min(age_group["aha_max_pct"], 10)
        has_peel_or_retinoid = False
        # Retinol ile AHA aynı rutinde netlik: şiddette retinol; orta/üstte AHA; hafifte ikisi yok
        if severity["level"] == "şiddetli" and age_group["retinol_ok"]:
            has_peel_or_retinoid = True
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "🔬",
                "action": _skin_retinol("%0.3"),
                "detail": "Gece leke aktifi; yalnızca haftalık plandaki akşamlarda. Aynı rutinde AHA yok. Haftada 2 gece ile başla.",
                "priority": 2, "step_order": 20,
            })
        elif severity["level"] != "hafif":
            has_peel_or_retinoid = True
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "🔬",
                "action": _skin_glycolic(float(aha_pct)),
                "detail": (
                    f"Yüzey yenileme; yalnızca haftalık plandaki akşamlarda. Haftada 2-3 gece; günler atanır. "
                    f"Yaşın için %{aha_pct} uygun. Bu rutinde retinol yok."
                ),
                "priority": 2, "step_order": 20,
            })
        ab_label = "(%2)" if age_group["group"] == "adolescent" else "(%2-3)"
        ab_step = 22 if has_peel_or_retinoid else 20
        if compress:
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "💎",
                "action": f"Leke kompleksi: {_skin_arbutin(ab_label)} + {_skin_niacin_tranexamic()}",
                "detail": (
                    "Kişisel puan: arbutin ve niasinamid+TXA ayrı satır yerine tek blok; güçlü asit/retinol gecelerinde "
                    "önce onlar, sonra bu leke katmanı. Tek serum veya sıralı ince katmanlar."
                    if has_peel_or_retinoid else
                    "Kişisel puan: iki leke adımı tek blokta; arbutin sonra niasinamid+TXA ince katman."
                ),
                "priority": 2, "step_order": ab_step,
            })
        else:
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "💎",
                "action": _skin_arbutin(ab_label),
                "detail": "Leke hedefleme; sabah C ile çiftlenmez (C sabah, arbutin akşam). Güçlü asit/retinol gecelerinde sıra: önce onlar, sonra bu.",
                "priority": 2, "step_order": ab_step,
            })
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "✨",
                "action": _skin_niacin_tranexamic(),
                "detail": (
                    "Leke baskılama; güçlü gece adımı ve arbutinden sonra, gece nemlendiricisinden önce."
                    if has_peel_or_retinoid else
                    "Leke baskılama; arbutinden sonra, gece nemlendiricisinden önce."
                ),
                "priority": 2, "step_order": 25 if has_peel_or_retinoid else 22,
            })

    elif concern == "dryness":
        if not compress:
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "🧴",
                "action": "Seramid NP/AP/EOP + squalane onarım serumu (INCI: Ceramide NP vb. + skualan)",
                "detail": "Cilt bariyerinin %50'si seramiddir. Gece boyu bariyer onarımı sağlar.",
                "priority": 2, "step_order": 20,
            })
        if severity["level"] == "şiddetli" and not pers.get("merge_barrier_layers"):
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "💦",
                "action": "Gece: Hyaluronik asit + Seramid (uyku maskesi formülü)",
                "detail": "Serumdan sonra, standart gece nemlendiricisinden önce veya son katman olarak uygula.",
                "priority": 2, "step_order": 35,
            })

    elif concern == "sensitivity":
        # Akşam ayrı centella/panthenol serumu yok; şiddetli dahil gece tek katman → build_evening_moisturizer_item
        pass

    elif concern == "oiliness":
        # Yağlılık: akne gibi agresif değil; temel dengeleme
        if compress:
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "🎯",
                "action": f"{_skin_salicylic_toner()} → ardından {_skin_niacin_zinc()}",
                "detail": "Sebum/gözenek için BHA + niasinamid/çinko. Haftada 2-3 gece.",
                "priority": 2, "step_order": 20,
            })
        else:
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "🎯",
                "action": _skin_salicylic_toner(),
                "detail": "BHA akşamda; haftada 2-3 gece. Göz çevresinden kaçın.",
                "priority": 2, "step_order": 20,
            })
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "🍯",
                "action": _skin_niacin_zinc(),
                "detail": "BHA sonrası veya BHA olmayan gecelerde. Sebumu dengelemeye destek olur.",
                "priority": 2, "step_order": 25,
            })

    elif concern == "pores":
        # Siyah nokta/gözenek: ana hedef komedon tıkacı ve sebum dengesi
        if compress:
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "🕳️",
                "action": f"{_skin_salicylic_toner()} → ardından {_skin_niacin_zinc()}",
                "detail": "Siyah nokta ve tıkanıklık için BHA; ardından sebum dengesi için niasinamid/çinko. Haftada 2-3 gece.",
                "priority": 2, "step_order": 20,
            })
        else:
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "🕳️",
                "action": _skin_salicylic_toner(),
                "detail": "Siyah nokta için en direkt adım: BHA. Akşam haftada 2-3 gece.",
                "priority": 2, "step_order": 20,
            })
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "🍯",
                "action": _skin_niacin_zinc(),
                "detail": "BHA sonrası veya BHA olmayan gecelerde. Gözenek/sebum dengesine destek olur.",
                "priority": 2, "step_order": 25,
            })

    elif concern == "general":
        # Genel bakım: gece güçlü aktif şart değil; bariyer odaklı kal
        pass


# ══════════════════════════════════════════════════════════════════════
# 7. LIFESTYLE MODIFIERS - Yaşam tarzı dalları
# ══════════════════════════════════════════════════════════════════════

def compute_lifestyle_branches(
    stress_score: int,
    sleep_hours: float,
    water_intake: float,
    smoking: bool,
    alcohol: bool,
    age: int,
    concern: str,
    smoking_per_day: int = 0,
    smoking_years: int = 0,
    alcohol_frequency: int = 0,
    alcohol_amount: int = 1,
) -> list:
    """Her yaşam tarzı faktörü için rutin öğeleri üretir."""
    items = []

    # ── Stres Dalı (TÜM concern'ler için aktif) ──
    if stress_score > 10:
        items.append({
            "time": "Akşam", "category": "Zihin", "icon": "🧘",
            "action": "Box Breathing + 10 dk Meditasyon",
            "detail": f"Stres puanın çok yüksek ({stress_score}/16). Yüksek kortizol cildi doğrudan bozar: "
                     f"{'akne alevlenmesi, sebum artışı' if concern == 'acne' else 'kolajen yıkımı hızlanır' if concern == 'aging' else 'bariyer zayıflaması'}.",
            "usage": (
                "Box breathing: 4 sn nefes al, 4 sn tut, 4 sn ver, 4 sn bekle; 5–10 tur. "
                "Ardından 10 dk sessiz oturma veya rehberli nefes/meditasyon uygula."
            ),
            "priority": 1,
        })
        items.append({
            "time": "Akşam", "category": "Beslenme", "icon": "🍵",
            "action": "Adaptojenik Çay (Ashwagandha + Melisa)",
            "detail": "Kortizolü düşürmek için adaptojenik bitkiler yatış öncesi rahatlamayı destekleyebilir.",
            "usage": "Paket önerisine göre demle; yatmadan yaklaşık 30 dk önce iç, aşırı sıcak içme.",
            "priority": 2,
        })
    elif stress_score > 6:
        items.append({
            "time": "Akşam", "category": "Zihin", "icon": "🌿",
            "action": "5 Dakika Nefes Egzersizi",
            "detail": f"Stres puanın orta ({stress_score}/16). Parasempatik sistemi güçlendirmek yenilenmeyi destekler.",
            "usage": (
                "4-7-8: burnundan 4 sn nefes al, 7 sn tut, ağızdan 8 sn ver; 4–6 tur, yaklaşık 5 dakika. "
                "Rahat otur, omuzları gevşet."
            ),
            "priority": 2,
        })
    elif stress_score > 3:
        items.append({
            "time": "Akşam", "category": "Zihin", "icon": "🎵",
            "action": "Rahatlama Rutini",
            "detail": "Geçiş ritüeli uyku kalitesini ve gece onarımını destekleyebilir.",
            "usage": "Yatmadan yaklaşık 1 saat önce ekranları kapat; sakin müzik, kitap veya hafif esneme ile günü bitir.",
            "priority": 3,
        })

    # ── Uyku Dalı ──
    if sleep_hours < 5:
        items.append({
            "time": "Akşam", "category": "Yaşam", "icon": "🚨",
            "action": "Acil Uyku Düzenlemesi",
            "detail": f"Sadece {sleep_hours} saat uyku cilt için kriz durumu. "
                     "Melatonin üretimi bozulur, HGH salgısı düşer. Hedef: en az 7 saat.",
            "usage": (
                "Bu hafta her gece 15–30 dk daha erken yatmaya çalış; sabah aynı pencerede uyan. "
                "Oda karanlık ve serin; yatmadan 60 dk ekranı kes."
            ),
            "priority": 1,
        })
    elif sleep_hours < 6.5:
        items.append({
            "time": "Akşam", "category": "Yaşam", "icon": "😴",
            "action": "Uyku Hijyeni Protokolü",
            "detail": f"{sleep_hours} saat yetersiz. Karanlık, serin ortam ve ışık yönetimi onarımı destekler.",
            "usage": (
                "Yatak odasını serin ve karanlık tut; akşam parlak ekranı azalt. "
                "23:00–03:00 arası uyku, cilt yenilenmesi için özellikle değerlidir."
            ),
            "priority": 2,
        })
    elif sleep_hours < 7.5:
        items.append({
            "time": "Akşam", "category": "Yaşam", "icon": "🌙",
            "action": "Uyku Optimizasyonu",
            "detail": "Derin uyku fazında büyüme hormonu salgılanır; cilt onarımı bu dönemde hızlanır.",
            "usage": "Her gece hedefin 15–30 dk daha erken yatmak; hafta içi yatış/kalkış saatlerini sabitle.",
            "priority": 3,
        })

    # ── Su Dalı ──
    if water_intake < 1.0:
        items.append({
            "time": "Sabah", "category": "Yaşam", "icon": "🚰",
            "action": "Acil Hidrasyon Planı",
            "detail": f"Günde {water_intake}L su kritik seviyede düşük; cilt ve genel doku nemini doğrudan etkiler.",
            "usage": "Sabah kalkınca ~500 ml; her ana öğünde ~400 ml; ara öğünlerde ~200 ml hedefle.",
            "priority": 1,
        })
    elif water_intake < 1.5:
        items.append({
            "time": "Sabah", "category": "Yaşam", "icon": "💧",
            "action": "Hidrasyon Artışı (2L+ Hedef)",
            "detail": f"{water_intake}L yeterli değil; cilt nem dengesi su alımıyla yakından ilişkilidir.",
            "usage": "Günlük 2 L+ için telefona hatırlatıcı kur; her öğünle bir bardak içmeyi alışkanlık yap.",
            "priority": 2,
        })
    elif water_intake < 2.0:
        items.append({
            "time": "Sabah", "category": "Yaşam", "icon": "💧",
            "action": "Su Optimizasyonu",
            "detail": "Mevcut alımın iyi; 2 L civarı hedef bariyer ve genel hidrasyonu destekler.",
            "usage": "Günlük suyu artırmak için limonlu veya salatalıklı su gibi hafif tatlar kullan.",
            "priority": 3,
        })

    # ── Sigara Dalı (Detaylı Paket-Yıl Analizi) ──
    pack_years = round((smoking_per_day / 20) * smoking_years, 1) if smoking_per_day > 0 else 0.0

    if smoking_per_day > 0:
        if pack_years >= 10:
            items.append({
                "time": "Sabah", "category": "Yaşam", "icon": "🚨",
                "action": "Acil Sigara Azaltma Programı",
                "detail": f"Günde {smoking_per_day} sigara x {smoking_years} yıl = {pack_years} paket-yıl. "
                         f"Ciddi kümülatif hasar: kolajen üretimi %{min(25 + int(pack_years), 50)} düşmüş, "
                         "elastin hasarı geri dönüşü zor. Dermatolog kontrolü önerilir.",
                "priority": 1,
            })
            items.append({
                "time": "Sabah", "category": "Beslenme", "icon": "💊",
                "action": "Yüksek Doz Antioksidan Protokolü",
                "detail": f"{pack_years} paket-yıl sigara hasarı için: C Vitamini 2000mg/gün, "
                         "NAC 1200mg/gün, CoQ10 200mg/gün, E Vitamini 400IU. "
                         "Glutatyon depolarını yeniden doldur.",
                "priority": 1,
            })
        elif pack_years >= 5:
            items.append({
                "time": "Sabah", "category": "Yaşam", "icon": "🚭",
                "action": "Sigara Hasarı Onarım Programı",
                "detail": f"Günde {smoking_per_day} sigara x {smoking_years} yıl = {pack_years} paket-yıl. "
                         "Orta düzey kümülatif hasar. Kolajen üretimi yavaşlamış, "
                         "cilt rengi solmuş olabilir. Antioksidan desteği kritik.",
                "priority": 1,
            })
            items.append({
                "time": "Sabah", "category": "Beslenme", "icon": "🥦",
                "action": "Antioksidan Zengin Diyet + Supplement",
                "detail": "C Vitamini 1000mg + NAC 600mg + günde 5 porsiyon koyu renkli "
                         "sebze-meyve (yaban mersini, ıspanak, brokoli, domates).",
                "priority": 2,
            })
        else:
            items.append({
                "time": "Sabah", "category": "Yaşam", "icon": "🚭",
                "action": "Antioksidan Takviyesi (Erken Müdahale)",
                "detail": f"Günde {smoking_per_day} sigara. Erken dönem hasarı geri çevrilebilir! "
                         "Şimdi bırakmak cilt yenilenmesini 6-12 ayda belirgin iyileştirir. "
                         "C + E vitamini serumu günlük kullan.",
                "priority": 2,
            })

        if age > 30 and pack_years >= 3:
            items.append({
                "time": "Sabah", "category": "Bakım", "icon": "🛡️",
                "action": "Sigara + Yaş Kombine Koruma",
                "detail": f"{age} yaş + {pack_years} paket-yıl: serbest radikal hasarı katlanıyor. "
                         "SPF 50+ her gün, C Vitamini serum + peptid onarım gece rutinine ekle.",
                "priority": 1,
            })
    elif smoking:
        items.append({
            "time": "Sabah", "category": "Yaşam", "icon": "🚭",
            "action": "Antioksidan Takviyesi (Sigara Hasarı)",
            "detail": "Sigara kolajen üretimini %25 düşürür ve serbest radikalleri artırır. "
                     "C + E vitamini serumu şart.",
            "priority": 1,
        })

    # ── Alkol Dalı (Detaylı Haftalık Analiz) ──
    weekly_drinks = alcohol_frequency * alcohol_amount if alcohol_frequency > 0 else 0

    if weekly_drinks >= 14:
        items.append({
            "time": "Sabah", "category": "Yaşam", "icon": "🚨",
            "action": "Ağır Alkol Hasarı Protokolü",
            "detail": f"Haftalık ~{weekly_drinks} kadeh: ağır tüketim. Ciddi dehidrasyon, "
                     "B12/folat/çinko eksikliği, karaciğer stresi. Cilt: şişkinlik, "
                     "kızarıklık, erken yaşlanma, rozasea riski. Azaltmak şart.",
            "priority": 1,
        })
        items.append({
            "time": "Sabah", "category": "Beslenme", "icon": "💊",
            "action": "Alkol Hasar Onarım Supplementleri",
            "detail": "B Kompleks (B1, B6, B12 yüksek doz), Çinko 30mg, "
                     "Milk Thistle 600mg (karaciğer koruma), Omega-3 2000mg. "
                     "Alkol günlerinde 1L ekstra su iç.",
            "priority": 1,
        })
    elif weekly_drinks >= 7:
        items.append({
            "time": "Sabah", "category": "Yaşam", "icon": "🫗",
            "action": "Alkol Azaltma + Hidrasyon Planı",
            "detail": f"Haftalık ~{weekly_drinks} kadeh: orta-yüksek tüketim. "
                     "Alkol cilt pH'ını bozar, gözenekleri genişletir, dehidrate eder. "
                     "Her alkollü içecek için 1 bardak su iç, haftada 2 alkol-free gün hedefle.",
            "priority": 2,
        })
        items.append({
            "time": "Sabah", "category": "Beslenme", "icon": "💊",
            "action": "B Vitamini + Elektrolit Desteği",
            "detail": "B Kompleks vitamin + çinko takviyesi. Alkol bu mineralleri tüketir, "
                     "eksiklik cilt sorunlarını kötüleştirir.",
            "priority": 2,
        })
    elif weekly_drinks >= 3:
        items.append({
            "time": "Sabah", "category": "Yaşam", "icon": "🫗",
            "action": "Ekstra Hidrasyon (Alkol Kompanzasyonu)",
            "detail": f"Haftalık ~{weekly_drinks} kadeh. Her alkollü günde 500ml ekstra su iç. "
                     "Sabah ilk iş ılık limonlu su + B kompleks vitamin.",
            "priority": 3,
        })
    elif alcohol and alcohol_frequency > 0:
        items.append({
            "time": "Sabah", "category": "Yaşam", "icon": "💧",
            "action": "Alkol Sonrası Hidrasyon",
            "detail": "Düşük alkol tüketimi. Yine de alkollü günlerde ekstra su iç ve "
                     "ertesi sabah nemlendiriciyi artır.",
            "priority": 4,
        })

    return items


# ══════════════════════════════════════════════════════════════════════
# 8. HOLİSTİK YAŞAM MOTORU - Beslenme, Egzersiz, Supplement
# ══════════════════════════════════════════════════════════════════════

def compute_holistic_recommendations(
    concern: str,
    age: int,
    severity_level: str,
    water_intake: float,
    sleep_hours: float,
    smoking: bool,
) -> list:
    """Kişiye özel beslenme, egzersiz ve supplement önerileri."""
    items = []

    # ── BESLENME ──
    nutrition = _get_nutrition_plan(concern, age, severity_level)
    for n in nutrition:
        items.append(n)

    # ── EGZERSİZ (Günlük: takip ekranında “gün boyunca” ile birlikte görünsün) ──
    items.append({
        "time": "Günlük",
        "category": "Yaşam",
        "icon": "🚶",
        "action": "Yürüyüş veya hafif hareket",
        "detail": (
            "Kan dolaşımını destekler; nefes ve stres rutinleriyle birlikte düşünüldüğünde cilt için dolaylı fayda sağlayabilir."
        ),
        "usage": (
            "Gün içinde toplam yaklaşık 20–30 dakika tempolu yürüyüş, bisiklet veya hafif kardiyo hedefle; "
            "tek seferde veya parçalara bölerek uygula."
        ),
        "priority": 4,
        "step_order": 8,
    })

    # ── SUPPLEMENT ──
    supplements = _get_supplement_plan(concern, age, severity_level, smoking)
    for s in supplements:
        items.append(s)

    return items


def build_mind_body_protocol_items(
    water_intake: float,
    sleep_hours: float,
    stress_score: int,
    risk_level: str,
    concern: str,
) -> list:
    """
    Bütüncül rutin: su, nefes, uyku ritmi (+ endişeye göre antioksidan besin vurgusu).
    Tek paragraf yerine ayrı Yaşam satırları.
    """
    stress_hi = stress_score >= 10
    w_low = float(water_intake or 0) < 2.0
    s_low = float(sleep_hours or 0) < 7.0
    cold = risk_level in ("moderate", "high", "crisis")

    items = [
        {
            "time": "Günlük",
            "category": "Yaşam",
            "icon": "💧",
            "action": "Su rutini (hidrodenge)",
            "detail": (
                "Düzenli sıvı alımı bariyer fonksiyonu ve genel doku tazeliğini destekler."
                + (" Şu an hedefe yaklaşmak cilt bariyeri ve elastikiyet için özellikle önerilir." if w_low else "")
            ),
            "usage": (
                "Hedef yaklaşık 1.8–2.5 L (kilo ve aktiviteye göre ayarla). "
                "Sabah bir bardak, öğünlerle ve susadığında iç; kafein veya alkollü günlerde ekstra bir bardak ekle."
            ),
            "priority": 2 if (w_low or cold) else 5,
            "step_order": 2,
        },
        {
            "time": "Sabah",
            "category": "Yaşam",
            "icon": "🌬️",
            "action": "Kısa nefes egzersizi",
            "detail": (
                "Otonom sinir sistemini yumuşatır; stresle uyumlu cilt tepkilerini hafifletmeye yardımcı olabilir."
                + (" Bugün stres yüksek görünüyor; özellikle önerilir." if stress_hi else "")
            ),
            "usage": (
                "2–4 dakika ayır: 4 sn burundan al, 6 sn ağızdan ver; 6–10 tekrar. "
                "İstersen 4-7-8: 4 sn burundan al, 7 sn tut, 8 sn ağızdan ver; birkaç tur."
            ),
            "priority": 1 if stress_hi else 5,
            "step_order": 12,
        },
        {
            "time": "Akşam",
            "category": "Yaşam",
            "icon": "🌙",
            "action": "Uyku öncesi protokol",
            "detail": (
                "Düzenli, yeterli uyku gece onarımı ve rutindeki nem/onarım adımlarını destekler."
                + (" Uyku süreni kademeli olarak 7 saat civarına yaklaştırmayı hedefle." if s_low else "")
            ),
            "usage": (
                "Yatmadan 60–90 dk önce ekran ve parlak ışığı azalt; odayı serin ve karanlık tut. "
                "Yatış/kalkış saatlerini hafta içi birbirine yakın tut."
            ),
            "priority": 1 if (s_low or cold) else 5,
            "step_order": 80,
        },
    ]
    if concern in ("aging", "pigmentation"):
        items.append({
            "time": "Sabah",
            "category": "Yaşam",
            "icon": "🫐",
            "action": "Antioksidan yoğun besinler (tabaktan)",
            "detail": (
                "Renkli sebze-meyve, yeşil çay, domates/biber gibi kaynaklar UV ve oksidatif strese karşı içerden destek sunar."
            ),
            "usage": (
                "Öğünlere renkli sebze-meyve ekle; yeşil çay veya domates/biberi gün içine yay. "
                "Tablet/oral takviye için önce eczacı veya hekim onayı al; rutindeki ürünlerle birlikte kendi kendine başlama."
            ),
            "priority": 4,
            "step_order": 25,
        })
    return items


def _get_nutrition_plan(concern: str, age: int, severity_level: str) -> list:
    """Concern'e özel beslenme önerileri."""
    items = []

    if concern == "acne":
        items.append({
            "time": "Sabah", "category": "Beslenme", "icon": "🥗",
            "action": "Düşük Glisemik İndeks Diyeti",
            "detail": "Beyaz ekmek, şeker, süt ürünleri akneyi %30-50 artırır (meta-analiz). "
                     "Tam tahıl, sebze, protein tercih et.",
            "priority": 2,
        })
        if severity_level in ("orta", "şiddetli"):
            items.append({
                "time": "Sabah", "category": "Beslenme", "icon": "🐟",
                "action": "Omega-3 Zengin Beslenme",
                "detail": "Haftada 3x yağlı balık (somon, sardalya) veya günlük ceviz/keten tohumu. "
                         "Anti-enflamatuar etki akne şiddetini azaltır.",
                "priority": 2,
            })

    elif concern == "aging":
        items.append({
            "time": "Sabah", "category": "Beslenme", "icon": "🫐",
            "action": "Antioksidan Zengin Beslenme",
            "detail": "Her gün 5 porsiyon renkli sebze-meyve. Likopen (domates), "
                     "resveratrol (üzüm), kateşinler (yeşil çay) kolajen korur.",
            "priority": 2,
        })
        if age > 40:
            items.append({
                "time": "Sabah", "category": "Beslenme", "icon": "🍖",
                "action": "Protein Artışı (1.2g/kg)",
                "detail": "40+ yaşta kas ve kolajen kaybı hızlanır. "
                         "Her öğünde avuç içi kadar protein (yumurta, balık, baklagil).",
                "priority": 3,
            })

    elif concern == "pigmentation":
        items.append({
            "time": "Sabah", "category": "Beslenme", "icon": "🍊",
            "action": "C Vitamini Zengin Beslenme",
            "detail": "Portakal, kivi, kırmızı biber her gün. İçeriden C vitamini melanin inhibisyonunu destekler.",
            "priority": 3,
        })

    elif concern == "dryness":
        items.append({
            "time": "Sabah", "category": "Beslenme", "icon": "🥑",
            "action": "Sağlıklı Yağ Tüketimi",
            "detail": "Avokado, zeytinyağı, ceviz her gün. Yağ asitleri cilt bariyerinin yapı taşıdır.",
            "priority": 2,
        })

    elif concern == "sensitivity":
        items.append({
            "time": "Sabah", "category": "Beslenme", "icon": "🦠",
            "action": "Probiyotik + Prebiyotik Beslenme",
            "detail": "Bağırsak-cilt ekseni: kefir, yoğurt, lahana turşusu. "
                     "Bağırsak florasını güçlendirmek cilt hassasiyetini azaltır.",
            "priority": 2,
        })

    # Herkes için: İşlenmiş gıda azaltma
    items.append({
        "time": "Sabah", "category": "Beslenme", "icon": "🚫",
        "action": "İşlenmiş Gıda ve Şeker Azaltma",
        "detail": "Rafine şeker, kızartma ve paketli gıdalar enflamasyonu artırır. "
                 "Doğal, taze gıdaları tercih et.",
        "priority": 4,
    })

    return items


def _get_supplement_plan(concern: str, age: int, severity_level: str, smoking: bool) -> list:
    """Concern ve yaşa özel supplement önerileri."""
    items = []

    if concern == "acne":
        items.append({
            "time": "Sabah", "category": "Beslenme", "icon": "💊",
            "action": "Çinko Bisglisinat (30mg/gün)",
            "detail": "Çinko sebum üretimini düzenler ve anti-enflamatuar. "
                     "17 çalışmanın meta-analizi etkinliğini doğruluyor.",
            "priority": 3,
        })
        if severity_level in ("orta", "şiddetli"):
            items.append({
                "time": "Sabah", "category": "Beslenme", "icon": "🦠",
                "action": "Probiyotik (Lactobacillus + Bifidobacterium)",
                "detail": "Bağırsak-cilt bağlantısı: probiyotik akne şiddetini %40 azaltabilir.",
                "priority": 3,
            })

    elif concern == "aging":
        if age >= 30:
            items.append({
                "time": "Sabah", "category": "Beslenme", "icon": "💊",
                "action": "Kolajen Peptid (10g/gün)",
                "detail": "Hidrolize kolajen peptidleri 8 haftalık çalışmalarda cilt elastikiyetini %20 artırdı.",
                "priority": 3,
            })
        if age >= 40:
            items.append({
                "time": "Sabah", "category": "Beslenme", "icon": "💊",
                "action": "Koenzim Q10 (100mg/gün)",
                "detail": "Hücresel enerji üretimi ve antioksidan. 40+ yaşta doğal CoQ10 azalır.",
                "priority": 4,
            })

    elif concern == "dryness":
        items.append({
            "time": "Sabah", "category": "Beslenme", "icon": "💊",
            "action": "Omega-3 (EPA + DHA 1000mg/gün)",
            "detail": "Balık yağı cilt bariyerini güçlendirir, transepidermal su kaybını azaltır.",
            "priority": 3,
        })

    elif concern == "sensitivity":
        items.append({
            "time": "Sabah", "category": "Beslenme", "icon": "💊",
            "action": "Quersetin + C Vitamini Kompleks",
            "detail": "Doğal antihistaminik etki. Cilt reaktivitesini azaltır.",
            "priority": 3,
        })

    if smoking:
        items.append({
            "time": "Sabah", "category": "Beslenme", "icon": "💊",
            "action": "C Vitamini (1000mg) + NAC (600mg)",
            "detail": "Sigara C vitaminini tüketir. NAC glutatyon üretimini destekler (en güçlü antioksidan).",
            "priority": 2,
        })

    return items


# ══════════════════════════════════════════════════════════════════════
# 9. ENVIRONMENT MODIFIERS - Çevresel dallar
# ══════════════════════════════════════════════════════════════════════

def compute_environment_branches(
    uv_index: float,
    humidity: float,
    temperature: float,
    skin_type: dict,
) -> list:
    """Hava durumu + cilt tipine göre çevresel öneriler."""
    items = []

    # ── UV Dalı (SPF = sabah rutininin SON adımı) ──
    spf_type = skin_type.get("spf_type", "geniş spektrumlu SPF")
    if uv_index >= 8:
        items.append({
            "time": "Sabah", "category": "Koruma", "icon": "🛡️",
            "action": f"SPF 50+ ({spf_type})",
            "detail": f"UV tehlikeli ({uv_index}). Nemlendirici emildikten sonra bol miktarda sür. Her 2 saatte yenile.",
            "priority": 1, "step_order": 40,
        })
    elif uv_index >= 5:
        items.append({
            "time": "Sabah", "category": "Koruma", "icon": "☀️",
            "action": f"SPF 50 ({spf_type})",
            "detail": f"UV yüksek ({uv_index}). Son adım olarak sür, öğlen direkt güneşten kaçın.",
            "priority": 1, "step_order": 40,
        })
    elif uv_index >= 3:
        items.append({
            "time": "Sabah", "category": "Koruma", "icon": "🌤️",
            "action": f"SPF 30+ ({spf_type})",
            "detail": f"UV orta ({uv_index}). Her gün son adım olarak sür.",
            "priority": 2, "step_order": 40,
        })
    else:
        items.append({
            "time": "Sabah", "category": "Koruma", "icon": "☁️",
            "action": f"SPF 30 ({spf_type})",
            "detail": "Bulutlu havada bile %80 UV geçer. Her gün kullan.",
            "priority": 3, "step_order": 40,
        })

    # ── Nem Dalı ──
    if humidity < 25:
        items.append({
            "time": "Sabah", "category": "Bakım", "icon": "🏜️",
            "action": "Yoğun nemlendirme: HA (çoklu mol.) + Seramid %2",
            "detail": f"Hava çok kuru (%{humidity} nem). HA serum + seramid krem ikili şart.",
            "priority": 1,
        })
        items.append({
            "time": "Akşam", "category": "Bakım", "icon": "💦",
            "action": "Gece maskesi: HA + Seramid (oklüzif katman)",
            "detail": "Gece nem kaybını engellemek için oklüzif sleeping mask uygula.",
            "priority": 2,
        })
    elif humidity < 40:
        items.append({
            "time": "Sabah", "category": "Bakım", "icon": "💦",
            "action": "Ekstra nem: HA + Panthenol %5 katmanı",
            "detail": f"Nem düşük (%{humidity}). Serum + nemlendirici ikili kullan.",
            "priority": 2,
        })
    elif humidity > 75:
        items.append({
            "time": "Sabah", "category": "Bakım", "icon": "🌊",
            "action": "Hafif jel: HA + Niasinamid %5",
            "detail": f"Nem çok yüksek (%{humidity}). Bu planda ağır krem yerine su bazlı jel formülü öne alındı.",
            "priority": 2,
        })

    # ── Sıcaklık Dalı ──
    if temperature > 35:
        items.append({
            "time": "Sabah", "category": "Bakım", "icon": "🔥",
            "action": "HA + Panthenol %5 (hafif, sıcak hava)",
            "detail": f"Hava çok sıcak ({temperature}°C). Termal su yanında taşı, yoğun maddelerden kaçın.",
            "priority": 3,
        })
    elif temperature < 5:
        items.append({
            "time": "Sabah", "category": "Bakım", "icon": "❄️",
            "action": "Seramid %2-5 + Kolesterol + Vazelin (bariyer onarım)",
            "detail": f"Hava çok soğuk ({temperature}°C). Rüzgar ve soğuk bariyeri zayıflatır; seramid+kolesterol bariyer onarımı.",
            "priority": 2,
        })

    return items


# ══════════════════════════════════════════════════════════════════════
# 10. HAMİLELİK GÜVENLİK FİLTRESİ
# ══════════════════════════════════════════════════════════════════════

PREGNANCY_UNSAFE_KEYWORDS = [
    "retinol", "retinoid", "tretinoin", "adapalen", "isotretinoin",
    "salisilik asit", "bha", "benzoil peroksit",
    "aha", "glikolik asit", "laktik asit",
    "hidroquinon", "formaldehit",
]

PREGNANCY_SAFE_REPLACEMENTS = {
    "retinol": ("Bakuchiol", "Hamilelikte retinol yasak. Bakuchiol doğal ve güvenli bir alternatif."),
    "retinoid": ("Bakuchiol", "Retinoidler hamilelikte kontrendike. Bakuchiol aynı reseptöre bağlanır."),
    "tretinoin": ("Bakuchiol + Peptid", "Reçeteli retinoid hamilelikte kesinlikle yasak."),
    "adapalen": ("Azelaik Asit %15", "Adapalen hamilelikte güvensiz. Azelaik asit güvenli alternatif."),
    "salisilik asit": ("Glikolsüz Enzim Peeling", "Salisilik asit hamilelikte sınırlı. Enzim peeling daha güvenli."),
    "benzoil peroksit": ("Azelaik Asit %10", "BP hamilelikte güvenlik verisi yetersiz. Azelaik asit güvenli."),
    "aha": ("Laktik Asit %5 (düşük doz)", "Yüksek doz AHA'lardan kaçın. Düşük doz laktik asit güvenli sayılır."),
    "glikolik asit": ("Mandel Asit %5", "Yüksek konsantrasyon glikolik asitten kaçın."),
}

def apply_pregnancy_safety(routine_items: list) -> list:
    """Hamilelikte güvensiz maddeleri güvenli alternatiflerle değiştirir."""
    safe_items = []
    for item in routine_items:
        action_lower = item.get("action", "").lower()
        detail_lower = item.get("detail", "").lower()
        combined = action_lower + " " + detail_lower

        replaced = False
        for keyword in PREGNANCY_UNSAFE_KEYWORDS:
            if keyword in combined:
                replacement = PREGNANCY_SAFE_REPLACEMENTS.get(keyword)
                if replacement:
                    new_item = dict(item)
                    new_item["action"] = f"🤰 {replacement[0]} (Hamilelik Güvenli)"
                    new_item["detail"] = replacement[1]
                    new_item["icon"] = "🤰"
                    safe_items.append(new_item)
                    replaced = True
                    break
        if not replaced:
            safe_items.append(item)

    safe_items.insert(0, {
        "time": "Sabah", "category": "Koruma", "icon": "🤰",
        "action": "Hamilelik Güvenlik Modu Aktif",
        "detail": "Retinoidler, salisilik asit ve bazı aktifler güvenli alternatiflerle değiştirildi.",
        "priority": 0,
    })

    return safe_items


# ══════════════════════════════════════════════════════════════════════
# 11. HORMONAL DÖNGÜ MODİFİYERLERİ
# ══════════════════════════════════════════════════════════════════════

def compute_hormonal_modifiers(cycle_phase: str, concern: str) -> list:
    """Adet döngüsü fazına göre cilt bakım modifiyeleri."""
    items = []

    if cycle_phase == "menstrual":
        # Ekstra centella/panthenol nemlendirici satırı ekleme — rutindeki sabah nemlendirici ile çakışırdı.
        items.append({
            "time": "Sabah", "category": "Zihin", "icon": "🔴",
            "action": "Dönem notu: adet fazı",
            "detail": "Östrojen/progesteron düşüşü cildi hassas veya kuruk yapabilir. Rutindeki temizlik + nemlendirici + SPF’yi sürdür; "
                     "aynı işi gören ekstra centella/panthenol katmanı ekleme. Agresif aktif yoksa bile tahrişte adımları azalt.",
            "priority": 2,
        })
        items.append({
            "time": "Sabah", "category": "Beslenme", "icon": "🫘",
            "action": "Demir Zengin Beslenme",
            "detail": "Adet kanaması demir kaybına neden olur. Kırmızı et, ıspanak, mercimek tüket. "
                     "C vitamini ile birlikte alırsan emilim artar.",
            "priority": 2,
        })

    elif cycle_phase == "follicular":
        # Retinol/AHA asla sabah adımı değil; bilgi notu (ürün listesine ekstra madde eklemez)
        items.append({
            "time": "Sabah", "category": "Zihin", "icon": "🌱",
            "action": "Döngü notu: foliküler faz",
            "detail": "Bu dönemde cilt toleransı genelde daha iyidir. Retinol ve glikolik/salisilik gibi "
                     "maddeleri yalnızca AKŞAM rutinindeki ilgili adımda kullan; sabahda antioksidan + SPF yeterlidir. "
                     "Retinol mü AHA mı: ikisini aynı gece kullanma; bu rutinde zaten tek strateji seçilir.",
            "priority": 2,
        })

    elif cycle_phase == "ovulation":
        items.append({
            "time": "Sabah", "category": "Zihin", "icon": "🌟",
            "action": "Döngü notu: ovülasyon",
            "detail": "Cilt genelde en dengeli dönemindedir. Ekstra sabah/akşam ürün ekleme; mevcut rutin + SPF yeterli.",
            "priority": 3,
        })

    elif cycle_phase == "luteal":
        items.append({
            "time": "Sabah", "category": "Zihin", "icon": "🌙",
            "action": "Döngü notu: luteal faz",
            "detail": "Sebum artabilir. Ekstra sabah ürünü bu planda açılmadı; yağ kontrolü akşam BHA/niasinamid "
                     "adımları üzerinden yürütülür. Sıklık check-in verileriyle güncellenir.",
            "priority": 2,
        })
        if concern == "acne":
            items.append({
                "time": "Akşam", "category": "Bakım", "icon": "⚡",
                "action": "Çinko 30mg + Niasinamid %5 nokta (PMS akne)",
                "detail": "Adet öncesi hormonsal akne bekleniyor. Çinko takviyesi (30mg) + nokta tedavisi ile önceden müdahale.",
                "priority": 1,
            })

    elif cycle_phase == "menopause":
        items.append({
            "time": "Sabah", "category": "Zihin", "icon": "🍂",
            "action": "Döngü notu: menopoz",
            "detail": "Kuruluk ve elastikiyet için rutindeki peptid/seramid içeren nemlendirici adımlarını kullan. "
                     "Ekstra sabah ürünü eklemeden önce mevcut rutini tam uygula.",
            "priority": 1,
        })
        items.append({
            "time": "Sabah", "category": "Beslenme", "icon": "💊",
            "action": "Kalsiyum + D Vitamini + Kolajen",
            "detail": "Menopoz sonrası kemik ve cilt sağlığı için üçlü destek. "
                     "Günlük 1000mg Ca, 2000 IU D3, 10g kolajen peptid.",
            "priority": 2,
        })

    return items


# ══════════════════════════════════════════════════════════════════════
# 12. AKNE BÖLGE ANALİZİ
# ══════════════════════════════════════════════════════════════════════

# Bölge önerileri: action = ne kullanılmalı (etken madde), detail = neden/nasıl (açıklama)
ACNE_ZONE_MAP = {
    "forehead": {
        "label": "Alın",
        "causes": ["Stres", "Sindirim sorunları", "T-bölge yağlanma"],
        "recommendations": [
            {
                "time": "Akşam", "category": "Bakım", "icon": "🎯",
                "action": f"{_skin_salicylic_toner()} — alın & T-bölge hedefli",
                "detail": "Alın aknesi genellikle T-bölge yağlanmasından kaynaklanır. Burun için ayrı BHA ekleme; burunda haftada 2 kez kil maskesi ayrı adımda. Saç ürününün alına taşınmamasına dikkat et.",
                "priority": 2,
                "step_order": 18,
            },
        ],
    },
    "nose": {
        "label": "Burun",
        "causes": ["Yoğun sebum üretimi", "Gözenek genişlemesi"],
        "recommendations": [
            {
                "time": "Akşam", "category": "Bakım", "icon": "🎯",
                "action": "Kaolin kil maskesi — yalnızca burun (haftada 2 kez; aynı akşam önce BHA tonik, sonra buruna ince tabaka)",
                "detail": "İkinci bir salisilik ürünü yok: rutindeki tek BHA ile uyumlu. Haftada 2 kez buruna kaolin; gözenek ve siyah nokta desteği.",
                "priority": 3,
                "step_order": 26,
            },
        ],
    },
    "left_cheek": {
        "label": "Sol Yanak",
        "causes": ["Telefon bakterisi", "Yastık kirliliği"],
        "recommendations": [
            {
                "time": "Akşam", "category": "Yaşam", "icon": "📱",
                "action": "Niasinamid %5 (INCI: Niacinamide) + hijyen — sol yanak",
                "detail": "Sol yanaktaki akne genellikle telefon bakterisinden. Kulaklık kullan, telefonu her gün sil, yastık kılıfını haftada 2 değiştir. Niasinamid anti-enflamatuar destek.",
                "priority": 2,
            },
        ],
    },
    "right_cheek": {
        "label": "Sağ Yanak",
        "causes": ["Telefon bakterisi", "Yastık kirliliği"],
        "recommendations": [
            {
                "time": "Akşam", "category": "Yaşam", "icon": "📱",
                "action": "Niasinamid %5 (INCI: Niacinamide) + hijyen — sağ yanak",
                "detail": "Sağ yanaktaki akne dış etkenlerle bağlantılı. Yastık kılıfını sık değiştir, ellerini yüzüne sürmekten kaçın.",
                "priority": 2,
            },
        ],
    },
    "chin": {
        "label": "Çene / Alt Çene",
        "causes": ["Hormonal dalgalanma", "Adet döngüsü"],
        "recommendations": [
            {
                "time": "Akşam", "category": "Bakım", "icon": "💜",
                "action": "Niasinamid %5-10 (INCI: Niacinamide) + azelaik asit %15-20 (INCI: Azelaic Acid) — çene hormonal akne",
                "detail": "Çene ve alt çene aknesi %70 hormonal kaynaklıdır. Azelaik asit androjen etkisini azaltır. Spearmint çayı (günde 2 fincan) destek olabilir. Şiddetliyse dermatolog önerilir.",
                "priority": 1,
            },
        ],
    },
    "temples": {
        "label": "Şakaklar",
        "causes": ["Saç bakımı maddeleri", "Stres", "Böbrek/safra bağlantısı (geleneksel tıp)"],
        "recommendations": [
            {
                "time": "Akşam", "category": "Yaşam", "icon": "💇",
                "action": "Şakak çevresi: saç ürünü yüze taşınmasın + yastık hijyeni",
                "detail": "Şakak aknesi sıklıkla saç spreyi/jöleden olur. Ek BHA tonik ekleme; akşam rutinindeki tek salisilik adımı tüm T-bölgeye yeter. Saç çizgisini koruyarak uygula.",
                "priority": 3,
            },
        ],
    },
}

# Hafif aknede akşam rutininde zaten BHA var; bu bölgelerde ikinci BHA satırı oluşturma
_ZONES_SKIP_BHA_WHEN_HAFIF_ACNE = frozenset({"forehead"})


def compute_acne_zone_recommendations(acne_zones: list, acne_severity_level: str = "") -> list:
    """Seçilen akne bölgelerine göre hedefli öneriler üretir."""
    items = []
    sev = (acne_severity_level or "").lower()
    for zone_id in acne_zones:
        zone_data = ACNE_ZONE_MAP.get(zone_id)
        if not zone_data:
            continue
        for rec in zone_data["recommendations"]:
            if (
                sev == "hafif"
                and zone_id in _ZONES_SKIP_BHA_WHEN_HAFIF_ACNE
                and rec.get("category") == "Bakım"
                and "salisilik" in (rec.get("action") or "").lower()
            ):
                continue
            items.append(dict(rec))
    return items


# ══════════════════════════════════════════════════════════════════════
# 13. QUERY PLAN BUILDER - Supabase sorgu planı
# ══════════════════════════════════════════════════════════════════════

# Bilgi tabanında metadata.doc_type = pdf_dogal_urun (ingest_pdf_smart DATA/)
NATURAL_KNOWLEDGE_PURPOSE = "Doğal alternatifler (bilgi tabanı)"


def build_query_plan(concern: str, severity: dict) -> list:
    """Supabase'e atılacak hedefli sorguları planlar."""
    plan = []
    knowledge_map = CONCERN_KNOWLEDGE_MAP.get(concern, CONCERN_KNOWLEDGE_MAP["acne"])

    for alt_kat in knowledge_map["primary_alt_kategoriler"]:
        plan.append({
            "kategori": knowledge_map["primary_kategori"],
            "alt_kategori": alt_kat,
            "limit": 10,
            "purpose": f"{knowledge_map['label_tr']} - {alt_kat}",
        })

    for alt_kat in knowledge_map["treatment_alt_kategoriler"]:
        plan.append({
            "kategori": knowledge_map["treatment_kategori"],
            "alt_kategori": alt_kat,
            "limit": 8,
            "purpose": f"Tedavi - {alt_kat}",
        })

    # Doğal ürün / fitokozmetik PDF'leri — rutinde ayrı satır olarak gösterilir (main.py)
    plan.append({
        "doc_type": "pdf_dogal_urun",
        "limit": 8,
        "purpose": NATURAL_KNOWLEDGE_PURPOSE,
    })

    return plan


# ══════════════════════════════════════════════════════════════════════
# 14a. HAFTALIK GÜN ATAMA - "Haftada X gece/kez" olan rutin maddelerine gün atar (sistem)
# ══════════════════════════════════════════════════════════════════════

def _parse_weekly_frequency(detail: str) -> Optional[int]:
    """detail'den haftada kaç kez kullanılacağını çıkarır. Aralık varsa düşük ucu (ör. 3-4 -> 3)."""
    if not detail:
        return None
    detail_lower = detail.lower()
    # gece, kez, kere, defa, gün — örn. "haftada 3 kere", "haftada 2-3 gece"
    m = re.search(
        r"haftada\s*(\d+)\s*(?:[-–]\s*(\d+))?\s*(?:gece|kez|kere|defa|gün)\b",
        detail_lower,
    )
    if m:
        a, b = int(m.group(1)), m.group(2)
        return a if b is None else min(a, int(b))
    return None


def _spread_n_days_across_week(n: int) -> list:
    """
    Tam olarak n farklı gün (0=Pzt .. 6=Paz), mümkün olduğunca haftaya yaygın.
    Örn. n=3 -> [0, 3, 6]; n=2 -> [0, 6].
    """
    n = max(1, min(int(n), 7))
    if n >= 7:
        return list(range(7))
    if n == 1:
        return [0]
    # uçlar Pzt ve Paz dahil; ara değerler eşit aralıkla
    return sorted({min(6, max(0, round(i * 6 / (n - 1)))) for i in range(n)})


def _assign_weekly_days(routine_items: list) -> None:
    """
    'Haftada X ...' geçen rutin maddelerine weekly_days ata (0=Pzt .. 6=Paz).
    X kaç ise tam X güne yayılır (ör. haftada 3 -> 3 gün).
    """
    for item in routine_items:
        # Haftalık gün seçimi sadece cilt bakım adımları için (beslenme/yaşam vb. için değil)
        if item.get("category") not in ("Bakım", "Koruma"):
            continue
        if item.get("time") not in ("Sabah", "Akşam"):
            continue
        detail = item.get("detail") or ""
        n = _parse_weekly_frequency(detail)
        if n is None or n < 1:
            continue
        n = min(n, 7)
        item["weekly_days"] = _spread_n_days_across_week(n)


def _sync_morning_c_with_strong_evening_days(routine_items: list) -> None:
    """
    Haftalık atanmış güçlü gece aktifi (AHA veya retinol/retinal) olan takvim günlerinde
    aynı günün sabahında C vitamini içeren serumu gösterme — kullanıcıya 'ikisini aynı gün üst üste'
    izlenimi vermemek için. Diğer sabahlarda C gösterilir.
    """
    strong_days = set()
    for it in routine_items:
        if it.get("time") != "Akşam" or it.get("category") != "Bakım":
            continue
        wd = it.get("weekly_days")
        if not isinstance(wd, list) or len(wd) == 0 or len(wd) >= 7:
            continue
        act = (it.get("action") or "").lower()
        is_acid = "glikolik" in act or "glycolic" in act or " aha" in act or "laktik asit" in act
        is_retinoid = "retinol" in act or "retinal" in act
        if is_acid or is_retinoid:
            strong_days.update(wd)
    if not strong_days:
        return
    c_morning_days = [d for d in range(7) if d not in strong_days]
    if not c_morning_days:
        return
    for it in routine_items:
        if it.get("time") != "Sabah" or it.get("category") != "Bakım":
            continue
        act = (it.get("action") or "").lower()
        if "c vitamini" not in act:
            continue
        it["weekly_days"] = sorted(c_morning_days)
        if "Takvim:" not in (it.get("detail") or ""):
            it["detail"] = (
                (it.get("detail") or "").rstrip()
                + " Takvim: yalnızca haftalık planda işaretli sabahlarda; güçlü gece adımının olduğu günlerin sabahında gösterilmez."
            )


def _optimize_weekly_days_for_strong_conflicts(routine_items: list) -> None:
    """
    Haftalık plan kalitesi:
    Aynı akşamda birikmemesi gereken güçlü aktif ailelerini farklı günlere yay.
    Hedef: Kullanıcıya "aynı gece retinol + asit" gibi birikim yaşatmadan deterministik bir takvim üretmek.
    """
    conflict_pairs = {
        ("retinol", "aha"),
        ("retinol", "bha"),
        ("retinol", "benzoyl"),
        ("retinol", "vitamin_c"),
        ("aha", "vitamin_c"),
    }

    def _has_conflict(fam: set, day_fam: set) -> bool:
        if not fam or not day_fam:
            return False
        for a in fam:
            for b in day_fam:
                if a == b:
                    continue
                if (a, b) in conflict_pairs or (b, a) in conflict_pairs:
                    return True
        return False

    def _conflict_count(fam: set, day_fam: set) -> int:
        if not fam or not day_fam:
            return 0
        c = 0
        for a in fam:
            for b in day_fam:
                if a == b:
                    continue
                if (a, b) in conflict_pairs or (b, a) in conflict_pairs:
                    c += 1
        return c

    # Sadece haftalık atanmış akşam "Bakım" adımlarını optimize et
    evening_weekly = []
    for it in routine_items or []:
        if it.get("time") != "Akşam" or it.get("category") != "Bakım":
            continue
        wd = it.get("weekly_days")
        if not isinstance(wd, list) or len(wd) == 0 or len(wd) >= 7:
            continue
        fam = _strong_actives_families_for_item(it)
        # güçlü ailesi yoksa dokunma
        if not fam:
            continue
        evening_weekly.append((it, fam, len(wd)))

    if len(evening_weekly) <= 1:
        return

    # Deterministik sıra: daha kritik (düşük priority) önce yerleşsin
    def _sort_key(x):
        it, fam, n = x
        return (it.get("priority", 5), it.get("step_order", 50), it.get("action", ""))

    evening_weekly.sort(key=_sort_key)

    day_families: dict[int, set] = {d: set() for d in range(7)}
    day_load: dict[int, int] = {d: 0 for d in range(7)}

    def _circ_dist(a: int, b: int) -> int:
        d = abs(int(a) - int(b))
        return min(d, 7 - d)

    for it, fam, n in evening_weekly:
        chosen = []
        for _ in range(n):
            best = None
            for d in range(7):
                if d in chosen:
                    continue
                # yayılım: seçilmiş günlerle aralık mümkün olsun
                spacing_pen = 0
                if chosen:
                    # dairesel (Paz-Pzt komşu) mesafe ile ardışık günleri daha fazla cezalandır
                    min_dist = min(_circ_dist(d, x) for x in chosen)
                    # 0: aynı gün (zaten engelli), 1: ardışık (yüksek ceza), 2: orta, 3+: ceza yok
                    spacing_pen = 0 if min_dist >= 3 else (3 - min_dist) * 3

                cc = _conflict_count(fam, day_families[d])
                score = (cc * 100) + (day_load[d] * 2) + spacing_pen
                cand = (score, d)
                if best is None or cand < best:
                    best = cand

            if best is None:
                break
            _, d_best = best
            chosen.append(d_best)
            day_load[d_best] += 1
            day_families[d_best].update(fam)

        if chosen:
            it["weekly_days"] = sorted(chosen)


def _ensure_weekly_days_for_strong_evening_actives(routine_items: list) -> None:
    """
    Bazı güçlü akşam aktifleri (retinol/BHA/AHA/BP gibi) metinde 'haftada X' yazmasa bile
    haftalık takvim gerektirir. Aksi halde aynı gece birikim riski artar ve optimizer çalışamaz.

    Basit kural:
    - starter ramp: haftada 2
    - standard: haftada 3
    (existing weekly_days varsa dokunma)
    """
    strong = {"retinol", "bha", "aha", "benzoyl"}
    for it in routine_items or []:
        if it.get("time") != "Akşam" or it.get("category") != "Bakım":
            continue
        wd = it.get("weekly_days")
        if isinstance(wd, list) and len(wd) > 0:
            continue
        fam = _strong_actives_families_for_item(it)
        if not (fam & strong):
            continue
        stage = (it.get("ramp_stage") or "").lower()
        n = 2 if stage == "starter" else 3
        it["weekly_days"] = _spread_n_days_across_week(n)


def _split_arrow_chained_evening_steps(routine_items: list) -> list:
    """
    Bazı akşam "Bakım" satırları action içinde iki adımı zincirler: "X → ardından Y".
    Bu durumda tek gecede birikim (özellikle güçlü aktif + güçlü aktif) riski artar ve haftalık plan netleşmez.

    Basit/geriye-uyumlu yaklaşım:
    - action içinde "→" varsa iki item'e böl
    - weekly_days varsa günleri ikiye paylaştır (interleave). Tek günse ikinci adımı farklı güne kaydır.
    """
    out = []
    for it in routine_items or []:
        if it.get("time") == "Akşam" and it.get("category") == "Bakım":
            action = it.get("action") or ""
            if "→" in action:
                left, right = action.split("→", 1)
                left = left.strip()
                right = right.strip()
                # sağ parçada "ardından" gibi ön ekleri temizle
                right = re.sub(r"^(ardından|sonra)\s+", "", right, flags=re.IGNORECASE).strip()
                if left and right:
                    base = dict(it)
                    a = dict(base)
                    b = dict(base)
                    a["action"] = left
                    # sağ adım: "ardından/alternatif geceler" gibi sözleri at
                    right2 = re.sub(
                        r"^(?:ardından|sonra)\s*(?:/|\-|–)?\s*(?:alternatif\s+geceler)?\s*",
                        "",
                        right,
                        flags=re.IGNORECASE,
                    ).strip()
                    right2 = re.sub(r"^alternatif\s+geceler\s*", "", right2, flags=re.IGNORECASE).strip()
                    b["action"] = right2 or right
                    # split sonrası detail sadeleştir: "aynı akşam/sırayla" gibi ifadeleri temizle, ayrı gecelere yayıldığını belirt
                    base_detail = (base.get("detail") or "").strip()
                    if base_detail:
                        cleaned = re.sub(
                            r"(?i)\b(sırayla|ardından|sonra|tek\s+formül|tek\s+blok|aynı\s+akşam)\b[^.]*\.?\s*",
                            "",
                            base_detail,
                        ).strip()
                        note = "Bu adım diğer güçlü adımlarla çakışmasın diye farklı gecelere dağıtıldı."

                        # split sonrası: yanlış aktif ismini taşıyan cümleleri kırp (en basit güvenli filtre)
                        a_clean = cleaned
                        b_clean = cleaned
                        if "benzoil" in (a["action"] or "").lower():
                            a_clean = re.sub(r"(?i)[^.]*azelaik[^.]*\.\s*", "", a_clean).strip()
                        if "azelaik" in (a["action"] or "").lower():
                            a_clean = re.sub(r"(?i)[^.]*benzoil[^.]*\.\s*", "", a_clean).strip()
                        if "benzoil" in (b["action"] or "").lower():
                            b_clean = re.sub(r"(?i)[^.]*azelaik[^.]*\.\s*", "", b_clean).strip()
                        if "azelaik" in (b["action"] or "").lower():
                            b_clean = re.sub(r"(?i)[^.]*benzoil[^.]*\.\s*", "", b_clean).strip()

                        a["detail"] = sanitize_routine_detail_system_voice((a_clean + " " + note).strip())
                        b["detail"] = sanitize_routine_detail_system_voice((b_clean + " " + note).strip())
                    # active_families: detail tüm zinciri taşıyabilir; burada action bazlı aileyi sabitle
                    try:
                        a.setdefault("active_families", sorted(_strong_actives_families_for_item({"action": a["action"], "detail": ""})))
                        b.setdefault("active_families", sorted(_strong_actives_families_for_item({"action": b["action"], "detail": ""})))
                    except Exception:
                        pass
                    # step order: ikinci adım biraz sonra gelsin
                    so = base.get("step_order", 20)
                    a["step_order"] = so
                    b["step_order"] = so + 1

                    wd = base.get("weekly_days")
                    if isinstance(wd, list) and wd:
                        wd_sorted = sorted({int(x) for x in wd if isinstance(x, int) and 0 <= x <= 6})
                        if len(wd_sorted) >= 2:
                            a["weekly_days"] = wd_sorted[::2]
                            b["weekly_days"] = wd_sorted[1::2]
                        else:
                            d0 = wd_sorted[0]
                            a["weekly_days"] = [d0]
                            b["weekly_days"] = [int((d0 + 3) % 7)]
                    out.extend([a, b])
                    continue
        out.append(it)
    return out


def _split_plus_combined_conflicting_actives(routine_items: list) -> list:
    """
    Action içinde '+' ile birleştirilmiş iki güçlü aktif aynı gecede birikiyorsa (retinol+asit/BP vb.),
    tek satırı iki satıra bölüp farklı gecelere yay.

    Not: Niasinamid + azelaik gibi genelde birlikte tolere edilebilen kombinasyonlara dokunma.
    """
    conflict_pairs = {
        ("retinol", "aha"),
        ("retinol", "bha"),
        ("retinol", "benzoyl"),
        ("retinol", "vitamin_c"),
        ("aha", "vitamin_c"),
    }

    def _has_conflicting_pair(fam: set) -> bool:
        for a, b in conflict_pairs:
            if a in fam and b in fam:
                return True
        return False

    def _keywords_for_families(fams: set) -> dict:
        """
        Split sonrası yanlış anlatımı kırpmak için aile->anahtar kelime.
        """
        m = {
            "retinol": ["retinol", "retinal"],
            "aha": ["aha", "glikolik", "glycolic", "laktik", "lactic"],
            "bha": ["bha", "salisilik", "salicylic"],
            "benzoyl": ["benzoil", "benzoyl"],
            "vitamin_c": ["c vitamini", "vitamin c", "askorbik", "ascorbic"],
            "azelaic": ["azelaik", "azelaic"],
            "niacinamide": ["niasinamid", "niacinamide"],
            "pigment": ["arbutin", "traneks", "tranex", "kojik", "hidrokinon"],
        }
        out = {}
        for f in fams or []:
            if f in m:
                out[f] = m[f]
        return out

    def _strip_sentences_mentioning(text: str, keywords: list[str]) -> str:
        if not text or not keywords:
            return text
        out = str(text)
        for kw in keywords:
            out = re.sub(rf"(?i)[^.]*{re.escape(kw)}[^.]*\.\s*", "", out).strip()
        return out

    out = []
    for it in routine_items or []:
        if it.get("time") == "Akşam" and it.get("category") == "Bakım":
            action = it.get("action") or ""
            if " + " in action:
                fam = _strong_actives_families_for_item(it)
                # Katman azaltma: 3+ aktif aile veya çatışma çifti varsa böl
                if fam and (_has_conflicting_pair(fam) or len(fam) >= 3):
                    left, right = action.split(" + ", 1)
                    left = left.strip()
                    right = right.strip()
                    # sağ başlık küçük harfle başlıyorsa düzelt (UI tutarlılığı)
                    if right and right[0].islower():
                        right = right[0].upper() + right[1:]
                    if left and right:
                        base = dict(it)
                        a = dict(base)
                        b = dict(base)
                        a["action"] = left
                        b["action"] = right

                        so = base.get("step_order", 20)
                        a["step_order"] = so
                        b["step_order"] = so + 1

                        wd = base.get("weekly_days")
                        if isinstance(wd, list) and wd:
                            wd_sorted = sorted({int(x) for x in wd if isinstance(x, int) and 0 <= x <= 6})
                            if len(wd_sorted) >= 2:
                                a["weekly_days"] = wd_sorted[::2]
                                b["weekly_days"] = wd_sorted[1::2]
                            else:
                                d0 = wd_sorted[0]
                                a["weekly_days"] = [d0]
                                b["weekly_days"] = [int((d0 + 3) % 7)]

                        try:
                            a["active_families"] = sorted(
                                _strong_actives_families_for_item({"action": a["action"], "detail": ""})
                            )
                            b["active_families"] = sorted(
                                _strong_actives_families_for_item({"action": b["action"], "detail": ""})
                            )
                        except Exception:
                            pass

                        base_detail = (base.get("detail") or "").strip()
                        if base_detail:
                            cleaned = re.sub(r"(?i)\b(tek\s+blok|aynı\s+gece|aynı\s+akşam|sırayla|ardından|sonra)\b[^.]*\.?\s*", "", base_detail).strip()
                            note = "Bu adımlar katman/birikim yapmaması için farklı gecelere dağıtıldı."
                            kw_map = _keywords_for_families(fam)
                            # a'nın detayından b'ye ait anahtarları, b'nin detayından a'ya ait anahtarları kırp
                            a_fam = set(a.get("active_families") or [])
                            b_fam = set(b.get("active_families") or [])
                            a_strip = []
                            b_strip = []
                            for f, kws in kw_map.items():
                                if f in b_fam and f not in a_fam:
                                    a_strip.extend(kws)
                                if f in a_fam and f not in b_fam:
                                    b_strip.extend(kws)
                            a_clean = _strip_sentences_mentioning(cleaned, a_strip)
                            b_clean = _strip_sentences_mentioning(cleaned, b_strip)
                            a["detail"] = sanitize_routine_detail_system_voice((a_clean + " " + note).strip())
                            b["detail"] = sanitize_routine_detail_system_voice((b_clean + " " + note).strip())

                        out.extend([a, b])
                        continue
        out.append(it)
    return out


# ══════════════════════════════════════════════════════════════════════
# 14. DEDUPLICATE + LIMIT - Fazla öneriyi kes, kişiye özel seç
# ══════════════════════════════════════════════════════════════════════

def _dedupe_duplicate_azelaik_bakim(items: list) -> list:
    """Aynı rutinde iki kez Azelaik Asit listelenmesin (bölge + akşam tekrarı)."""
    az_found = False
    out = []
    for it in items:
        if it.get("category") != "Bakım":
            out.append(it)
            continue
        act = (it.get("action") or "").lower()
        if "azelaik" in act:
            if az_found:
                continue
            az_found = True
        out.append(it)
    return out


def _deduplicate_and_limit(items: list) -> list:
    """
    Aşırı öneriyi önle:
    - Bakım: sabah/akşam en fazla 5 slot (temizlik + aktif(ler) + nemlendirici + SPF vb.; sıra korunur)
    - Yaşamsal (Zihin/Yaşam/Beslenme): toplam max 3
    - Aynı action tekrarlarını kaldır
    """
    seen_actions = set()
    unique = []
    for item in items:
        action_key = item.get("action", "").lower()[:30]
        if action_key not in seen_actions:
            seen_actions.add(action_key)
            unique.append(item)

    skincare_morning = [i for i in unique if i["time"] == "Sabah" and i["category"] in ("Bakım", "Koruma")]
    skincare_evening = [i for i in unique if i["time"] == "Akşam" and i["category"] in ("Bakım", "Koruma")]
    lifestyle = [i for i in unique if i["category"] in ("Zihin", "Yaşam", "Beslenme")]
    other = [i for i in unique if i not in skincare_morning and i not in skincare_evening and i not in lifestyle]

    # Sabah: eksik step_order → temizlik 10, serum 20, nem 30, SPF 40
    for item in skincare_morning:
        if "step_order" not in item:
            al = (item.get("action") or "").lower()
            if any(w in al for w in ["temizl", "yıka", "misel"]):
                item["step_order"] = 10
            elif "spf" in al or "güneş" in al or "gunes" in al:
                item["step_order"] = 40
            elif "nemlendirici" in al:
                item["step_order"] = 30
            else:
                item["step_order"] = 20

    # Akşam Bakım öğelerine otomatik step_order ata (eksikse); "Gece:" ile başlayan = nemlendirici katmanı
    for item in skincare_evening:
        if "step_order" not in item:
            action_lower = (item.get("action") or "").lower()
            if any(w in action_lower for w in ["temizl", "yıka", "misel", "çift"]):
                item["step_order"] = 10
            elif action_lower.startswith("gece:"):
                item["step_order"] = 30
            elif any(w in action_lower for w in ["nemlendirici", "bariyer kilidi", "onarım krem", "uyku mask", "maskesi"]):
                item["step_order"] = 35 if "mask" in action_lower else 30
            elif "vazelin" in action_lower:
                item["step_order"] = 35
            else:
                item["step_order"] = 20

    skincare_morning.sort(key=lambda x: (x.get("step_order", 50), x.get("priority", 5)))
    skincare_evening.sort(key=lambda x: (x.get("step_order", 50), x.get("priority", 5)))
    lifestyle.sort(key=lambda x: x.get("priority", 5))

    # Akşam: temizlik + 1–2 aktif + nemlendirici/maske için en az 4–5 slot (sıra bozulmasın diye)
    result = skincare_morning[:5] + skincare_evening[:5] + lifestyle[:3] + other[:2]
    return result


# ══════════════════════════════════════════════════════════════════════
# 14b. ANALİZ NETLEŞTİRİCİ İŞARETLER (UI special_flags → rutin + özet)
# ══════════════════════════════════════════════════════════════════════

_SPECIAL_FLAG_KEYS = (
    "frown_lines",
    "smile_lines",
    "eye_crows_feet",
    "redness_diffuse",
    "redness_acne_marks",
    "cold_sensitive",
    "stings_with_products",
)


def _normalize_special_flags(raw: Optional[dict]) -> dict:
    """İstemciden gelen dict'i güvenli bool haritaya çevirir."""
    if not raw or not isinstance(raw, dict):
        return {}
    out = {}
    for k in _SPECIAL_FLAG_KEYS:
        v = raw.get(k)
        if v is True or v == 1 or (isinstance(v, str) and v.lower() in ("true", "1", "yes")):
            out[k] = True
    return out


def build_special_flags_routine_items(
    flags: dict,
    *,
    concern: str,
    temperature: float,
) -> list:
    """
    Kullanıcının işaretlediği özel durumlar için 1–2 adet Yaşam satırı (bilgilendirme + yönlendirme).
    Bakım satırı eklemez; finalize içindeki etken-madde mantığına girmez.
    """
    if not flags:
        return []
    items = []

    line_bits = []
    if flags.get("frown_lines"):
        line_bits.append("kaş çatınca belirginleşen alın/kaş arası çizgiler")
    if flags.get("eye_crows_feet"):
        line_bits.append("gülünce göz kenarında belirginleşen ince çizgiler")
    if flags.get("smile_lines"):
        line_bits.append("gülünce burun–ağız çevresinde belirginleşen çizgiler")

    if line_bits:
        detail = (
            "İşaretlediğin bölgeler: " + "; ".join(line_bits) + ". "
            "Bu çizgiler çoğu zaman mimik + zamanla birlikte oluşur; tıbbi işlem önerisi değildir. "
            "Günlük geniş spektrum güneş koruma ve düzenli nem/bariyer katmanı, çizgilerin daha hızlı belirginleşmesini "
            "yavaşlatmaya yardımcı olabilir."
        )
        usage = (
            "Yüz kaslarını sürekli germeden (özellikle kaş çatmadan) güne başla; akşam rutininde nem/bariyeri atlama. "
            "Yeni güçlü aktifleri aynı haftada üst üste deneme."
        )
        items.append(
            {
                "time": "Günlük",
                "category": "Yaşam",
                "icon": "✨",
                "action": "Çizgi bölgeleri — kişisel not",
                "detail": detail,
                "usage": usage,
                "priority": 3,
                "step_order": 96,
            }
        )

    sens_bits = []
    if flags.get("redness_diffuse"):
        sens_bits.append("yüzde daha yaygın (difüz) kızarıklık / ısınma hissi")
    if flags.get("redness_acne_marks"):
        sens_bits.append("sivilce veya leke sonrası kırmızılık / iz görünümü")
    if flags.get("cold_sensitive"):
        sens_bits.append("soğuk hava veya rüzgârda hassasiyetin artması")
    if flags.get("stings_with_products"):
        sens_bits.append("ürün sürünce batma, yanma veya ani kızarma")

    if sens_bits:
        detail = "Senin tarifin: " + "; ".join(sens_bits) + ". "
        if flags.get("redness_acne_marks") and concern == "sensitivity":
            detail += (
                "Eğer asıl şikâyetin sivilce sonrası kırmızılık ve lekeler ise, bazen ana endişeyi "
                "'Akne' seçmek iz ve renk eşitliği yönetimini daha netleştirir (bu planda hassasiyet reaktivitesi de dikkate alındı). "
            )
        if flags.get("redness_diffuse") and concern == "acne":
            detail += (
                "Yaygın kızarıklık sivilce lekesinden farklı olabilir; kızarıklık baskınsa ve sivilce azsa "
                "'Hassasiyet / Kızarıklık' endişesiyle ikinci bir analiz değerlendirilebilir. "
            )
        if flags.get("stings_with_products"):
            detail += (
                "Batma/yanma varsa yeni ürünleri tek tek ekle; mümkünse 24–48 saat küçük bölge (kulak arkası veya yanak) yama testi yap. "
                "Aynı gece birden fazla güçlü aktif üst üste kullanmaktan kaçın. "
            )
        if flags.get("cold_sensitive"):
            cold_hint = (
                f"Bugünkü sıcaklık yaklaşık {temperature:.0f}°C; soğuk tetikliyorsa bariyer nemini sabit tut, "
                "rüzgâra maruz kaldıktan sonra ani sıcak suyla yüzü yıkamaktan kaçın."
                if temperature is not None
                else "Soğuk tetikliyorsa bariyer nemini sabit tut, rüzgâra maruz kaldıktan sonra ani sıcak suyla yüzü yıkamaktan kaçın."
            )
            detail += cold_hint

        items.append(
            {
                "time": "Günlük",
                "category": "Yaşam",
                "icon": "🌸",
                "action": "Hassasiyet / kızarıklık — netleştirme notu",
                "detail": detail.strip(),
                "usage": (
                    "Bu madde cilt tipinden (yağlı/kuru/karma) bağımsız bir reaktivite tarifidir; "
                    "normal ciltte bile soğuk veya ürünle tetiklenen hassasiyet görülebilir."
                ),
                "priority": 2,
                "step_order": 95,
            }
        )

    return items


def _special_flags_context_tr(flags: dict) -> str:
    if not flags:
        return ""
    parts = []
    if flags.get("frown_lines"):
        parts.append("alın/kaş çatma çizgisi")
    if flags.get("eye_crows_feet"):
        parts.append("göz kenarı çizgileri")
    if flags.get("smile_lines"):
        parts.append("gülme çizgileri")
    if flags.get("redness_diffuse"):
        parts.append("difüz kızarıklık")
    if flags.get("redness_acne_marks"):
        parts.append("sivilce sonrası kırmızılık")
    if flags.get("cold_sensitive"):
        parts.append("soğukta hassasiyet")
    if flags.get("stings_with_products"):
        parts.append("ürünle batma/yanma")
    return " Kullanıcı ek işaretleri: " + ", ".join(parts) + "."


# ══════════════════════════════════════════════════════════════════════
# 15. MASTER ORCHESTRATOR - Tüm dalları birleştirir
# ══════════════════════════════════════════════════════════════════════

def run_flow(
    concern: str,
    severity_score: int,
    age: int,
    gender: str,
    skin_type_key: str,
    stress_score: int,
    sleep_hours: float,
    water_intake: float,
    smoking: bool,
    alcohol: bool,
    uv_index: float,
    humidity: float,
    temperature: float,
    smoking_per_day: int = 0,
    smoking_years: int = 0,
    alcohol_frequency: int = 0,
    alcohol_amount: int = 1,
    is_pregnant: bool = False,
    cycle_phase: str = "",
    acne_zones: list = None,
    actives_experience: str = "occasional",
    actives_unused: Optional[list] = None,
    actives_tolerance: Optional[dict] = None,
    makeup_frequency: int = 0,
    makeup_removal: str = "cleanser",
    special_flags: Optional[dict] = None,
) -> dict:
    """
    Ana akış fonksiyonu. Tüm dalları çalıştırır, sıfır token harcar.

    v4 Yenilikler:
    - Hamilelik güvenlik filtresi
    - Hormonal döngü modifiyeleri
    - Akne bölge analizi

    Returns:
        {
            "concern_map": dict,
            "severity": dict,
            "age_group": dict,
            "skin_type": dict,
            "query_plan": list,
            "routine_items": list,
            "context_summary": str,
            "hormonal_info": dict,
            "acne_zone_info": list,
        }
    """
    if acne_zones is None:
        acne_zones = []

    special_flags_norm = _normalize_special_flags(special_flags)

    # 1. Concern route
    concern_map = CONCERN_KNOWLEDGE_MAP.get(concern, CONCERN_KNOWLEDGE_MAP["acne"])

    # 2. Age group
    age_group = classify_age_group(age)

    # 3. Skin type (kopya — niasinamid % düzeltmesi global şablonu kirletmesin)
    skin_type = dict(SKIN_TYPE_PROFILES.get(skin_type_key, SKIN_TYPE_PROFILES["normal"]))

    # 4. Severity classify (age-aware)
    severity = classify_severity(severity_score, concern, age_group)

    # 5. Query plan for Supabase
    query_plan = build_query_plan(concern, severity)

    # 5.5 Risk skoru hesapla (INGREDIENT_DB entegrasyonu)
    from ingredient_db import compute_risk_score as _compute_risk
    risk_info = _compute_risk(
        stress=stress_score,
        water_intake=water_intake,
        humidity=humidity,
        sleep_hours=sleep_hours,
        makeup_frequency=makeup_frequency,
        makeup_removal=makeup_removal,
        cycle_phase=cycle_phase or "",
        gender=gender or "",
    )
    risk_level = risk_info["level"]

    # Kullanıcıya tek satırlık durum özeti (düşük risk dahil her durumda görünür)
    rl_tr = {
        "normal": "Normal",
        "moderate": "Orta",
        "high": "Yüksek",
        "crisis": "Kriz",
    }.get(risk_level, str(risk_level))
    risk_summary_item = {
        "time": "Günlük",
        "category": "Yaşam",
        "icon": "📍",
        "action": f"Günlük denge: {rl_tr}",
        "detail": (risk_info.get("detail") or "").strip(),
        "priority": 0,
        "step_order": 0,
    }

    merged_actives_tol = merge_actives_tolerance(actives_tolerance, actives_unused)
    _na_pct = _niacinamide_start_pct(
        _normalize_actives_experience(actives_experience), merged_actives_tol
    )
    _strength_stage = _active_strength_stage(
        _normalize_actives_experience(actives_experience), merged_actives_tol, risk_level
    )
    # UI netleştirme: ürünle batma/yanma işaretliyse daha yumuşak başlangıç (yüzde + sıklık)
    if special_flags_norm.get("stings_with_products"):
        _strength_stage = "starter"
    _apply_niacinamide_pct_to_skin_profile(skin_type, _na_pct)
    personalization = compute_personalization_profile(
        risk_info, severity_score, skin_type_key, merged_actives_tol, concern
    )

    # 6. Base skincare routine (concern + severity + age + skin_type + kişisel puan)
    routine_items = get_base_skincare_routine(
        concern, severity, age_group, skin_type,
        actives_experience=actives_experience,
        personalization=personalization,
        makeup_frequency=makeup_frequency,
        makeup_removal=makeup_removal,
    )

    # Ingredient-level plan (no product recommendations)
    try:
        from active_plan import build_active_plan

        active_plan = build_active_plan(
            concern=concern,
            skin_type_key=skin_type_key,
            age_group=age_group,
            severity=severity,
            risk_info=risk_info,
            strength_stage=_strength_stage,
            niacinamide_start_pct=_na_pct,
            merged_actives_tol=merged_actives_tol,
            is_pregnant=(is_pregnant and gender == "female"),
            stings_with_products=bool(special_flags_norm.get("stings_with_products")),
        )
    except Exception:
        active_plan = []

    # 7. Lifestyle branches (stress, sleep, water, smoking, alcohol)
    lifestyle_items = compute_lifestyle_branches(
        stress_score, sleep_hours, water_intake, smoking, alcohol, age, concern,
        smoking_per_day=smoking_per_day,
        smoking_years=smoking_years,
        alcohol_frequency=alcohol_frequency,
        alcohol_amount=alcohol_amount,
    )
    routine_items.extend(lifestyle_items)
    routine_items.append(risk_summary_item)

    # 7b. Zihin–beden protokolleri (su, nefes, uyku; endişeye göre antioksidan besin notu)
    routine_items.extend(
        build_mind_body_protocol_items(
            water_intake, sleep_hours, stress_score, risk_level, concern
        )
    )

    # 8. Holistic recommendations (nutrition, exercise, supplements)
    holistic_items = compute_holistic_recommendations(
        concern, age, severity["level"], water_intake, sleep_hours, smoking
    )
    routine_items.extend(holistic_items)

    # 9. Environment branches
    env_items = compute_environment_branches(uv_index, humidity, temperature, skin_type)
    routine_items.extend(env_items)

    # 10. Hormonal modifiers (kadınlar için)
    hormonal_info = {}
    if gender == "female" and cycle_phase:
        hormonal_items = compute_hormonal_modifiers(cycle_phase, concern)
        routine_items.extend(hormonal_items)
        hormonal_info = {
            "cycle_phase": cycle_phase,
            "is_pregnant": is_pregnant,
            "items_added": len(hormonal_items),
        }

    # 11. Acne zone analysis
    acne_zone_info = []
    if concern == "acne" and acne_zones:
        zone_items = compute_acne_zone_recommendations(acne_zones, severity.get("level", ""))
        routine_items.extend(zone_items)
        acne_zone_info = [
            {"zone": z, "label": ACNE_ZONE_MAP.get(z, {}).get("label", z)}
            for z in acne_zones
        ]

    _apply_niacinamide_pct_to_routine_items(routine_items, _na_pct)
    _apply_active_strength_ramp(routine_items, _strength_stage)

    # 12. Uyumluluk matrisi arka planda kalır; kullanıcıya "çakışan X+Y" satırı eklenmez (motor zaten dağıtır)
    # check_ingredient_compatibility(routine_items) — istenirse log/test için kullanılır

    # 13. Pregnancy safety filter (MUST be last - overrides unsafe ingredients)
    if is_pregnant and gender == "female":
        routine_items = apply_pregnancy_safety(routine_items)

    # 14. Aynı etken tekrarını azalt, sonra DEDUPLICATE + LIMIT
    routine_items = _dedupe_duplicate_azelaik_bakim(routine_items)
    routine_items = _deduplicate_and_limit(routine_items)

    routine_items = _remove_routine_items_by_avoided_families(
        routine_items, avoided_families_from_tolerance(merged_actives_tol)
    )

    # 15. SORT: doğru uygulama sırası
    # Sabah: temizlik(10) → aktif serum(20) → nemlendirici(30) → SPF(40)
    # Akşam: temizlik(10) → aktif tedavi(20) → nemlendirici(30)
    # Yaşamsal: priority sırasıyla
    time_order = {"Sabah": 0, "Akşam": 1}
    routine_items.sort(key=lambda x: (
        time_order.get(x["time"], 2),
        x.get("step_order", 50),
        x.get("priority", 5),
    ))

    from skincare_absolute_rules import enforce_absolute_rules_on_routine, get_absolute_rules_catalog

    routine_items, absolute_enforcement_report = enforce_absolute_rules_on_routine(routine_items)

    routine_items.extend(
        build_special_flags_routine_items(
            special_flags_norm,
            concern=concern,
            temperature=float(temperature or 0),
        )
    )
    routine_items.sort(
        key=lambda x: (
            time_order.get(x["time"], 2),
            x.get("step_order", 50),
            x.get("priority", 5),
        )
    )

    # 15x. Tüm Bakım/Koruma satırlarına kullanıcı dilinde gerekçe + (varsa) yaşam riski notu
    routine_items = finalize_user_routine_item_details(
        routine_items,
        risk_level=risk_level,
        concern=concern,
        severity_level=severity["level"],
        skin_label_tr=skin_type["label_tr"],
        age_label_tr=age_group["label_tr"],
    )

    # 15a. Aktif deneyimi + tolerans: sıklık / alıştırma metinleri (weekly_days atamasından önce)
    actives_experience_for_ramp = actives_experience
    if special_flags_norm.get("stings_with_products"):
        actives_experience_for_ramp = "none"
    _apply_actives_experience_ramp(
        routine_items, actives_experience_for_ramp,
        actives_unused=None,
        actives_tolerance=merged_actives_tol,
    )

    # 15b. Haftalık kullanım: hangi günler? (sistem atar; check-in/geri dönüşe göre sonra güncellenebilir)
    _assign_weekly_days(routine_items)
    # Ürünle batma/yanma: güçlü aktiflerin haftalık gün sayısını daha konservatif tut
    if special_flags_norm.get("stings_with_products"):
        for it in routine_items:
            if it.get("category") != "Bakım":
                continue
            fam = _strong_actives_families_for_item(it)
            if not fam:
                continue
            wd = it.get("weekly_days")
            if isinstance(wd, list) and len(wd) > 3:
                it["weekly_days"] = _spread_n_days_across_week(3)
    _sync_morning_c_with_strong_evening_days(routine_items)
    _ensure_weekly_days_for_strong_evening_actives(routine_items)
    routine_items = _split_arrow_chained_evening_steps(routine_items)
    # '+' zincirleri: çatışma veya 3+ aktif aile varsa katman azalt (gerekirse 2 tur)
    for _ in range(2):
        routine_items = _split_plus_combined_conflicting_actives(routine_items)
    _optimize_weekly_days_for_strong_conflicts(routine_items)
    attach_structured_fields_to_routine_items(routine_items)

    # 16. Build context summary for AI
    mk_labels = {0: "yok", 1: "seyrek", 3: "haftada birkaç", 5: "günlük"}
    makeup_ctx = (
        f" Makyaj sıklığı: {mk_labels.get(int(makeup_frequency or 0), str(makeup_frequency))}, "
        f"temizleme: {makeup_removal}."
    )

    hormonal_ctx = ""
    if gender == "female":
        if is_pregnant:
            hormonal_ctx = " HAMİLE - tüm maddeler güvenlik filtresinden geçti."
        elif cycle_phase:
            phase_labels = {
                "menstrual": "adet dönemi", "follicular": "foliküler faz",
                "ovulation": "ovülasyon", "luteal": "luteal faz",
                "menopause": "menopoz", "unknown": "bilinmiyor",
            }
            hormonal_ctx = f" Döngü fazı: {phase_labels.get(cycle_phase, cycle_phase)}."
        else:
            hormonal_ctx = (
                " Hormonal: son adet / döngü fazı bu planda yok; "
                "luteal veya adet dönemi özel önerileri açılmadı."
            )

    zone_ctx = ""
    if acne_zones:
        zone_labels = [ACNE_ZONE_MAP.get(z, {}).get("label", z) for z in acne_zones]
        zone_ctx = f" Akne bölgeleri: {', '.join(zone_labels)}."

    exp_lbl = {"none": "aktif deneyimi yok/ilk kez", "occasional": "ara sıra aktif kullanmış", "regular": "düzenli aktif kullanmış"}.get(
        _normalize_actives_experience(actives_experience), "bilinmiyor"
    )
    tol_ctx = ""
    if merged_actives_tol:
        bad = [k for k, v in merged_actives_tol.items() if v == "bad"]
        nev = [k for k, v in merged_actives_tol.items() if v == "never"]
        mild = [k for k, v in merged_actives_tol.items() if v == "mild"]
        parts = []
        if bad:
            parts.append(f"ciddi tepki bildirilen (rutinden çıkarıldı): {', '.join(bad)}")
        if nev:
            parts.append(f"hiç kullanılmamış (düşük sıklık): {', '.join(nev)}")
        if mild:
            parts.append(f"hafif tepki / dikkat (seyrekleştirildi): {', '.join(mild)}")
        if parts:
            tol_ctx = " Aktif tolerans: " + "; ".join(parts) + "."
    pers_ctx = (
        f" Kişiselleştirme: {personalization['label_tr']} "
        f"(katman {personalization['tier']}/3, özet skor {personalization['composite_score']}/100; "
        f"yaşam riski {personalization['risk_score']} puan → {personalization['risk_level']})."
    )
    special_ctx = _special_flags_context_tr(special_flags_norm)

    context_summary = (
        f"Kullanıcı: {age} yaşında ({age_group['label_tr']}), {gender}, "
        f"cilt tipi: {skin_type['label_tr']}, "
        f"ana sorun: {concern_map['label_tr']}, "
        f"şiddet: {severity['label_tr']} ({severity_score}/10). "
        f"Aktif geçmişi: {exp_lbl}.{tol_ctx}{pers_ctx} "
        f"Stres: {stress_score}/16, uyku: {sleep_hours}s, su: {water_intake}L.{makeup_ctx}"
        f"Sigara: {'evet (' + str(smoking_per_day) + '/gün, ' + str(smoking_years) + ' yıl)' if smoking_per_day > 0 else 'hayır'}, "
        f"alkol: {'evet (haftalık ~' + str(alcohol_frequency * alcohol_amount) + ' kadeh)' if alcohol_frequency > 0 else 'hayır'}. "
        f"Hava: {temperature}°C, UV {uv_index}, nem %{humidity}."
        f"{hormonal_ctx}{zone_ctx}{special_ctx} "
        f"Önerilen ajanlar: {', '.join(severity['preferred_agents'][:4])}. "
        f"Kaçınılacaklar: {', '.join(severity['avoid'][:3]) if severity['avoid'] else 'yok'}."
    )

    care_guide = get_routine_care_guide(
        is_pregnant=(is_pregnant and gender == "female"),
    )

    return {
        "concern_map": concern_map,
        "severity": severity,
        "age_group": age_group,
        "skin_type": skin_type,
        "query_plan": query_plan,
        "routine_items": routine_items,
        "context_summary": context_summary,
        "hormonal_info": hormonal_info,
        "acne_zone_info": acne_zone_info,
        "risk_info": risk_info,
        "personalization": personalization,
        "active_plan": active_plan,
        "care_guide": care_guide,
        "absolute_rules_catalog": get_absolute_rules_catalog(),
        "absolute_enforcement_report": absolute_enforcement_report,
        "special_flags_normalized": special_flags_norm,
    }


# ══════════════════════════════════════════════════════════════════════
# 16. KULLANICI DİLİ: NEDEN BU ADIM + KOŞULLARA GÖRE AYAR
# ══════════════════════════════════════════════════════════════════════

CONCERN_FOCUS_USER_TR = {
    "acne": "sivilce, gözenek ve yağ dengesi",
    "aging": "kırışıklık ve cilt kalitesi",
    "dryness": "kuruluk ve bariyer",
    "pigmentation": "leke ve ton eşitsizliği",
    "sensitivity": "hassasiyet ve sakinleşme",
}

SEVERITY_CONTEXT_USER_TR = {
    "hafif": "Belirtilerin hafif olduğu için",
    "orta": "Orta düzey bir tablo gösterdiğin için",
    "şiddetli": "Daha yoğun bir bakım ihtiyacı olduğu için",
}


def _routine_slot_phrase(time_slot: str) -> str:
    t = (time_slot or "").lower()
    if "sabah" in t:
        return "Sabah rutininde"
    if "akşam" in t:
        return "Akşam rutininde"
    return "Rutininde"


def _ingredient_key_for_risk_adjustment(ingredient_key: str) -> str:
    """ingredient_db risk tablosu anahtarına eşle."""
    if ingredient_key == "bakuchiol":
        return "retinol"
    if ingredient_key == "glycolic_aha":
        return "salisilik_asit"
    if ingredient_key == "leke_kompleksi":
        return "niacinamid"
    if ingredient_key in ("peptides", "toco_ferulic"):
        return "vitamin_c"
    return ingredient_key or ""


def _why_this_step_for_user(
    ingredient_key: str,
    concern: str,
    severity_level: str,
    skin_label_tr: str,
    age_label_tr: str,
    time_slot: str,
) -> str:
    """Kısa gerekçe; uzun açıklama 'Neden bu madde' alanında şişmesin."""
    if not ingredient_key or not (concern or "").strip():
        return ""
    focus = CONCERN_FOCUS_USER_TR.get(concern, "cilt hedeflerin")
    ctx = SEVERITY_CONTEXT_USER_TR.get(severity_level, "Şiddet profilin")
    slot = _routine_slot_phrase(time_slot)

    templates = {
        "vitamin_c": f"{slot} C vitamini: {focus} ile uyumlu gündüz antioksidan; ton ve parlaklığa destek. {ctx} dikkate alındı.",
        "retinol": f"{slot} retinol: {focus} için gece yenilenme aktifi; sıklık haftalık plana yayıldı. {ctx} ve tahriş riski dengelendi.",
        "bakuchiol": f"{slot} bakuchiol: retinole benzer hedefte genelde daha yumuşak alternatif. {focus} ve {ctx} için uygun görüldü.",
        "niacinamid": f"{slot} niasinamid: bariyer, sebum ve ton için çok yönlü B3. {focus} ile örtüşür; {ctx} ile doz/sıklık ayarlı.",
        "salisilik_asit": f"{slot} BHA: gözenek içi yağ/tıkanıklığa yönelir; {focus} akne bandında sık kullanılır. {ctx} ile sıklık kısıtlandı.",
        "benzoil_peroksit": f"{slot} benzoil peroksit: bakteri yükü için; {focus} yoğun akne tablolarında. Sabah kullanımı genelde önerilmez.",
        "hyaluronik_asit": f"{slot} hyaluronik asit: nem tutulumu ve dolgunluk hissi. {focus} hedefinde nem katmanı için.",
        "seramidler": f"{slot} seramid/lipid: bariyer onarımı; kuruluk ve hassasiyette öncelik. {focus} ile uyumlu.",
        "azelaik_asit": f"{slot} azelaik asit: akne ve kızarıklık/leke dengesinde orta güçlü seçenek. {focus} ve {ctx}.",
        "traneksamik_asit": f"{slot} traneksamik asit: leke/ton desteği; akşamda, güçlü asitlerden ayrı sırada.",
        "kojik_asit": f"{slot} kojik asit: leke baskılama seçeneklerinden; {focus} ve {ctx} sırasına göre.",
        "alfa_arbutin": f"{slot} alfa-arbutin: leke hedefli; genelde akşam bloğunda C vitamini ile gündüz-akşam ayrımı.",
        "leke_kompleksi": f"{slot} leke odaklı kombinasyon tek blokta: fazla gece katmanını azaltır, {focus} hedefini korur.",
        "petrolatum": f"{slot} oklüzif film: çok kuruda su kaybını kilitler; {focus} ile bariyer krizi dönemlerinde ek katman.",
        "cay_agaci": f"{slot} çay ağacı: hafif antimikrobiyal; noktasal, seyreltik. {focus} ve hassasiyet gözetildi.",
        "centella_panthenol": f"{slot} centella/pantenol: yatıştırma ve bariyer sakinliği; {focus} + hassasiyet uyumu.",
        "hidrokinon": f"{slot} hidrokinon: güçlü depigmentan; yalnızca uzman yönetiminde.",
        "mineral_spf": f"{slot} SPF: her hedefte sabahın kritik koruması; leke ve yaşlanma yönetiminin temeli.",
        "glycolic_aha": f"{slot} glikolik AHA: yüzey yenileme; {focus} leke/parlaklıkta akşam sıklığı. {ctx} tahriş eşiği ile.",
        "peptides": f"{slot} peptid: nazik anti-aging sinyali; {focus} yaşlanmada retinol öncesi basamak olabilir.",
        "toco_ferulic": f"{slot} E+ferulik: hafif antioksidan; hassas veya C öncesi sabah desteği.",
    }

    return templates.get(ingredient_key, "").strip()


def _risk_condition_sentence(
    risk_level: str,
    freq_multiplier: float,
    note: str,
    *,
    paused: bool,
) -> str:
    note = (note or "").strip()
    if paused:
        s = (
            "Yaşam verilerine göre bu adım geçici duraklatıldı; bariyer öne alındı. "
            "Sıklık check-in ile yeniden planlanır."
        )
        if note and note.lower() not in ("ara ver, sadece bariyer bakım",):
            s += f" ({note})"
        return s
    if freq_multiplier >= 1.0:
        return ""
    if not note or note.lower() in ("standart", "standart protokol"):
        return ""
    if risk_level == "crisis":
        return f"Tempo yumuşatıldı: {note}. Bariyer öncelikli."
    return f"Sıklık/güç hafif düşürüldü: {note}. Tahriş riski azaltıldı."


def _strip_prior_daily_risk_overlay(detail: str) -> str:
    """Check-in tekrarında eski günlük risk cümlelerini kaldır (çiftleşmeyi önler)."""
    if not detail:
        return detail
    patterns = (
        r"Aynı yaşam koşulların nedeniyle[^.]*\.\s*Faydayı korurken[^.]*\.\s*",
        r"Aynı veriler ışığında[^.]*\.\s*Hedef aynı[^.]*\.\s*",
        r"Bugünkü stres, uyku veya nem[^.]*\.\s*önce cildini sakinleştir[^.]*\.\s*",
    )
    d = detail
    for p in patterns:
        d = re.sub(p, "", d, flags=re.IGNORECASE)
    return d.strip()


def _is_spf_routine_row(item: dict) -> bool:
    a = (item.get("action") or "").lower()
    return "spf" in a or "güneş koruyucu" in a or "gunes koruyucu" in a


def _is_moisturizer_or_barrier_row(item: dict) -> bool:
    """Nemlendirici / gece bariyer katmanı: uzun içerik tekrarı + 'tek ürün' uyarısı."""
    if item.get("category") not in ("Bakım", "Koruma"):
        return False
    if _is_spf_routine_row(item):
        return False
    a = (item.get("action") or "").lower()
    so = item.get("step_order")
    if so == 30:
        return True
    if "nemlendirici" in a:
        return True
    if "gece" in a and any(x in a for x in ("krem", "katman", "bariyer", "onarım", "yoğun", "tek ")):
        return True
    if "bariyer kilidi" in a or "uyku mask" in a:
        return True
    return False


def _detect_ingredient_key(action_lower: str) -> str:
    """Özgün eşleşmeler önce (birleşik satırlar, bakuchiol / arbutin önceliği)."""
    al = (action_lower or "").lower()
    ordered = (
        ("leke kompleksi", "leke_kompleksi"),
        ("bakuchiol", "bakuchiol"),
        ("alfa-arbutin", "alfa_arbutin"),
        ("tretinoin", "retinol"),
        ("adapalen", "retinol"),
        ("retinoid", "retinol"),
        ("retinol", "retinol"),
        ("l-askorbik", "vitamin_c"),
        ("askorbik", "vitamin_c"),
        ("c vitamini", "vitamin_c"),
        ("ferulik", "toco_ferulic"),
        ("tokoferol", "toco_ferulic"),
        ("glikolik", "glycolic_aha"),
        ("traneksamik", "traneksamik_asit"),
        ("hidrokinon", "hidrokinon"),
        ("benzoil", "benzoil_peroksit"),
        ("bpo", "benzoil_peroksit"),
        ("salisilik", "salisilik_asit"),
        ("bha", "salisilik_asit"),
        ("azelaik", "azelaik_asit"),
        ("arbutin", "alfa_arbutin"),
        ("kojik", "kojik_asit"),
        ("niasinamid", "niacinamid"),
        ("niacinamid", "niacinamid"),
        ("hyaluronik", "hyaluronik_asit"),
        ("seramid", "seramidler"),
        ("petrolatum", "petrolatum"),
        ("vazelin", "petrolatum"),
        ("çay ağacı", "cay_agaci"),
        ("tea tree", "cay_agaci"),
        ("centella", "centella_panthenol"),
        ("cica", "centella_panthenol"),
        ("panthenol", "centella_panthenol"),
        ("sinyal peptid", "peptides"),
        ("peptid", "peptides"),
        ("matrixyl", "peptides"),
        ("spf", "mineral_spf"),
        ("güneş koruyucu", "mineral_spf"),
    )
    for kw, key in ordered:
        if kw in al:
            return key
    return ""


def finalize_user_routine_item_details(
    items: list,
    *,
    risk_level: str,
    concern: str = "",
    severity_level: str = "",
    skin_label_tr: str = "",
    age_label_tr: str = "",
) -> list:
    """
    Bakım/Koruma: `detail` yalnızca kısa “neden” (+ SPF/nem bütçe ipuçları).
    Sıklık, risk motoru ve adım talimatları `usage` alanında birleştirilir (arka plan metni kullanıcıya “neden”de gösterilmez).
    """
    from ingredient_db import get_risk_adjustment

    def _looks_like_usage(text: str) -> bool:
        """
        `detail` alanına yanlışlıkla yazılmış uygulama talimatlarını yakalamak için basit sezgisel.
        Amaç: "neden" paragrafına talimat (temiz cilde, SPF, durula vb.) kaçmasını engellemek.
        """
        if not text:
            return False
        t = " " + text.lower().strip() + " "
        triggers = (
            " temiz cilde ",
            " ince katman",
            " nohut ",
            " damla",
            " durula",
            " köpürt",
            " masaj",
            " göz çevresi",
            " emilince",
            " kuruyunca",
            " nemlendirici",
            " spf",
            " güneş",
            " gunes",
            " 2 saatte",
            " yenile",
            " haftalık planda",
            " takvim",
            " gün aşırı",
            " gun asiri",
            " yama testi",
            " kulak arkası",
            " bekle",
        )
        return any(k in t for k in triggers)

    out = []
    for item in items:
        cat = item.get("category", "")
        if cat not in ("Bakım", "Koruma"):
            out.append(item)
            continue

        orig = dict(item)
        ik = _detect_ingredient_key(orig.get("action", "").lower())
        motor_detail = (orig.get("detail") or "").strip()
        motor_usage = (orig.get("usage") or "").strip()

        # Motor bazı satırlarda talimatı `detail` içine yazmış olabilir.
        # Bu durumda talimatı `usage` tarafına taşır, `detail` sadece "neden" için kalır.
        moved_usage = ""
        if motor_detail and not motor_usage and _looks_like_usage(motor_detail):
            moved_usage = motor_detail
            motor_detail = ""

        why = _why_this_step_for_user(
            ik,
            concern,
            severity_level or "orta",
            skin_label_tr,
            age_label_tr,
            orig.get("time", ""),
        )

        # Sıklık / risk motoru cümleleri kullanıcıya "neden" yerine "nasıl uygularsın"da gösterilir
        risk_usage_addon = ""
        rk = _ingredient_key_for_risk_adjustment(ik)
        if ik and rk and risk_level and risk_level != "normal":
            adj = get_risk_adjustment(rk, risk_level)
            mult = float(adj.get("freq_multiplier", 1.0))
            note = adj.get("note", "")
            if mult == 0:
                orig["action"] = f"⏸️ {orig['action']} — şimdilik kullanma"
                orig["priority"] = 10
                risk_usage_addon = _risk_condition_sentence(risk_level, mult, note, paused=True)
                why = "Şu an bu adım güvenlik için duraklatıldı; önce bariyer ve sakinleşme."
            elif mult < 1.0:
                risk_usage_addon = _risk_condition_sentence(risk_level, mult, note, paused=False)

        if _is_spf_routine_row(orig):
            budget = (
                "Tek geniş spektrumlu güneş koruyucu yeter; istersen nem + SPF’yi tek üründe birleştirebilirsin."
            )
            detail_parts = [p for p in [why, budget] if p]
        elif _is_moisturizer_or_barrier_row(orig):
            budget = (
                "Aynı işi gören birkaç ayrı ürün almak zorunda değilsin: mümkünse tek nemlendiricide bu hedef içerikleri topla; "
                "olmazsa bu adımdaki içeriklerden birini seçerek rutine devam et."
            )
            detail_parts = [p for p in [why, budget] if p]
        else:
            detail_parts = [why] if why else []

        orig["detail"] = sanitize_routine_detail_system_voice(" ".join(detail_parts).strip())

        usage_bits = [b for b in [motor_usage, moved_usage, risk_usage_addon] if b]
        if usage_bits:
            orig["usage"] = sanitize_routine_detail_system_voice(" ".join(usage_bits).strip())
        elif not motor_usage:
            orig["usage"] = "Önerilen sırada, temiz cilde uygula."

        out.append(orig)

    if risk_level == "crisis":
        has_ceramide = any("seramid" in i.get("action", "").lower() for i in out)
        if not has_ceramide:
            out.append({
                "time": "Sabah ve Akşam", "category": "Bakım", "icon": "🛡️",
                "action": "Seramid + niasinamid içeren bariyer nemlendirici (öncelik)",
                "detail": "Önce bariyeri desteklemek için bu katman öne alındı; diğer güçlü adımlar hafifletildi veya durduruldu.",
                "usage": (
                    "Günde iki kez veya tahrişe göre sabah-akşam ince katman. "
                    "Eczane veya güvendiğin kanalda seramid/niasinamid içeren tek ürün yeterli olabilir."
                ),
                "priority": 1, "step_order": 15,
            })

    return out


def overlay_daily_risk_on_saved_routine(items: list, risk_level: str) -> list:
    """
    Günlük check-in: kayıtlı rutinde yalnızca günlük risk katmanını yenile (neden paragrafını tekrar ekleme).
    """
    from ingredient_db import get_risk_adjustment

    if risk_level == "normal":
        adjusted = []
        for item in items:
            ni = dict(item)
            if ni.get("category") in ("Bakım", "Koruma") and ni.get("detail"):
                ni["detail"] = _strip_prior_daily_risk_overlay(ni["detail"])
            adjusted.append(ni)
        return adjusted

    adjusted = []
    for item in items:
        orig = dict(item)
        cat = orig.get("category", "")
        if cat not in ("Bakım", "Koruma"):
            adjusted.append(orig)
            continue

        base_detail = _strip_prior_daily_risk_overlay(orig.get("detail") or "")
        motor_usage = (orig.get("usage") or "").strip()
        ik = _detect_ingredient_key(orig.get("action", "").lower())
        rk = _ingredient_key_for_risk_adjustment(ik)
        risk_part = ""
        if ik and rk:
            adj = get_risk_adjustment(rk, risk_level)
            mult = float(adj.get("freq_multiplier", 1.0))
            note = adj.get("note", "")
            if mult == 0:
                orig["action"] = f"⏸️ {orig['action']} — şimdilik kullanma"
                orig["priority"] = 10
                risk_part = _risk_condition_sentence(risk_level, mult, note, paused=True)
            elif mult < 1.0:
                risk_part = _risk_condition_sentence(risk_level, mult, note, paused=False)

        orig["detail"] = base_detail
        if risk_part:
            orig["usage"] = sanitize_routine_detail_system_voice(
                f"{risk_part} {motor_usage}".strip() if motor_usage else risk_part
            )
        else:
            orig["usage"] = motor_usage
        adjusted.append(orig)

    if risk_level == "crisis":
        has_ceramide = any("seramid" in i.get("action", "").lower() for i in adjusted)
        if not has_ceramide:
            adjusted.append({
                "time": "Sabah ve Akşam", "category": "Bakım", "icon": "🛡️",
                "action": "Seramid + niasinamid içeren bariyer nemlendirici (öncelik)",
                "detail": "Önce bariyeri desteklemek için bu katman öne alındı; diğer güçlü adımlar hafifletildi veya durduruldu.",
                "usage": (
                    "Günde iki kez veya tahrişe göre sabah-akşam ince katman. "
                    "Eczane veya güvendiğin kanalda seramid/niasinamid içeren tek ürün yeterli olabilir."
                ),
                "priority": 1, "step_order": 15,
            })

    return adjusted


def adjust_routine_for_risk(items: list, risk_level: str) -> list:
    """Geriye uyumluluk: kayıtlı rutin için günlük risk katmanı."""
    return overlay_daily_risk_on_saved_routine(items, risk_level)


# ══════════════════════════════════════════════════════════════════════
# 17. ADAPTIVE ROUTINE — Günlük check-in sonrası mevcut rutini adapte et
# ══════════════════════════════════════════════════════════════════════

def adapt_existing_routine(
    current_routine: list,
    daily_data: dict,
    risk_info: dict,
) -> dict:
    """
    Günlük check-in verisiyle mevcut rutini adapte et.

    daily_data: {sleep_hours, stress_today, skin_feeling, applied_routine, notes}
    risk_info: compute_risk_score() çıktısı

    Returns: {
        "adapted_items": list,
        "changes": [{"item": str, "old": str, "new": str, "reason": str}],
        "risk_level": str,
        "adaptation_type": "minor" | "major",
    }
    """
    from ingredient_db import get_daily_trigger_action, INGREDIENT_DB

    risk_level = risk_info["level"]
    skin_feeling = daily_data.get("skin_feeling", "iyi")
    changes = []
    adapted = []

    def _shrink_weekly_days_for_reduce(it: dict, mult: float) -> None:
        """
        Reduce aksiyonunda sıklığı kullanıcıya bırakmadan somutlaştır:
        - weekly_days varsa gün sayısını azalt
        - yoksa detail içindeki 'Haftada N' ifadesinden çıkarıp weekly_days ata
        """
        try:
            mult = float(mult)
        except Exception:
            mult = 0.5
        if mult <= 0:
            mult = 0.5

        # mevcut gün sayısı
        wd = it.get("weekly_days")
        n = len(wd) if isinstance(wd, list) else None
        if not n:
            # detail'dan çıkar
            n = _parse_weekly_frequency(it.get("detail") or "")

        if not n or n >= 7:
            return

        new_n = max(1, min(n - 1, int(round(n * mult)))) if n > 1 else 1
        new_n = max(1, min(new_n, n))
        if new_n == n:
            # en az 1 azaltmayı dene
            if n > 1:
                new_n = n - 1
            else:
                return
        it["weekly_days"] = _spread_n_days_across_week(new_n)

    for item in current_routine:
        action_lower = item.get("action", "").lower()
        ingredient_key = _detect_ingredient_key(action_lower)
        new_item = dict(item)

        if ingredient_key:
            trigger = get_daily_trigger_action(ingredient_key, skin_feeling)
            action_type = trigger.get("action", "maintain")

            if action_type == "pause":
                days = trigger.get("days", 3)
                changes.append({
                    "item": item.get("action", ""),
                    "old": "aktif",
                    "new": f"{days} gün ara ver",
                    "reason": trigger.get("note", f"Cilt hissi: {skin_feeling}"),
                })
                new_item["action"] = f"⏸️ {item['action']} — {days} gün ara ver"
                tn = trigger.get("note", "")
                prior_u = (item.get("usage") or "").strip()
                check_u = (
                    f"Check-in: cilt hissi “{skin_feeling}”; bu adım yaklaşık {days} gün duraklatıldı"
                    f"{(': ' + tn) if tn else ''}."
                )
                new_item["usage"] = sanitize_routine_detail_system_voice(
                    f"{check_u} {prior_u}".strip() if prior_u else check_u
                )
                new_item["priority"] = 10

            elif action_type == "reduce":
                mult = trigger.get("freq_multiplier", 0.5)
                changes.append({
                    "item": item.get("action", ""),
                    "old": "standart sıklık",
                    "new": f"sıklık x{mult}",
                    "reason": trigger.get("note", f"Cilt hissi: {skin_feeling}"),
                })
                tn = trigger.get("note", "")
                prior_u = (item.get("usage") or "").strip()
                _shrink_weekly_days_for_reduce(new_item, mult)
                check_u = (
                    f"Check-in: cilt hissi ({skin_feeling}); haftalık sıklık düşürüldü"
                    f"{(': ' + tn) if tn else ''}."
                )
                new_item["usage"] = sanitize_routine_detail_system_voice(
                    f"{check_u} {prior_u}".strip() if prior_u else check_u
                )

            elif action_type == "increase":
                changes.append({
                    "item": item.get("action", ""),
                    "old": "standart",
                    "new": "artırıldı",
                    "reason": trigger.get("note", f"Cilt hissi: {skin_feeling}"),
                })
                tn = trigger.get("note", "")
                prior_u = (item.get("usage") or "").strip()
                check_u = (
                    f"Check-in: cilt hissi olumlu; sıklık hafif artırıldı"
                    f"{(': ' + tn) if tn else ''}."
                )
                new_item["usage"] = sanitize_routine_detail_system_voice(
                    f"{check_u} {prior_u}".strip() if prior_u else check_u
                )

        adapted.append(new_item)

    adapted = adjust_routine_for_risk(adapted, risk_level)
    sanitize_routine_items_details(adapted)

    adaptation_type = "major" if len(changes) >= 3 or risk_level in ("high", "crisis") else "minor"

    return {
        "adapted_items": adapted,
        "changes": changes,
        "risk_level": risk_level,
        "risk_detail": risk_info.get("detail", ""),
        "adaptation_type": adaptation_type,
    }
