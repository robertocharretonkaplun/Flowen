pragma Singleton
import QtQuick

// The looks of Lunqio. `mode` is the saved choice:
//   "dark" / "light"   Lunqio oscuro / claro, the identity "Pluma y diálogo" (design/identidad/tokens.json):
//                      warm surfaces, coral or rust accent, two-tone ivory/coral symbols.
//   "white" / "black"  the usual Claro and Oscuro themes: neutral white and black, a blue accent and
//                      one-colour symbols.
//   "system"           Claro or Oscuro, as Windows is.
// Canvas, surface, text, muted, line, accent, glyph and success of the Lunqio themes come straight from
// the tokens; the steps between canvas and line are the surfaces the interface needs for hover,
// pressed and borders. The window binds `mode` to the preference saved by the editor.
QtObject {
    property string mode: "dark"
    readonly property string scheme: mode === "system"
        ? (Qt.styleHints.colorScheme === Qt.ColorScheme.Dark ? "black" : "white")
        : (["dark","light","white","black"].indexOf(mode) >= 0 ? mode : "dark")
    readonly property bool dark: scheme === "dark" || scheme === "black"
    readonly property bool identity: scheme === "dark" || scheme === "light"
    //                          Lunqio oscuro  Lunqio claro  Claro      Oscuro
    function pick(night, day, white, black) {
        return scheme === "light" ? day : scheme === "white" ? white : scheme === "black" ? black : night
    }

    // Brand: the icon and brand accents.
    readonly property color vermilion: "#F32201"
    readonly property color ivory: "#FBF1E0"
    readonly property color ink: "#2C1312"

    // Surfaces, from the page outwards.
    readonly property color canvas: pick("#231B19", "#FFF9F0", "#FFFFFF", "#191919")     // the page
    readonly property color base: pick("#271E1C", "#FCF4E8", "#FBFBFA", "#1D1D1E")       // tab bar, sunk fields
    readonly property color sidebar: pick("#2A201E", "#F8EDDD", "#F7F7F5", "#202020")
    readonly property color surface: pick("#302523", "#FBF1E0", "#FFFFFF", "#252526")    // menus, popups, cards
    readonly property color raised: pick("#362A27", "#F4E6D4", "#F2F2F0", "#2C2C2E")     // hover on the canvas
    readonly property color hover: pick("#3D2F2B", "#EEDDCA", "#EBEBE9", "#333335")      // hover on surfaces
    readonly property color pressed: pick("#46362F", "#E6D2BE", "#E0E0DD", "#3E3D41")
    readonly property color line: pick("#5B4640", "#DACAC0", "#DDDDD9", "#4A4A4E")       // borders

    // Text, strongest to faintest.
    readonly property color text: pick("#FBF1E0", "#2C1312", "#1F1F1F", "#EFEDF0")
    readonly property color textSoft: pick("#F0E3D2", "#3A221E", "#2D2D2C", "#E4E3E5")   // body text
    readonly property color secondary: pick("#DDCEC1", "#4E3832", "#474745", "#C9C7CC")
    readonly property color muted: pick("#C8B7AC", "#65544E", "#6B6B68", "#A09DA5")
    readonly property color faint: pick("#9C867B", "#8C7870", "#9A9A97", "#77757B")      // placeholders

    // Action. For small text and buttons use `accent`; `accentInk` is the text on it ("onAccent").
    readonly property color accent: pick("#FF7959", "#A82E13", "#1F6FD1", "#9DBDF0")
    readonly property color accentHover: pick("#FF8D71", "#B93B1E", "#2C7BDB", "#B2CBF4")
    readonly property color accentPressed: pick("#E9664A", "#8E2510", "#1A5DB1", "#86A8DD")
    readonly property color accentInk: pick("#2C1312", "#FFF9F0", "#FFFFFF", "#10161F")
    readonly property color accentSoft: pick("#4A2C24", "#F5DACF", "#E4EEFB", "#22314A")  // selected rows
    readonly property color accentLine: pick("#9A4A39", "#D79A87", "#9FC2EC", "#3E5F8C")  // calm accent border
    readonly property color focus: accent
    readonly property color selection: pick("#7A3627", "#F3C8B9", "#CCE0F7", "#294D73")   // selected text
    // Symbols: two inks in Lunqio, one in the usual Claro and Oscuro.
    readonly property color glyph: pick("#FBF1E0", "#2C1312", "#3B3B39", "#D6D4DA")
    readonly property color glyphAccent: pick("#FF7959", "#C83918", "#3B3B39", "#D6D4DA")

    // States. Pair them with a text label, as the guide asks for warnings and MCP state.
    readonly property color success: pick("#90CAA5", "#33644C", "#2E7A4E", "#7ABB99")
    readonly property color successSoft: pick("#22342A", "#DCEBE0", "#E3F2E8", "#21342A")
    readonly property color warning: pick("#E6B76F", "#85560E", "#8A5A00", "#DDBA84")
    readonly property color warningSoft: pick("#3B2F1E", "#F7E7C6", "#FBF0D8", "#3B3221")
    readonly property color danger: pick("#FFA48E", "#A3241A", "#C4321F", "#EFB69C")
    readonly property color dangerSoft: pick("#46241E", "#F9DED8", "#FBE4E0", "#3B2622")
    readonly property color favorite: pick("#E8B949", "#B98300", "#C99400", "#E8B949")
    readonly property color shadow: pick("#38000000", "#142C1312", "#14000000", "#38000000")
    readonly property color shadowSoft: pick("#1c000000", "#082C1312", "#08000000", "#1c000000")

    // Type and shape.
    readonly property string family: "Segoe UI"
    readonly property string mono: "Consolas"
    readonly property int radiusButton: 8
    readonly property int radiusPanel: 12
}
