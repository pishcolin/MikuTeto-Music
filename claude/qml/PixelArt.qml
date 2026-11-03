import QtQuick
import QtQuick.Window

// A block of deck art from deckart.js, rastered once on the logical pixel grid.
Image {
    id: art
    property string svg: ""
    property int cols: 0
    property int rows: 0
    property int unit: 1
    readonly property int raster: Math.max(1, Math.round(unit * Math.max(1, Screen.devicePixelRatio)))

    width: cols * unit
    height: rows * unit
    sourceSize.width: cols * raster
    sourceSize.height: rows * raster
    smooth: false
    cache: false
    source: svg
}
