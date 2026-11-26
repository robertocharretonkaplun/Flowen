"""Copies the screenshots the UI tests take into docs/capturas, for the README and the documentation.

1. Run the UI tests in a real window, saving their captures (no -platform offscreen; connectorsFlow
   uses the clipboard, so leave it out):
       $env:FLOWEN_PREVIEW_DIR = "$env:TEMP\\flowen-capturas"
       build\\editor_test.exe formattingFlow writingFlow composeFlow askFlow templatesFlow themeFlow favoritesFlow viewModesFlow helpAboutFlow
2. python packaging/capturas.py "$env:TEMP\\flowen-capturas" docs/capturas

Each picture is scaled to 1400 px wide at most and saved as an optimised PNG.
"""
import sys
from pathlib import Path

from PIL import Image

# Name of the test's capture → name in docs/capturas.
CHOSEN = {
    "editor-flowen-oscuro": "editor",
    "formato": "formato",
    "comentario-respuesta": "comentarios",
    "crear-con-ia-propuesta": "crear-con-ia",
    "preguntar": "preguntar",
    "plantillas": "plantillas",
    "inicio-recientes": "inicio",
    "vista-lectura": "lectura",
    "vista-pagina-salto": "diseno-pagina",
    "guia-atajos": "atajos",
    "acerca-de": "acerca-de",
    "uso": "uso",
    "ia-pagina": "ia-pagina",
    # The same page in the other three themes, for the themes slide of packaging/recorrido.py.
    "editor-flowen-claro": "tema-flowen-claro",
    "editor-claro": "tema-claro",
    "editor-oscuro": "tema-oscuro",
}
WIDTH = 1400

source, out = Path(sys.argv[1]), Path(sys.argv[2])
out.mkdir(parents=True, exist_ok=True)
for name, target in CHOSEN.items():
    path = source / f"{name}.png"
    if not path.exists():
        print("falta", path)
        continue
    image = Image.open(path).convert("RGB")
    if image.width > WIDTH:
        image = image.resize((WIDTH, round(image.height * WIDTH / image.width)), Image.LANCZOS)
    image.save(out / f"{target}.png", optimize=True)
    print(out / f"{target}.png", image.size)
