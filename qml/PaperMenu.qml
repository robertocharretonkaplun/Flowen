import QtQuick
import QtQuick.Controls.Basic

// The sheet of Diseño de página and of PDF files: its size and margins, as Word's Disposición menu.
// Used on its own (the paper button of the top bar) and as a submenu of Ver.
UiMenu {
    id: menu
    required property var workspace
    title: "Papel y márgenes"
    glyph: "page"
    minWidth: 300
    UiMenuItem { objectName: "paper-letter"; text: "Carta    21,6 × 27,9 cm"; marked: menu.workspace.paper === "letter"; onTriggered: menu.workspace.setPaper("letter") }
    UiMenuItem { objectName: "paper-a4"; text: "A4    21 × 29,7 cm"; marked: menu.workspace.paper === "a4"; onTriggered: menu.workspace.setPaper("a4") }
    UiMenuSeparator {}
    UiMenuItem { objectName: "margins-normal"; text: "Márgenes normales    2,54 cm"; marked: menu.workspace.margins === "normal"; onTriggered: menu.workspace.setMargins("normal") }
    UiMenuItem { objectName: "margins-narrow"; text: "Márgenes estrechos    1,27 cm"; marked: menu.workspace.margins === "narrow"; onTriggered: menu.workspace.setMargins("narrow") }
    UiMenuItem { objectName: "margins-wide"; text: "Márgenes anchos    5,08 cm"; marked: menu.workspace.margins === "wide"; onTriggered: menu.workspace.setMargins("wide") }
}
