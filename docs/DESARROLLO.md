# Desarrollo

Cómo compilar, probar, documentar y empaquetar Flowen, y qué promete su contrato MCP. La organización del código está en [Arquitectura](ARQUITECTURA.md). Los comandos se ejecutan desde la raíz del repositorio.

## Documentación

La documentación del código está en **[robertocharretonkaplun.github.io/Flowen](https://robertocharretonkaplun.github.io/Flowen/)**: una portada, la [guía de uso](GUIA.md), la [arquitectura](ARQUITECTURA.md), esta página y las clases y funciones de `src/` con sus diagramas. La genera [Doxygen](https://www.doxygen.nl) con `docs/Doxyfile` y la publica GitHub Actions (`.github/workflows/docs.yml`) en GitHub Pages cada vez que cambian `src/`, `docs/` o las imágenes en `main`. También se puede lanzar a mano desde la pestaña **Actions**.

Para activarla una sola vez en GitHub: **Settings → Pages → Build and deployment → Source: GitHub Actions**. En un repositorio privado, GitHub Pages requiere un plan que lo permita.

Para generarla en tu equipo (Doxygen 1.9.5 o posterior; Graphviz es opcional, para los diagramas), desde la raíz:

```powershell
doxygen docs/Doxyfile
start build-docs\html\index.html
```

Los comentarios `///` de los encabezados (`src/**/*.h`) son los que aparecen en la documentación. La interfaz QML no la lee Doxygen; está descrita en [Arquitectura](ARQUITECTURA.md).

Las capturas de `docs/capturas` salen de las pruebas de la interfaz. Para rehacerlas, ejecuta las pruebas en una ventana real con `FLOWEN_PREVIEW_DIR` y copia las elegidas con `python packaging/capturas.py` (el script explica los pasos). `python packaging/recorrido.py docs/capturas` rehace con ellas el recorrido animado del README (`recorrido.gif`) y la imagen de los cuatro temas.

## Compilar y probar

El entorno de referencia utiliza Windows x64, C++17, Qt 6.8.3 para MSVC 2022 x64 (Base, Declarative y SVG), Qt SQL con QSQLITE, Visual Studio con herramientas C++, CMake 3.22 o posterior y Ninja. Las pruebas requieren Python 3.11 o posterior y Qt Test. El paquete compilado incluye el runtime de Visual C++. El inventario del SDK identifica SQLite 3.49.1. [Licencias de Qt](https://doc.qt.io/qt-6.8/licensing.html)

Desde **Developer PowerShell for VS** con herramientas x64, en la raíz del repositorio:

```powershell
$qt = 'C:\Qt\6.8.3\msvc2022_64'
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release "-DCMAKE_PREFIX_PATH=$qt"
cmake --build build
ctest --test-dir build --output-on-failure
.\packaging\windows.ps1 -BuildDir build -QtDir $qt
```

Si Visual Studio no ha definido `VCToolsRedistDir`, indica `-CrtDir` con la ruta absoluta de la carpeta redistribuible x64 `Microsoft.VC*.CRT`. El empaquetado produce `dist/Flowen-x64` y `dist/Flowen-x64.zip`. Acepta `-OutputDir` para crear otra distribución. [Despliegue de Qt en Windows](https://doc.qt.io/qt-6/windows-deployment.html)

El icono de la aplicación sale de `Lunquio-icon.png`, en la raíz. Si cambias la imagen, regenera `assets/flowen.ico` y los PNG con `python packaging/icon.py Lunquio-icon.png assets` (requiere Pillow) y vuelve a compilar. El script descarta los restos sueltos alrededor del cuadro.

La organización del código (biblioteca, servidor MCP, editor e interfaz) y las reglas para ampliarlo están en [Arquitectura](ARQUITECTURA.md).

Para repetir la prueba con el cliente Codex instalado, ejecuta `python tests/codex_smoke.py dist/Flowen-x64/notas-mcp.exe` desde el repositorio. Esta prueba usa una biblioteca temporal y las llamadas locales del app-server de Codex. Se verificó con `codex-cli 0.169.0-alpha.11.1`.

## Publicar una versión

El botón **Descargar** del README lleva a la última versión publicada en GitHub (Releases). Para publicar una, compila y empaqueta (arriba) y sube el zip, por ejemplo con [GitHub CLI](https://cli.github.com):

```powershell
gh release create v0.5.0 dist\Flowen-x64.zip --title "Flowen 0.5.0" --notes "Novedades de esta versión."
```

Usa la misma versión que `project(Flowen VERSION …)` en `CMakeLists.txt`, que es la que muestra **Acerca de Flowen**.

## Contrato y persistencia

El servidor implementa directamente el subconjunto JSON-RPC de MCP por stdio. Negocia las versiones 2025-11-25, 2025-06-18 y 2025-03-26. Publica sus esquemas y anotaciones mediante `tools/list`. El catálogo oficial de SDK consultado carece de SDK C++ oficial. [SDK de MCP](https://modelcontextprotocol.io/docs/sdk) · [Ciclo de vida](https://modelcontextprotocol.io/specification/2025-11-25/basic/lifecycle) · [Herramientas](https://modelcontextprotocol.io/specification/2025-11-25/server/tools)

| Herramienta | Uso |
| --- | --- |
| `list_pages` | Hijas de un padre o páginas de la raíz. `trashed: true` consulta la papelera. |
| `search_notes` | Búsqueda literal en títulos y bloques activos con un fragmento por página. |
| `get_page` | Metadatos y bloques ordenados de la página. |
| `create_page` | Crear con título, padre opcional y bloques iniciales. |
| `update_page` | Cambiar título o padre. El valor JSON `null` selecciona la raíz. |
| `apply_block_changes` | Insertar, sustituir, mover o quitar bloques en una sola transacción. La operación `replace_text` recibe el identificador del bloque, el desplazamiento `start` en unidades UTF-16, el texto `original` y su `replacement`. |
| `trash_page`, `restore_page` | Enviar a la papelera o recuperar el subárbol de una operación. |

Las consultas admiten `limit` entre 1 y 50 y devuelven `next_cursor` para continuar, válido mientras la colección permanece estable. Las modificaciones a páginas existentes requieren `expected_revision`. Todas las escrituras aceptan `operation_key` para reintentos idénticos. Los errores de herramienta incluyen `code` y `message`. Los bloques utilizan `heading`, `paragraph`, `list`, `task` e `image`. Las fotos guardan una referencia al recurso local, el pie y `width_percent`. MCP recibe estos metadatos. Se permiten 512 bloques y 1 MiB de contenido JSON por página. Los datos de imagen se almacenan por separado dentro de SQLite.

El esquema de fotos utiliza `PRAGMA user_version=2`. La primera apertura en modo escritura de una biblioteca v1 guarda una copia `*.v1-*.sqlite3` en la misma carpeta antes de añadir la tabla de imágenes. Cada proceso usa una conexión propia con claves foráneas, WAL y espera de escritura de 2,5 segundos. La escritura de contenido, la revisión, el historial y la clave de reintento se confirman en la misma transacción. La secuencia de revisiones sirve de contador persistente de cambios.
