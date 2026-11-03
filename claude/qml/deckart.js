.pragma library
// Original pixel art and geometry for the two-bay deck.
// Everything is drawn here on a logical pixel grid and handed to QML as SVG, so
// it needs no shaders, works on the software Qt Quick backend, and contains no
// third-party image data. The two character sprites are separate PNG assets.

// Opaque area of each sprite in source pixels; keeps the feet on one baseline.
// Update these if the sprite PNGs are re-cropped.
var SPRITE = {
    miku: { w: 1145, h: 1374, left: 16, top: 113, right: 1132, bottom: 1288 },
    teto: { w: 1182, h: 1330, left: 99, top: 32, right: 1054, bottom: 1278 }
};

var DISC_FRAMES = 8;
var REEL_FRAMES = 6;

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

function mediaOf(provider) {
    return provider === "qq" ? "cd" : (provider === "netease" ? "tape" : "");
}

// ------------------------------------------------------------------ colour

function hexRgb(h) {
    var s = String(h).replace("#", "");
    if (s.length === 8) s = s.substring(2);
    return [parseInt(s.substring(0, 2), 16), parseInt(s.substring(2, 4), 16), parseInt(s.substring(4, 6), 16)];
}
function byteHex(n) {
    var s = Math.round(clamp(n, 0, 255)).toString(16);
    return s.length < 2 ? "0" + s : s;
}
function mix(a, b, t) {
    var x = hexRgb(a), y = hexRgb(b);
    return "#" + byteHex(x[0] + (y[0] - x[0]) * t) + byteHex(x[1] + (y[1] - x[1]) * t) + byteHex(x[2] + (y[2] - x[2]) * t);
}

// Faceplate colours follow the browsing theme; the media always keep their own.
function colors(p) {
    return {
        bg: String(p.pane),
        face: String(p.bar),
        faceHi: String(p.barHover),
        faceLo: mix(p.bar, p.pane, 0.36),
        faceDeep: mix(p.bar, p.pane, 0.62),
        edge: String(p.mint),
        line: mix(p.pane, "#000000", 0.55),
        well: mix(p.pane, "#000000", 0.28),
        bay: String(p.pane),
        lamp: mix(p.pane, "#000000", 0.42),
        ink: String(p.ink)
    };
}

// ------------------------------------------------------------------ pixel grid

function Grid(w, h) {
    this.w = w;
    this.h = h;
    this.cells = new Uint16Array(w * h); // 0 is transparent
    this.inks = [""];
    this.lookup = {};
}
Grid.prototype.ink = function (c) {
    var n = this.lookup[c];
    if (n === undefined) {
        n = this.inks.length;
        this.inks.push(c);
        this.lookup[c] = n;
    }
    return n;
};
Grid.prototype.fill = function (x, y, w, h, n) {
    var x1 = Math.min(this.w, x + w), y1 = Math.min(this.h, y + h);
    for (var j = Math.max(0, y); j < y1; j++)
        for (var i = Math.max(0, x); i < x1; i++) this.cells[j * this.w + i] = n;
};
Grid.prototype.dot = function (x, y, c) {
    if (x >= 0 && y >= 0 && x < this.w && y < this.h) this.cells[y * this.w + x] = this.ink(c);
};
Grid.prototype.rect = function (x, y, w, h, c) { this.fill(x, y, w, h, this.ink(c)); };
Grid.prototype.clear = function (x, y, w, h) { this.fill(x, y, w, h, 0); };
// Corner-notched panel: one pixel off each corner reads as moulded plastic.
Grid.prototype.plate = function (x, y, w, h, c) {
    this.rect(x + 1, y, w - 2, h, c);
    this.rect(x, y + 1, 1, h - 2, c);
    this.rect(x + w - 1, y + 1, 1, h - 2, c);
};
// Recessed window: dark top/left lip, lit bottom/right lip.
Grid.prototype.recess = function (x, y, w, h, fill, lip, lit) {
    this.plate(x, y, w, h, lip);
    this.rect(x + 1, y + 1, w - 2, h - 2, fill);
    this.rect(x + 1, y + h - 1, w - 2, 1, lit);
    this.rect(x + w - 1, y + 1, 1, h - 2, lit);
};
Grid.prototype.svg = function () {
    var w = this.w, h = this.h, cells = this.cells, open = {}, done = {}, y, x, key, run;
    for (y = 0; y < h; y++) {
        x = 0;
        while (x < w) {
            var c = cells[y * w + x];
            if (c === 0) { x++; continue; }
            var start = x;
            while (x < w && cells[y * w + x] === c) x++;
            key = c + "|" + start + "|" + (x - start);
            run = open[key];
            if (run && run.y + run.h === y) run.h++;
            else {
                run = { x: start, y: y, w: x - start, h: 1 };
                open[key] = run;
                if (!done[c]) done[c] = [];
                done[c].push(run);
            }
        }
    }
    var out = '<svg xmlns="http://www.w3.org/2000/svg" width="' + w + '" height="' + h + '" viewBox="0 0 ' + w + ' ' + h + '">';
    for (var n = 1; n < this.inks.length; n++) {
        var list = done[n];
        if (!list) continue;
        var parts = [], color = this.inks[n];
        for (var i = 0; i < list.length; i++) {
            run = list[i];
            parts.push("M" + run.x + " " + run.y + "h" + run.w + "v" + run.h + "h" + (-run.w) + "z");
        }
        var at = color.indexOf("@");
        var paint = at < 0 ? 'fill="' + color + '"'
            : 'fill="' + color.substring(0, at) + '" fill-opacity="' + color.substring(at + 1) + '"';
        out += '<path shape-rendering="crispEdges" ' + paint + ' d="' + parts.join("") + '"/>';
    }
    return out + "</svg>";
};

