"""Builds docs/capturas/recorrido.gif: a short tour of Flowen that changes view every few seconds, for
the top of the README (GitHub shows no scripts, so an animated image stands in for a carousel).

Usage, from the repository (Windows, for the Segoe UI fonts; Pillow required):
    python packaging/recorrido.py docs/capturas
It reads the screenshots of docs/capturas (see packaging/capturas.py) and first writes temas.png, the
same page in the four themes.
Each slide: the Flowen icon, a title and one line on Flowen oscuro's dark canvas, the screenshot in a
rounded frame, and dots that show where the tour is.
"""
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
SLIDES = [
    ("editor.png", "Escribe como en Notion", "Bloques, «/», Markdown, enlaces entre páginas y arrastrar para ordenar."),
    ("diseno-pagina.png", "Diseño de página, como en Word", "Hojas Carta o A4 con márgenes, y un PDF del mismo tamaño."),
    ("crear-con-ia.png", "Crea con IA", "Claude o Codex escriben bloques nuevos; tú decides si entran."),
    ("preguntar.png", "Pregunta sobre tus notas", "Respuestas con las páginas de donde salen."),
    ("comentarios.png", "Comenta y revisa", "Hilos con respuestas al margen, como en Google Docs."),
    ("temas.png", "Cuatro temas", "Flowen oscuro y claro, Claro y Oscuro."),
]
WIDTH, HEIGHT = 1200, 880
BOX = (60, 128, 1140, 822)            # where the screenshot goes
BACKGROUND, FRAME = (27, 20, 18), (70, 54, 49)
TITLE, LINE, DOT, CURRENT = (251, 241, 224), (200, 183, 172), (91, 70, 64), (255, 121, 89)
SECONDS = 3.6

FONTS = Path("C:/Windows/Fonts")
def font(name, size):
    try:
        return ImageFont.truetype(str(FONTS / name), size)
    except OSError:
        return ImageFont.load_default(size)

def slide(index, picture, title, line):
    canvas = Image.new("RGB", (WIDTH, HEIGHT), BACKGROUND)
    draw = ImageDraw.Draw(canvas)
    icon = Image.open(ROOT / "assets/flowen-64.png").convert("RGBA").resize((46, 46), Image.LANCZOS)
    canvas.paste(icon, (BOX[0], 36), icon)
    draw.text((BOX[0] + 62, 30), title, font=font("seguisb.ttf", 34), fill=TITLE)
    draw.text((BOX[0] + 63, 78), line, font=font("segoeui.ttf", 19), fill=LINE)
    # The screenshot, as large as the box allows, centred, with rounded corners and a thin frame.
    shot = Image.open(picture).convert("RGB")
    bw, bh = BOX[2] - BOX[0], BOX[3] - BOX[1]
    scale = min(bw / shot.width, bh / shot.height)
    shot = shot.resize((round(shot.width * scale), round(shot.height * scale)), Image.LANCZOS)
    x, y = BOX[0] + (bw - shot.width) // 2, BOX[1] + (bh - shot.height) // 2
    mask = Image.new("L", shot.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, shot.width - 1, shot.height - 1), radius=12, fill=255)
    draw.rounded_rectangle((x - 2, y - 2, x + shot.width + 1, y + shot.height + 1), radius=14, fill=FRAME)
    canvas.paste(shot, (x, y), mask)
    # Where the tour is.
    gap, size = 22, 8
    start = WIDTH // 2 - (len(SLIDES) * gap) // 2
    for i in range(len(SLIDES)):
        cx = start + i * gap + gap // 2
        r = size // 2 + (1 if i == index else 0)
        draw.ellipse((cx - r, 852 - r, cx + r, 852 + r), fill=CURRENT if i == index else DOT)
    return canvas

def themes(out):
    """temas.png: the same page in the four themes, two by two, each with its name."""
    shots = [("editor.png", "Flowen oscuro"), ("tema-flowen-claro.png", "Flowen claro"),
             ("tema-oscuro.png", "Oscuro"), ("tema-claro.png", "Claro")]
    cell, label, gap = 1000, 56, 40
    images = []
    for name, title in shots:
        shot = Image.open(out / name).convert("RGB")
        images.append((shot.resize((cell, round(shot.height * cell / shot.width)), Image.LANCZOS), title))
    tall = max(img.height for img, _ in images)
    grid = Image.new("RGB", (2 * cell + 3 * gap, 2 * (tall + label) + 3 * gap - 10), BACKGROUND)
    draw = ImageDraw.Draw(grid)
    for i, (img, title) in enumerate(images):
        x, y = gap + (i % 2) * (cell + gap), gap - 10 + (i // 2) * (tall + label + gap)
        draw.text((x, y), title, font=font("seguisb.ttf", 30), fill=TITLE)
        grid.paste(img, (x, y + label))
    grid.save(out / "temas.png", optimize=True)

out = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "docs/capturas"
themes(out)
frames = [slide(i, out / name, title, line) for i, (name, title, line) in enumerate(SLIDES)]
# One palette per slide and no dithering: flat colours and crisp text.
frames = [f.quantize(colors=256, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE) for f in frames]
frames[0].save(out / "recorrido.gif", save_all=True, append_images=frames[1:], duration=int(SECONDS * 1000),
               loop=0, optimize=True, disposal=1)
print(out / "recorrido.gif", f"{(out / 'recorrido.gif').stat().st_size // 1024} KB")
