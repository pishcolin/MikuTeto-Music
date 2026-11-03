.pragma library
// Palette sampled from wallpaper-reference.png (frame #39C5BB, bar #176E78, pane #031C22).

var mint = "#39c5bb";
var mintDim = "#1f6f6c";
var bar = "#176e78";
var barHover = "#1f8691";
var pane = "#031c22";
var raised = "#06262d";
var hover = "#0a333b";
var select = "#0e414a";
var rule = "#0f3b43";
var ink = "#e7f6f4";
var inkDim = "#8ab7b4";
var inkFaint = "#4e7f7e";
var alert = "#ff6474";
var alertBar = "#8e2a3a";
var trial = "#f2e48a";
var paper = "#ffffff";
var veil = "#99031c22";

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

function num(v) { var n = Number(v); return isFinite(n) ? n : 0; }

function pad2(n) { return n < 10 ? "0" + n : "" + n; }

// m:ss for list durations (input milliseconds)
function time(ms) {
    ms = num(ms);
    if (ms <= 0) return "0:00";
    var t = Math.floor(ms / 1000), h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
    return h > 0 ? h + ":" + pad2(m) + ":" + pad2(s) : m + ":" + pad2(s);
}

// zero-padded readout for the pixel clock
function clock(ms) {
    ms = num(ms);
    var t = Math.max(0, Math.floor(ms / 1000)), h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
    return h > 0 ? h + ":" + pad2(m) + ":" + pad2(s) : pad2(m) + ":" + pad2(s);
}

function isList(v) { return !!v && typeof v === "object" && typeof v.length === "number"; }

function artists(item) {
    if (!item) return "";
    if (item.artist) return String(item.artist);
    if (isList(item.artists)) {
        var names = [];
        for (var i = 0; i < item.artists.length; i++) if (item.artists[i] && item.artists[i].name) names.push(item.artists[i].name);
        return names.join(" / ");
    }
    return "";
}

function keyOf(item) {
    if (!item) return "";
    if (item.key) return String(item.key);
    var id = item.id || item.mediaId || item.songID || item.title;
    return id ? String((item.kind || "") + ":" + id) : "";
}

var kindLabel = { song: "歌曲", album: "专辑", artist: "歌手", playlist: "歌单" };
var kindPixel = { song: "SONG", album: "ALBUM", artist: "ARTIST", playlist: "PLAYLIST" };

// Source identity for mixed lists (local Favorites, the shared queue). These are
// deliberately not skin-reactive: QQ songs always carry MIKU's teal and NetEase
// songs TETO's red (both sampled from the skins' window frames), so the source
// of a song reads the same whichever skin is browsing.
var sourceTint = { qq: "#39c5bb", netease: "#f11c30" };
var sourceShort = { qq: "QQ", netease: "163" };
var sourceName = { qq: "QQ 音乐", netease: "网易云音乐" };
var sourceSkin = { qq: "MIKU", netease: "TETO" };

function providerOf(item) { return item && item.provider ? String(item.provider) : ""; }
function sourceLabel(p) { return sourceName[p] || ""; }
