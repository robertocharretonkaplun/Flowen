# Arquitectura de Flowen

Flowen tiene dos programas que comparten una biblioteca SQLite:

- **flowen.exe**: el editor de escritorio, hecho con Qt Quick (QML).
- **notas-mcp.exe**: el servidor MCP por stdio. Claude y Codex leen y editan la biblioteca a través de él.

Ninguno de los dos guarda estado propio de las páginas: todo pasa por la biblioteca. Por eso pueden trabajar a la vez. La biblioteca usa transacciones `IMMEDIATE`, lleva revisiones por página, y el editor detecta los cambios externos con `generation`.

```
                ┌────────────── src/core (notes_core) ──────────────┐
 flowen.exe ──▶ │ store.cpp     páginas, bloques, revisiones, fotos  │ ◀── notas-mcp.exe
 (QML + C++)    │ library.cpp   favoritos, visitas, plantillas,      │     (src/mcp/main.cpp)
                │               referencias, notas para preguntar     │
                │ contract.cpp  herramientas MCP y su esquema        │
                │ inlines.cpp   formato en línea: validar y a HTML   │
                └─────────────────────── SQLite ─────────────────────┘
```

## src/core: la biblioteca

| Archivo | Qué hace |
| --- | --- |
| `contract.cpp/.h` | Define las ocho herramientas MCP con su esquema JSON y valida cada llamada. Es la única descripción del formato de páginas y bloques. El editor también lo usa: lo que guarda cumple el mismo esquema que lo que escribe Claude. |
| `store.cpp/.h` | La clase `Store`. Abre y actualiza el esquema sin cambiar `user_version` (las columnas y tablas nuevas son opcionales, así que un `notas-mcp` anterior sigue abriendo la biblioteca). Guarda cada cambio como una revisión, aplica las herramientas MCP y mantiene las claves de búsqueda sin acentos. Al renombrar una página, actualiza las menciones a ella. |
| `library.cpp` | La parte de `Store` que solo usa el escritorio: favoritos, páginas recientes, plantillas, referencias («N páginas enlazan aquí») y la selección de notas para **Preguntar a Flowen**. Usa tablas propias y no crea revisiones. |
| `storeinternal.h` | Ayudas internas de los dos archivos anteriores: fecha, JSON, plegado de acentos, errores y `Transaction`. |
| `inlines.cpp/.h` | Valida los `spans` (estilos, enlaces, menciones `lunqio://page/<id>` (el esquema conserva el nombre anterior de Flowen para no romper los enlaces guardados), colores y comentarios) y los convierte a HTML para exportar. |

## src/mcp: notas-mcp

`main.cpp` implementa JSON-RPC por stdio (`initialize`, `tools/list`, `tools/call`, `ping`) sobre `Store`. Con `--read-only`, solo ofrece las herramientas de lectura.

## src/desktop: el editor

| Archivo | Qué hace |
| --- | --- |
| `main.cpp` | Crea la aplicación, abre la biblioteca, registra los tipos de C++ y carga `qml/Main.qml`. |
| `editor.cpp/.h` | El puente entre QML y la biblioteca (`backend`). `run(acción, argumentos)` busca la acción en una tabla de manejadores agrupados por tema: lectura, favoritos y plantillas, guardado, fotos y archivos. Lo que no está en la tabla es una herramienta de la biblioteca, la misma que usa MCP. También guarda las preferencias (tema y autor) y avisa cuando el portapapeles tiene una foto. |
| `inlineeditor.cpp/.h` | El formato en línea de cada bloque: estilos, enlaces, menciones, colores y comentarios con hilos. Convierte los `spans` a `QTextCharFormat` y al revés, y vuelve a pintarlos al cambiar de tema. |
| `svgglyph.cpp/.h` | Elementos que se dibujan en C++: `SvgGlyph` (los íconos de la identidad en dos tintas) y `PhotoView` (fotos con esquinas redondeadas, que funcionan también con el renderizado por software). |
| `pagefile.cpp/.h` | Archivos y fotos: exportar a PDF, HTML, Markdown y texto; leer y guardar fotos; pegar desde el portapapeles; guardar o copiar una foto. |
| `writingassistant.cpp/.h` | Claude Code y Codex sin herramientas: **Editar con IA**, **Crear con IA** y **Preguntar a Flowen**. Cuenta los tokens (`usagelog`) y lee los límites del plan (`planlimits`). Los cambios de **Crear** y **Editar** se aplican por la sesión MCP propia del editor (`mcplink`). |
| `connectors.cpp/.h` | Conecta y desconecta Flowen en Claude Desktop, Claude Code y Codex. |

