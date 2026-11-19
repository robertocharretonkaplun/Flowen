import QtQuick

Text {
    required property string name
    readonly property var glyphs: ({
        page:"\uE7C3", pages:"\uE8C8", search:"\uE721", home:"\uE80F", newPage:"\uE70F",
        panel:"\uE700", add:"\uE710", trash:"\uE74D", more:"\uE712", settings:"\uE713",
        right:"\uE76C", down:"\uE70D", lock:"\uE72E", check:"\uE73E", history:"\uE81C",
        close:"\uE711", copy:"\uE8C8", task:"\uE73A", list:"\uE8FD", text:"\uE8D2",
        link:"\uE71B", bulb:"\uEA80", help:"\uE897", heading:"\uE8D2", edit:"\uE70F", photo:"\uEB9F",
        comment:"\uE90A", code:"\uE943", desktop:"\uE7F4", terminal:"\uE756", send:"\uE724", stop:"\uE71A"
    })
    text: glyphs[name] || ""
    font.family: "Segoe MDL2 Assets"
    font.pixelSize: 15
    color: "#a4a3a6"
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    Accessible.ignored: true
}
