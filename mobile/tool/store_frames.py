#!/usr/bin/env python3
"""Mağaza görselleri: ham ekran görüntülerini başlıklı, marka renkli çerçeveye yerleştirir.

    cd mobile
    REBI_STORE_SHOTS=1 flutter test test/store_screenshots_test.dart   # ham görüntüler: build/store/<dil>/apple-6.9
    python3 tool/store_frames.py                                       # çıktı: build/store/framed/<dil>/*.png

Gereken: Pillow (`pip install pillow`). Yazı tipleri uygulamanınkiyle aynı (assets/fonts: Fraunces + Inter).
Boyut App Store iPhone 6,9" (1320×2868). Başlıklar aşağıdaki SHOTS tablosundadır; görsel yalnızca uygulamada gerçekten
olan ekranı gösterir, başlık o ekranı anlatır.
"""
from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "assets" / "fonts"
SRC = ROOT / "build" / "store"
OUT = SRC / "framed"

W, H = 1320, 2868

# Marka (lib/ui/brand/palette.dart)
PAPER = (247, 243, 236)
FOREST = (11, 61, 56)
FOREST_DEEP = (6, 43, 39)
TEAL = (20, 184, 166)
MINT, BLUSH, SAND = (211, 231, 223), (242, 218, 205), (237, 224, 200)

# (ham dosya, koyu zemin mi, {dil: (başlık, alt satır)})
SHOTS = [
    ("01-bugun", False, {
        "tr": ("Bugünkü rutinin\nhazır", "Adım adım işaretle, gün akışını tek ekranda gör."),
        "en": ("Your routine,\nready for today", "Tick off each step and see your whole day at a glance."),
    }),
    ("02-rutin", False, {
        "tr": ("Her ürünün\nnedenini gör", "Sabah ve akşam rutinin, cildine ve gününe göre."),
        "en": ("See why each\nproduct is there", "Morning and evening steps tailored to your skin and your day."),
    }),
    ("03-sohbet", False, {
        "tr": ("Gününü bilen\ncilt asistanı", "Rutinini, suyunu ve havayı bilen Rebi'ye sor."),
        "en": ("A skin assistant\nthat knows your day", "Ask Rebi, who knows your routine, water and weather."),
    }),
    ("05-hatirlaticilar", False, {
        "tr": ("Hatırlatıcılar\nsenin saatlerinde", "Kendi saat aralığını seç, sessiz saatleri tanımla."),
        "en": ("Reminders on\nyour schedule", "Pick your own time windows and set quiet hours."),
    }),
    ("07-su", False, {
        "tr": ("Suyunu tek\ndokunuşla kaydet", "Günlük hedefini takip et, yanlış girişi kolayca düzelt."),
        "en": ("Log water\nin one tap", "Track your daily goal and fix a wrong entry easily."),
    }),
    ("06-rafim", False, {
        "tr": ("Biten ürünü\nunutma", "Rafım, yenisini alana kadar hatırlatır."),
        "en": ("Never lose track of\na finished product", "My shelf reminds you until you restock."),
    }),
    ("08-bugun-koyu", True, {
        "tr": ("Karanlık modda\nda rahat", "Gece rutininde gözünü yormayan tasarım."),
        "en": ("Easy on the eyes\nin dark mode", "A calm design for your evening routine."),
    }),
]


def serif(size: int) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONTS / "Fraunces.ttf"), size)
    f.set_variation_by_axes([144, 500, 40, 0])  # opsz, wght, SOFT, WONK (uygulamadaki başlıklarla aynı)
    return f


def sans(size: int, weight: int = 450) -> ImageFont.FreeTypeFont:
    f = ImageFont.truetype(str(FONTS / "InterVariable.ttf"), size)
    f.set_variation_by_axes([32, weight])
    return f


