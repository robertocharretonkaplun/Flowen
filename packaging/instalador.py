"""Builds the pictures of Flowen's setup wizard (FlowenInnoSetup.iss) into assets/instalador:

    panel-claro-*.png / panel-oscuro-*.png   the tall picture of the Welcome and Finish pages
    icono-*.png                              the small picture at the top right of the other pages

Light and dark versions follow Windows (Inno Setup's WizardStyle=modern dynamic), at 100, 150, 200
and 250 % so the wizard stays sharp on high-density screens.

Usage, from the repository (Windows, for the Segoe UI fonts; Pillow required):
    python packaging/instalador.py
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets/instalador"
SCALES = [1, 1.5, 2, 2.5]
PANEL = (164, 314)          # Inno Setup's size at 100 %
SMALL = (55, 55)
THEMES = {
    # Flowen claro and Flowen oscuro (qml/Theme.qml): canvas, a slightly deeper band, title, line.
    "claro": {"canvas": (255, 249, 240), "band": (248, 237, 221), "title": (44, 19, 18), "line": (101, 84, 78),
              "brand": "ao-lockup-ink.png"},
    "oscuro": {"canvas": (35, 27, 25), "band": (42, 32, 30), "title": (251, 241, 224), "line": (200, 183, 172),
               "brand": "ao-lockup-white.png"},
}
FONTS = Path("C:/Windows/Fonts")


def font(name, size):
    try:
        return ImageFont.truetype(str(FONTS / name), size)
    except OSError:
        return ImageFont.load_default(size)


def icon(size):
    art = Image.open(ROOT / "assets/flowen-256.png").convert("RGBA")
    return art.resize((size, size), Image.LANCZOS)


def panel(theme, scale):
    w, h = round(PANEL[0] * scale), round(PANEL[1] * scale)
    c = THEMES[theme]
    image = Image.new("RGB", (w, h), c["canvas"])
    draw = ImageDraw.Draw(image)
    # A soft band behind the icon, as the page header of Flowen.
    draw.rectangle((0, 0, w, round(150 * scale)), fill=c["band"])
    mark = icon(round(72 * scale))
    image.paste(mark, ((w - mark.width) // 2, round(48 * scale)), mark)
    title = font("seguisb.ttf", round(26 * scale))
    draw.text((w // 2, round(170 * scale)), "Flowen", font=title, fill=c["title"], anchor="mm")
    line = font("segoeui.ttf", round(11.5 * scale))
    for i, text in enumerate(["Notas, páginas y tareas", "para Windows"]):
        draw.text((w // 2, round((196 + i * 16) * scale)), text, font=line, fill=c["line"], anchor="mm")
    # The studio at the foot.
    brand = Image.open(ROOT / "assets/brand" / c["brand"]).convert("RGBA")
    bw = round(118 * scale)
    brand = brand.resize((bw, round(brand.height * bw / brand.width)), Image.LANCZOS)
    image.paste(brand, ((w - bw) // 2, h - brand.height - round(18 * scale)), brand)
    return image


def small(scale):
    w, h = round(SMALL[0] * scale), round(SMALL[1] * scale)
    image = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    mark = icon(round(46 * scale))
    image.alpha_composite(mark, ((w - mark.width) // 2, (h - mark.height) // 2))
    return image


OUT.mkdir(parents=True, exist_ok=True)
for scale in SCALES:
    tag = f"{round(scale * 100)}"
    for theme in THEMES:
        panel(theme, scale).save(OUT / f"panel-{theme}-{tag}.png", optimize=True)
    small(scale).save(OUT / f"icono-{tag}.png", optimize=True)
print("\n".join(sorted(p.name for p in OUT.iterdir())))
