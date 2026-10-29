#!/usr/bin/env python3
"""App Store "Header and Search Results" görselleri (iOS 27 ürün sayfası başlığı ve arama sonucu görseli).

    cd mobile
    REBI_STORE_SHOTS=1 flutter test test/store_screenshots_test.dart   # ham görüntüler gerekir
    python3 tool/store_creatives.py                                    # çıktı: build/store/creatives/<dil>/

Boyutlar (App Store Connect): başlık 3840×1646 (21:9), arama sonucu 3840×2560 (3:2); saydamlık yok.
Önemli içerik (ikon, ad, başlık metni) Apple'ın güvenli alanında kalır; kenarlardaki telefonlar süstür, kırpılabilir.
Yazı tipleri ve renkler store_frames.py ile aynı.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, str(Path(__file__).resolve().parent))
from store_frames import BLUSH, FOREST, FOREST_DEEP, MINT, PAPER, SAND, SRC, blob, sans, serif, wrap  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
OUT = SRC / "creatives"
ICON = ROOT / "assets" / "icon" / "icon.png"

HEADER = (3840, 1646)
HEADER_SAFE = (1097, 493, 2743, 1154)
SEARCH = (3840, 2560)
SEARCH_SAFE = (836, 765, 3004, 1795)

TEXT = {
    "tr": {
        "tagline": "Cildini tanıyan bakım asistanı",
        "search_title": "Bugünkü rutinin\nhazır",
        "search_sub": "Kişisel rutin, havaya göre güneş kremi kararı ve zamanında hatırlatmalar.",
    },
    "en": {
        "tagline": "The skincare assistant that knows your skin",
        "search_title": "Your routine,\nready for today",
        "search_sub": "A personal routine, sunscreen calls based on the weather and well-timed reminders.",
    },
}


def phone(canvas: Image.Image, raw: Path, left: int, top: int, width: int, dark_bg: bool) -> None:
    """Ekran görüntüsünü yuvarlatılmış, çerçeveli, gölgeli telefon olarak yerleştirir."""
    shot = Image.open(raw).convert("RGBA")
    h = round(shot.height * width / shot.width)
    shot = shot.resize((width, h), Image.LANCZOS)
    bezel, radius = round(width * 0.023), round(width * 0.117)
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (left - bezel, top - bezel + 40, left + width + bezel, top + h + bezel + 40),
        radius + bezel,
        fill=(0, 0, 0, 150 if dark_bg else 80),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(50)))
    ImageDraw.Draw(canvas).rounded_rectangle(
        (left - bezel, top - bezel, left + width + bezel, top + h + bezel), radius + bezel, fill=(17, 24, 23, 255)
    )
    mask = Image.new("L", (width, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, width, h), radius, fill=255)
    canvas.paste(shot, (left, top), mask)


def icon(size: int) -> tuple[Image.Image, Image.Image]:
    im = Image.open(ICON).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size, size), round(size * 0.225), fill=255)
    return im, mask


def header(lang: str) -> Image.Image:
    W, H = HEADER
    c = Image.new("RGBA", (W, H), (*FOREST_DEEP, 255))
    blob(c, (W // 2, H // 2), 900, (20, 110, 98), 150)
    blob(c, (300, 200), 700, (15, 48, 43), 255)
    blob(c, (W - 300, H - 200), 700, (15, 60, 54), 255)
    raw = SRC / lang / "apple-6.9"
    # Kenar telefonları (güvenli alanın dışında, süs).
    pw = 600
    phone(c, raw / "01-bugun.png", 380, 230, pw, True)
    phone(c, raw / "05-hatirlaticilar.png", -330, 420, pw, True)
    phone(c, raw / "03-sohbet.png", W - 380 - pw, 230, pw, True)
    phone(c, raw / "02-rutin.png", W + 330 - pw, 420, pw, True)

    # Güvenli alan: ikon + ad + slogan, ortada.
    x0, y0, x1, y1 = HEADER_SAFE
    d = ImageDraw.Draw(c)
    isz = 300
    im, mask = icon(isz)
    title_font = serif(230)
    tw = d.textlength("Rebi", font=title_font)
    gap = 60
    row_w = isz + gap + tw
    rx = (W - row_w) // 2
    ry = y0 + 40
    c.paste(im, (int(rx), ry), mask)
    d.text((rx + isz + gap, ry + isz // 2), "Rebi", font=title_font, fill=(241, 237, 228, 255), anchor="lm")
    tf = sans(64, 500)
    tag = TEXT[lang]["tagline"]
    d.text((W // 2, ry + isz + 110), tag, font=tf, fill=(234, 243, 239, 215), anchor="mm")
    assert d.textlength(tag, font=tf) <= x1 - x0, "slogan güvenli alana sığmıyor"
    return c.convert("RGB")


def search(lang: str) -> Image.Image:
    W, H = SEARCH
    c = Image.new("RGBA", (W, H), (*PAPER, 255))
    blob(c, (500, 500), 1100, MINT, 255)
    blob(c, (W - 400, 900), 1000, BLUSH, 200)
    blob(c, (900, H - 200), 1000, SAND, 210)
    x0, y0, x1, y1 = SEARCH_SAFE
    raw = SRC / lang / "apple-6.9"
    # Sağda iki telefon: arkadaki koyu mod, öndeki Bugün ekranı (öndekinin üst kısmı güvenli alanda).
    pw = 640
    phone(c, raw / "08-bugun-koyu.png", x1 - pw + 260, y0 - 60, pw, False)
    phone(c, raw / "01-bugun.png", x1 - pw - 230, y0 - 200, pw, False)

    d = ImageDraw.Draw(c)
    tx = x0 + 10
    im, mask = icon(150)
    c.paste(im, (tx, y0 + 20), mask)
    d.text((tx + 190, y0 + 95), "Rebi", font=sans(84, 650), fill=(*FOREST, 255), anchor="lm")
    fs = 150
    tf = serif(fs)
    y = y0 + 260
    for line in TEXT[lang]["search_title"].split("\n"):
        d.text((tx, y), line, font=tf, fill=(*FOREST, 255))
        y += int(fs * 1.08)
    sf = sans(60)
    y += 40
    for line in wrap(d, TEXT[lang]["search_sub"], sf, 1150):
        d.text((tx, y), line, font=sf, fill=(*FOREST, 190))
        y += 82
    assert y <= y1, "arama görseli metni güvenli alana sığmıyor"
    return c.convert("RGB")


def main() -> int:
    for lang in TEXT:
        if not (SRC / lang / "apple-6.9").is_dir():
            print("Ham görüntü yok: önce `REBI_STORE_SHOTS=1 flutter test test/store_screenshots_test.dart`.", file=sys.stderr)
            return 1
        out = OUT / lang
        out.mkdir(parents=True, exist_ok=True)
        header(lang).save(out / "header-3840x1646.png", optimize=True)
        search(lang).save(out / "search-3840x2560.png", optimize=True)
        print(f"{lang}: başlık ve arama görseli → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
