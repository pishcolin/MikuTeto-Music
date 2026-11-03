import QtQuick
import "theme.js" as T

// One retro desktop window: teal bitmap title bar, mint seam, petrol body.
// Tiled panes let the mint desk show through as their border; overlapping
// windows (framed: true) draw their own mint frame.
Item {
    id: pane
    required property var ui
    property string title: ""
    property bool framed: false
    property color barColor: skinTheme.palette.bar
    property color titleColor: skinTheme.palette.paper
    property var chromeWindow: null
    property alias tools: toolRow.data
    property alias leading: leadRow.data
    default property alias content: bodyRect.data
    readonly property alias bodyItem: bodyRect
    readonly property int edge: framed ? ui.border : 0

    Rectangle { anchors.fill: parent; color: skinTheme.palette.mint; visible: pane.framed }

    Rectangle {
        id: bar
        x: pane.edge
        y: pane.edge
        width: pane.width - 2 * pane.edge
        height: pane.ui.titleH
        color: pane.barColor
        MouseArea {
            anchors.fill: parent
            enabled: pane.chromeWindow !== null
            property point pressPoint: Qt.point(0, 0)
            onPressed: (mouse) => pressPoint = Qt.point(mouse.x, mouse.y)
            onPositionChanged: (mouse) => {
                if (pressed && Math.abs(mouse.x - pressPoint.x) + Math.abs(mouse.y - pressPoint.y) > 3)
                    pane.chromeWindow.startSystemMove()
            }
            onDoubleClicked: pane.chromeWindow.toggleWindowSize()
        }
        PixelText {
            id: label
            x: pane.ui.px * 3
            anchors.verticalCenter: parent.verticalCenter
            text: pane.title
            px: pane.ui.px
            color: pane.titleColor
        }
        Row {
            id: leadRow
            anchors.left: label.right
            anchors.leftMargin: pane.title !== "" ? pane.ui.px * 6 : 0
            height: parent.height
            spacing: pane.ui.px * 2
        }
        Row {
            id: toolRow
            anchors.right: parent.right
            anchors.rightMargin: pane.ui.px * 2
            height: parent.height
            spacing: pane.ui.px * 3
        }
    }
    Rectangle {
        id: bodyRect
        x: pane.edge
        y: bar.y + bar.height + pane.ui.border
        width: pane.width - 2 * pane.edge
        height: Math.max(0, pane.height - y - pane.edge)
        color: skinTheme.palette.pane
        clip: true
    }
}
