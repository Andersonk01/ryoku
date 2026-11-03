pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import shell.services
import Ryoku.Ui.Singletons
import "../../components"

// The dock's cheat-sheet tool (user_edits fork, 2026-10-23): a question to
// cht.sh, answered as a short annotated snippet. `python/list comprehension`,
// `js array map`, `git undo commit`: the first word is the topic, the rest the
// question; a topic alone (`go`, `rust/:learn`) gives its overview. Plain text
// is requested (?T), so the answer reads in the mono pane here, where it can
// be selected, copied whole, or opened in the browser.
FocusScope {
    id: ch

    required property var band
    property bool shown: false

    property string path: ""
    property string answer: ""
    property string error: ""
    property bool busy: false
    property string hint: ""
    readonly property var examples: ["python/lambda", "js/array map", "go/:learn", "git/undo commit", "bash/for loop", "rust/ownership"]

    implicitHeight: col.implicitHeight

    Keys.onEscapePressed: (event) => {
        ch.band.closeTool();
        event.accepted = true;
    }

    function toPath(q) {
        q = q.replace(/\s+/g, " ").trim();
        if (q === "")
            return "";
        let topic, rest;
        const slash = q.indexOf("/");
        if (slash >= 0) {
            topic = q.slice(0, slash).trim();
            rest = q.slice(slash + 1).trim();
        } else {
            const sp = q.indexOf(" ");
            topic = sp < 0 ? q : q.slice(0, sp);
            rest = sp < 0 ? "" : q.slice(sp + 1);
        }
        topic = topic.replace(/ /g, "+");
        rest = rest.replace(/ /g, "+");
        return rest === "" ? topic : topic + "/" + rest;
    }
    function go(q) {
        if (q !== undefined)
            input.text = q;
        const p = ch.toPath(input.text);
        if (p === "" || proc.running)
            return;
        ch.path = p;
        ch.error = "";
        ch.hint = "";
        ch.answer = "";
        ch.busy = true;
        pane.contentY = 0;
        proc.command = ["curl", "-fsSL", "-m", "12", "-A", "curl", "https://cht.sh/" + p + (p.indexOf("?") >= 0 ? "&T" : "?T")];
        proc.running = true;
    }
    Process {
        id: proc
        stdout: StdioCollector {
            onStreamFinished: {
                ch.busy = false;
                const t = this.text.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "").replace(/\s+$/, "");
                ch.answer = t;
                if (t === "" && ch.error === "")
                    ch.error = I18n.tr("No answer");
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                ch.busy = false;
                ch.error = I18n.tr("No answer: offline, or an unknown topic");
            }
        }
    }
    function copy() {
        if (ch.answer === "")
            return;
        Quickshell.execDetached(["wl-copy", "--", ch.answer]);
        ch.flash(I18n.tr("Copied"));
    }
    function openBrowser() {
        if (ch.path === "")
            return;
        Quickshell.execDetached(["xdg-open", "https://cht.sh/" + ch.path]);
        ch.band.closeTool();
    }
    Timer {
        id: hintTimer
        interval: 1600
        onTriggered: ch.hint = ""
    }
    function flash(s) {
        ch.hint = s;
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
        implicitWidth: chipText.implicitWidth + 14
        height: 24
        radius: 12
        color: chip.on ? ch.primaryTint : (chipHover.hovered ? ch.wash : "transparent")
        border.width: 1
        border.color: chip.on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5) : ch.hairline
        Behavior on color { enabled: ch.band.animate; ColorAnimation { duration: Motion.thumbHover } }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: Theme.onSurface
            font.family: Theme.mono
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onSingleTapped: chip.tap() }
    }
    component IconBtn: Item {
        id: ib
        property string glyph: ""
        signal tap()
        width: 26
        height: 26
        Rectangle {
            anchors.fill: parent
            radius: 7
            color: ibHover.hovered ? ch.washHi : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, 0.85)
            border.width: 1
            border.color: ch.hairline
        }
        MaterialIcon {
            anchors.centerIn: parent
            width: 18
            height: 18
            font.pixelSize: 16
            text: ib.glyph
            color: Theme.onSurface
        }
        HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onSingleTapped: ib.tap() }
    }

    Column {
        id: col
        width: parent.width
        spacing: 8

        // ── the question ──────────────────────────────────────────────────────
        Rectangle {
            width: parent.width
            height: 38
            radius: Motion.rTile
            color: ch.wash
            border.width: 1
            border.color: input.activeFocus ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6) : ch.hairline
            TextInput {
                id: input
                focus: true
                anchors.left: parent.left
                anchors.right: goBtn.left
                anchors.leftMargin: 10
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.onSurface
                font.family: Theme.mono
                font.pixelSize: 12
                selectByMouse: true
                selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                clip: true
                Keys.onReturnPressed: ch.go()
                Keys.onEnterPressed: ch.go()
                Text {
                    anchors.fill: parent
                    visible: input.text === ""
                    text: I18n.tr("language/question, e.g. python/list comprehension")
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
                    color: goHover.hovered ? ch.washHi : "transparent"
                }
                MaterialIcon {
                    id: goIcon
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    font.pixelSize: 19
                    text: ch.busy ? "progress_activity" : "search"
                    color: Theme.onSurface
                    RotationAnimation on rotation {
                        running: ch.busy
                        from: 0
                        to: 360
                        duration: 900
                        loops: Animation.Infinite
                        onRunningChanged: if (!running) goIcon.rotation = 0
                    }
                }
                HoverHandler { id: goHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onSingleTapped: ch.go() }
            }
        }

        // ── starters ──────────────────────────────────────────────────────────
        Flow {
            width: parent.width
            spacing: 4
            Repeater {
                model: ch.examples
                delegate: Chip {
                    required property string modelData
                    label: modelData
                    on: ch.path !== "" && ch.path === ch.toPath(modelData)
                    onTap: ch.go(modelData)
                }
            }
        }

        // ── the sheet ─────────────────────────────────────────────────────────
        Rectangle {
            id: sheet
            width: parent.width
            height: 250
            radius: Motion.rTile
            color: Qt.rgba(Theme.surfaceContainerLowest.r, Theme.surfaceContainerLowest.g, Theme.surfaceContainerLowest.b, 0.45)
            border.width: 1
            border.color: ch.hairline
            clip: true
            Flickable {
                id: pane
                anchors.fill: parent
                anchors.margins: 10
                contentWidth: width
                contentHeight: body.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                TextEdit {
                    id: body
                    width: pane.width
                    text: ch.answer
                    readOnly: true
                    selectByMouse: true
                    wrapMode: TextEdit.WrapAnywhere
                    textFormat: TextEdit.PlainText
                    color: Theme.onSurface
                    selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
                    font.family: Theme.mono
                    font.pixelSize: 11
                }
            }
            Text {
                anchors.centerIn: parent
                width: parent.width - 28
                visible: ch.answer === ""
                text: ch.error !== "" ? ch.error : (ch.busy ? I18n.tr("Asking cht.sh…") : I18n.tr("The sheet lands here. Topic first, then the question."))
                color: ch.error !== "" ? Theme.error : Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: 11
                wrapMode: Text.Wrap
                horizontalAlignment: Text.AlignHCenter
            }
            Row {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 6
                spacing: 4
                visible: ch.answer !== ""
                IconBtn { glyph: "content_copy"; onTap: ch.copy() }
                IconBtn { glyph: "open_in_new"; onTap: ch.openBrowser() }
            }
        }
        Text {
            width: parent.width
            text: ch.hint !== "" ? ch.hint : (ch.path !== "" ? "cht.sh/" + ch.path : I18n.tr("cht.sh · :learn for a language tour, :list for its topics"))
            color: Theme.onSurfaceVariant
            font.family: Theme.mono
            font.pixelSize: 10
            elide: Text.ElideRight
        }
    }
}