// ------------------------------------------------------------------ layout

// The deck is stepped: a tower holds the two bays, the low shelf beside it holds
// the mascot, and the album spans the full width underneath.
// All values are logical deck pixels unless the name ends in Px.
function layout(width, height, unit) {
    var u = Math.max(1, Math.floor(unit));
    var lw = Math.max(120, Math.floor(width / u));
    var lh = Math.max(200, Math.floor(height / u));
    var side = 5, top = 3, gap = 3;
    var devW = lw - 2 * side;
    var innerX = side + 4;
    var innerW = devW - 8;
    var vfdH = lw >= 200 ? 19 : 17;
    var below = vfdH + 16; // lid, well lip, gaps, bottom edge, outline and feet

    // The album takes the width; the shelf band takes the height that is left.
    var caseSide = Math.min(innerW - 2, lh - top - 58 - below);
    caseSide -= caseSide % 2;
    var band = lh - top - caseSide - below;
    var maxBand = Math.round(devW * 0.6);
    var grilleH = 0;
    if (band - maxBand >= 14) { // very tall window: a speaker takes the surplus
        grilleH = band - maxBand - gap;
        band = maxBand;
    }
    var shelfY = top + band;

    var figH = Math.min(band - 4, Math.floor(devW * 0.45));
    var nicheW = Math.ceil(figH * 0.95) + 5;
    var tower = { x: side + nicheW, y: top, w: devW - nicheW, h: band + 3 };

    var stackX = tower.x + 4, stackY = top + 4, stackH = band - 3;
    var railW = 7;
    var bayW = tower.w - 8 - railW - 2;
    var bayH = Math.floor((stackH - 2) / 2);
    var bayA = { x: stackX, y: stackY, w: bayW, h: bayH };
    var bayB = { x: stackX, y: stackY + bayH + 2, w: bayW, h: bayH };
    var sw = { x: stackX + bayW + 2, y: stackY, w: railW, h: 2 * bayH + 2 };

    var wellY = shelfY + 4;
    var wellH = caseSide + 2;
    var well = { x: innerX, y: wellY, w: innerW, h: wellH };
    var cs = { x: innerX + Math.floor((innerW - caseSide) / 2), y: wellY + 1, s: caseSide };
    var cover = { x: cs.x + 2, y: cs.y + 2, s: caseSide - 4 };
    cover.band = 11;
    cover.rowH = Math.max(12, Math.floor((cover.s - cover.band - 6) / 5));

    var vfdY = wellY + wellH + gap;
    var vfd = { x: innerX, y: vfdY, w: innerW, h: vfdH };
    var grille = { x: innerX, y: vfdY + vfdH + gap, w: innerW, h: grilleH };
    var contentEnd = grilleH > 0 ? grille.y + grilleH : vfdY + vfdH;
    var base = { x: side, y: shelfY, w: devW, h: contentEnd + gap + 1 - shelfY };

    var d = bayH - 4;
    if (d % 2 === 0) d--;
    var disc = {
        x: bayA.x + 3, y: bayA.y + 2, d: d,
        r: (d - 1) / 2, hub: Math.max(3, Math.round(d * 0.13)), print: Math.round(d * 0.46)
    };

    // The bay label needs its column, so a narrow bay gets a smaller tape.
    var th = bayH - 6;
    var tw = Math.round(th * 1.56);
    if (tw > bayW - 25) { tw = bayW - 25; th = Math.round(tw / 1.56); }
    var tape = { x: bayB.x + 3, y: bayB.y + Math.floor((bayH - th) / 2), w: tw, h: th };
    tape.labelX = 3;
    tape.labelY = 2;
    tape.labelW = tw - 6;
    tape.labelH = Math.round(th * 0.62);
    tape.winH = Math.max(5, Math.round(th * 0.22));
    tape.winW = Math.round(tw * 0.52);
    tape.winX = Math.floor((tw - tape.winW) / 2);
    tape.winY = tape.labelY + Math.floor((tape.labelH - tape.winH) / 2);
    tape.hub = Math.max(2, Math.floor((tape.winH - 1) / 2));
    tape.reelY = tape.winY + Math.floor(tape.winH / 2);
    tape.reelA = tape.winX + tape.hub + 1;
    tape.reelB = tape.winX + tape.winW - tape.hub - 2;

    return {
        u: u, lw: lw, lh: lh,
        ox: Math.floor((width - lw * u) / 2), oy: Math.floor(height - lh * u),
        figH: figH, figTeto: Math.round(figH * 1.04), baseY: shelfY + 1,
        figX: side + nicheW / 2,
        tower: tower, base: base,
        bayA: bayA, bayB: bayB, sw: sw, well: well, kase: cs, cover: cover,
        vfd: vfd, grille: grille, disc: disc, tape: tape,
        hopY: shelfY - Math.round(figH * 0.55), hopH: Math.max(8, Math.round(figH * 0.2))
    };
}