## qml: la interfaz

- **`Main.qml`**: la ventana. Contiene el estado de la página abierta: el modelo de bloques `blocks` y su conversión `rowOf`/`draft`, el guardado automático y los conflictos, deshacer entre bloques (`rememberStructure`), las operaciones sobre páginas (papelera, duplicar, mover, plantillas), la vista de la página, las pestañas y los diálogos. Los paneles la reciben como `workspace`.
- **`Sidebar.qml`**: la barra lateral (búsqueda, Inicio, Preguntar, Favoritos, Recientes, árbol de páginas con su menú contextual y pie con el estado de MCP y el uso).
- **`BlockRow.qml`**: un bloque. Maneja el teclado al estilo de Notion, el menú **⋮⋮**, el aspecto del bloque y las fotos (`PhotoBlock.qml`).
- **Menús y selección**: `SelectionBubble.qml` (formato y colores), `SlashMenu.qml` («/»), `PageMenu.qml` («@»), `UiMenu`, `UiMenuItem` y `UiMenuSeparator` (todos los menús con el mismo aspecto).
- **Página**: `PageHeader`, `PageCover`, `PageOutline` (índice de encabezados), `TemplateStrip` (plantillas) y `CommentRail` y `CommentCard` (comentarios).
- **Vistas**: `ViewSwitch` (Edición, Lectura, Diseño de página), `PaperSheets` (las hojas) y `PaperMenu` (papel y márgenes). En `Main.qml`, `viewMode` decide la vista y `locked` (papelera o lectura) bloquea toda edición: cada función que cambia la página lo comprueba. `paginate()` calcula en Diseño de página el espacio que lleva un bloque a la hoja siguiente (`pageBreaks`), sin tocar los bloques guardados. La vista, el papel y los márgenes se guardan con `backend.preference`/`setPreference`, fuera de la biblioteca.
- **Pestañas**: `ConnectorsPage`, `UsagePage` y `AskPage`.
- **IA de la página**: `PageAssist`, el panel del botón ✦. Envía la página como texto (`pageText()` en `Main.qml`) a `WritingAssistant::review`, que guarda las respuestas en `insights` sin tocar la biblioteca; solo `insertInsight()` las lleva a la página, como un paso de deshacer.
- **Ayuda**: `HelpDialog` (Guía y atajos: los atajos en tablas por tema; al añadir un atajo, añádelo también a su tabla) y `AboutDialog` (versión de CMake vía `backend.version`, logotipo de Attribute Overload en `assets/brand` y enlaces al sitio, al código y a la documentación).
- **Estilo**: `Theme.qml` es un singleton con los colores de los cuatro temas (Flowen oscuro y claro, Claro y Oscuro) y la paleta de nueve colores. Ningún otro archivo usa colores fijos, salvo los de Claude, Codex, las gráficas y las portadas. `Glyph.qml` y `UiButton.qml` son los ladrillos básicos.

## Reglas que conviene mantener

1. **Un solo formato.** Todo lo que escribe el editor pasa por `contract.cpp` y `Store::saveDraft`. Un campo nuevo de bloque o de página se añade al esquema, a `completeBlock` o `record`, a `rowOf`/`draft` en `Main.qml` y a las pruebas de `integration.py`.
2. **Compatibilidad.** El esquema crece con columnas y tablas opcionales y sin subir `user_version`, para que un `notas-mcp` anterior (por ejemplo, el que tiene abierto Claude Desktop) siga funcionando.
3. **Sin nulos en el JSON.** Lee los objetos JSON con `value()`. `operator[]` de un `QJsonObject` no constante añade la clave con valor nulo.
4. **Colores solo desde `Theme`.** Así los cuatro temas se mantienen coherentes.
5. **Pruebas.** `tests/integration.py` comprueba el contrato MCP de punta a punta. `tests/editor_test.cpp` prueba la interfaz real con Qt Test (con `-platform offscreen`; las capturas se guardan en `FLOWEN_PREVIEW_DIR`). Las pruebas que usan el portapapeles se saltan fuera de `offscreen`.
6. **Documentación.** Comenta con `///` lo público de los encabezados: Doxygen (`docs/Doxyfile`) lo publica en GitHub Pages con cada cambio en `main`.
