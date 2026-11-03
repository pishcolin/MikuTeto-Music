import QtQuick
import "pixelfont.js" as PF

// Claude's original bitmap glyph paths, rasterized with crisp pixel edges.
Item {
    id: root
    property string text: ""
    property real px: 2
    property color color: "#ffffff"
    readonly property var layout: PF.build(root.text.toUpperCase(), root.px)

    implicitWidth: layout.width
    implicitHeight: 7 * px
    width: implicitWidth
    height: implicitHeight

    Image {
        width: root.layout.width
        height: 7 * root.px
        smooth: false
        cache: false
        sourceSize.width: Math.ceil(width * Screen.devicePixelRatio)
        sourceSize.height: Math.ceil(height * Screen.devicePixelRatio)
        source: width > 0 ? "data:image/svg+xml," + encodeURIComponent(
            '<svg xmlns="http://www.w3.org/2000/svg" width="' + width + '" height="' + height
            + '" viewBox="0 0 ' + width + ' ' + height + '"><path shape-rendering="crispEdges" fill="'
            + root.color + '" d="' + root.layout.path + '"/></svg>') : ""
    }
}