// On-screen rectangle of a sprite image with its feet on the deck and its opaque
// area centred over cx; both in logical pixels, result in item pixels.
function spriteBox(name, L, cx, visibleH) {
    var s = SPRITE[name];
    var k = visibleH * L.u / (s.bottom - s.top);
    var w = Math.round(s.w * k), h = Math.round(s.h * k);
    var mid = (s.left + s.right) / 2 * k;
    return {
        x: Math.round(cx * L.u - mid),
        y: Math.round(L.baseY * L.u - s.bottom * k),
        w: w, h: h
    };
}

// ------------------------------------------------------------------ deck body

function bodySvg(L, C) {
    var g = new Grid(L.lw, L.lh);
    var t = L.tower, b = L.base;

    // Shadow the device casts on the wall behind it.
    g.rect(b.x + 2, b.y + b.h, b.w - 4, 1, C.line);

    // Stepped silhouette: outlines first, then both faces so they merge.
    g.plate(t.x - 1, t.y - 1, t.w + 2, t.h + 2, C.line);
    g.plate(b.x - 1, b.y - 1, b.w + 2, b.h + 2, C.line);
    g.plate(t.x, t.y, t.w, t.h, C.face);
    g.plate(b.x, b.y, b.w, b.h, C.face);

    g.rect(t.x + 1, t.y, t.w - 2, 1, C.edge);
    g.rect(t.x, t.y + 1, 1, b.y - t.y - 1, C.faceHi);
    g.rect(t.x + t.w - 1, t.y + 1, 1, b.y - t.y, C.faceLo);
    g.rect(b.x + 1, b.y, t.x - b.x - 1, 1, C.edge);
    g.rect(b.x, b.y + 1, 1, b.h - 2, C.faceHi);
    g.rect(b.x + b.w - 1, b.y + 1, 1, b.h - 2, C.faceLo);
    g.rect(b.x + 1, b.y + b.h - 1, b.w - 2, 1, C.faceLo);
    // Shelf seam, and the mascot's contact shadow on it.
    g.rect(b.x + 1, b.y + 2, t.x - b.x - 1, 1, C.faceLo);
    var footW = Math.round(L.figH * 0.42);
    g.rect(Math.round(L.figX - footW / 2), b.y + 1, footW, 1, C.faceDeep);

    // Bays and the routing switch beside them.
    g.recess(L.bayA.x, L.bayA.y, L.bayA.w, L.bayA.h, C.bay, C.line, C.faceHi);
    g.recess(L.bayB.x, L.bayB.y, L.bayB.w, L.bayB.h, C.bay, C.line, C.faceHi);
    g.recess(L.sw.x + 1, L.sw.y, 5, L.sw.h, C.well, C.line, C.faceHi);

    // Album well and display.
    g.recess(L.well.x, L.well.y, L.well.w, L.well.h, C.well, C.line, C.faceHi);
    g.recess(L.vfd.x, L.vfd.y, L.vfd.w, L.vfd.h, C.lamp, C.line, C.faceHi);

    // Rails either side of the album case, when a short window narrows it.
    var railW = L.kase.x - L.well.x - 3;
    if (railW >= 2) {
        for (var ry = L.well.y + 3; ry < L.well.y + L.well.h - 3; ry += 3) {
            g.rect(L.well.x + 2, ry, railW, 1, C.faceDeep);
            g.rect(L.kase.x + L.kase.s + 1, ry, railW, 1, C.faceDeep);
        }
    }

    // Speaker grille: only appears when the window is tall enough to need it.
    if (L.grille.h > 0) {
        for (var y = 0; y < L.grille.h; y += 2) {
            for (var x = (y % 4 === 0 ? 0 : 1); x < L.grille.w; x += 2) {
                g.dot(L.grille.x + x, L.grille.y + y, C.line);
            }
        }
    }

    // Feet.
    g.rect(b.x + 8, b.y + b.h + 1, 12, 2, C.line);
    g.rect(b.x + b.w - 20, b.y + b.h + 1, 12, 2, C.line);
    return g.svg();
}

