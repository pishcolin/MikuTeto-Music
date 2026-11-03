import QtQuick
import QtQuick.Controls.Basic
import "theme.js" as T

// Segmented bar after the wallpaper's quota meter. The backend value is
// mirrored only while the user is not dragging or stepping with the keys.
Slider {
    id: s
    required property var ui
    property real external: 0
    property color on: skinTheme.palette.mint
    property color off: skinTheme.palette.mintDim
    readonly property int seg: Math.max(3, ui.px * 2)
    readonly property int gapW: Math.max(2, ui.px)
    signal committed(real v)
    signal dragged(real v)

    from: 0
    to: 1
    padding: 0
    live: true
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    implicitHeight: ui.px * 7
    implicitWidth: 200

    Binding {
        target: s
        property: "value"
        value: s.external
        when: !s.pressed && !keyHold.running
        restoreMode: Binding.RestoreNone
    }
    Timer { id: keyHold; interval: 350; onTriggered: s.committed(s.value) }
    onMoved: {
        if (pressed) dragged(value)
        else keyHold.restart()
    }
    onPressedChanged: if (!pressed) committed(value)

    background: Item {
        id: track
        x: s.leftPadding
        y: s.topPadding
        width: s.availableWidth
        height: s.availableHeight
        readonly property int count: Math.max(6, Math.floor((width + s.gapW) / (s.seg + s.gapW)))
        readonly property real pitch: count > 1 ? (width - s.seg) / (count - 1) : 0
        Repeater {
            model: track.count
            Rectangle {
                required property int index
                x: Math.round(index * track.pitch)
                width: s.seg
                height: track.height
                color: (index + 0.5) / track.count <= s.visualPosition ? s.on : s.off
            }
        }
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            color: "transparent"
            border.width: 2
            border.color: skinTheme.palette.paper
            visible: s.visualFocus
        }
    }
    handle: Rectangle {
        x: s.leftPadding + s.visualPosition * (s.availableWidth - width)
        y: s.topPadding - s.ui.px
        width: s.ui.px * 2
        height: s.availableHeight + s.ui.px * 2
        color: skinTheme.palette.paper
        visible: s.enabled && (s.hovered || s.pressed || s.visualFocus)
    }
}
