"""Builds the app icons from the artwork: assets/lunqio.ico (exe and taskbar) and PNGs for the window.

Usage: python packaging/icon.py Lunquio-icon.png assets
Only the shape connected to the center is kept, so specks left by background removal disappear.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

source, out = Path(sys.argv[1]), Path(sys.argv[2])
art = Image.open(source).convert("RGBA")
w, h = art.size
alpha = art.getchannel("A")

# Solid pixels connected to the center are the icon; anything else is a leftover.
solid = alpha.point(lambda a: 255 if a > 96 else 0)
ImageDraw.floodfill(solid, (w // 2, h // 2), 128)
body = solid.point(lambda v: 255 if v == 128 else 0)
# Grow the mask by a few pixels so the soft, antialiased edge survives, then soften it.
body = body.filter(ImageFilter.MaxFilter(7)).filter(ImageFilter.GaussianBlur(1.2))
art.putalpha(Image.composite(alpha, Image.new("L", art.size, 0), body))

# Square crop around the shape with a small margin, as Windows icons have.
left, top, right, bottom = art.getchannel("A").point(lambda a: 255 if a > 8 else 0).getbbox()
side = max(right - left, bottom - top)
margin = round(side * 0.03)
side += 2 * margin
cx, cy = (left + right) / 2, (top + bottom) / 2
square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
square.paste(art, (round(side / 2 - cx), round(side / 2 - cy)))

out.mkdir(parents=True, exist_ok=True)
sizes = [16, 20, 24, 32, 40, 48, 64, 96, 128, 256]
square.resize((256, 256), Image.LANCZOS).save(out / "lunqio.ico", sizes=[(s, s) for s in sizes])
for s in (64, 256):
    square.resize((s, s), Image.LANCZOS).save(out / f"lunqio-{s}.png", optimize=True)
print(f"{source.name}: {w}x{h} -> {side}x{side}, icons in {out}")