// ------------------------------------------------------------------ album case

function caseSvg(L) {
    var s = L.kase.s, g = new Grid(s, s);
    g.plate(0, 0, s, s, "#d6dcdc");
    g.rect(1, 1, s - 2, s - 2, "#101416");
    g.rect(1, 0, s - 2, 1, "#ffffff");
    g.rect(1, s - 1, s - 2, 1, "#8d9899");
    g.rect(s - 1, 1, 1, s - 2, "#8d9899");
    return g.svg();
}

// Hand-labelled card used when a song has no cover.
function sleeveSvg(L, tint) {
    var K = L.cover, s = K.s, g = new Grid(s, s);
    var paper = "#f4efe2", rule = mix(paper, tint, 0.3);
    g.rect(0, 0, s, s, paper);
    g.rect(0, 0, s, K.band, tint);
    g.rect(0, s - 2, s, 2, tint);
    for (var y = K.band + K.rowH; y < s - 4; y += K.rowH) g.rect(4, y, s - 8, 1, rule);
    return g.svg();
}

// ------------------------------------------------------------------ compact disc

var DISC = ["#effcfa", "#c7f0ec", "#9fe3dd", "#67d3ca", "#39c5bb", "#f7b9d0"];

function discRing(r, angle, D) {
    if (r > D.r - 0.6) return "#ffffff";
    var band = Math.floor(angle / (Math.PI / 4)) % 2;
    var fine = Math.floor(r) % 3 === 0;
    if (band === 0) return fine ? DISC[0] : DISC[1];
    return fine ? DISC[3] : DISC[2];
}

