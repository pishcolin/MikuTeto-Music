import QtQuick
import QtQuick.Window
import "deckart.js" as Art

// A character sprite standing on the deck lid: a companion, never the subject.
Image {
    id: figure
    required property string who
    required property var layout
    property real centerX: 0
    property int figureH: 0
    property int lift: 0
    readonly property var box: Art.spriteBox(who, layout, centerX, figureH)
    readonly property real ratio: Math.max(1, Screen.devicePixelRatio)

    x: box.x
    y: box.y - lift
    width: box.w
    height: box.h
    fillMode: Image.PreserveAspectFit
    smooth: false
    asynchronous: true
    sourceSize.width: Math.ceil(box.w * ratio)
    sourceSize.height: Math.ceil(box.h * ratio)
}
