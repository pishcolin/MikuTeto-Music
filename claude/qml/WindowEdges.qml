import QtQuick
import QtQuick.Window

// Native resize gestures on the existing mint border; no extra visible frame.
Item {
    id: edges
    required property var hostWindow
    enabled: hostWindow.visibility !== Window.Maximized
    readonly property int border: 3
    readonly property int corner: 8
    Repeater {
        model: [
            { x: 0, y: 0, w: edges.corner, h: edges.corner, edge: Qt.TopEdge | Qt.LeftEdge, cursor: Qt.SizeFDiagCursor },
            { x: edges.width - edges.corner, y: 0, w: edges.corner, h: edges.corner, edge: Qt.TopEdge | Qt.RightEdge, cursor: Qt.SizeBDiagCursor },
            { x: 0, y: edges.height - edges.corner, w: edges.corner, h: edges.corner, edge: Qt.BottomEdge | Qt.LeftEdge, cursor: Qt.SizeBDiagCursor },
            { x: edges.width - edges.corner, y: edges.height - edges.corner, w: edges.corner, h: edges.corner, edge: Qt.BottomEdge | Qt.RightEdge, cursor: Qt.SizeFDiagCursor },
            { x: edges.corner, y: 0, w: edges.width - 2 * edges.corner, h: edges.border, edge: Qt.TopEdge, cursor: Qt.SizeVerCursor },
            { x: edges.corner, y: edges.height - edges.border, w: edges.width - 2 * edges.corner, h: edges.border, edge: Qt.BottomEdge, cursor: Qt.SizeVerCursor },
            { x: 0, y: edges.corner, w: edges.border, h: edges.height - 2 * edges.corner, edge: Qt.LeftEdge, cursor: Qt.SizeHorCursor },
            { x: edges.width - edges.border, y: edges.corner, w: edges.border, h: edges.height - 2 * edges.corner, edge: Qt.RightEdge, cursor: Qt.SizeHorCursor }
        ]
        MouseArea {
            required property var modelData
            x: modelData.x
            y: modelData.y
            width: modelData.w
            height: modelData.h
            cursorShape: modelData.cursor
            onPressed: edges.hostWindow.startSystemResize(modelData.edge)
        }
    }
}
