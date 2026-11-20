# Lunqio · Pluma y diálogo

El paquete parte del ícono naranja de Lunqio. El original a color se usa en el lanzador. El símbolo monocromo y las firmas horizontales se usan en cabeceras, menús y documentos.

## Archivos del sistema

| Ruta | Contenido y uso |
| --- | --- |
| `Guia-de-identidad.pdf` | Paleta, construcción de marca, tipografía, ejemplos de interfaz clara y oscura y catálogo de las diez familias. |
| `Vista-de-iconografia.png` | Lámina rotulada de los 100 símbolos. Sirve para elegir uno por su función. |
| `marca/` | Ícono principal en PNG y en ICO para Windows, adaptación vectorial a tres tintas, símbolo monocromo y firmas horizontales en SVG y PNG transparentes. La firma clara tiene tinta oscura para un fondo claro. |
| `tokens.json` | Colores de marca y por tema, tipografía, espacios, radios y medidas de iconografía. |
| `iconografia/atlas.json` | ID estable, nombre en español, familia y rectángulo de recorte de cada ícono. |
| `iconografia/atlas-claro.png`, `atlas-oscuro.png` | Atlas transparentes a escala 1x, con versiones `@2x` y originales SVG. |
| `iconografia/svg/` | Los 100 íconos individuales en SVG de 24 × 24, en los colores de interfaz clara. |
| `iconografia/simbolos.svg` | Colección monocroma para HTML. Cada símbolo hereda `currentColor` y conserva el mismo ID que en el atlas. |
| `iconografia/ampliacion/atlas-02.png` | Hoja adicional de 100 símbolos para el tema oscuro. El PNG transparente mide 640 × 640 px. El SVG editable y el índice JSON están en la misma carpeta. |

## Recortar un ícono para la aplicación

1. Busca su ID en `iconografia/atlas.json`. Los nombres que ya utiliza `Glyph.qml`, como `newPage`, `photo`, `comment` y `terminal`, se conservan.
2. Elige el atlas del tema. Cada fila contiene una familia. Las coordenadas parten de la esquina superior izquierda. Cada rectángulo contiene `[x, y, ancho, alto]` en píxeles a 1x.
3. Para una pantalla de alta densidad usa `@2x` y multiplica los cuatro valores por dos. Dibuja el resultado con el mismo tamaño lógico.

Por ejemplo, `plug` es el conector MCP. Su rectángulo es `[64, 192, 32, 32]` a 1x y `[128, 384, 64, 64]` a 2x. Un recorte lógico de 32 px incluye un lienzo de dibujo de 24 px y un margen transparente de 4 px por lado.

Para la hoja adicional usa directamente los rectángulos de `ampliacion/atlas-02.json` sobre su PNG. Ya están en píxeles a 2x. Por ejemplo, `undo` ocupa `[0, 0, 64, 64]` y se dibuja en una celda lógica de 32 × 32 px.

En una barra compacta se puede usar directamente el SVG individual a 16, 20 o 24 px. Para dar a un símbolo el color del texto en una interfaz web, puedes referenciar la colección monocroma:

```html
<button type="button" aria-label="Buscar páginas">
  <svg width="20" height="20" aria-hidden="true">
    <use href="iconografia/simbolos.svg#search"></use>
  </svg>
</button>
```

Los nombres de los símbolos describen su función visual. El catálogo incluye recursos para diseñar páginas y vistas, además de los controles del editor.