def blob(canvas: Image.Image, center: tuple[int, int], radius: int, color: tuple[int, int, int], alpha: int) -> None:
    # Saydam pikseller de aynı renkte: bulanıklaştırınca kenarlar griye kaymasın.
    layer = Image.new("RGBA", canvas.size, (*color, 0))
    d = ImageDraw.Draw(layer)
    x, y = center
    d.ellipse((x - radius, y - radius, x + radius, y + radius), fill=(*color, alpha))
    canvas.alpha_composite(layer.filter(ImageFilter.GaussianBlur(radius // 2)))


def wrap(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, width: int) -> list[str]:
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=font) <= width:
            line = trial
        else:
            lines.append(line)
            line = word
    return [*lines, line] if line else lines


def frame(raw: Path, dark: bool, title: str, subtitle: str) -> Image.Image:
    bg = FOREST_DEEP if dark else PAPER
    ink = (234, 243, 239) if dark else FOREST
    soft = (*ink, 190)
    canvas = Image.new("RGBA", (W, H), (*bg, 255))
    if dark:
        blob(canvas, (180, 380), 520, (15, 48, 43), 255)
        blob(canvas, (1220, 1500), 620, (20, 90, 80), 140)
    else:
        blob(canvas, (160, 360), 560, MINT, 255)
        blob(canvas, (1250, 1250), 600, BLUSH, 200)
        blob(canvas, (200, 2500), 620, SAND, 210)

    draw = ImageDraw.Draw(canvas)
    # Küçük marka satırı
    draw.ellipse((110, 150, 136, 176), fill=(*TEAL, 255))
    draw.text((152, 140), "Rebi", font=sans(40, 650), fill=(*ink, 255))

    # Başlık: satırlar elle bölünmüş; yine de sığmazsa punto küçülür.
    size = 128
    while True:
        tf = serif(size)
        if all(draw.textlength(l, font=tf) <= W - 220 for l in title.split("\n")) or size <= 80:
            break
        size -= 4
    y = 250
    for line in title.split("\n"):
        draw.text((110, y), line, font=tf, fill=(*ink, 255))
        y += int(size * 1.08)
    sf = sans(46)
    y += 34
    for line in wrap(draw, subtitle, sf, W - 220):
        draw.text((110, y), line, font=sf, fill=soft)
        y += 62

    # Telefon: ekran görüntüsü yuvarlatılmış, ince çerçeveli, gölgeli.
    shot = Image.open(raw).convert("RGBA")
    pw = 940
    ph = round(shot.height * pw / shot.width)
    shot = shot.resize((pw, ph), Image.LANCZOS)
    bezel, radius = 22, 110
    top = max(y + 70, 760)
    left = (W - pw) // 2
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (left - bezel, top - bezel + 30, left + pw + bezel, top + ph + bezel + 30), radius + bezel, fill=(0, 0, 0, 90 if not dark else 140)
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(40)))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        (left - bezel, top - bezel, left + pw + bezel, top + ph + bezel), radius + bezel, fill=(17, 24, 23, 255)
    )
    mask = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, pw, ph), radius, fill=255)
    canvas.paste(shot, (left, top), mask)
    # Alttan taşan kısım kesilir (telefon görselin altına doğru devam ediyormuş gibi).
    return canvas.convert("RGB")


def main() -> int:
    langs = [p.name for p in SRC.iterdir() if (p / "apple-6.9").is_dir()] if SRC.is_dir() else []
    if not langs:
        print("Ham görüntü yok: önce `REBI_STORE_SHOTS=1 flutter test test/store_screenshots_test.dart`.", file=sys.stderr)
        return 1
    for lang in sorted(langs):
        out = OUT / lang
        out.mkdir(parents=True, exist_ok=True)
        for i, (name, dark, texts) in enumerate(SHOTS, start=1):
            raw = SRC / lang / "apple-6.9" / f"{name}.png"
            title, subtitle = texts[lang]
            frame(raw, dark, title, subtitle).save(out / f"{i:02d}-{name.split('-', 1)[1]}.png", optimize=True)
        print(f"{lang}: {len(SHOTS)} görsel → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
