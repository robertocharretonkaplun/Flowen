# Lunqio

Editor de notas para Windows x64 con páginas anidadas, tareas y un servidor MCP local. La interfaz y el asistente comparten una biblioteca SQLite. Puedes usar el editor sin conexión.

## Abrir la aplicación

1. Descomprime **Lunqio-x64.zip** en una carpeta permanente.
2. Abre **lunqio.exe**. Pulsa **Nueva página**, escribe el título y edita el primer párrafo. Usa los controles al pie de la página para añadir encabezados, párrafos, elementos de lista o tareas.
3. El indicador **Guardado** muestra la revisión actual. **Opciones de página** permite crear subpáginas, mover la página, consultar el historial, guardar una copia en distintos formatos o enviar la página y sus descendientes a la papelera. El menú de cada bloque permite reordenarlo o eliminarlo.

**Ctrl+N** crea una página, **Ctrl+F** activa la búsqueda y **Ctrl+S** guarda la edición. El guardado automático agrupa las pulsaciones tras una pausa de 750 ms. El editor comprueba los cambios externos al recuperar el foco y cada segundo mientras está activo. Si tu borrador entra en conflicto, puedes exportarlo a Markdown antes de descartar los cambios y recargar.

## Barra lateral, archivos y fotos

La barra lateral reúne la búsqueda, Inicio, las páginas privadas y la papelera. El lápiz de arriba crea una página. Al pasar sobre una página, el botón **+** crea una subpágina. Puedes plegar **Privado**, ocultar la barra o arrastrar su borde derecho para cambiar el ancho. Un doble clic en el borde recupera el ancho automático. El estado de MCP aparece junto al espacio de trabajo, en la parte inferior.

**File → Guardar como…** (**Ctrl+Shift+S**) guarda una copia de la página en la carpeta que elijas. **Ctrl+S** guarda los cambios en la biblioteca local.

| Formato | Fotos |
| --- | --- |
| PDF | Incluye las imágenes con su proporción y ancho de impresión. |
| HTML | Incluye las imágenes en el mismo archivo. |
| Markdown | Guarda los archivos de imagen en una carpeta `.media` junto al documento. Para compartirlo con fotos, incluye esa carpeta. |
| Texto plano | Usa el pie de foto para identificar cada imagen. |

### Favoritos y recientes

La estrella junto a **Opciones de página** añade la página abierta a **Favoritos**, arriba en la barra lateral. Pulsa la estrella otra vez para quitarla. También puedes hacerlo con **Opciones de página** o con clic derecho sobre cualquier página de la barra. Arrastra un favorito para cambiar su orden. Al pasar el ratón sobre un favorito, su estrella lo quita.

**Recientes** muestra las cinco últimas páginas que abriste, con el tiempo transcurrido. En **Inicio**, **Visitado recientemente** muestra hasta ocho como tarjetas con su portada e icono. Las páginas en la papelera desaparecen de ambas listas. Si las restauras, vuelven a Favoritos en el mismo lugar.

Favoritos y recientes se guardan en la biblioteca, así que también viajan en las copias de seguridad. Marcar un favorito o abrir una página no crea revisiones, y MCP no ve estas listas. Buscar o abrir la papelera las oculta mientras tanto.

Pulsa **Foto** al pie del editor o **Edit → Insertar foto…** para elegir un PNG o JPEG local de hasta 32 MiB y 40 megapíxeles. Arrastra la esquina inferior derecha o usa **Ancho** para ajustar la foto entre el 10 % y el 100 % de la columna. Puedes editar el pie, reordenar la foto o quitarla desde su menú. La biblioteca guarda la imagen, su pie y el ancho. Seguirá disponible si mueves el original. Las copias de seguridad incluyen las fotos.