// Base art: the silver disc as it sits parked in the bay.
function discBaseSvg(L) {
    var D = L.disc, g = new Grid(D.d, D.d), c = D.r;
    for (var y = 0; y < D.d; y++) for (var x = 0; x < D.d; x++) {
        var dx = x - c, dy = y - c, r = Math.sqrt(dx * dx + dy * dy);
        if (r > D.r + 0.3) continue;
        var a = Math.atan2(dy, dx) + Math.PI;
        g.dot(x, y, r > D.print ? DISC[4] : discRing(r, a, D));
    }
    return g.svg();
}

// Frame drawn above the cover: masks the bay corners, rim and hub, leaves the
// printed ring open. A shader-free circular mask.
function discFrameSvg(L, C) {
    var D = L.disc, g = new Grid(D.d, D.d), c = D.r;
    for (var y = 0; y < D.d; y++) for (var x = 0; x < D.d; x++) {
        var dx = x - c, dy = y - c, r = Math.sqrt(dx * dx + dy * dy);
        var a = Math.atan2(dy, dx) + Math.PI;
        if (r > D.r + 0.3) g.dot(x, y, C.bay);
        else if (r > D.print) g.dot(x, y, discRing(r, a, D));
        else if (r <= 1.5) g.dot(x, y, C.bay);
        else if (r <= D.hub - 1) g.dot(x, y, "#ffffff");
        else if (r <= D.hub) g.dot(x, y, "#7fb9b4");
    }
    return g.svg();
}

function discGlintSvg(L) {
    var D = L.disc, n = DISC_FRAMES, g = new Grid(D.d * n, D.d), c = D.r;
    for (var f = 0; f < n; f++) {
        var at = f / n * Math.PI;
        for (var y = 0; y < D.d; y++) for (var x = 0; x < D.d; x++) {
            var dx = x - c, dy = y - c, r = Math.sqrt(dx * dx + dy * dy);
            if (r > D.r - 0.6 || r < D.hub + 1) continue;
            var diff = Math.abs(((Math.atan2(dy, dx) - at) % Math.PI + Math.PI) % Math.PI);
            if (diff > Math.PI / 2) diff = Math.PI - diff;
            if (diff < 0.17) g.dot(f * D.d + x, y, "#ffffff@0.55");
            else if (diff < 0.3 && (x + y) % 2 === 0) g.dot(f * D.d + x, y, "#ffffff@0.3");
        }
    }
    return g.svg();
}

// ------------------------------------------------------------------ cassette

// Label art of a parked tape, beneath the shell.
function tapeBaseSvg(L) {
    var T = L.tape, g = new Grid(T.w, T.h);
    g.rect(T.labelX, T.labelY, T.labelW, T.labelH, "#fbedee");
    g.rect(T.labelX, T.labelY + 2, T.labelW, 2, "#f11c30");
    g.rect(T.labelX, T.labelY + T.labelH - 3, T.labelW, 1, "#941e26");
    return g.svg();
}

// Shell over the label: window, screws and head block. Shader-free label mask.
function tapeFrameSvg(L) {
    var T = L.tape, g = new Grid(T.w, T.h), shell = "#332a2e", hi = "#54474d", lo = "#1a1417";
    g.plate(0, 0, T.w, T.h, shell);
    g.rect(1, 0, T.w - 2, 1, hi);
    g.rect(0, 1, 1, T.h - 2, hi);
    g.rect(1, T.h - 1, T.w - 2, 1, lo);
    g.rect(T.w - 1, 1, 1, T.h - 2, lo);
    // Open the label.
    g.clear(T.labelX, T.labelY, T.labelW, T.labelH);
    // Reel window.
    g.rect(T.winX - 1, T.winY - 1, T.winW + 2, T.winH + 2, shell);
    g.rect(T.winX, T.winY, T.winW, T.winH, "#120c0e");
    // Head block.
    var hy = T.labelY + T.labelH + 1, hx = Math.round(T.w * 0.2), hw = T.w - 2 * hx;
    g.rect(hx, hy, hw, Math.max(2, T.h - hy - 1), lo);
    g.rect(hx + 1, hy, hw - 2, 1, hi);
    g.dot(hx + 2, hy + 1, "#fbedee");
    g.dot(hx + hw - 3, hy + 1, "#fbedee");
    g.dot(hx + Math.floor(hw / 2), hy + 1, "#fbedee");
    // Screws.
    g.dot(1, T.h - 2, hi);
    g.dot(T.w - 2, T.h - 2, hi);
    return g.svg();
}

