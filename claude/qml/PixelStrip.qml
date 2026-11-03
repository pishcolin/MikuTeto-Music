import QtQuick

// One cell of a horizontal PixelArt sheet. Stepping a frame only moves the sheet
// inside its clip, so running animation never re-renders the art.
Item {
    id: strip
    property string svg: ""
    property int cellW: 0
    property int cellH: 0
    property int frames: 1
    property int frame: 0
    property int unit: 1

    width: cellW * unit
    height: cellH * unit
    clip: true

    PixelArt {
        x: -strip.frame * strip.cellW * strip.unit
        svg: strip.svg
        cols: strip.cellW * strip.frames
        rows: strip.cellH
        unit: strip.unit
    }
}
