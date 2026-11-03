import QtQuick
import "theme.js" as T
import "deckart.js" as Art

// The right-hand stage: a stepped hi-fi with the album across its face, two
// stacked bays in its tower, and one mascot on the shelf beside them. QQ Music
// songs play from the CD bay, NetEase songs from the tape bay. Bays, lamps, the
// switch and the display follow the song actually playing; the faceplate and the
// mascot alone follow the browsing theme, so MIKU can stand beside a playing
// tape, and switching theme leaves playback and the bays exactly as they were.
Item {
    id: deck
    required property var app
    required property var ui
    property url mikuSource
    property url tetoSource
    property bool hostVisible: true
    // 1 decodes covers on the deck's pixel grid; 2 is twice as fine, and so on.
    property int coverDetail: 1

    readonly property int unit: Math.max(2, ui.px, Math.floor(width / 220))

    // Geometry and art are rebuilt only after a resize settles.
    property var geo: Art.layout(337, 535, 2)
    property bool laidOut: false
    readonly property var deckInk: Art.colors(skinTheme.palette)

    function relayout() {
        if (width < 1 || height < 1) return
        geo = Art.layout(width, height, unit)
        laidOut = true
    }
    onWidthChanged: laidOut ? settle.restart() : relayout()
    onHeightChanged: laidOut ? settle.restart() : relayout()
    onUnitChanged: laidOut ? settle.restart() : relayout()
    Component.onCompleted: relayout()
    Timer { id: settle; interval: 90; onTriggered: deck.relayout() }

    // ---------------------------------------------------------------- playback
    readonly property var now: Art.deckState({
        hasTrack: app.hasTrack, playingProvider: app.playingProvider, playing: app.playing,
        loading: app.loading, buffering: app.buffering, failed: app.failed, playError: app.playError,
        connected: app.connected, reconnecting: app.serviceReconnecting === true
    })
    readonly property string media: now.media
    readonly property string tint: media !== "" ? T.sourceTint[app.playingProvider] : skinTheme.palette.mint
    readonly property color lampColor: now.failed || now.offline ? skinTheme.palette.alert : tint
    readonly property color readoutColor: now.failed || now.offline ? skinTheme.palette.alert
        : (media !== "" ? tint : skinTheme.palette.inkFaint)
    readonly property string errorText: app.playError !== "" ? app.playError : "这首歌没能播放"
    readonly property string readoutSource: media === "cd" ? "QQ CD" : (media === "tape" ? "163 TAPE" : "")
    readonly property string mascot: skinTheme.choice === "teto" ? "teto" : "miku"

    // ---------------------------------------------------------------- cover
    readonly property string coverSource: app.hasTrack ? app.coverUrl : ""
    readonly property int coverDecode: geo.cover.s * coverDetail
    readonly property string coverState: !app.hasTrack ? "empty"
        : (coverSource === "" ? "none"
        : (albumCover.status === Image.Ready ? "ready"
        : (albumCover.status === Image.Error ? "failed" : "loading")))
    readonly property bool coverReady: coverState === "ready"

    // ---------------------------------------------------------------- motion
    readonly property bool motionOk: hostVisible && visible && app.settingsOpen !== true && !ui.reducedMotion
    readonly property int hopFrames: 9
    property int hopStep: 0
    property string lastMedia: ""
    property int tick: 0

    // Pausing during a cross-source handoff must stop that short animation too.
    onNowChanged: if (now && !now.spinning && !now.busy) hopStep = 0

    onMediaChanged: {
        if (media === "") return
        var paused = !now.spinning && !now.busy
        if (lastMedia !== "" && lastMedia !== media && motionOk && !paused) hopStep = 1
        lastMedia = media
    }
    onMotionOkChanged: if (!motionOk) hopStep = 0

    Timer {
        interval: 125
        repeat: true
        running: deck.motionOk && (deck.now.spinning || deck.now.busy || deck.hopStep > 0)
        onTriggered: {
            deck.tick = (deck.tick + 1) % 840
            if (deck.hopStep > 0) deck.hopStep = deck.hopStep >= deck.hopFrames ? 0 : deck.hopStep + 1
        }
    }

    readonly property bool lampOn: !now.busy || !motionOk || tick % 6 < 3
    readonly property int beatLift: now.spinning && motionOk && tick % 8 < 4 ? geo.u : 0
    readonly property int tossLift: hopStep > 0 && hopStep <= 2 ? 2 * geo.u : 0
    readonly property int mascotLift: Math.max(beatLift, tossLift)

    // ---------------------------------------------------------------- art
    readonly property string bodyUrl: laidOut ? Art.dataUrl(Art.bodySvg(geo, deckInk)) : ""
    readonly property string caseUrl: laidOut ? Art.dataUrl(Art.caseSvg(geo)) : ""
    readonly property string discBaseUrl: laidOut ? Art.dataUrl(Art.discBaseSvg(geo)) : ""
    readonly property string discFrameUrl: laidOut ? Art.dataUrl(Art.discFrameSvg(geo, deckInk)) : ""
    readonly property string discGlintUrl: laidOut ? Art.dataUrl(Art.discGlintSvg(geo)) : ""
    readonly property string tapeBaseUrl: laidOut ? Art.dataUrl(Art.tapeBaseSvg(geo)) : ""
    readonly property string tapeFrameUrl: laidOut ? Art.dataUrl(Art.tapeFrameSvg(geo)) : ""
    readonly property string reelUrl: laidOut ? Art.dataUrl(Art.reelSheetSvg(geo)) : ""
    readonly property string sleeveUrl: laidOut && app.hasTrack && !coverReady ? Art.dataUrl(Art.sleeveSvg(geo, tint)) : ""
    readonly property string miniDiscUrl: Art.dataUrl(Art.miniDiscSvg())
    readonly property string miniTapeUrl: Art.dataUrl(Art.miniTapeSvg())

    Accessible.role: Accessible.Graphic
    Accessible.name: media === "cd" ? "CD 仓正在使用，QQ 音乐" : (media === "tape" ? "磁带仓正在使用，网易云音乐" : "双仓音响，没有放入音乐")

    Item {
        id: grid
        readonly property int u: deck.geo.u
        x: deck.geo.ox
        y: deck.geo.oy
        width: deck.geo.lw * u
        height: deck.geo.lh * u
        visible: deck.laidOut

        PixelArt { svg: deck.bodyUrl; cols: deck.geo.lw; rows: deck.geo.lh; unit: grid.u }

        // ------------------------------------------------------------ CD bay
        Item {
            id: cdBay
            readonly property var disc: deck.geo.disc
            x: disc.x * grid.u
            y: disc.y * grid.u
            width: disc.d * grid.u
            height: disc.d * grid.u

            PixelArt { svg: deck.discBaseUrl; cols: cdBay.disc.d; rows: cdBay.disc.d; unit: grid.u }
            Image {
                anchors.fill: parent
                visible: deck.media === "cd" && deck.coverReady
                source: deck.media === "cd" && deck.coverReady ? deck.coverSource : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                sourceSize.width: deck.coverDecode
                sourceSize.height: deck.coverDecode
            }
            PixelArt { svg: deck.discFrameUrl; cols: cdBay.disc.d; rows: cdBay.disc.d; unit: grid.u }
            PixelStrip {
                visible: deck.media === "cd"
                svg: deck.discGlintUrl
                cellW: cdBay.disc.d
                cellH: cdBay.disc.d
                frames: Art.DISC_FRAMES
                frame: deck.tick % Art.DISC_FRAMES
                unit: grid.u
            }
        }

        // ---------------------------------------------------------- tape bay
        Item {
            id: tapeBay
            readonly property var tape: deck.geo.tape
            readonly property real played: deck.media === "tape" ? deck.app.fraction : 0
            readonly property int packA: Art.packWidth(deck.geo, 1 - played)
            readonly property int packB: Art.packWidth(deck.geo, played)
            x: tape.x * grid.u
            y: tape.y * grid.u
            width: tape.w * grid.u
            height: tape.h * grid.u

            PixelArt { svg: deck.tapeBaseUrl; cols: tapeBay.tape.w; rows: tapeBay.tape.h; unit: grid.u }
            Item {
                x: tapeBay.tape.labelX * grid.u
                y: tapeBay.tape.labelY * grid.u
                width: tapeBay.tape.labelW * grid.u
                height: tapeBay.tape.labelH * grid.u
                clip: true
                visible: deck.media === "tape" && deck.coverReady
                // A square image clipped to the label strip: cropped, never squeezed.
                Image {
                    width: parent.width
                    height: parent.width
                    y: Math.round((parent.height - height) / 2)
                    source: deck.media === "tape" && deck.coverReady ? deck.coverSource : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    sourceSize.width: deck.coverDecode
                    sourceSize.height: deck.coverDecode
                }
            }
            PixelArt { svg: deck.tapeFrameUrl; cols: tapeBay.tape.w; rows: tapeBay.tape.h; unit: grid.u }
            Rectangle {
                x: tapeBay.tape.winX * grid.u
                y: tapeBay.tape.winY * grid.u
                width: (tapeBay.packA + tapeBay.tape.hub) * grid.u
                height: tapeBay.tape.winH * grid.u
                color: "#5a3a30"
            }
            Rectangle {
                x: (tapeBay.tape.winX + tapeBay.tape.winW - tapeBay.packB - tapeBay.tape.hub) * grid.u
                y: tapeBay.tape.winY * grid.u
                width: (tapeBay.packB + tapeBay.tape.hub) * grid.u
                height: tapeBay.tape.winH * grid.u
                color: "#5a3a30"
            }
            Repeater {
                model: 2
                PixelStrip {
                    required property int index
                    x: ((index === 0 ? tapeBay.tape.reelA : tapeBay.tape.reelB) - tapeBay.tape.hub) * grid.u
                    y: (tapeBay.tape.reelY - tapeBay.tape.hub) * grid.u
                    svg: deck.reelUrl
                    cellW: 2 * tapeBay.tape.hub + 1
                    cellH: 2 * tapeBay.tape.hub + 1
                    frames: Art.REEL_FRAMES
                    frame: deck.media === "tape" ? deck.tick % Art.REEL_FRAMES : 0
                    unit: grid.u
                }
            }
        }

        // ------------------------------------------- bay veils, labels, lamps
        Repeater {
            model: [
                { bay: deck.geo.bayA, media: "cd", provider: "qq", color: T.sourceTint.qq },
                { bay: deck.geo.bayB, media: "tape", provider: "netease", color: T.sourceTint.netease }
            ]
            Item {
                id: bayState
                required property var modelData
                readonly property bool live: deck.media === modelData.media
                x: modelData.bay.x * grid.u
                y: modelData.bay.y * grid.u
                width: modelData.bay.w * grid.u
                height: modelData.bay.h * grid.u

                Rectangle {
                    anchors.fill: parent
                    color: skinTheme.palette.veil
                    visible: deck.media !== "" && !bayState.live
                }
                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    visible: bayState.live
                    border.width: grid.u
                    border.color: deck.now.failed || deck.now.offline ? skinTheme.palette.alert : bayState.modelData.color
                }
                PixelText {
                    anchors.right: parent.right
                    anchors.rightMargin: 4 * grid.u
                    y: 4 * grid.u
                    text: T.sourceShort[bayState.modelData.provider]
                    px: grid.u
                    color: bayState.live ? deck.lampColor : skinTheme.palette.inkFaint
                }
                Rectangle {
                    x: parent.width - 7 * grid.u
                    y: parent.height - 6 * grid.u
                    width: 3 * grid.u
                    height: 2 * grid.u
                    color: bayState.live && deck.lampOn ? deck.lampColor : deck.deckInk.lamp
                }
            }
        }
        Rectangle {
            readonly property var rail: deck.geo.sw
            x: (rail.x + 2) * grid.u
            y: (deck.media === "cd" ? rail.y + 2 : (deck.media === "tape" ? rail.y + rail.h - 7 : rail.y + Math.floor((rail.h - 5) / 2))) * grid.u
            width: 3 * grid.u
            height: 5 * grid.u
            color: deck.media !== "" ? deck.lampColor : skinTheme.palette.inkFaint
        }

        // --------------------------------------------------------- album case
        PixelArt {
            x: deck.geo.kase.x * grid.u
            y: deck.geo.kase.y * grid.u
            svg: deck.caseUrl
            cols: deck.geo.kase.s
            rows: deck.geo.kase.s
            unit: grid.u
        }
        Item {
            id: album
            x: deck.geo.cover.x * grid.u
            y: deck.geo.cover.y * grid.u
            width: deck.geo.cover.s * grid.u
            height: width

            Image {
                id: albumCover
                anchors.fill: parent
                visible: deck.coverReady
                source: deck.coverSource
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: false
                sourceSize.width: deck.coverDecode
                sourceSize.height: deck.coverDecode
            }

            // No cover yet, or none at all: a hand-labelled card.
            Item {
                id: card
                anchors.fill: parent
                visible: deck.app.hasTrack && !deck.coverReady
                readonly property int rowPx: deck.geo.cover.rowH * grid.u
                readonly property int inset: 5 * grid.u
                PixelArt { svg: deck.sleeveUrl; cols: deck.geo.cover.s; rows: deck.geo.cover.s; unit: grid.u }
                PixelText {
                    anchors.right: parent.right
                    anchors.rightMargin: 3 * grid.u
                    y: 2 * grid.u
                    text: deck.coverState === "loading" ? "COVER..." : "NO COVER"
                    px: grid.u
                    color: skinTheme.palette.paper
                }
                Text {
                    id: cardTitle
                    x: card.inset
                    y: deck.geo.cover.band * grid.u
                    width: card.width - 2 * card.inset
                    text: deck.app.hasTrack ? String(deck.app.current.title || "未知歌曲") : ""
                    color: "#1f2a30"
                    font.pixelSize: Math.round(card.rowPx * 0.56)
                    font.weight: Font.DemiBold
                    lineHeightMode: Text.FixedHeight
                    lineHeight: card.rowPx
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
                Text {
                    x: card.inset
                    y: cardTitle.y + cardTitle.height
                    width: card.width - 2 * card.inset
                    text: deck.app.hasTrack ? T.artists(deck.app.current) : ""
                    color: "#4a5a60"
                    font.pixelSize: Math.round(card.rowPx * 0.44)
                    lineHeightMode: Text.FixedHeight
                    lineHeight: card.rowPx
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    textFormat: Text.PlainText
                }
            }

            // Nothing playing: the empty case says what to do next.
            Column {
                visible: !deck.app.hasTrack
                x: 8 * grid.u
                width: parent.width - 16 * grid.u
                anchors.verticalCenter: parent.verticalCenter
                spacing: 3 * grid.u
                PixelText {
                    text: "NO MEDIA"
                    px: grid.u
                    color: skinTheme.palette.inkFaint
                }
                Text {
                    width: parent.width
                    text: "还没有放入音乐"
                    color: skinTheme.palette.ink
                    font.pixelSize: deck.ui.fBody + 2
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
                Text {
                    width: parent.width
                    text: "选一首歌开始播放。QQ 音乐的歌进 CD 仓，网易云的歌进磁带仓。"
                    color: skinTheme.palette.inkDim
                    font.pixelSize: deck.ui.fSmall
                    lineHeight: 1.25
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                }
            }

            // Playback failed: the album stays, the reason sits along its foot.
            Rectangle {
                visible: deck.now.failed
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: failureLabel.implicitHeight + 6 * grid.u
                color: skinTheme.palette.alertBar
                Text {
                    id: failureLabel
                    x: 4 * grid.u
                    y: 3 * grid.u
                    width: parent.width - 8 * grid.u
                    text: deck.errorText
                    color: skinTheme.palette.paper
                    font.pixelSize: deck.ui.fSmall
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }
        }

        // ------------------------------------------------------------ display
        Item {
            id: readout
            readonly property var panel: deck.geo.vfd
            readonly property int count: Math.floor((panel.w - 7) / 3)
            readonly property int filled: deck.app.hasTrack ? Math.round(deck.app.fraction * count) : 0
            readonly property color offColor: Art.mix(deck.deckInk.lamp, deck.deckInk.ink, 0.12)
            x: panel.x * grid.u
            y: panel.y * grid.u
            width: panel.w * grid.u
            height: panel.h * grid.u

            Row {
                x: 4 * grid.u
                y: 3 * grid.u
                spacing: 3 * grid.u
                visible: deck.lampOn
                PixelText {
                    visible: deck.now.icon !== ""
                    text: deck.now.icon
                    px: grid.u
                    color: deck.readoutColor
                }
                PixelText {
                    text: deck.now.word
                    px: grid.u
                    color: deck.readoutColor
                }
            }
            PixelText {
                anchors.right: parent.right
                anchors.rightMargin: 4 * grid.u
                y: 3 * grid.u
                visible: deck.readoutSource !== ""
                text: deck.readoutSource
                px: grid.u
                color: deck.readoutColor
            }
            Repeater {
                model: readout.count
                Rectangle {
                    required property int index
                    x: (4 + index * 3) * grid.u
                    y: (readout.panel.h - 6) * grid.u
                    width: 2 * grid.u
                    height: 3 * grid.u
                    color: index < readout.filled ? deck.readoutColor : readout.offColor
                }
            }
        }

        // ------------------------------------------------------------- mascot
        // Both stay loaded so a theme switch swaps them at once, without a gap.
        DeckFigure {
            who: "miku"
            visible: deck.mascot === "miku"
            layout: deck.geo
            source: deck.mikuSource
            centerX: deck.geo.figX
            figureH: deck.geo.figH
            lift: deck.mascotLift
        }
        DeckFigure {
            who: "teto"
            visible: deck.mascot === "teto"
            layout: deck.geo
            source: deck.tetoSource
            centerX: deck.geo.figX
            figureH: deck.geo.figTeto
            lift: deck.mascotLift
        }

        // Cross-platform change: the mascot tosses the next medium into its bay.
        PixelArt {
            id: handoff
            readonly property bool tape: deck.media === "tape"
            readonly property real t: deck.hopStep / deck.hopFrames
            readonly property real toX: tape ? deck.geo.tape.x + deck.geo.tape.w / 2 : deck.geo.disc.x + deck.geo.disc.d / 2
            readonly property real toY: tape ? deck.geo.tape.y + deck.geo.tape.h / 2 : deck.geo.disc.y + deck.geo.disc.d / 2
            visible: deck.hopStep > 0
            x: Math.round(deck.geo.figX + (toX - deck.geo.figX) * t - cols / 2) * grid.u
            y: Math.round(deck.geo.hopY + (toY - deck.geo.hopY) * t - deck.geo.hopH * 4 * t * (1 - t) - rows / 2) * grid.u
            svg: tape ? deck.miniTapeUrl : deck.miniDiscUrl
            cols: tape ? 17 : 13
            rows: tape ? 11 : 13
            unit: grid.u
        }
    }
}
