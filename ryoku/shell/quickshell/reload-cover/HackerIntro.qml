pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import Ryoku.Ui.Singletons
import "PixelFont.js" as PixelFont

// The user's own login intro: a decrypting title, a typed tagline and a quiet
// terminal HUD, drawn on the reload cover in place of the Ryoku wordmark.
// Every choice lives in ~/.config/ryoku/intro.json (Hub > Desktop > General).
// The surface stays transparent: the cover underneath supplies the black, so
// the reload iris still reads through it.
Item {
    id: intro

    property bool active: true
    readonly property string mode: Quickshell.env("RYOKU_RELOAD_COVER_MODE") || ""
    readonly property real s: Math.max(0.12, Math.min(width / 1920, height / 1080))
    readonly property bool calm: Tokens.reduceMotion
    readonly property string mono: "JetBrainsMono Nerd Font"

    // ── config ───────────────────────────────────────────────────────────
    readonly property string cfgPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/intro.json"
    FileView {
        id: cfgFile
        path: intro.cfgPath
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        JsonAdapter {
            id: cfg
            property bool enabled: false
            property string title: "ANDERSONK"
            property string subtitle: "Full Stack Developer"
            property string tagline: "React · Next.js · Node.js · TypeScript"
            property string header: "ACCESS GRANTED"
            property string style: "pixel"
            property string accent: "#6EE7F9"
            property string accent2: "#34D399"
            property bool rain: true
            property bool glitch: true
            property bool scanlines: true
            property bool bootLog: true
            property real minHold: 3
        }
    }
    Connections {
        target: cfg
        function onTitleChanged() { intro.restart(); }
        function onStyleChanged() { intro.restart(); }
        function onSubtitleChanged() { intro.restart(); }
    }

    // Small facts for the boot log; read once, never written.
    FileView { id: kernelFile; path: "/proc/sys/kernel/osrelease"; blockLoading: true; printErrors: false }
    FileView { id: hostFile; path: "/etc/hostname"; blockLoading: true; printErrors: false }
    readonly property string kernel: (kernelFile.text() || "").trim() || "linux"
    readonly property string host: (hostFile.text() || "").trim() || "localhost"
    readonly property string user: Quickshell.env("USER") || "user"

    // ── palette ──────────────────────────────────────────────────────────
    function hexOr(v, fallback) {
        var t = String(v === undefined || v === null ? "" : v).trim();
        if (!/^#?[0-9a-fA-F]{6}$/.test(t)) return fallback;
        return t[0] === "#" ? t : "#" + t;
    }
    readonly property color c1: hexOr(cfg.accent, "#6EE7F9")
    readonly property color c2: hexOr(cfg.accent2, "#34D399")
    readonly property color ink: "#E6F1FF"
    readonly property color dim: "#5E7287"
    readonly property color white: "#ffffff"
    readonly property color black: "#000000"
    function mix(a, b, k) {
        k = Math.max(0, Math.min(1, k));
        return Qt.rgba(a.r + (b.r - a.r) * k, a.g + (b.g - a.g) * k, a.b + (b.b - a.b) * k, 1);
    }
    function hex(c) {
        function h(v) { var x = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16); return x.length < 2 ? "0" + x : x; }
        return "#" + h(c.r) + h(c.g) + h(c.b);
    }
    function esc(ch) {
        if (ch === " ") return "&nbsp;";
        if (ch === "&") return "&amp;";
        if (ch === "<") return "&lt;";
        if (ch === ">") return "&gt;";
        return ch;
    }

    // ── timeline ─────────────────────────────────────────────────────────
    // One clock drives the whole entrance; once it stops, only the idle loops
    // (rain, cursor, glitch, the status sweep) keep the GPU awake.
    readonly property string styleKey: cfg.style === "terminal" ? "terminal" : "pixel"
    readonly property string titleText: {
        var raw = String(cfg.title || "").trim();
        if (raw === "") raw = "RYOKU";
        return intro.styleKey === "pixel" ? PixelFont.fold(raw) : raw.toUpperCase();
    }
    readonly property int n: titleText.length
    readonly property real decodeStart: 160
    readonly property real stagger: Math.min(95, 760 / Math.max(1, n))
    function revealAt(i) { return decodeStart + 260 + i * stagger; }
    readonly property real decodeEnd: revealAt(Math.max(0, n - 1)) + 140
    readonly property string subText: String(cfg.subtitle || "")
    readonly property real typeStart: decodeEnd + 140
    readonly property real typeStep: Math.max(16, Math.min(46, 1000 / Math.max(1, subText.length)))
    readonly property real typeEnd: typeStart + typeStep * subText.length
    readonly property real tagAt: typeEnd + 140
    readonly property real total: tagAt + 600

    property real t: 0
    readonly property int tick: Math.floor(t / 50)
    property bool lockFired: false

    NumberAnimation {
        id: clock
        target: intro
        property: "t"
        from: 0
        to: intro.total
        duration: intro.total
        paused: running && !intro.active
    }
    function restart() {
        clock.stop();
        lockFired = false;
        glitch = 0;
        if (calm) {
            t = total;
            return;
        }
        t = 0;
        clock.start();
    }
    Component.onCompleted: restart()
    onTChanged: {
        if (!lockFired && t >= decodeEnd) {
            lockFired = true;
            if (cfg.glitch && !calm) fireGlitch();
        }
    }

    function hash(i, k) {
        var h = Math.imul(i | 0, 374761393) + Math.imul(k | 0, 668265263);
        h = Math.imul(h ^ (h >>> 13), 1274126177);
        h = h ^ (h >>> 16);
        return (h >>> 0) / 4294967295;
    }
    readonly property string noiseSet: "ABCDEF0123456789#$%&@*+=<>/\\|{}[]"
    function noiseChar(i, k) { return noiseSet[Math.floor(hash(i, k) * noiseSet.length) % noiseSet.length]; }

    // Idle loop, 0..1 every 1.2 s: the spinner, the status sweep, the cursor.
    property real loop: 0
    NumberAnimation on loop {
        from: 0
        to: 1
        duration: 1200
        loops: Animation.Infinite
        running: intro.active && !intro.calm
    }
    readonly property bool cursorOn: calm || t < typeEnd || loop < 0.5

    // ── glitch ───────────────────────────────────────────────────────────
    property real glitch: 0
    property real seed: 0.5
    function fireGlitch() {
        seed = Math.random();
        glitchAnim.restart();
    }
    SequentialAnimation {
        id: glitchAnim
        PropertyAction { target: intro; property: "glitch"; value: 1 }
        PauseAnimation { duration: 70 }
        ScriptAction { script: intro.seed = Math.random() }
        PauseAnimation { duration: 55 }
        ScriptAction { script: intro.seed = Math.random() }
        PauseAnimation { duration: 40 }
        PropertyAction { target: intro; property: "glitch"; value: 0 }
    }
    Timer {
        id: glitchTimer
        interval: 2400
        repeat: true
        running: cfg.glitch && intro.active && !intro.calm && intro.lockFired
        onTriggered: {
            interval = 1800 + Math.floor(Math.random() * 2600);
            intro.fireGlitch();
        }
    }

    // ── code rain ────────────────────────────────────────────────────────
    // Drawn at half resolution and scaled up unsmoothed: a quarter of the
    // pixels to push, and the glyphs come out as crisp blocks.
    Canvas {
        id: rain
        visible: cfg.rain
        width: Math.ceil(intro.width / 2)
        height: Math.ceil(intro.height / 2)
        scale: 2
        transformOrigin: Item.TopLeft
        smooth: false
        opacity: (intro.calm ? 1 : Math.min(1, intro.t / 700)) * 0.34

        property var drops: []
        readonly property int fs: Math.max(4, Math.round(9 * intro.s))
        readonly property real cw: fs * 1.25
        readonly property string glyphs: "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾊﾋﾌﾍﾎﾏﾐﾑﾒﾓﾔﾕﾗﾘﾜ0123456789ABCDEF<>/=+*"
        property string headCss: "#ffffff"
        property string trailCss: "#6EE7F9"

        onWidthChanged: drops = []
        onHeightChanged: drops = []

        function seedDrops() {
            var cols = Math.ceil(width / cw);
            var d = [];
            for (var i = 0; i < cols; i++)
                d.push({ y: -Math.random() * height / fs * 1.4, v: 0.25 + Math.random() * 0.55, last: -1 });
            drops = d;
        }

        onPaint: {
            var ctx = getContext("2d");
            if (!drops.length) {
                ctx.reset();
                seedDrops();
            }
            ctx.globalCompositeOperation = "destination-out";
            ctx.fillStyle = "rgba(0,0,0,0.16)";
            ctx.fillRect(0, 0, width, height);
            ctx.globalCompositeOperation = "source-over";
            ctx.font = fs + "px \"" + intro.mono + "\"";
            ctx.textBaseline = "top";
            for (var i = 0; i < drops.length; i++) {
                var d = drops[i];
                d.y += d.v;
                if (d.y < 0) continue;
                var row = Math.floor(d.y);
                if (row !== d.last) {
                    var x = i * cw;
                    if (d.last >= 0) {
                        ctx.fillStyle = trailCss;
                        ctx.fillText(glyphs[Math.floor(Math.random() * glyphs.length)], x, d.last * fs);
                    }
                    ctx.fillStyle = headCss;
                    ctx.fillText(glyphs[Math.floor(Math.random() * glyphs.length)], x, row * fs);
                    d.last = row;
                }
                if (row * fs > height + Math.random() * height * 0.6) {
                    d.y = -Math.random() * 18;
                    d.v = 0.25 + Math.random() * 0.55;
                    d.last = -1;
                }
            }
        }
        Timer {
            interval: 50
            repeat: true
            running: rain.visible && intro.active && !intro.calm
            onTriggered: {
                rain.headCss = intro.hex(intro.mix(intro.c1, intro.white, 0.75));
                rain.trailCss = intro.hex(intro.c1);
                rain.requestPaint();
            }
        }
    }
    // keep the centre legible: the rain lives at the edges
    RadialGradient {
        anchors.fill: parent
        visible: cfg.rain
        horizontalRadius: width * 0.62
        verticalRadius: height * 0.62
        gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.94) }
            GradientStop { position: 0.42; color: Qt.rgba(0, 0, 0, 0.72) }
            GradientStop { position: 0.78; color: Qt.rgba(0, 0, 0, 0.0) }
        }
    }

    // ── centre stack ─────────────────────────────────────────────────────
    Column {
        id: stack
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -Math.round(18 * intro.s)
        spacing: 0

        // header: DECRYPTING… then the user's seal
        Row {
            id: header
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(12 * intro.s)
            opacity: intro.calm ? 1 : Math.min(1, intro.t / 220)
            readonly property bool granted: intro.t >= intro.decodeEnd
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(2, Math.round(7 * intro.s))
                height: width
                radius: width / 2
                color: header.granted ? intro.c2 : intro.c1
                opacity: header.granted ? 1 : (intro.tick % 6 < 3 ? 1 : 0.25)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: header.granted
                    ? String(cfg.header || "").toUpperCase()
                    : I18n.tr("DECRYPTING IDENTITY") + [".  ", ".. ", "..."][intro.tick % 3]
                color: header.granted ? intro.c2 : intro.c1
                font.family: intro.mono
                font.pixelSize: Math.max(5, Math.round(14 * intro.s))
                font.weight: Font.Medium
                font.letterSpacing: Math.round(6 * intro.s)
            }
        }

        Item { width: 1; height: Math.max(0, Math.round(30 * intro.s) - art.pad) }

        // title, with its glow, its glitch ghosts and its slices
        Item {
            id: titleHolder
            anchors.horizontalCenter: parent.horizontalCenter
            width: art.width
            height: art.height

            Glow {
                anchors.fill: art
                source: art
                radius: Math.max(2, Math.round(16 * intro.s))
                samples: 25
                spread: 0.18
                color: intro.c1
                transparentBorder: false
                opacity: 0.5 * Math.min(1, Math.max(0, (intro.t - intro.decodeStart) / 600))
            }

            Item {
                id: art
                readonly property int cols: PixelFont.columns(intro.titleText)
                readonly property real cell: Math.max(2, Math.floor(Math.min(
                    intro.width * 0.62 / Math.max(1, cols),
                    intro.height * 0.15 / PixelFont.H)))
                readonly property real gap: Math.max(1, Math.round(cell * 0.12))
                // room for the glow inside the layer, so it never clips or shifts
                readonly property int pad: Math.round(24 * intro.s)
                readonly property int termSize: Math.max(8, Math.round(Math.min(intro.height * 0.13, intro.width * 0.62 / Math.max(1, intro.n * 0.66))))
                width: (intro.styleKey === "pixel" ? cols * cell : term.implicitWidth) + pad * 2
                height: (intro.styleKey === "pixel" ? PixelFont.H * cell : term.implicitHeight) + pad * 2
                x: intro.glitch > 0 ? Math.round((intro.seed - 0.5) * 8 * intro.s) : 0
                layer.enabled: true

                Repeater {
                    model: intro.styleKey === "pixel" ? PixelFont.cells(intro.titleText) : []
                    delegate: Rectangle {
                        id: px
                        required property var modelData
                        required property int index
                        readonly property real rv: intro.revealAt(modelData.gi)
                        readonly property real since: intro.t - rv
                        readonly property bool locked: since >= 0
                        readonly property color base: intro.mix(intro.c1, intro.c2, modelData.col / Math.max(1, art.cols - 1))
                        readonly property real ramp: Math.max(0, Math.min(1, (intro.t - intro.decodeStart) / 260))
                        x: art.pad + modelData.col * art.cell + art.gap / 2
                        y: art.pad + modelData.row * art.cell + art.gap / 2
                        width: art.cell - art.gap
                        height: art.cell - art.gap
                        color: locked
                            ? (since < 150 ? intro.mix(intro.white, base, since / 150) : base)
                            : intro.c1
                        opacity: locked
                            ? (modelData.on ? 1 : 0)
                            : (intro.hash(index, intro.tick) < 0.36 * ramp ? 0.15 + 0.45 * intro.hash(index + 911, intro.tick) : 0)
                    }
                }

                Text {
                    id: term
                    x: art.pad
                    y: art.pad
                    visible: intro.styleKey === "terminal"
                    textFormat: Text.StyledText
                    font.family: intro.mono
                    font.weight: Font.ExtraBold
                    font.pixelSize: art.termSize
                    font.letterSpacing: Math.round(art.termSize * 0.06)
                    text: {
                        if (intro.styleKey !== "terminal") return "";
                        var out = "";
                        for (var i = 0; i < intro.n; i++) {
                            var ch = intro.titleText[i];
                            var since = intro.t - intro.revealAt(i);
                            if (ch === " ") { out += "&nbsp;"; continue; }
                            if (since >= 0) {
                                var base = intro.mix(intro.c1, intro.c2, i / Math.max(1, intro.n - 1));
                                var col = since < 150 ? intro.mix(intro.white, base, since / 150) : base;
                                out += "<font color=\"" + intro.hex(col) + "\">" + intro.esc(ch) + "</font>";
                            } else if (intro.t >= intro.decodeStart) {
                                out += "<font color=\"" + intro.hex(intro.mix(intro.c1, intro.black, 0.3)) + "\">" + intro.esc(intro.noiseChar(i, intro.tick)) + "</font>";
                            } else {
                                out += "&nbsp;";
                            }
                        }
                        return out;
                    }
                }
            }

            // chromatic ghosts, only while a glitch fires
            ColorOverlay {
                visible: intro.glitch > 0
                x: art.x - Math.round((3 + intro.seed * 6) * intro.s)
                width: art.width
                height: art.height
                source: art
                color: "#FF2BD6"
                opacity: 0.55
            }
            ColorOverlay {
                visible: intro.glitch > 0
                x: art.x + Math.round((3 + (1 - intro.seed) * 6) * intro.s)
                width: art.width
                height: art.height
                source: art
                color: "#00E5FF"
                opacity: 0.55
            }
            Repeater {
                model: 2
                delegate: Item {
                    id: slice
                    required property int index
                    readonly property real k: intro.hash(index + 3, Math.floor(intro.seed * 1000))
                    readonly property real sh: Math.max(2, Math.round(art.height * (0.08 + 0.14 * k)))
                    readonly property real sy: Math.round((art.height - sh) * intro.hash(index + 17, Math.floor(intro.seed * 1000)))
                    visible: intro.glitch > 0
                    x: 0
                    y: sy
                    width: art.width
                    height: sh
                    Rectangle { anchors.fill: parent; color: "black" }
                    ShaderEffectSource {
                        x: Math.round((slice.k - 0.5) * 34 * intro.s)
                        width: art.width
                        height: slice.sh
                        sourceItem: art
                        sourceRect: Qt.rect(0, slice.sy, art.width, slice.sh)
                        live: true
                    }
                }
            }
        }

        Item { width: 1; height: Math.max(0, Math.round(38 * intro.s) - art.pad) }

        // typed subtitle with a block cursor
        Item {
            id: subLine
            anchors.horizontalCenter: parent.horizontalCenter
            width: subMetrics.advanceWidth + cursor.width + cursor.anchors.leftMargin
            height: subMetrics.height
            visible: intro.subText !== ""
            readonly property int typed: intro.calm ? intro.subText.length
                : Math.max(0, Math.min(intro.subText.length, Math.floor((intro.t - intro.typeStart) / intro.typeStep)))
            opacity: intro.calm || intro.t >= intro.typeStart - 80 ? 1 : 0

            TextMetrics {
                id: subMetrics
                font: subLabel.font
                text: "> " + intro.subText
            }
            Text {
                id: subLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.StyledText
                font.family: intro.mono
                font.pixelSize: Math.max(6, Math.round(30 * intro.s))
                text: "<font color=\"" + intro.hex(intro.c1) + "\">&gt;&nbsp;</font>"
                    + "<font color=\"" + intro.hex(intro.ink) + "\">"
                    + intro.subText.substring(0, subLine.typed).split("").map(intro.esc).join("")
                    + "</font>"
            }
            Rectangle {
                id: cursor
                anchors.left: subLabel.right
                anchors.leftMargin: Math.round(4 * intro.s)
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(2, Math.round(subLabel.font.pixelSize * 0.55))
                height: Math.round(subLabel.font.pixelSize * 1.05)
                color: intro.c1
                opacity: intro.cursorOn ? 0.9 : 0
            }
        }

        Item { width: 1; height: Math.round(16 * intro.s) }

        Text {
            id: tag
            anchors.horizontalCenter: parent.horizontalCenter
            visible: String(cfg.tagline || "") !== ""
            readonly property real k: intro.calm ? 1 : Math.max(0, Math.min(1, (intro.t - intro.tagAt) / 420))
            text: String(cfg.tagline || "")
            color: intro.mix(intro.dim, intro.c2, 0.35)
            font.family: intro.mono
            font.pixelSize: Math.max(5, Math.round(17 * intro.s))
            font.letterSpacing: Math.round(3 * intro.s)
            opacity: k
            transform: Translate { y: (1 - tag.k) * 10 * intro.s }
        }
    }

    // HUD brackets around the stack
    Item {
        id: hud
        readonly property real pad: Math.round(46 * intro.s)
        readonly property real len: Math.round(34 * intro.s) * (intro.calm ? 1 : Math.min(1, intro.t / 420))
        readonly property real th: Math.max(1, Math.round(2 * intro.s))
        x: stack.x - pad
        y: stack.y - pad
        width: stack.width + pad * 2
        height: stack.height + pad * 2
        opacity: 0.55
        Repeater {
            model: 4
            delegate: Item {
                id: corner
                required property int index
                readonly property bool isRight: index === 1 || index === 3
                readonly property bool isBottom: index >= 2
                x: isRight ? hud.width - hud.len : 0
                y: isBottom ? hud.height - hud.len : 0
                width: hud.len
                height: hud.len
                Rectangle { x: 0; y: corner.isBottom ? parent.height - hud.th : 0; width: parent.width; height: hud.th; color: intro.c1 }
                Rectangle { x: corner.isRight ? parent.width - hud.th : 0; y: 0; width: hud.th; height: parent.height; color: intro.c1 }
            }
        }
    }

    // ── status: spinner + label + sweep ─────────────────────────────────
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Math.round(70 * intro.s)
        spacing: Math.round(10 * intro.s)
        opacity: intro.calm ? 1 : Math.min(1, intro.t / 500)

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Math.round(10 * intro.s)
            Text {
                text: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[Math.floor(intro.loop * 10) % 10]
                color: intro.c1
                font.family: intro.mono
                font.pixelSize: Math.max(5, Math.round(13 * intro.s))
            }
            Text {
                text: intro.mode === "reload" ? I18n.tr("SHELL RELOADING")
                    : (intro.mode === "boot" ? I18n.tr("LOADING DESKTOP") : I18n.tr("PREVIEW"))
                color: intro.ink
                opacity: 0.62
                font.family: intro.mono
                font.pixelSize: Math.max(5, Math.round(12 * intro.s))
                font.letterSpacing: Math.round(4 * intro.s)
            }
        }
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: Math.round(240 * intro.s)
            height: Math.max(1, Math.round(2 * intro.s))
            color: Qt.rgba(intro.c1.r, intro.c1.g, intro.c1.b, 0.16)
            clip: true
            Rectangle {
                width: parent.width * 0.32
                height: parent.height
                x: -width + (parent.width + width) * intro.loop
                color: intro.c1
            }
        }
    }

    // ── boot log, bottom left ───────────────────────────────────────────
    Column {
        visible: cfg.bootLog
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: Math.round(48 * intro.s)
        anchors.bottomMargin: Math.round(44 * intro.s)
        spacing: Math.round(5 * intro.s)

        Repeater {
            model: [
                { at: 220, label: "kernel", value: intro.kernel },
                { at: 520, label: "host", value: intro.host },
                { at: 820, label: "identity", value: intro.user },
                { at: intro.decodeEnd, label: "session keys", value: "decrypted" },
                { at: intro.typeEnd, label: "desktop", value: "", live: true }
            ]
            delegate: Text {
                id: logLine
                required property var modelData
                readonly property bool shown: intro.calm || intro.t >= modelData.at
                readonly property string leader: {
                    var l = modelData.label + " ";
                    while (l.length < 18) l += ".";
                    return l;
                }
                readonly property string tagHtml: modelData.live
                    ? "<font color=\"" + intro.hex(intro.c1) + "\">[ " + "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[Math.floor(intro.loop * 10) % 10] + "&nbsp;&nbsp;]</font>"
                    : "<font color=\"" + intro.hex(intro.c2) + "\">[ OK ]</font>"
                textFormat: Text.StyledText
                text: tagHtml + "&nbsp;<font color=\"" + intro.hex(intro.dim) + "\">" + leader.replace(/ /g, "&nbsp;") + "&nbsp;</font>"
                    + "<font color=\"" + intro.hex(intro.mix(intro.dim, intro.ink, 0.55)) + "\">"
                    + (modelData.live ? (intro.mode === "reload" ? "reloading" : "loading") : String(modelData.value).split("").map(intro.esc).join(""))
                    + "</font>"
                font.family: intro.mono
                font.pixelSize: Math.max(5, Math.round(12 * intro.s))
                opacity: shown ? 0.8 : 0
            }
        }
    }

    // ── CRT: static scanlines and one slow refresh band ─────────────────
    Canvas {
        id: scan
        anchors.fill: parent
        visible: cfg.scanlines
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            ctx.fillStyle = "rgba(0,0,0,0.2)";
            var step = Math.max(2, Math.round(3 * intro.s));
            for (var y = 0; y < height; y += step)
                ctx.fillRect(0, y, width, Math.max(1, Math.round(step / 3)));
        }
    }
    Rectangle {
        id: band
        visible: cfg.scanlines && !intro.calm
        width: parent.width
        height: Math.round(parent.height * 0.2)
        gradient: Gradient {
            GradientStop { position: 0.0; color: "transparent" }
            GradientStop { position: 0.5; color: Qt.rgba(intro.c1.r, intro.c1.g, intro.c1.b, 0.045) }
            GradientStop { position: 1.0; color: "transparent" }
        }
        NumberAnimation on y {
            from: -band.height
            to: intro.height
            duration: 5200
            loops: Animation.Infinite
            running: band.visible && intro.active
        }
    }
}
