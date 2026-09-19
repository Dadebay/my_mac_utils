"""Paylaşım görseli (og.png) üretir.

Site tokenlarıyla aynı renkler ve aynı Gilroy ailesi kullanılıyor, böylece
Slack/X/WhatsApp önizlemesi sayfanın kendisiyle aynı görünüyor. Elle
tasarlanmış bir PNG yerine betik olmasının sebebi: metin değiştiğinde
yeniden üretilebilsin.

Çalıştırma:  python3 scripts/make-og.py
"""

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

W, H = 1200, 630
BG = (10, 11, 15)
FG = (242, 243, 247)
MUTED = (166, 172, 187)
TEAL = (62, 217, 196)
VIOLET = (124, 111, 255)

FONTS = "public/fonts/gilroy"


def glow(canvas, center, radius, color, strength):
    """Sayfadaki `.glow-*` sınıflarının karşılığı: yumuşak renkli ışık.

    Işık katmanı arka planın üstüne toplanarak ekleniyor (ImageChops.add),
    yani karartmadan aydınlatıyor — CSS'teki `screen` karışımıyla aynı etki.
    """
    layer = Image.new("RGB", (W, H), (0, 0, 0))
    ImageDraw.Draw(layer).ellipse(
        [center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius],
        fill=tuple(int(c * strength) for c in color),
    )
    layer = layer.filter(ImageFilter.GaussianBlur(radius * 0.55))
    return ImageChops.add(canvas, layer)


img = Image.new("RGB", (W, H), BG)
img = glow(img, (170, 120), 420, VIOLET, 0.30)
img = glow(img, (1050, 560), 420, TEAL, 0.22)

draw = ImageDraw.Draw(img)

title = ImageFont.truetype(f"{FONTS}/Gilroy-Bold.ttf", 108)
sub = ImageFont.truetype(f"{FONTS}/Gilroy-Medium.ttf", 42)
small = ImageFont.truetype(f"{FONTS}/Gilroy-SemiBold.ttf", 26)

draw.text((96, 186), "GlassDo", font=title, fill=FG)
draw.text((96, 322), "A calmer command center", font=sub, fill=MUTED)
draw.text((96, 376), "for your Mac.", font=sub, fill=MUTED)

# Alt rozet: kenarlık + metin, sitedeki cam yüzeylerle aynı ton.
badge = "macOS 26  ·  Free  ·  Fully local"
tw = draw.textlength(badge, font=small)
draw.rounded_rectangle([96, 470, 96 + tw + 56, 470 + 58], radius=29, outline=(255, 255, 255, 40), width=2)
draw.text((96 + 28, 470 + 15), badge, font=small, fill=FG)

img.save("public/og.png", optimize=True)
print("public/og.png", img.size)
