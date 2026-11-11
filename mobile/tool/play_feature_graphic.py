#!/usr/bin/env python3
"""Google Play "Özellik grafiği" (feature graphic): 1024×500 PNG, en fazla 15 MB, saydamlık yok.

    cd mobile
    REBI_STORE_SHOTS=1 flutter test test/store_screenshots_test.dart   # ham görüntüler gerekir
    python3 tool/play_feature_graphic.py                               # çıktı: build/store/play-feature/<dil>/feature-graphic-1024x500.png

Play'de bu görsel mağaza sayfasının en üstünde ve öne çıkarma alanlarında kırpılarak gösterilir; bir tanıtım videosu eklenirse
ortasına oynat düğmesi biner. Bu yüzden metin sol tarafta toplanır, orta üst bölge boş bırakılır ve telefonlar yalnızca süstür.
2× çizilip LANCZOS ile küçültülür (kenarlar ve küçük yazı keskin kalsın). Yazı tipleri ve renkler store_frames.py ile aynı.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from store_frames import FOREST_DEEP, SRC, TEAL, blob, sans, serif  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = SRC / "play-feature"
ICON = ROOT / "assets" / "icon" / "icon.png"

W, H = 1024, 500
S = 2  # çizim ölçeği

TEXT = {
    "tr": {"head": "Cildini tanıyan\nbakım asistanı", "sub": "Kişisel rutin · hava durumuna göre SPF · zamanında hatırlatma"},
    "en": {"head": "The skincare assistant\nthat knows your skin", "sub": "Personal routine · weather-based SPF · well-timed reminders"},
}
CREAM = (241, 237, 228)
MIST = (234, 243, 239)


def phone(canvas: Image.Image, raw: Path, left: int, top: int, width: int) -> None:
    """Ekran görüntüsünü yuvarlatılmış, çerçeveli, gölgeli telefon olarak yerleştirir (alttan taşabilir)."""
    shot = Image.open(raw).convert("RGBA")
    h = round(shot.height * width / shot.width)
    shot = shot.resize((width, h), Image.LANCZOS)
    bezel, radius = round(width * 0.03), round(width * 0.117)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (left - bezel, top - bezel + 14 * S, left + width + bezel, top + h + bezel + 14 * S), radius + bezel, fill=(0, 0, 0, 170)
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(18 * S)))
    ImageDraw.Draw(canvas).rounded_rectangle(
        (left - bezel, top - bezel, left + width + bezel, top + h + bezel), radius + bezel, fill=(17, 24, 23, 255)
    )
    mask = Image.new("L", (width, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width, h), radius, fill=255)
    canvas.paste(shot, (left, top), mask)


def render(lang: str) -> Image.Image:
    w, h = W * S, H * S
    c = Image.new("RGBA", (w, h), (*FOREST_DEEP, 255))
    # Zemin: sağda telefonların arkasında soluk turkuaz ışık, sol altta koyu yeşil derinlik.
    blob(c, (round(0.80 * w), round(0.42 * h)), 330 * S, (20, 110, 98), 170)
    blob(c, (round(0.10 * w), round(0.95 * h)), 300 * S, (15, 48, 43), 255)
    blob(c, (round(0.42 * w), round(0.02 * h)), 220 * S, (15, 60, 54), 200)

    raw = SRC / lang / "play-telefon"
    # Arkada Sohbet, önde Bugün; öndeki alttan taşar (alt gezinme çubuğu kesilir).
    phone(c, raw / "03-sohbet.png", 806 * S, 58 * S, 176 * S)
    phone(c, raw / "01-bugun.png", 600 * S, 96 * S, 200 * S)

    d = ImageDraw.Draw(c)
    x = 72 * S
    isz = 76 * S
    icon = Image.open(ICON).convert("RGBA").resize((isz, isz), Image.LANCZOS)
    mask = Image.new("L", (isz, isz), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, isz, isz), round(isz * 0.225), fill=255)
    top = 88 * S
    c.paste(icon, (x, top), mask)
    d.text((x + isz + 22 * S, top + isz // 2), "Rebi", font=serif(60 * S), fill=(*CREAM, 255), anchor="lm")

    # Başlık: iki satır, elle bölünmüş; metin alanı telefonların soluyla (606) sınırlı.
    limit = 606 * S - 36 * S - x
    fs = 46 * S
    while True:
        tf = serif(fs)
        if all(d.textlength(line, font=tf) <= limit for line in TEXT[lang]["head"].split("\n")) or fs <= 30 * S:
            break
        fs -= S
    y = top + isz + 52 * S
    for line in TEXT[lang]["head"].split("\n"):
        d.text((x, y), line, font=tf, fill=(*CREAM, 255))
        y += int(fs * 1.12)

    # Küçük nokta ayraçlı özellik satırı (teal nokta, markanın küçük imi).
    sf = sans(15 * S, 500)
    sub = TEXT[lang]["sub"]
    y += 18 * S
    d.ellipse((x, y + 4 * S, x + 9 * S, y + 13 * S), fill=(*TEAL, 255))
    d.text((x + 20 * S, y), sub, font=sf, fill=(*MIST, 205))
    assert x + 20 * S + d.textlength(sub, font=sf) <= 606 * S - 20 * S, "özellik satırı telefonlara taşıyor"
    assert y + 20 * S <= h - 40 * S, "metin alt güvenli kenara taşıyor"
    return c.resize((W, H), Image.LANCZOS).convert("RGB")


def main() -> int:
    for lang in TEXT:
        if not (SRC / lang / "play-telefon").is_dir():
            print("Ham görüntü yok: önce `REBI_STORE_SHOTS=1 flutter test test/store_screenshots_test.dart`.", file=sys.stderr)
            return 1
        out = OUT / lang
        out.mkdir(parents=True, exist_ok=True)
        target = out / "feature-graphic-1024x500.png"
        render(lang).save(target, optimize=True)
        print(f"{lang}: özellik grafiği → {target}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
