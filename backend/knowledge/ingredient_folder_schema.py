"""
Standard internal "folders" inside each ingredient cabinet box.
These are logical sections, not filesystem paths.
"""

from __future__ import annotations

# Every ingredient entry can expose these sections when data exists.
INGREDIENT_INTERNAL_FOLDERS: dict[str, str] = {
    "profile": "Konsantrasyon, pH, çözünürlük, hamilelik, kanıt düzeyi",
    "interactions": "Çakışma, sinerji, pH koşulu, uygulama sırası (graf kenarları)",
    "concern_links": "Hangi cilt/saç sorunları için eşleme var (priority, not)",
    "safety": "Güvenlik kuralları (hamilelik, ilaç, hassas cilt)",
    "literature": "PDF/kitap pasajları (vektör + entity index)",
}

INGREDIENT_FOLDER_SLUGS: dict[str, str] = {
    "active": "ingredients/actives",
    "oil": "ingredients/oils-botanicals",
    "extract": "ingredients/extracts",
    "peptide": "ingredients/actives",
    "retinoid": "ingredients/actives",
    "spf": "ingredients/actives",
    "other": "ingredients/actives",
}
