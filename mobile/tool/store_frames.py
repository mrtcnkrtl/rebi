#!/usr/bin/env python3
"""Mağaza görselleri: ham ekran görüntülerini başlıklı, marka renkli çerçeveye yerleştirir.

    cd mobile
    REBI_STORE_SHOTS=1 flutter test test/store_screenshots_test.dart   # ham görüntüler: build/store/<dil>/apple-6.9
    python3 tool/store_frames.py                                       # çıktı: build/store/framed/<dil>/<biçim>/*.png

Gereken: Pillow (`pip install pillow`). Yazı tipleri uygulamanınkiyle aynı (assets/fonts: Fraunces + Inter).
Boyutlar: iPhone 6,9" ve 6,3", iPhone Duo dış/iç ekran ve iPad 13" (FORMATS). Başlıklar aşağıdaki SHOTS tablosundadır; görsel yalnızca uygulamada gerçekten
olan ekranı gösterir, başlık o ekranı anlatır.
"""
from __future__ import annotations

import shutil
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / "assets" / "fonts"
SRC = ROOT / "build" / "store"
OUT = SRC / "framed"


# Marka (lib/ui/brand/palette.dart)
PAPER = (247, 243, 236)
FOREST = (11, 61, 56)
FOREST_DEEP = (6, 43, 39)
TEAL = (20, 184, 166)
MINT, BLUSH, SAND = (211, 231, 223), (242, 218, 205), (237, 224, 200)

# (ham dosya, koyu zemin mi, {dil: (başlık, alt satır)}[, yalnızca bu biçimlerde])
# Su kaydı alttan açılan bir pencere olduğu için iPad'de (alttan taşan çerçeve) kesilir; iPad setine alınmaz.
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
    }, {"apple-6.9", "apple-6.3", "apple-duo-dis", "apple-duo-ic"}),
    ("04-gecmis", False, {
        "tr": ("İlerlemeni\ntakip et", "Su, uyku, stres ve rutin grafikleri tek bakışta."),
        "en": ("Track your\nprogress", "Water, sleep, stress and routine charts at a glance."),
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


def frame(raw: Path, dark: bool, title: str, subtitle: str, size: tuple[int, int], tablet: bool, bleed: bool) -> Image.Image:
    W, H = size
    # Ölçü birimi: 6,9" iPhone (1320×2868) = 1. Geniş/kısa tuvallerde (Duo, iPad) yazı yüksekliğe göre sınırlanır.
    u = min(W / 1320, H / 2000)
    sx, sy = W / 1320, H / 2868
    mx = round(110 * sx)
    bg = FOREST_DEEP if dark else PAPER
    ink = (234, 243, 239) if dark else FOREST
    soft = (*ink, 190)
    canvas = Image.new("RGBA", (W, H), (*bg, 255))
    if dark:
        blob(canvas, (round(180 * sx), round(380 * sy)), round(520 * sx), (15, 48, 43), 255)
        blob(canvas, (round(1220 * sx), round(1500 * sy)), round(620 * sx), (20, 90, 80), 140)
    else:
        blob(canvas, (round(160 * sx), round(360 * sy)), round(560 * sx), MINT, 255)
        blob(canvas, (round(1250 * sx), round(1250 * sy)), round(600 * sx), BLUSH, 200)
        blob(canvas, (round(200 * sx), round(2500 * sy)), round(620 * sx), SAND, 210)

    draw = ImageDraw.Draw(canvas)
    # Küçük marka satırı
    top0 = round(140 * u)
    dot = round(26 * u)
    draw.ellipse((mx, top0 + round(10 * u), mx + dot, top0 + round(10 * u) + dot), fill=(*TEAL, 255))
    draw.text((mx + round(42 * u), top0), "Rebi", font=sans(round(40 * u), 650), fill=(*ink, 255))

    # Başlık: satırlar elle bölünmüş; yine de sığmazsa punto küçülür.
    fs = round(128 * u)
    while True:
        tf = serif(fs)
        if all(draw.textlength(l, font=tf) <= W - 2 * mx for l in title.split("\n")) or fs <= 80 * u:
            break
        fs -= 4
    y = round(250 * u)
    for line in title.split("\n"):
        draw.text((mx, y), line, font=tf, fill=(*ink, 255))
        y += int(fs * 1.08)
    sf = sans(round(46 * u))
    y += round(34 * u)
    for line in wrap(draw, subtitle, sf, W - 2 * mx):
        draw.text((mx, y), line, font=sf, fill=soft)
        y += round(62 * u)

    # Cihaz: ekran görüntüsü yuvarlatılmış, ince çerçeveli, gölgeli. Kısa tuvallerde (bleed) cihaz büyük çizilir ve
    # alttan taşar; yoksa içerik okunamayacak kadar küçülürdü.
    shot = Image.open(raw).convert("RGBA")
    aspect = shot.height / shot.width
    top = max(y + round(70 * u), round(760 * u))
    pw = round(0.84 * W) if bleed else round(min(0.712 * W, (H - top - 66 * u) / aspect))
    ph = round(pw * aspect)
    shot = shot.resize((pw, ph), Image.LANCZOS)
    bezel = round(22 * u)
    radius = round(pw * (0.035 if tablet else 0.117))
    left = (W - pw) // 2
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        (left - bezel, top - bezel + round(30 * u), left + pw + bezel, top + ph + bezel + round(30 * u)),
        radius + bezel,
        fill=(0, 0, 0, 90 if not dark else 140),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(round(40 * u))))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        (left - bezel, top - bezel, left + pw + bezel, top + ph + bezel), radius + bezel, fill=(17, 24, 23, 255)
    )
    mask = Image.new("L", (pw, ph), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, pw, ph), radius, fill=255)
    canvas.paste(shot, (left, top), mask)
    return canvas.convert("RGB")


# Ham görüntü klasörü → (çıktı boyutu, tablet çerçevesi mi, cihaz alttan taşsın mı). Ham boyutlar test/store_screenshots_test.dart'taki gibi.
FORMATS = {
    "apple-6.9": ((1320, 2868), False, False),  # iPhone 6,9"
    "apple-6.3": ((1206, 2622), False, False),  # iPhone 6,3" (zorunlu boyut)
    "apple-duo-dis": ((1398, 2034), False, False),  # iPhone Duo dış ekran
    "apple-duo-ic": ((2007, 2853), False, True),  # iPhone Duo iç ekran
    "apple-ipad-13": ((2064, 2752), True, True),  # iPad 13"
}


def main() -> int:
    langs = [p.name for p in SRC.iterdir() if (p / "apple-6.9").is_dir()] if SRC.is_dir() else []
    if not langs:
        print("Ham görüntü yok: önce `REBI_STORE_SHOTS=1 flutter test test/store_screenshots_test.dart`.", file=sys.stderr)
        return 1
    for lang in sorted(langs):
        for fmt, (size, tablet, bleed) in FORMATS.items():
            out = OUT / lang / fmt
            shutil.rmtree(out, ignore_errors=True)  # eski adlarla kalan görseller mağazaya karışmasın
            out.mkdir(parents=True)
            shots = [s for s in SHOTS if len(s) < 4 or fmt in s[3]]
            for i, (name, dark, texts, *_) in enumerate(shots, start=1):
                raw = SRC / lang / fmt / f"{name}.png"
                title, subtitle = texts[lang]
                frame(raw, dark, title, subtitle, size, tablet, bleed).save(out / f"{i:02d}-{name.split('-', 1)[1]}.png", optimize=True)
            print(f"{lang}/{fmt}: {len(shots)} görsel → {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
