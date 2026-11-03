pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import shell.services
import Ryoku.Ui.Singletons
import "../../components"

// The dock's translate tool (user_edits fork, 2026-10-23): a word or sentence
// in, its translation out, with the source language detected. "Auto" aims at
// English and flips to Portuguese when the text already is English; a language
// chip forces the target. Lookups go through Google's keyless dictionary
// endpoint and fall back to MyMemory, in a short python run with no library
// beyond urllib. Either side can be spoken (Google TTS through mpv), the result
// copied, or the pair dropped as a card into the flashcards' `vocab` deck.
FocusScope {
    id: tr

    required property var band
    property bool shown: false

    readonly property var langs: ["en", "pt", "es", "fr", "de", "it", "ja"]
    // Auto: translate into home[0]; text already in home[0] goes to home[1].
    readonly property var home: ["en", "pt"]
    property string target: "auto"
    property string query: ""
    property string src: ""
    property string tl: ""
    property string result: ""
    property string provider: ""
    property string error: ""
    property bool busy: false
    property string hint: ""
    readonly property string vocabPath: Paths.home + "/Documents/Flashcards/vocab.md"

    implicitHeight: col.implicitHeight

    Keys.onEscapePressed: (event) => {
        tr.band.closeTool();
        event.accepted = true;
    }

    readonly property string script: "import sys, json, urllib.request, urllib.parse\n"
        + "text, target, h1, h2 = sys.argv[1:5]\n"
        + "def get(url):\n"
        + "    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})\n"
        + "    with urllib.request.urlopen(req, timeout=8) as r:\n"
        + "        return r.read().decode('utf-8', 'replace')\n"
        + "def google(tl):\n"
        + "    u = 'https://clients5.google.com/translate_a/t?client=dict-chrome-ex&sl=auto&tl=%s&q=%s' % (tl, urllib.parse.quote(text))\n"
        + "    d = json.loads(get(u))\n"
        + "    item = d[0]\n"
        + "    if isinstance(item, list):\n"
        + "        return item[0], item[1]\n"
        + "    return item, ''\n"
        + "def mymemory(tl):\n"
        + "    u = 'https://api.mymemory.translated.net/get?q=%s&langpair=Autodetect|%s' % (urllib.parse.quote(text), tl)\n"
        + "    d = json.loads(get(u))\n"
        + "    rd = d.get('responseData') or {}\n"
        + "    if d.get('responseStatus') != 200:\n"
        + "        raise Exception(str(rd.get('translatedText') or 'no answer'))\n"
        + "    return rd.get('translatedText', ''), (rd.get('detectedLanguage') or '')\n"
        + "out = {'ok': False, 'error': 'no network'}\n"
        + "tl = h1 if target == 'auto' else target\n"
        + "for fn, name in ((google, 'google'), (mymemory, 'mymemory')):\n"
        + "    try:\n"
        + "        t, src = fn(tl)\n"
        + "        if target == 'auto' and src and src.split('-')[0].lower() == h1:\n"
        + "            tl = h2\n"
        + "            t, src = fn(tl)\n"
        + "        out = {'ok': True, 'text': t, 'src': src.split('-')[0].lower(), 'tl': tl, 'provider': name}\n"
        + "        break\n"
        + "    except Exception as e:\n"
        + "        out = {'ok': False, 'error': str(e)[:120]}\n"
        + "print(json.dumps(out, ensure_ascii=False))\n"

    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: tr.finish(this.text)
        }
        onExited: (code, status) => {
            if (code !== 0 && tr.busy) {
                tr.busy = false;
                tr.error = I18n.tr("No answer (offline?)");
            }
        }
    }
    function go() {
        const q = input.text.replace(/\s+/g, " ").trim();
        if (q === "" || proc.running)
            return;
        tr.query = q;
        tr.error = "";
        tr.hint = "";
        tr.busy = true;
        proc.command = ["python3", "-I", "-c", tr.script, q, tr.target, tr.home[0], tr.home[1]];
        proc.running = true;
    }
    function finish(text) {
        tr.busy = false;
        let d = null;
        try {
            d = JSON.parse(text);
        } catch (e) {
            d = null;
        }
        if (!d) {
            tr.error = I18n.tr("No answer (offline?)");
            return;
        }
        if (!d.ok) {
            tr.error = d.error ? String(d.error) : I18n.tr("No answer");
            return;
        }
        tr.src = d.src || "";
        tr.tl = d.tl || "";
        tr.result = d.text || "";
        tr.provider = d.provider || "";
    }
    function speak(text, lang) {
        const t = text.trim().slice(0, 200);
        if (t === "")
            return;
        const l = (lang && lang !== "auto") ? lang : tr.home[0];
        Quickshell.execDetached(["mpv", "--no-terminal", "--no-video", "--really-quiet",
            "https://translate.google.com/translate_tts?ie=UTF-8&client=tw-ob&tl=" + l + "&q=" + encodeURIComponent(t)]);
    }
    function copy() {
        if (tr.result === "")
            return;
        Quickshell.execDetached(["wl-copy", "--", tr.result]);
        tr.flash(I18n.tr("Copied"));
    }
    function addToVocab() {
        if (tr.result === "")
            return;
        Quickshell.execDetached(["bash", "-c", "mkdir -p \"$(dirname \"$3\")\"; printf '%s :: %s\\n' \"$1\" \"$2\" >> \"$3\"",
            "vocab-add", tr.query, tr.result, tr.vocabPath]);
        tr.flash(I18n.tr("Added to the vocab deck"));
    }
    Timer {
        id: hintTimer
        interval: 1600
        onTriggered: tr.hint = ""
    }
    function flash(s) {
        tr.hint = s;
        hintTimer.restart();
    }

    readonly property color wash: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.06)
    readonly property color washHi: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12)
    readonly property color hairline: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12)
    readonly property color primaryTint: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22)

    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool on: false
        signal tap()
        implicitWidth: Math.max(28, chipText.implicitWidth + 12)
        height: 24
        radius: 12
        color: chip.on ? tr.primaryTint : (chipHover.hovered ? tr.wash : "transparent")
        border.width: 1
        border.color: chip.on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5) : tr.hairline
        Behavior on color { enabled: tr.band.animate; ColorAnimation { duration: Motion.thumbHover } }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: Theme.onSurface
            font.family: Theme.mono
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }
        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onSingleTapped: chip.tap() }
    }
    // A small pill button: glyph plus an optional mono tag.
    component SBtn: Rectangle {
        id: sb
        property string glyph: ""
        property string tag: ""
        signal tap()
        width: sbRow.implicitWidth + 14
        height: 26
        radius: 13
        color: sbHover.hovered ? tr.washHi : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08)
        Row {
            id: sbRow
            anchors.centerIn: parent
            spacing: 3
            MaterialIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 16
                height: 16
                font.pixelSize: 15
                text: sb.glyph
                color: Theme.onSurface
            }
            Text {
                visible: sb.tag !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: sb.tag
                color: Theme.onSurface
                font.family: Theme.mono
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }
        HoverHandler { id: sbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onSingleTapped: sb.tap() }
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        // ── the field ─────────────────────────────────────────────────────────
        Rectangle {
            id: fieldPlate
            width: parent.width
            height: 38
            radius: Motion.rTile
            color: tr.wash
            border.width: 1
            border.color: input.activeFocus ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6) : tr.hairline
            TextInput {
                id: input
                focus: true
                anchors.left: parent.left
                anchors.right: goBtn.left
                anchors.leftMargin: 10
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: 13
                selectByMouse: true
                selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                clip: true
                Keys.onReturnPressed: tr.go()
                Keys.onEnterPressed: tr.go()
                Text {
                    anchors.fill: parent
                    visible: input.text === ""
                    text: I18n.tr("Word or sentence, Enter to translate")
                    color: Theme.onSurfaceVariant
                    font: input.font
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                }
            }
            Item {
                id: goBtn
                anchors.right: parent.right
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 30
                height: 30
                Rectangle {
                    anchors.fill: parent
                    radius: 8
                    color: goHover.hovered ? tr.washHi : "transparent"
                }
                MaterialIcon {
                    id: goIcon
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    font.pixelSize: 19
                    text: tr.busy ? "progress_activity" : "translate"
                    color: Theme.onSurface
                    RotationAnimation on rotation {
                        running: tr.busy
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) goIcon.rotation = 0
                    }
                }
                HoverHandler { id: goHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onSingleTapped: tr.go() }
            }
        }

        // ── target ────────────────────────────────────────────────────────────
        Row {
            spacing: 4
            Chip { label: I18n.tr("AUTO"); on: tr.target === "auto"; onTap: { tr.target = "auto"; if (tr.query !== "") tr.go(); } }
            Repeater {
                model: tr.langs
                delegate: Chip {
                    required property string modelData
                    label: modelData.toUpperCase()
                    on: tr.target === modelData
                    onTap: { tr.target = modelData; if (tr.query !== "") tr.go(); }
                }
            }
        }

        // ── the answer ────────────────────────────────────────────────────────
        Rectangle {
            id: out
            width: parent.width
            height: Math.max(132, outCol.implicitHeight + 24)
            Behavior on height { enabled: tr.band.animate; NumberAnimation { duration: Motion.rowReveal; easing.type: Motion.rowRevealCurve } }
            radius: Motion.rTile
            color: tr.wash
            border.width: 1
            border.color: tr.hairline
            Column {
                id: outCol
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                spacing: 8
                Text {
                    width: parent.width
                    text: tr.error !== "" ? tr.error
                        : (tr.result !== "" ? tr.src.toUpperCase() + "  →  " + tr.tl.toUpperCase() + "   ·   " + tr.provider
                            : (tr.busy ? I18n.tr("Translating…") : I18n.tr("The translation lands here")))
                    color: tr.error !== "" ? Theme.error : Theme.onSurfaceVariant
                    font.family: Theme.mono
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
                TextEdit {
                    visible: tr.result !== ""
                    width: parent.width
                    text: tr.result
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    color: Theme.onSurface
                    selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                    font.family: Theme.fontPrimary
                    font.pixelSize: 16
                }
                Text {
                    visible: tr.result !== "" && tr.query !== ""
                    width: parent.width
                    text: tr.query
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }
                Row {
                    visible: tr.result !== ""
                    spacing: 4
                    SBtn { glyph: "volume_up"; tag: tr.src.toUpperCase(); onTap: tr.speak(tr.query, tr.src) }
                    SBtn { glyph: "volume_up"; tag: tr.tl.toUpperCase(); onTap: tr.speak(tr.result, tr.tl) }
                    SBtn { glyph: "content_copy"; onTap: tr.copy() }
                    SBtn { glyph: "style"; tag: I18n.tr("deck"); onTap: tr.addToVocab() }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        leftPadding: 4
                        text: tr.hint
                        color: Theme.onSurfaceVariant
                        font.family: Theme.fontPrimary
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
