import QtQuick
import QtQuick.Controls.Basic

// A thin line between groups of a Lunqio menu.
MenuSeparator {
    topPadding: 4; bottomPadding: 4; leftPadding: 10; rightPadding: 10
    height: visible ? implicitHeight : 0
    contentItem: Rectangle { implicitHeight: 1; color: Theme.hover }
}