function reelSheetSvg(L) {
    var T = L.tape, r = T.hub, n = REEL_FRAMES, s = 2 * r + 1, g = new Grid(s * n, s);
    var step = Math.PI / 3;
    for (var f = 0; f < n; f++) {
        var at = f / n * step;
        for (var y = 0; y < s; y++) for (var x = 0; x < s; x++) {
            var dx = x - r, dy = y - r, q = Math.sqrt(dx * dx + dy * dy);
            if (q > r + 0.3) continue;
            var a = ((Math.atan2(dy, dx) - at) % step + step) % step;
            var tooth = q >= r * 0.5 && (a < 0.28 || a > step - 0.28);
            g.dot(f * s + x, y, q > r - 0.7 || tooth ? "#f4e9e4" : "#2a2024");
        }
    }
    return g.svg();
}

// Width of the tape pack visible beside a reel, 0..1 of the room available.
function packWidth(L, remaining) {
    var T = L.tape, room = Math.floor(T.winW / 2) - T.hub - 2;
    return Math.max(1, Math.round(1 + (room - 1) * Math.sqrt(clamp(remaining, 0, 1))));
}

// ------------------------------------------------------------------ small props

function miniDiscSvg() {
    var g = new Grid(13, 13), c = 6;
    for (var y = 0; y < 13; y++) for (var x = 0; x < 13; x++) {
        var dx = x - c, dy = y - c, r = Math.sqrt(dx * dx + dy * dy);
        if (r > 6.4) continue;
        if (r <= 1) continue;
        g.dot(x, y, r > 5.5 ? "#ffffff" : (r <= 2.5 ? "#ffffff" : ((x - y) > 0 ? DISC[1] : DISC[3])));
    }
    return g.svg();
}

function miniTapeSvg() {
    var g = new Grid(17, 11);
    g.plate(0, 0, 17, 11, "#332a2e");
    g.rect(2, 1, 13, 6, "#fbedee");
    g.rect(2, 2, 13, 1, "#f11c30");
    g.rect(4, 4, 9, 2, "#120c0e");
    g.dot(5, 4, "#f4e9e4");
    g.dot(11, 4, "#f4e9e4");
    g.rect(4, 8, 9, 2, "#1a1417");
    return g.svg();
}

function dataUrl(svg) {
    return svg ? "data:image/svg+xml," + encodeURIComponent(svg) : "";
}

// ------------------------------------------------------------------ state

// Pure reading of the store, so the deck never derives state in two places.
function deckState(s) {
    var media = s.hasTrack ? mediaOf(s.playingProvider) : "";
    var offline = !!s.hasTrack && s.connected === false;
    var failed = !offline && !!s.hasTrack && (!!s.failed || String(s.playError || "") !== "");
    var busy = !offline && !failed && (!!s.loading || !!s.buffering);
    var spinning = !offline && !failed && !busy && !!s.playing && !!s.hasTrack;
    var word = "NO MEDIA", icon = "";
    if (s.hasTrack) {
        if (offline) word = s.reconnecting ? "RECONNECT" : "OFFLINE";
        else if (failed) word = "ERROR";
        else if (s.loading) word = "LOADING";
        else if (s.buffering) word = "BUFFER";
        else if (s.playing) { word = "PLAY"; icon = "{play}"; }
        else { word = "PAUSE"; icon = "{pause}"; }
    } else if (s.loading) word = "LOADING";
    return { media: media, offline: offline, failed: failed, busy: busy, spinning: spinning, word: word, icon: icon };
}