También puedes pegar una imagen con **Ctrl+V** (o **Pegar** en el menú contextual). Sirve con una captura de pantalla, con **Copiar imagen** de un navegador o con archivos PNG y JPEG copiados en el Explorador. La foto aparece debajo del bloque donde está el cursor. Si ese bloque es un párrafo vacío, la foto lo sustituye. Los archivos conservan su nombre como pie de foto. Si copias texto de Word, Excel o una página web, se pega como texto aunque el portapapeles incluya una imagen de ese texto. Las imágenes grandes sin transparencia se guardan como JPEG, igual que al elegir un archivo.

## Escribir como en Notion

- **Intro** crea un bloque nuevo; si el cursor está en medio, el resto del texto pasa al bloque nuevo con su formato. **Mayús+Intro** salta de línea dentro del mismo bloque. En una lista o tarea, Intro continúa la lista; en un elemento vacío, la termina.
- **Retroceso** al inicio de un bloque lo une con el anterior. En un encabezado, lista o tarea, primero lo convierte en texto.
- **↑** y **↓** pasan al bloque anterior o siguiente desde la primera o la última línea.
- **/** abre el menú de bloques: texto, encabezados 1, 2 y 3, lista con viñetas, lista numerada, tarea, desplegable, cita, nota destacada, código, separador, foto o **Crear con IA**. Sigue escribiendo para filtrar («/tar», «/enc»), elige con las flechas e **Intro**, o cierra con **Esc**.
- Atajos Markdown al inicio de una línea, seguidos de un espacio: `#`, `##` y `###` encabezados, `-`, `*` o `+` lista, `1.` lista numerada, `[]` tarea, `>` desplegable, `"` cita y ```` ``` ```` código. `---` crea un separador. Dentro del texto: `**negrita**`, `*cursiva*` o `_cursiva_`, `~~tachado~~` y `` `código` `` se convierten al escribir el cierre.
- **Tab** anida el bloque bajo el anterior (como mucho un nivel más) y **Mayús+Tab** lo saca. Las viñetas cambian con el nivel (•, ◦, ▪) y las listas numeradas cuentan por nivel. Un **desplegable** oculta lo que tiene anidado debajo; pulsa su triángulo para abrirlo o cerrarlo, e **Intro** en un desplegable abierto crea su primer elemento.
- En un bloque de **código**, **Intro** añade una línea, **Tab** inserta espacios y **Ctrl+Intro** sale del bloque. En una **nota destacada**, pulsa el emoji para cambiarlo.
- Al pasar el puntero por un bloque aparecen, a su izquierda, **+** (añade una línea debajo con el menú «/» abierto) y **⋮⋮**. Arrastra ⋮⋮ para mover el bloque; una línea azul marca dónde quedará. Un clic en ⋮⋮ abre el menú del bloque (convertir, subir, bajar o eliminar).

## Enlaces entre páginas

Escribe **@** o **[[** para mencionar otra página. Sigue escribiendo para buscarla (sin importar acentos), elige con las flechas e **Intro**, o **Nueva página «…»** para crearla como subpágina de la actual. La mención se ve como una etiqueta con el nombre de la página; un clic la abre.

Bajo el título, **«N páginas enlazan aquí»** muestra qué páginas mencionan la actual, con el fragmento donde lo hacen. Las menciones se guardan como enlaces `lunqio://page/<id>` dentro del formato del texto, así que MCP también las ve. Al exportar, la mención queda como texto.

## Icono y portada

Pasa el puntero sobre el título y pulsa **Añadir icono** para elegir un emoji, o **Añadir portada** para poner un degradado. Al pasar el puntero por la portada, **Cambiar portada** ofrece ocho degradados o **Subir una foto…** (PNG o JPEG); **Quitar** la elimina. Pulsa el icono para cambiarlo o quitarlo. El icono aparece también en la barra lateral, en la cabecera y en el título de las exportaciones. Ambos se guardan con la página y su historial, y MCP puede cambiarlos con `update_page` (`icon` y `cover`).

## Dar formato al texto

Selecciona texto dentro de un bloque. Al soltar el ratón, o tras seleccionar con el teclado, aparece un menú junto a la selección:

- **Convertir** el bloque en texto, encabezado, lista o tarea.
- Aplicar **resaltado**, **negrita**, **cursiva**, **subrayado**, **tachado**, **código en línea** o **superíndice**. El botón se marca cuando toda la selección ya tiene ese estilo y al pulsarlo se quita. **Quitar formato** elimina los estilos y conserva enlaces y comentarios.
- Añadir un **enlace** `http` o `https`. Si escribes `ejemplo.com`, Lunqio añade `https://`. Ctrl+clic abre el enlace en el navegador.
- **Comentar** la selección. Ver **Comentarios** más abajo.
- Pedir a Claude o Codex que mejore, corrija o acorte la selección, o abrir **Editar con IA**.

**Esc** cierra el menú y conserva la selección. Los estilos se guardan con la página, se pueden deshacer con **Ctrl+Z**, llegan a MCP como `spans` y se exportan a PDF, HTML y Markdown.

| Atajo | Estilo |
| --- | --- |
| Ctrl+B | Negrita |
| Ctrl+I | Cursiva |
| Ctrl+U | Subrayado |
| Ctrl+Shift+X | Tachado |
| Ctrl+E | Código en línea |
| Ctrl+Shift+H | Resaltar |
| Ctrl+K | Enlace (con texto seleccionado; sin selección abre la búsqueda) |

## Comentarios

Selecciona texto y pulsa **Comentar** en el menú de selección. A la derecha del texto aparece una tarjeta: escribe el comentario y pulsa **Intro** o **Comentar** (**Mayús+Intro** añade una línea).

- Cada tarjeta muestra tu nombre, la hora («10:31 Hoy»), el texto con los enlaces activos y sus respuestas. Escribe en **Responder…** para contestar.
- **✓** marca el comentario como resuelto: se oculta y el texto deja de estar sombreado. Arriba aparece «N comentarios resueltos · Mostrar» para verlos o **Reabrir** uno.
- **⋯** permite editar o eliminar el comentario y **Cambiar mi nombre…**. Por defecto se usa el nombre completo de tu cuenta de Windows.
- Al colocar el cursor en un texto comentado se abre su tarjeta. Las tarjetas se alinean con su texto; la columna de la página se estrecha para dejarles sitio. Si la ventana es estrecha, solo flota la tarjeta abierta.
- Los comentarios se guardan con la página, se pueden deshacer con **Ctrl+Z** y llegan a MCP dentro de cada `span` (`comment` y `thread` con autor, hora, estado y respuestas), así que Claude o Codex también pueden leerlos y responderlos.

## Crear con IA

Pulsa **Espacio** en una línea vacía, **Ctrl+J** o **✦ Crear con IA** al pie de la página. Aparece un cuadro para pedir lo que quieras, por ejemplo «Crea una serie de puntos sobre qué es el prototipado en videojuegos».

- Con el cuadro vacío verás sugerencias: continuar escribiendo, resumir lo anterior, lista de puntos, lluvia de ideas, esquema, lista de tareas o explicar. Usa las flechas e **Intro** para elegir.
- La IA escribe bloques reales (encabezados, párrafos, elementos de lista y tareas) y te los muestra antes de tocar la página. Recibe el título y el texto cercano para continuar con coherencia.
- **Intro** o **Insertar** los añade. Si abriste el cuadro en una línea vacía, la reemplaza; si no, los pone debajo. Escribe otra indicación para ajustar el resultado, o usa **Reintentar** o **Descartar**. **Esc** detiene o cierra.

## Elegir Claude o Codex

**Crear con IA** y **Editar con IA** pueden escribir con **Claude** o con **Codex**. Cambia entre ellos en el propio cuadro, en el diálogo o en **Conectores → IA dentro de Lunqio**. Si uno alcanza su límite de uso, el aviso ofrece **Usar** el otro.

Claude usa Claude Code, el que trae la app de Claude o uno instalado aparte. Esa copia necesita su propio inicio de sesión una vez: pulsa **Iniciar sesión**, entra con tu cuenta de Claude en la ventana que se abre y vuelve a Lunqio. Codex usa tu sesión de Codex.

## Uso

La pestaña **Uso**, junto a **Conectores**, muestra los tokens que consumen **Crear con IA** y **Editar con IA**, según los informa cada asistente:

- Tokens de hoy, de los últimos 7 días y en total, con el número de peticiones, y el costo estimado. Solo Claude informa el costo, calculado a precio de API; con una suscripción no se cobra aparte.
- **Última petición**: un anillo con el porcentaje de la ventana de contexto que ocupó y su desglose en entrada, caché leída, caché escrita y salida.
- Una gráfica de los últimos 14 días por asistente (pasa el puntero sobre un día para ver las cifras) y la lista de peticiones recientes.

Cada propuesta indica también sus tokens. El historial se guarda solo en este equipo, en `%LOCALAPPDATA%\Lunqio\usage.jsonl`; **Borrar historial** lo elimina.

### Límites del plan

Junto al engrane de la barra lateral hay un indicador de uso: un anillo azul con el porcentaje usado del límite de 5 horas y, en el centro, un rombo con el color del asistente activo (naranja para Claude, violeta para Codex). Al pasar el puntero se ven el límite de 5 horas y el semanal, cuándo se restablecen y, en Codex, los créditos; un clic, o **Ver todo**, abre la pestaña **Uso**, que muestra los límites de ambos asistentes.

Estos límites son los de tu plan y cuentan también lo que usas fuera de Lunqio. Codex los informa en cualquier momento mediante `codex app-server`. Claude Code los informa junto con cada petición, así que Lunqio muestra los de tu última petición con Claude.

## Editar un fragmento con IA

1. Selecciona una frase dentro de un bloque. Pulsa **Editar con IA** en el menú junto a la selección o usa **Ctrl+Shift+I**. La misma acción está en **Edit** y en el menú del botón derecho. Las acciones rápidas del menú generan la propuesta directamente.
2. Elige **Mejorar redacción**, **Corregir** o **Acortar**, o escribe tu instrucción. **Generar propuesta** envía la selección y la instrucción a Claude o Codex, según el que elijas arriba a la derecha.
3. Compara el original con la propuesta. **Aplicar** reemplaza esa aparición del fragmento y crea una revisión. **Cancelar** conserva el texto original. Si la página cambió mientras revisabas la propuesta, vuelve a seleccionar el fragmento en la revisión actual.

El indicador **MCP conectado** corresponde a la conexión entre esta ventana y el ejecutable local `notas-mcp` de la biblioteca abierta. Aparece después de negociar el protocolo y verificar las herramientas. Pulsa el indicador o la pestaña **Conectores** para revisarla. La escritura con IA requiere Claude Code o Codex con una sesión iniciada, acceso al servicio y la conexión del editor activa. El editor manual funciona también con MCP desconectado.

**File** reúne las acciones de archivo y copia de seguridad. **Edit** incluye los comandos de texto. **View** controla la barra lateral, la búsqueda, el historial y la papelera. **Help** ofrece los atajos y la información de la aplicación.

## Conectores: Claude y Codex

1. Abre Lunqio desde su carpeta permanente. Selecciona la pestaña **Conectores**, junto a **Editor**, o pulsa **Ctrl+,**.
2. En **Clientes**, activa el interruptor de **Claude Desktop**, **Claude Code** o **Codex**. Lunqio registra el servidor `notas-mcp` y la biblioteca abierta en la configuración de ese cliente. Desactívalo para dejar de compartir la biblioteca con él.
3. Abre un chat nuevo en el cliente y pide, por ejemplo, «Crea una subpágina llamada Acuerdos en la página Reuniones y añade una tarea para enviar la minuta». Puedes volver a **Editor** para ver el resultado.

| Cliente | Dónde se guarda | Al desactivar |
| --- | --- | --- |
| Claude Desktop | `claude_desktop_config.json`. Lunqio guarda antes una copia `.lunqio-backup` junto al archivo. | Quita la entrada. Reinicia Claude Desktop para aplicar el cambio. |
| Claude Code | Ámbito de usuario (`~/.claude.json`) mediante `claude mcp add`. Sirve en todos tus proyectos. | Ejecuta `claude mcp remove`. |
| Codex | `~/.codex/config.toml` mediante `codex mcp add`. | Marca la entrada con `enabled = false`, igual que el interruptor de Codex. **Quitar registro** la elimina. |

Lunqio busca `claude.exe` en el PATH, en `~\.local\bin` y dentro de la app de Claude, y `codex.exe` en el PATH y en la app de Codex. Si no los encuentra, el menú **⋯** de cada cliente permite elegir el ejecutable, comprobar el estado o mostrar el archivo de configuración. La primera biblioteca usa el nombre `lunqio`. Otra biblioteca recibe un nombre propio. Si mueves el paquete, el cliente muestra **Ruta antigua**; actívalo de nuevo para actualizar la ruta.

En **Servidor de la biblioteca** puedes conectar o desconectar la sesión del editor que usa **Editar con IA** y elegir si se inicia con Lunqio. Los clientes abren su propia sesión, aunque Lunqio esté cerrado. El listado de herramientas procede de la sesión del editor. Para otros clientes compatibles con la configuración JSON `mcpServers`, pulsa **Copiar JSON** en **Otro cliente MCP**.

También puedes registrar el servidor desde PowerShell. Abre la carpeta descomprimida y mantén los archivos del paquete juntos.

```powershell
$server = (Resolve-Path .\notas-mcp.exe).Path
codex mcp add lunqio -- $server
codex mcp get lunqio
```

Abre una conversación nueva de Codex con el servidor habilitado. Por ejemplo, crea una página titulada **Bitácora** en Lunqio y pídele a Codex «Busca Bitácora, lee sus bloques y añade una tarea que diga Revisar el borrador». La revisión deberá avanzar en el editor. En **Opciones → Historial de revisiones**, pulsa **Restaurar** junto a la versión previa para recuperar el contenido.

Para una biblioteca de prueba, utiliza la misma ruta absoluta en ambos procesos. Para acceso de solo lectura añade `--read-only` después de los argumentos del servidor y abre previamente esa biblioteca en el editor. Al mover el paquete, vuelve a registrar la ruta del ejecutable. [Configuración MCP de Codex](https://developers.openai.com/codex/mcp/)

```powershell
$db = Join-Path $env:LOCALAPPDATA 'Lunqio\prueba.sqlite3'
.\lunqio.exe --db $db
codex mcp add lunqio-prueba -- $server --db $db
```

## Datos y recuperación

La ruta habitual es `%LOCALAPPDATA%\Lunqio\notas.sqlite3`. Ambos ejecutables resuelven, por orden, `--db`, la variable `LUNQIO_DB` o la ubicación predeterminada. El servidor puede funcionar con la ventana cerrada. Al utilizar un asistente remoto, los fragmentos y páginas que consulte pasan a su contexto.

- **Historial** recupera el título, el contenido y el padre de una revisión y crea una revisión nueva. Un destino antiguo que ya no es válido se sustituye por la raíz.
- **Papelera** permite recuperar un subárbol. Las páginas eliminadas por separado conservan su propio estado.
- **File → Copia de seguridad…** guarda una instantánea de la biblioteca completa en un archivo nuevo mediante `VACUUM INTO`. Incluye historial, papelera y operaciones. Para recuperar una copia, duplica el archivo de respaldo bajo un nombre nuevo y abre la copia de trabajo con `lunqio.exe --db "C:\ruta\recuperada.sqlite3"`. Usa esa misma ruta al registrar MCP. Así puedes validar el contenido y conservar el original. [Copias de SQLite](https://sqlite.org/backup.html)

## Identidad visual

Elige la vista en **View → Tema**. Lunqio recuerda la elección y empieza en **Lunqio oscuro**.

| Tema | Aspecto |
| --- | --- |
| **Lunqio oscuro** | La identidad **Pluma y diálogo** de `design/identidad`: superficies marrones cálidas y acento coral. |
| **Lunqio claro** | La misma identidad sobre crema, con acento rojo óxido. |
| **Claro** | El tema claro habitual: blanco, grises neutros y acento azul. |
| **Oscuro** | El tema oscuro habitual: negro, grises neutros y acento azul claro. |
| **Según Windows** | **Claro** u **Oscuro**, según el modo de color de Windows. |

**Ctrl+Shift+L** pasa a la versión clara u oscura del mismo tema, como en Notion: de Lunqio oscuro a Lunqio claro, o de Claro a Oscuro. En `design/vistas/comparativa.png` se ve la misma página en los cuatro temas.

En Claro y Oscuro los símbolos se dibujan en un solo color. En los temas de Lunqio siguen la identidad:

- **Color.** En Lunqio oscuro, las superficies son marrones cálidos, el texto es marfil y el acento es coral (`#FF7959`) con tinta oscura encima. En Lunqio claro, el fondo es crema (`#FFF9F0`), el texto es tinta (`#2C1312`) y el acento es rojo óxido (`#A82E13`) con texto crema encima. El bermellón (`#F32201`) queda para el ícono. Éxito, aviso y error usan los tonos de cada tema. Claude naranja, Codex violeta, la barra azul de los límites y los degradados de portada conservan sus colores.
- **Símbolos.** Los íconos son los de `design/identidad/iconografia`, dibujados en dos tintas: el contorno en marfil y el detalle en coral en Lunqio oscuro, y el contorno en tinta y el detalle en bermellón oscuro en Lunqio claro. Cuando un control está apagado o indica un estado, el símbolo usa un solo color.
- **Forma y texto.** Los botones tienen esquinas de 8 px y los paneles, de 12 px. Los controles usan Segoe UI de 14 px seminegrita y el texto de las páginas, 16 px. El código usa Consolas.

Para cambiar un color o una medida, edita `qml/Theme.qml`. Los nombres siguen `tokens.json`; `onAccent` se llama `accentInk`, porque QML reserva los nombres que empiezan por «on». Los símbolos se toman de `assets/glyphs`, una copia de `design/identidad/iconografia/svg`. Para añadir uno, copia su SVG ahí y úsalo por su nombre en `Glyph`. La variable de entorno `LUNQIO_THEME` (`dark` y `light` para Lunqio, `white` y `black` para Claro y Oscuro, o `system`) impone un tema sin guardarlo, lo que resulta útil para revisar pantallas.

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

Si Visual Studio no ha definido `VCToolsRedistDir`, indica `-CrtDir` con la ruta absoluta de la carpeta redistribuible x64 `Microsoft.VC*.CRT`. El empaquetado produce `dist/Lunqio-x64` y `dist/Lunqio-x64.zip`. Acepta `-OutputDir` para crear otra distribución. [Despliegue de Qt en Windows](https://doc.qt.io/qt-6/windows-deployment.html)

El icono de la aplicación sale de `Lunquio-icon.png`, en la raíz. Si cambias la imagen, regenera `assets/lunqio.ico` y los PNG con `python packaging/icon.py Lunquio-icon.png assets` (requiere Pillow) y vuelve a compilar. El script descarta los restos sueltos alrededor del cuadro.

Para repetir la prueba con el cliente Codex instalado, ejecuta `python tests/codex_smoke.py dist/Lunqio-x64/notas-mcp.exe` desde el repositorio. Esta prueba usa una biblioteca temporal y las llamadas locales del app-server de Codex. Se verificó con `codex-cli 0.169.0-alpha.11.1`.

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
