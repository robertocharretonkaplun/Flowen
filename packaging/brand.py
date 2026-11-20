"""Builds the Attribute Overload lockups the app shows in Acerca de, from the studio's artwork.

Usage: python packaging/brand.py assets/brand/AO_Lockup_Compact_ColorAndWhite.png assets/brand
Writes ao-lockup-white.png (the artwork as is: colour mark, white name, for dark themes),
ao-lockup-ink.png (the same with the name in ink, for light themes) and ao-lockup-badge.png (the white
one on a dark panel, for the README), cropped to the drawing and
560 px wide, enough for the dialog on high-density screens.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw

INK = (30, 30, 30)
WIDTH = 560

source, out = Path(sys.argv[1]), Path(sys.argv[2])
art = Image.open(source).convert("RGBA")
left, top, right, bottom = art.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
margin = round((bottom - top) * 0.06)
art = art.crop((max(0, left - margin), max(0, top - margin), min(art.width, right + margin), min(art.height, bottom + margin)))
art = art.resize((WIDTH, round(art.height * WIDTH / art.width)), Image.LANCZOS)

# The name is the only white in the drawing (the mark is teal and red): give it the ink colour.
ink = art.copy()
pixels = ink.load()
for y in range(ink.height):
    for x in range(ink.width):
        r, g, b, a = pixels[x, y]
        if a and min(r, g, b) > 150 and max(r, g, b) - min(r, g, b) < 40:
            pixels[x, y] = (*INK, a)

out.mkdir(parents=True, exist_ok=True)
art.save(out / "ao-lockup-white.png", optimize=True)
ink.save(out / "ao-lockup-ink.png", optimize=True)

# For the README and the documentation site, which may be light or dark: the white lockup on a
# rounded panel of Lunqio oscuro's canvas, readable on any page.
pad_x, pad_y, radius = 36, 26, 22
badge = Image.new("RGBA", (art.width + 2 * pad_x, art.height + 2 * pad_y), (0, 0, 0, 0))
panel = Image.new("RGBA", badge.size, (35, 27, 25, 255))
mask = Image.new("L", badge.size, 0)
ImageDraw.Draw(mask).rounded_rectangle((0, 0, badge.width - 1, badge.height - 1), radius=radius, fill=255)
badge.paste(panel, (0, 0), mask)
badge.alpha_composite(art, (pad_x, pad_y))
badge.save(out / "ao-lockup-badge.png", optimize=True)
print(out / "ao-lockup-white.png", art.size)
