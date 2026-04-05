"""
REBI AI - Bilimsel Madde Veritabanı (Ingredient DB)
=====================================================
PDF ve Excel dosyalarından çıkarılan, doğrulanmış bilimsel veri.

Her madde için:
  - concern × şiddet × yaş × cilt tipi matrisinde konsantrasyon/sıklık
  - risk_adjustments: Günlük check-in sonucuna göre doz ayarlama referansı
  - daily_triggers: Kullanıcı cilt hissi raporuna göre tetikleyiciler
  - skin_type_adjust: Cilt tipine göre modifiye kuralları

Kaynak: Dermatolojik_Veri_Analizi_Master.xlsx + PDF derlemeler (Supabase knowledge_base)
"""

from config import get_logger

log = get_logger("ingredient_db")

# ═══════════════════════════════════════════════════════════════
# 1. INGREDIENT_DB  — Bilimsel Referans Veritabanı
# ═══════════════════════════════════════════════════════════════

INGREDIENT_DB = {

    # ── RETINOL / RETİNOİDLER ──────────────────────────────────
    "retinol": {
        "name": "Retinoidler (Tretinoin, Retinol, Retinaldeyde)",
        "evidence_level": "Level 1b",
        "expert_consensus": 96.0,
        "clinical_efficacy": "%32 kırışıklık azalması, %28 esneklik iyileşmesi",
        "time_to_effect": "6-12 ay tam etki, 8-12 hafta ilk fark",
        "mechanism": "Kolajen sentezi + hücre döngüsü hızlandırma",
        "photosensitive": True,
        "pregnancy_safe": False,
        "application_time": "Akşam",
        "concentrations": {
            "acne_hafif":        {"pct": "Adapalen %0.1",      "freq": "3x/hafta",   "time": "Akşam"},
            "acne_orta":         {"pct": "Adapalen %0.1",      "freq": "5x/hafta",   "time": "Akşam"},
            "acne_siddetli":     {"pct": "Tretinoin %0.025",   "freq": "her gece",   "time": "Akşam"},
            "aging_hassas_yeni": {"pct": "%0.1-0.2 retinol",   "freq": "2-3x/hafta", "time": "Akşam"},
            "aging_20_29":       {"pct": "%0.25-0.3 retinol",  "freq": "2x/hafta başla, kademeli artır", "time": "Akşam"},
            "aging_30_39":       {"pct": "%0.3 retinol",       "freq": "1-2 hafta 2-3x, sonra günlük gece", "time": "Akşam"},
            "aging_40_49":       {"pct": "%0.5 retinol",       "freq": "2-3x/hafta", "time": "Akşam"},
            "aging_50_plus":     {"pct": "Bakuchiol %1",       "freq": "3x/hafta",   "time": "Akşam"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0,  "note": "Standart protokol"},
            "high":    {"freq_multiplier": 0.5,  "note": "1-2x/hafta düşür, bariyer onarım ekle"},
            "crisis":  {"freq_multiplier": 0.0,  "note": "Ara ver, sadece bariyer bakım"},
        },
        "skin_type_adjust": {
            "sensitive": {"freq_multiplier": 0.5,  "note": "Yavaş başla, seramid destekli formül"},
            "dry":       {"freq_multiplier": 0.75, "note": "Seramid+squalane destekli formül"},
            "oily":      {"freq_multiplier": 1.0,  "note": "Standart uygulama"},
        },
        "daily_triggers": {
            "irritasyon": {"action": "pause",  "days": 3, "note": "2-3 gün ara ver, panthenol ile bariyer onar"},
            "kuru":       {"action": "reduce", "freq_multiplier": 0.5, "note": "Sıklık yarıya düşür"},
            "kirik":      {"action": "pause",  "days": 2, "note": "Bariyer hasarlı, aktiflerden kaçın"},
        },
        "combinations": {
            "synergy":  ["Benzoil Peroksit (sabah-akşam ayrı)", "Niasinamid"],
            "conflict": ["AHA (aynı gece)", "Vitamin C (aynı gece)", "BHA (aynı gece)"],
        },
        "critical_note": "Salisilik asit → Retinoid → Maintenance sırası zorunlu. Salisilik olmadan retinoid başlatma.",
    },

    # ── VİTAMİN C ──────────────────────────────────────────────
    "vitamin_c": {
        "name": "Vitamin C (L-Askorbit Asit, stabilize formlar)",
        "evidence_level": "Level 1b-2b",
        "expert_consensus": 88.7,
        "clinical_efficacy": "%9-13 kırışıklık azalması, kolajen sentezi",
        "time_to_effect": "8-12 hafta ilk fark, 6 ay tam etki",
        "mechanism": "Tirosinaz inhibisyonu (depigmentasyon) + kolajen sentezi + antioksidan",
        "photosensitive": False,
        "pregnancy_safe": True,
        "application_time": "Sabah",
        "application_note": "20 dakika bekleme, nemli cilde uygula",
        "concentrations": {
            "aging_20_29":         {"pct": "%10-15",          "freq": "her gün", "time": "Sabah"},
            "aging_30_39":         {"pct": "%15-20",          "freq": "her gün", "time": "Sabah"},
            "aging_40_plus":       {"pct": "%20 + E Vit + Ferulik Asit", "freq": "her gün", "time": "Sabah"},
            "pigmentation_genel":  {"pct": "%15-20",          "freq": "her gün", "time": "Sabah"},
            "pollution_orta":      {"pct": "%10-15 + Niasinamid", "freq": "her gün", "time": "Sabah"},
            "pollution_yuksek":    {"pct": "%15-20 + Salisilik %2", "freq": "her gün", "time": "Sabah"},
            "sensitivity_baslangic": {"pct": "%5-10 (stabilize form)", "freq": "günaşırı", "time": "Sabah"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Standart"},
            "high":    {"freq_multiplier": 0.7, "note": "her gün yerine gün aşırı kullan; mümkünse daha düşük konsantrasyonlu ürün seç"},
            "crisis":  {"freq_multiplier": 0.3, "note": "haftada en fazla iki kez ve düşük konsantrasyonla dene"},
        },
        "skin_type_adjust": {
            "sensitive": {"freq_multiplier": 0.5, "note": "%5-10 stabilize form, günaşırı"},
            "oily":      {"freq_multiplier": 1.0, "note": "Standart, mat formül tercih"},
        },
        "daily_triggers": {
            "irritasyon": {"action": "reduce", "freq_multiplier": 0.5, "note": "Günaşırıya geç"},
            "iyi":        {"action": "maintain", "note": "Devam et"},
        },
        "combinations": {
            "synergy":  ["Vitamin E + Ferulik Asit (üçlü formül)", "Niasinamid", "SPF"],
            "conflict": ["Retinol (aynı zaman)", "AHA (düşük pH çakışması)"],
        },
    },

    # ── NİASİNAMİD ─────────────────────────────────────────────
    "niacinamid": {
        "name": "Niasinamid (Vitamin B3)",
        "evidence_level": "Level 1b",
        "expert_consensus": 87.0,
        "clinical_efficacy": "Sebum düzenlemesi, IL-6/IL-8 azalması, bariyer tamir",
        "time_to_effect": "4-8 hafta",
        "mechanism": "Anti-enflamatuar + seramid sentezi uyarımı + sebum regülasyonu",
        "photosensitive": False,
        "pregnancy_safe": True,
        "application_time": "Sabah ve Akşam",
        "concentrations": {
            "sensitivity_bariyer":  {"pct": "%3-5",  "freq": "her gün", "time": "Sabah ve Akşam"},
            "acne_genel":           {"pct": "%4-5",  "freq": "her gün", "time": "Sabah ve Akşam"},
            "stress_yuksek":        {"pct": "%5 + Seramidler", "freq": "her gün", "time": "Sabah ve Akşam"},
            "stress_orta":          {"pct": "%4 + Vitamin C", "freq": "her gün", "time": "Sabah"},
            "pigmentation_destek":  {"pct": "%4-5",  "freq": "her gün", "time": "Sabah"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Standart"},
            "high":    {"freq_multiplier": 1.0, "note": "Niasinamid yüksek riskde bile güvenli, ZORUNLU ekle"},
            "crisis":  {"freq_multiplier": 1.0, "note": "Krizde Niasinamid + Seramid ZORUNLU"},
        },
        "skin_type_adjust": {},
        "daily_triggers": {
            "irritasyon": {"action": "maintain", "note": "Niasinamid yatıştırıcı, devam et"},
            "kuru":       {"action": "maintain", "note": "Bariyer tamir için devam"},
            "yagli":      {"action": "maintain", "note": "Sebum kontrolü için devam"},
        },
        "combinations": {
            "synergy":  ["Seramidler", "Vitamin C", "Çinko"],
            "conflict": ["AHA (düşük pH'da flushing, 10 dk ara ver)"],
        },
        "critical_note": "Mükemmel tolerabilite, TÜM ciltlerle uyumlu. Kriz modunda bile kesilmez.",
    },

    # ── SALİSİLİK ASİT (BHA) ──────────────────────────────────
    "salisilik_asit": {
        "name": "Salisilik Asit (BHA, %2)",
        "evidence_level": "Level 1b",
        "expert_consensus": 90.0,
        "clinical_efficacy": "Hızlı komedo azalması 2-4 hafta",
        "time_to_effect": "2-4 hafta",
        "mechanism": "Keratolit etki, lipid çözücü, pori temizleme",
        "photosensitive": False,
        "pregnancy_safe": False,
        "application_time": "Akşam",
        "concentrations": {
            "acne_hafif":     {"pct": "%2 tonik",     "freq": "2x/hafta", "time": "Akşam"},
            "acne_orta":      {"pct": "%2",           "freq": "3-4x/hafta", "time": "Akşam"},
            "acne_siddetli":  {"pct": "%2",           "freq": "her gün",  "time": "Akşam"},
            "makyaj_yogun":   {"pct": "%2",           "freq": "2x/hafta ZORUNLU", "time": "Akşam"},
            "dusuk_doz":      {"pct": "%0.5-1",       "freq": "2-3x/hafta", "time": "Akşam"},
            "karma_tzone":    {"pct": "%1-2",         "freq": "3x/hafta", "time": "Akşam"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Standart"},
            "high":    {"freq_multiplier": 0.5, "note": "Haftada 1-2x düşür"},
            "crisis":  {"freq_multiplier": 0.0, "note": "Ara ver, nazik temizlik yeterli"},
        },
        "skin_type_adjust": {
            "sensitive": {"freq_multiplier": 0.5, "note": "%0.5-1 düşük doz, haftada 1x"},
            "dry":       {"freq_multiplier": 0.5, "note": "Sadece sorunlu bölgelere, ardından nemlendirici"},
        },
        "daily_triggers": {
            "irritasyon": {"action": "pause", "days": 3, "note": "Ara ver, bariyer onar"},
            "kuru":       {"action": "reduce", "freq_multiplier": 0.5, "note": "Sıklık yarıya düşür"},
            "kirik":      {"action": "pause", "days": 2, "note": "Bariyer zayıf, ara ver"},
        },
        "combinations": {
            "synergy":  ["Benzoil Peroksit (artan etkinlik)", "Niasinamid"],
            "conflict": ["Retinol (aynı gece)", "AHA (aynı gece)"],
        },
        "critical_note": "Salisilik → Retinoid → Maintenance sırası zorunlu.",
    },

    # ── BENZOİL PEROKSİT ──────────────────────────────────────
    "benzoil_peroksit": {
        "name": "Benzoil Peroksit (BPO)",
        "evidence_level": "Level 1b",
        "expert_consensus": 95.2,
        "clinical_efficacy": "Bakterisidal: P. acnes %97.5 azalma (15. gün), inflamatuar lezyon %58.5 azalma",
        "time_to_effect": "2-4 hafta",
        "mechanism": "Bakterisidal + anti-enflamatuar + keratolit",
        "photosensitive": False,
        "pregnancy_safe": False,
        "application_time": "Sabah veya Akşam",
        "concentrations": {
            "acne_hafif":     {"pct": "%2.5 nokta tedavi",  "freq": "2x/hafta", "time": "Sabah"},
            "acne_orta":      {"pct": "%2.5-5",             "freq": "her gün",  "time": "Sabah"},
            "acne_siddetli":  {"pct": "%5-10",              "freq": "sabah-akşam", "time": "Sabah ve Akşam"},
            "kisa_temas":     {"pct": "%5 kısa temas",      "freq": "her gün",  "time": "Akşam", "note": "5-10 dk sür, yıka"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Standart"},
            "high":    {"freq_multiplier": 0.3, "note": "Sadece nokta tedavi, haftada 1-2x"},
            "crisis":  {"freq_multiplier": 0.0, "note": "BPO ARA VER, sadece nazik temizlik"},
        },
        "skin_type_adjust": {
            "sensitive": {"freq_multiplier": 0.3, "note": "Sadece %2.5 nokta tedavi, kısa temas"},
            "dry":       {"freq_multiplier": 0.5, "note": "Kısa temas tercih, ardından nemlendirici"},
        },
        "daily_triggers": {
            "irritasyon": {"action": "pause", "days": 3, "note": "Ara ver, panthenol ile onar"},
            "kuru":       {"action": "reduce", "freq_multiplier": 0.3, "note": "Kısa temas, haftada 1x"},
            "kirik":      {"action": "pause", "days": 3, "note": "Bariyer hasarlı, ara ver"},
        },
        "combinations": {
            "synergy":  ["Retinoid (sabah BPO + akşam retinoid)", "Salisilik Asit"],
            "conflict": ["Retinol (aynı anda inaktive eder)"],
        },
    },

    # ── HYALURONİK ASİT ───────────────────────────────────────
    "hyaluronik_asit": {
        "name": "Hyaluronik Asit (HA, çoklu moleküler ağırlık)",
        "evidence_level": "Level 2b",
        "expert_consensus": 79.0,
        "clinical_efficacy": "Ani hidrasyon %134, sürdürülen %55 (6. hafta), ince çizgi %31 iyileşme",
        "time_to_effect": "Anında hidrasyon, 6 hafta sürdürülen etki",
        "mechanism": "Humektant, su bağlama, dermal penetrasyon",
        "photosensitive": False,
        "pregnancy_safe": True,
        "application_time": "Sabah ve Akşam",
        "application_note": "Nemli cilde uygula, üzerine nemlendirici kilitle",
        "concentrations": {
            "genel":     {"pct": "Çoklu mol. ağırlık HA", "freq": "her gün", "time": "Sabah ve Akşam"},
            "kuruluk":   {"pct": "Çoklu mol. ağırlık HA + Seramid", "freq": "2x/gün", "time": "Sabah ve Akşam"},
            "oral":      {"pct": "120-240 mg/gün oral HA",  "freq": "her gün", "time": "Oral"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Standart"},
            "high":    {"freq_multiplier": 1.5, "note": "Artır: bariyer desteği için ekstra katman"},
            "crisis":  {"freq_multiplier": 2.0, "note": "2x/gün + oklüzif üstüne kilitle"},
        },
        "skin_type_adjust": {},
        "daily_triggers": {
            "kuru":       {"action": "increase", "note": "Ekstra katman + oklüzif kilitle"},
            "irritasyon": {"action": "maintain", "note": "HA yatıştırıcı, devam et"},
        },
        "combinations": {
            "synergy":  ["Seramidler", "Petrolatum (oklüzif kilitleme)", "Niasinamid"],
            "conflict": [],
        },
    },

    # ── SERAMİDLER ─────────────────────────────────────────────
    "seramidler": {
        "name": "Seramidler",
        "evidence_level": "Level 1b-2b",
        "expert_consensus": 82.1,
        "clinical_efficacy": "Hidrasyon %38 iyileşme, TEWL azalması, bariyer restorasyon",
        "time_to_effect": "2-4 hafta bariyer onarım",
        "mechanism": "Lipit bariyer restorasyonu, TEWL azalması",
        "photosensitive": False,
        "pregnancy_safe": True,
        "application_time": "Sabah ve Akşam",
        "concentrations": {
            "standart":     {"pct": "%1-3",  "freq": "her gün",  "time": "Sabah ve Akşam"},
            "bariyer_onarim": {"pct": "%5 + Petrolatum", "freq": "2x/gün", "time": "Sabah ve Akşam"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Standart"},
            "high":    {"freq_multiplier": 1.5, "note": "ZORUNLU ekle, doz artır"},
            "crisis":  {"freq_multiplier": 2.0, "note": "Krizde %5 Seramid + Petrolatum ZORUNLU"},
        },
        "skin_type_adjust": {
            "sensitive": {"freq_multiplier": 1.5, "note": "Bariyer öncelikli, doz artır"},
            "dry":       {"freq_multiplier": 1.5, "note": "%5 + Petrolatum, 2x/gün"},
            "oily":      {"freq_multiplier": 0.75, "note": "Hafif formül, 1x/gün yeterli"},
        },
        "daily_triggers": {
            "kuru":       {"action": "increase", "note": "%5 konsantrasyona çık, 2x/gün"},
            "irritasyon": {"action": "increase", "note": "Bariyer onarım için artır"},
            "kirik":      {"action": "increase", "note": "%5 + Petrolatum zorunlu"},
        },
        "combinations": {
            "synergy":  ["Niasinamid (sinerjistik etki)", "Kolesterol", "Yağ asitleri (3:1:1 oranı)"],
            "conflict": [],
        },
        "critical_note": "Kuru/Hassas cilt: Seramid %5 + Petrolatum ÖNCELIK, aktif maddeler %50 doz azalt.",
    },

    # ── AZELAİK ASİT ──────────────────────────────────────────
    "azelaik_asit": {
        "name": "Azelaik Asit",
        "evidence_level": "Level 2b",
        "expert_consensus": 85.0,
        "clinical_efficacy": "Çift yararı: akne + hiperpigmentasyon",
        "time_to_effect": "4-8 hafta",
        "mechanism": "Anti-bakteriyel + anti-enflamatuar + melanin inhibisyonu",
        "photosensitive": False,
        "pregnancy_safe": True,
        "application_time": "Akşam",
        "concentrations": {
            "akne_hassas":      {"pct": "%15",  "freq": "1x/hafta",  "time": "Akşam"},
            "akne_standart":    {"pct": "%20",  "freq": "her gün",   "time": "Akşam"},
            "pigmentation":     {"pct": "%20",  "freq": "her gün",   "time": "Akşam"},
            "rosacea":          {"pct": "%15",  "freq": "1x/hafta başla, kademeli artır", "time": "Akşam"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Standart"},
            "high":    {"freq_multiplier": 0.5, "note": "Haftada 2-3x düşür"},
            "crisis":  {"freq_multiplier": 0.3, "note": "Haftada 1x sadece"},
        },
        "skin_type_adjust": {
            "sensitive": {"freq_multiplier": 0.5, "note": "%15 haftada 1x, retinoid alternatifi"},
        },
        "daily_triggers": {
            "irritasyon": {"action": "reduce", "freq_multiplier": 0.5, "note": "Sıklık azalt"},
        },
        "combinations": {
            "synergy":  ["Niasinamid", "Vitamin C"],
            "conflict": [],
        },
        "critical_note": "Hassas cilt aknede retinoid yerine tercih edilen alternatif. İrritasyon %18.7.",
    },

    # ── TRANEKSAMİK ASİT ──────────────────────────────────────
    "traneksamik_asit": {
        "name": "Traneksamik Asit",
        "evidence_level": "Level 1b-2b",
        "expert_consensus": 90.0,
        "clinical_efficacy": "MASI skoru %50-70 azalma (8-12 hafta)",
        "time_to_effect": "8-12 hafta",
        "mechanism": "Plasmin inhibisyonu, melanogenez baskılama",
        "photosensitive": False,
        "pregnancy_safe": False,
        "application_time": "Akşam",
        "concentrations": {
            "pigmentation_topikal": {"pct": "%5-20 topikal",   "freq": "her gün", "time": "Akşam"},
            "melasma_oral":         {"pct": "500mg/gün oral",  "freq": "her gün", "time": "Oral"},
            "melasma_first_line":   {"pct": "%5-20 (FIRST LINE)", "freq": "her gün", "time": "Akşam"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Standart"},
            "high":    {"freq_multiplier": 0.7, "note": "Günaşırıya geç"},
            "crisis":  {"freq_multiplier": 0.0, "note": "Güneş varsa ara ver"},
        },
        "skin_type_adjust": {},
        "daily_triggers": {
            "irritasyon": {"action": "maintain", "note": "İrritasyon riski %0.8, genelde güvenli"},
        },
        "combinations": {
            "synergy":  ["Hidrokinon (daha etkili)", "Niasinamid", "Vitamin C"],
            "conflict": [],
        },
        "critical_note": "Melasma/leke FIRST LINE tedavi. İrritasyon riski %0.8 (çok düşük).",
    },

    # ── KOJİK ASİT ────────────────────────────────────────────
    "kojik_asit": {
        "name": "Kojik Asit",
        "evidence_level": "Level 2b",
        "expert_consensus": 93.6,
        "clinical_efficacy": "Melanin sentezi inhibisyonu",
        "time_to_effect": "8-12 hafta",
        "mechanism": "Tirosinaz inhibisyonu",
        "photosensitive": False,
        "pregnancy_safe": True,
        "application_time": "Akşam",
        "concentrations": {
            "pigmentation": {"pct": "%2", "freq": "her gün", "time": "Akşam"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Standart"},
            "high":    {"freq_multiplier": 0.5, "note": "Günaşırı"},
            "crisis":  {"freq_multiplier": 0.0, "note": "Ara ver"},
        },
        "skin_type_adjust": {
            "sensitive": {"freq_multiplier": 0.5, "note": "İrritasyon %5.3, dikkatli kullan"},
        },
        "daily_triggers": {
            "irritasyon": {"action": "reduce", "freq_multiplier": 0.5, "note": "Günaşırıya geç"},
        },
        "combinations": {
            "synergy":  ["Arbutin", "Vitamin C"],
            "conflict": [],
        },
    },

    # ── ALFA ARBUTİN ───────────────────────────────────────────
    "alfa_arbutin": {
        "name": "α-Arbutin",
        "evidence_level": "Level 2b",
        "expert_consensus": 80.0,
        "clinical_efficacy": "Melazma %5-13 skor azalması, THBG kombo %18 azalma (3 ay)",
        "time_to_effect": "8-12 hafta",
        "mechanism": "Tirosinaz inhibisyonu, melanin modülasyonu",
        "photosensitive": False,
        "pregnancy_safe": True,
        "application_time": "Sabah",
        "concentrations": {
            "pigmentation_hafif": {"pct": "%2 α-arbutin",  "freq": "her gün", "time": "Sabah"},
            "pigmentation_kombo": {"pct": "%2 + THBG %10", "freq": "her gün", "time": "Sabah"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Standart"},
            "high":    {"freq_multiplier": 0.7, "note": "Günaşırı"},
            "crisis":  {"freq_multiplier": 0.3, "note": "Haftada 2x"},
        },
        "skin_type_adjust": {},
        "daily_triggers": {},
        "combinations": {
            "synergy":  ["Vitamin C", "Niasinamid", "SPF (zorunlu)"],
            "conflict": [],
        },
    },

    # ── PETROLATUM ─────────────────────────────────────────────
    "petrolatum": {
        "name": "Petrolatum (Vazelin)",
        "evidence_level": "Level 1b",
        "expert_consensus": 85.5,
        "clinical_efficacy": "TEWL %25-35 azalma (2-3 hafta), su kaybı %14 (vs %50 tedavisiz)",
        "time_to_effect": "Anında oklüzif etki",
        "mechanism": "Oklüzif, transepidermal su kaybını engeller",
        "photosensitive": False,
        "pregnancy_safe": True,
        "application_time": "Akşam",
        "concentrations": {
            "standart":    {"pct": "İnce tabaka", "freq": "her gece", "time": "Akşam"},
            "kriz":        {"pct": "Gece gündüz", "freq": "2x/gün",  "time": "Sabah ve Akşam"},
            "inflamasyon": {"pct": "%100 oklüzif", "freq": "ilk 48 saat zorunlu", "time": "Sürekli"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Gece son katman"},
            "high":    {"freq_multiplier": 1.5, "note": "Sabah ve akşam"},
            "crisis":  {"freq_multiplier": 2.0, "note": "Gece GÜNDÜZ zorunlu, tüm aktifler üstüne kilitle"},
        },
        "skin_type_adjust": {
            "oily":  {"freq_multiplier": 0.5, "note": "Sadece kuru bölgelere, ince tabaka"},
            "dry":   {"freq_multiplier": 1.5, "note": "Her gece zorunlu"},
        },
        "daily_triggers": {
            "kuru":       {"action": "increase", "note": "Gece gündüz oklüzif"},
            "kirik":      {"action": "increase", "note": "Bariyer acil onarım, 2x/gün"},
            "irritasyon": {"action": "increase", "note": "Yatıştırıcı + oklüzif kilitle"},
        },
        "combinations": {
            "synergy": ["Hyaluronik Asit (altına)", "Seramidler (altına)"],
            "conflict": [],
        },
        "critical_note": "GOLD STANDART oklüzif. Kriz modunda gece gündüz zorunlu.",
    },

    # ── ÇAY AĞACI YAĞI ────────────────────────────────────────
    "cay_agaci": {
        "name": "Çay Ağacı Yağı (Tea Tree Oil)",
        "evidence_level": "Level 2b-3",
        "expert_consensus": 70.0,
        "clinical_efficacy": "Akne Ciddiyet İndeksi %66.7 azalma vs eritromisin %49.7",
        "time_to_effect": "4-6 hafta",
        "mechanism": "Terpinen-4-ol antimikrobiyal penetrasyon",
        "photosensitive": False,
        "pregnancy_safe": True,
        "application_time": "Akşam",
        "concentrations": {
            "acne_hafif": {"pct": "%5 jel", "freq": "her gün", "time": "Akşam"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Standart"},
            "high":    {"freq_multiplier": 0.5, "note": "Günaşırı"},
            "crisis":  {"freq_multiplier": 0.0, "note": "Ara ver"},
        },
        "skin_type_adjust": {
            "sensitive": {"freq_multiplier": 0.5, "note": "Dikkat, tahriş yapabilir"},
        },
        "daily_triggers": {
            "irritasyon": {"action": "pause", "days": 3, "note": "Tahriş riski, ara ver"},
        },
        "combinations": {
            "synergy":  [],
            "conflict": ["Yüksek konsantrasyonlu aktifler"],
        },
    },

    # ── CENTELLA / PANTHENOL ───────────────────────────────────
    "centella_panthenol": {
        "name": "Centella Asiatica (Cica) + Panthenol",
        "evidence_level": "Level 2b",
        "expert_consensus": 78.0,
        "clinical_efficacy": "Bariyer onarım, anti-enflamatuar, yatıştırıcı",
        "time_to_effect": "2-4 hafta",
        "mechanism": "Madecassoside bariyer onarımı + Panthenol nem tutma",
        "photosensitive": True,
        "pregnancy_safe": True,
        "application_time": "Akşam (Centella güneşle leke riski)",
        "concentrations": {
            "sensitivity_sabah": {"pct": "Panthenol %5",               "freq": "her gün", "time": "Sabah"},
            "sensitivity_aksam": {"pct": "Centella + Bisabolol",       "freq": "her gün", "time": "Akşam"},
            "bariyer_onarim":    {"pct": "Centella + Panthenol + HA",  "freq": "2x/gün",  "time": "Sabah(panthenol) Akşam(centella)"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Standart"},
            "high":    {"freq_multiplier": 1.5, "note": "Artır, bariyer onarım öncelikli"},
            "crisis":  {"freq_multiplier": 2.0, "note": "Ana tedavi ajanı olarak kullan"},
        },
        "skin_type_adjust": {
            "sensitive": {"freq_multiplier": 1.5, "note": "Temel bakım, her gün"},
        },
        "daily_triggers": {
            "irritasyon": {"action": "increase", "note": "Yatıştırıcı artır"},
            "kuru":       {"action": "increase", "note": "Panthenol nem desteği artır"},
            "kirik":      {"action": "increase", "note": "Centella bariyer onarım"},
        },
        "combinations": {
            "synergy":  ["Niasinamid", "Seramidler", "Hyaluronik Asit"],
            "conflict": [],
        },
        "critical_note": "CENTELLA sabah kullanımı leke yapabilir. Sabah: Panthenol, Akşam: Centella.",
    },

    # ── HİDROKİNON ────────────────────────────────────────────
    "hidrokinon": {
        "name": "Hidrokinon",
        "evidence_level": "Level 1b",
        "expert_consensus": 98.4,
        "clinical_efficacy": "En yüksek depigmentasyon etkinliği",
        "time_to_effect": "8-12 hafta",
        "mechanism": "Tirosinaz inhibisyonu (güçlü)",
        "photosensitive": True,
        "pregnancy_safe": False,
        "application_time": "Akşam",
        "concentrations": {
            "pigmentation_siddetli": {"pct": "%4 (reçeteli)", "freq": "her gece", "time": "Akşam"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Standart, max 3 ay kullan"},
            "high":    {"freq_multiplier": 0.5, "note": "Günaşırı, irritasyon izle"},
            "crisis":  {"freq_multiplier": 0.0, "note": "Ara ver"},
        },
        "skin_type_adjust": {
            "sensitive": {"freq_multiplier": 0.0, "note": "KULLANMA, irritasyon %50.9"},
        },
        "daily_triggers": {
            "irritasyon": {"action": "pause", "days": 5, "note": "Yüksek irritasyon riski %50.9, ara ver"},
        },
        "combinations": {
            "synergy":  ["Traneksamik Asit", "Tretinoin", "SPF (zorunlu)"],
            "conflict": ["Benzoil Peroksit (renklendirme)"],
        },
        "critical_note": "EN YÜKSEK uzman konsensüsü (%98.4) ama %50.9 irritasyon riski. Dikkatli kullanım.",
    },

    # ── MİNERAL GÜNEŞ FİLTRESİ (SPF) ─────────────────────────
    "mineral_spf": {
        "name": "Mineral Güneş Filtresi (Çinko oksit, Titanyum dioksit)",
        "evidence_level": "Level 1b",
        "expert_consensus": 96.8,
        "clinical_efficacy": "Fotoışınlanmadan koruma, hasar engelleme",
        "time_to_effect": "Anında koruma",
        "mechanism": "Fiziksel bariyer, UV yansıtma",
        "photosensitive": False,
        "pregnancy_safe": True,
        "application_time": "Sabah",
        "concentrations": {
            "genel":     {"pct": "SPF 30+",  "freq": "her gün", "time": "Sabah"},
            "yuksek_uv": {"pct": "SPF 50+",  "freq": "her gün, 2 saatte yenile", "time": "Sabah"},
            "leke_olan": {"pct": "SPF 50+ (ZORUNLU)", "freq": "her gün", "time": "Sabah"},
        },
        "risk_adjustments": {
            "normal":  {"freq_multiplier": 1.0, "note": "Her gün"},
            "high":    {"freq_multiplier": 1.0, "note": "Her gün, mineral tercih"},
            "crisis":  {"freq_multiplier": 1.0, "note": "Kesinlikle kesilmez"},
        },
        "skin_type_adjust": {
            "sensitive": {"freq_multiplier": 1.0, "note": "Mineral filtre tercih"},
            "oily":      {"freq_multiplier": 1.0, "note": "Mat bitişli, yağsız formül"},
        },
        "daily_triggers": {},
        "combinations": {
            "synergy":  ["TÜM aktif maddelerle güvenli"],
            "conflict": [],
        },
        "critical_note": "EN YÜKSEK konsensüs (%96.8). Tüm cilt tipleri, tüm senaryolar. ASLA kesilmez.",
    },
}


# ═══════════════════════════════════════════════════════════════
# 2. SENARYO PROTOKOLLERİ — 6 Klinik Senaryo
# ═══════════════════════════════════════════════════════════════

SCENARIO_PROTOCOLS = {
    "dehidrate_stres_makyaj": {
        "label": "Dehidrate + Yüksek Stres + Yüksek PM2.5 + Yoğun Makyaj",
        "match_criteria": {"hydration": "low", "stress": "high", "makeup": "heavy"},
        "morning": [
            {"ingredient": "niacinamid",  "pct": "%5",    "step_order": 20},
            {"ingredient": "vitamin_c",   "pct": "%15",   "step_order": 25},
            {"ingredient": "mineral_spf", "pct": "SPF 50", "step_order": 40},
        ],
        "evening": [
            {"ingredient": "salisilik_asit",  "pct": "%2",  "freq": "2x/hafta", "step_order": 20},
            {"ingredient": "seramidler",      "pct": "+HA",                      "step_order": 25},
            {"ingredient": "petrolatum",      "pct": "oklüzif",                  "step_order": 30},
        ],
        "special": "Retinoid %0.025 (2x/hafta) + Kolajen peptid (oral)",
        "expected": "4 hafta hidrasyon %30-40, 8 hafta bariyer restore, 12 hafta anti-aging",
    },
    "normal_antiaging": {
        "label": "Normal + Orta Stres + Düşük PM2.5 + Anti-Aging",
        "match_criteria": {"hydration": "normal", "stress": "medium", "concern": "aging"},
        "morning": [
            {"ingredient": "vitamin_c",   "pct": "%10-15", "step_order": 20},
            {"ingredient": "mineral_spf", "pct": "SPF 30", "step_order": 40},
        ],
        "evening": [
            {"ingredient": "retinol",    "pct": "%0.3 veya Bakuchiol %1", "freq": "3x/hafta", "step_order": 20},
            {"ingredient": "hyaluronik_asit", "pct": "+Seramidler",                             "step_order": 25},
        ],
        "expected": "12 hafta kırışıklık azalması %9-13, elastiklik artışı",
    },
    "akne_makyaj": {
        "label": "Akne + Orta PM2.5 + Orta Makyaj",
        "match_criteria": {"concern": "acne", "makeup": "moderate"},
        "morning": [
            {"ingredient": "benzoil_peroksit", "pct": "%2.5-5",  "step_order": 20},
            {"ingredient": "niacinamid",       "pct": "%4",      "step_order": 25},
            {"ingredient": "mineral_spf",      "pct": "SPF 50",  "step_order": 40},
        ],
        "evening": [
            {"ingredient": "salisilik_asit", "pct": "%2 veya BP alternans", "step_order": 20},
        ],
        "expected": "4-8 hafta akne azalması",
    },
    "melasma_kirlilik": {
        "label": "Melasma + Yüksek PM2.5 + Orta Makyaj",
        "match_criteria": {"concern": "pigmentation", "pollution": "high"},
        "morning": [
            {"ingredient": "vitamin_c",   "pct": "%15-20",        "step_order": 20},
            {"ingredient": "niacinamid",  "pct": "%4",            "step_order": 25},
            {"ingredient": "mineral_spf", "pct": "SPF 50 ZORUNLU", "step_order": 40},
        ],
        "evening": [
            {"ingredient": "traneksamik_asit", "pct": "%5-20 (FIRST LINE)", "step_order": 20},
        ],
        "special": "Oral: Traneksamik asit 500mg/gün",
        "expected": "8-12 hafta MASI %50-70 azalma",
    },
    "rosacea_sensitivite": {
        "label": "Dehidrate + Rosacea/Sensitivite",
        "match_criteria": {"concern": "sensitivity", "hydration": "low"},
        "morning": [
            {"ingredient": "niacinamid",        "pct": "%4-5",       "step_order": 20},
            {"ingredient": "centella_panthenol", "pct": "Panthenol",  "step_order": 25},
            {"ingredient": "mineral_spf",        "pct": "SPF 30 mineral", "step_order": 40},
        ],
        "evening": [
            {"ingredient": "seramidler",      "pct": "+HA",      "step_order": 20},
            {"ingredient": "petrolatum",      "pct": "oklüzif",  "step_order": 30},
        ],
        "special": "Azelaik asit %15 (1x/hafta)",
        "avoid": "Aniyonik temizleyici, fragrance, retinoid (6-8 hafta sonra)",
        "expected": "4-8 hafta kızarıklık azalması",
    },
    "kombinasyon_cilt": {
        "label": "Kombinasyon Cilt (Yağlı T-Zone + Kuru Yanaklar)",
        "match_criteria": {"skin_type": "combination"},
        "morning_tzone": [
            {"ingredient": "salisilik_asit", "pct": "%1-2", "step_order": 20},
            {"ingredient": "niacinamid",     "pct": "hafif", "step_order": 25},
        ],
        "morning_cheeks": [
            {"ingredient": "vitamin_c",      "pct": "serum",  "step_order": 20},
            {"ingredient": "hyaluronik_asit", "pct": "+zengin nemlendirici", "step_order": 25},
        ],
        "expected": "8-12 hafta cilt dengesi",
    },
}


# ═══════════════════════════════════════════════════════════════
# 3. RİSK SKORU HESAPLAMA
# ═══════════════════════════════════════════════════════════════

def _risk_detail_for_user(
    stress: int,
    water_intake: float,
    humidity: float,
    sleep_hours: float,
    makeup_frequency: int,
    makeup_removal: str,
    cycle_phase: str,
    gender: str,
    level: str,
) -> str:
    """Kullanıcıya gösterilecek düz Türkçe özet (formül satırı değil)."""
    hints: list[str] = []
    if stress >= 9:
        hints.append("Stres puanın oldukça yüksek; bu dönemde cilt daha kolay tepki verebilir.")
    elif stress >= 6:
        hints.append("Stres orta–yüksek banda yakın; yatıştırıcı yaşam adımları faydalı olur.")

    if water_intake < 1.5:
        hints.append("Günlük su hedefine henüz tam yaklaşmamış görünüyorsun; hidrasyon bariyer ve elastikiyeti destekler.")
    elif water_intake < 2.0:
        hints.append("Su tüketimin hedefin biraz altında kalabilir; gün içine birkaç bardak eklemek iyi olur.")

    if humidity < 40:
        hints.append("Ortam nemi düşük sayılır; nemlendirme ve bariyer bakımı özellikle önemli.")
    elif humidity < 60:
        hints.append("Ortam nemi orta; rutindeki nem adımlarını sürdürmek yeterli olabilir.")

    if sleep_hours < 6:
        hints.append("Uyku süren kısa; gece onarımı için süreyi kademeli olarak artırmayı düşünebilirsin.")
    elif sleep_hours < 7:
        hints.append("Uyku süren idealin biraz altında; düzenli yatış-kalkış saatleri bariyer onarımına yardım eder.")

    mf = int(makeup_frequency or 0)
    mr = (makeup_removal or "cleanser").lower()
    if mf >= 5:
        hints.append("Makyajı sık kullanıyorsun; gözenek ve bariyer için nazik ve eksiksiz temizlik önemli.")
    if mf > 0 and mr in ("none", "water"):
        hints.append("Makyaj sonrası yalnızca su veya temizlik yok denmiş; hafif çift aşama temizlik cildi daha rahat bırakır.")

    g = (gender or "").lower()
    cp = (cycle_phase or "").lower()
    if g in ("female", "kadın", "kadin") and cp in ("luteal", "menstrual"):
        hints.append("Döngünün bu fazında cilt biraz daha yağlı veya hassas olabilir; rutin buna göre muhafazakâr tutuldu.")

    band = {
        "normal": "Genel tablo bugün daha sakin; rutin standart güvenli çekirdekte ilerliyor.",
        "moderate": "Birkaç yaşam faktörü bir araya gelince orta düzeyde bir yük oluşuyor; rutin buna göre hafif yumuşatıldı.",
        "high": "Stres, uyku, su ve nem gibi faktörler birlikte değerlendirilince risk bandı yükseldi; koruyucu ve yatıştırıcı adımlar öne alındı.",
        "crisis": "İşaretler yüksek yük gösteriyor; şimdilik en güvenli ve sade çekirdek rutin öneriliyor.",
    }.get(level, "Rutin, güncel yaşam verilerine göre ayarlandı.")

    body = " ".join(hints) if hints else ""
    closing = " Bu özet rutini kişiselleştirmek içindir; tıbbi tanı veya tedavi yerine geçmez."
    if body:
        return f"{body} {band}{closing}"
    return f"{band}{closing}"


def compute_risk_score(
    stress: int,
    water_intake: float,
    humidity: float,
    sleep_hours: float,
    *,
    makeup_frequency: int = 0,
    makeup_removal: str = "cleanser",
    cycle_phase: str = "",
    gender: str = "",
) -> dict:
    """
    DB'deki Faktör Skoru algoritması.
    Stres (1-10) + Su (<1.5L=5p, 1.5-2.5L=2p, >2.5L=0p) + Nem (<40%=4p, 40-60%=2p, >60%=0p)
    + Uyku (<5s=5p, 5-6.5s=3p, 6.5-7.5s=1p, >7.5s=0p)
    + Makyaj (sık kullanım / zayıf temizleme hafif puan ekler)
    + Kadın döngüsü (luteal/menstrual fazda hafif puan — sebum/hassasiyet eğilimi)
    """
    score = 0

    score += min(stress, 10)

    if water_intake < 1.0:
        score += 5
    elif water_intake < 1.5:
        score += 4
    elif water_intake < 2.0:
        score += 2
    elif water_intake < 2.5:
        score += 1

    if humidity < 25:
        score += 4
    elif humidity < 40:
        score += 3
    elif humidity < 60:
        score += 1

    if sleep_hours < 5:
        score += 5
    elif sleep_hours < 6:
        score += 3
    elif sleep_hours < 7:
        score += 2
    elif sleep_hours < 7.5:
        score += 1

    # Makyaj: günlük kullanım bariyer / gözenek yükünü artırır; yetersiz temizleme ek risk
    mf = int(makeup_frequency or 0)
    mr = (makeup_removal or "cleanser").lower()
    if mf >= 5:
        score += 1
    if mf > 0 and mr in ("none", "water"):
        score += 2

    g = (gender or "").lower()
    cp_raw = (cycle_phase or "").lower()
    if g in ("female", "kadın", "kadin") and cp_raw in ("luteal", "menstrual"):
        score += 1

    if score >= 13:
        level = "crisis"
        label = "KRİZ MODU"
    elif score >= 8:
        level = "high"
        label = "Yüksek Risk"
    elif score >= 4:
        level = "moderate"
        label = "Orta"
    else:
        level = "normal"
        label = "Normal"

    detail_user = _risk_detail_for_user(
        stress=stress,
        water_intake=water_intake,
        humidity=humidity,
        sleep_hours=sleep_hours,
        makeup_frequency=mf,
        makeup_removal=mr,
        cycle_phase=cp_raw,
        gender=g,
        level=level,
    )
    detail_formula = (
        f"Stres:{stress} + Su:{water_intake}L + Nem:{humidity}% + Uyku:{sleep_hours}s"
        f" + makyaj:{mf}/{mr} + döngü:{cp_raw or '-'} = {score}"
    )

    return {
        "score": score,
        "level": level,
        "label": label,
        "detail": detail_user,
        "detail_formula": detail_formula,
    }


# ═══════════════════════════════════════════════════════════════
# 4. YARDIMCI FONKSİYONLAR
# ═══════════════════════════════════════════════════════════════

def get_ingredient(key: str) -> dict:
    """Madde bilgisini döndür."""
    return INGREDIENT_DB.get(key, {})


def get_concentration(ingredient_key: str, context_key: str) -> dict:
    """Belirli bir maddenin belirli bir bağlamdaki konsantrasyonunu döndür."""
    ing = INGREDIENT_DB.get(ingredient_key, {})
    concs = ing.get("concentrations", {})
    return concs.get(context_key, {})


def get_risk_adjustment(ingredient_key: str, risk_level: str) -> dict:
    """Maddenin risk seviyesine göre doz ayarlamasını döndür."""
    ing = INGREDIENT_DB.get(ingredient_key, {})
    adjustments = ing.get("risk_adjustments", {})
    return adjustments.get(risk_level, adjustments.get("normal", {"freq_multiplier": 1.0, "note": ""}))


def get_daily_trigger_action(ingredient_key: str, skin_feeling: str) -> dict:
    """Günlük cilt hissine göre madde aksiyonunu döndür."""
    ing = INGREDIENT_DB.get(ingredient_key, {})
    triggers = ing.get("daily_triggers", {})
    return triggers.get(skin_feeling, {"action": "maintain", "note": "Değişiklik gerekmiyor"})


def get_skin_type_adjustment(ingredient_key: str, skin_type: str) -> dict:
    """Cilt tipine göre madde doz ayarlamasını döndür."""
    ing = INGREDIENT_DB.get(ingredient_key, {})
    adjustments = ing.get("skin_type_adjust", {})
    return adjustments.get(skin_type, {"freq_multiplier": 1.0, "note": ""})


def match_best_scenario(concern: str, skin_type: str, stress_level: str, hydration: str) -> dict:
    """Kullanıcı profiline en yakın senaryoyu eşle."""
    best_match = None
    best_score = -1

    for key, scenario in SCENARIO_PROTOCOLS.items():
        criteria = scenario.get("match_criteria", {})
        score = 0

        if criteria.get("concern") == concern:
            score += 3
        if criteria.get("skin_type") == skin_type:
            score += 2
        if criteria.get("stress") == stress_level:
            score += 1
        if criteria.get("hydration") == hydration:
            score += 1

        if score > best_score:
            best_score = score
            best_match = {"key": key, "score": score, **scenario}

    return best_match or {}


def build_ingredient_context_for_ai(ingredient_keys: list) -> str:
    """AI polish/adaptation için madde referans bilgisini text olarak oluştur."""
    lines = []
    for key in ingredient_keys:
        ing = INGREDIENT_DB.get(key)
        if not ing:
            continue
        lines.append(
            f"- {ing['name']}: {ing['evidence_level']}, "
            f"konsensüs %{ing['expert_consensus']}, "
            f"etki: {ing['clinical_efficacy']}, "
            f"süre: {ing['time_to_effect']}"
        )
        if ing.get("critical_note"):
            lines.append(f"  DİKKAT: {ing['critical_note']}")
    return "\n".join(lines)


log.info("Ingredient DB yüklendi: %d madde, %d senaryo", len(INGREDIENT_DB), len(SCENARIO_PROTOCOLS))
