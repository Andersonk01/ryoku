pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import shell.services
import Ryoku.Ui.Singletons
import "../../components"

// The dock's notes tool (user_edits fork, 2026-10-22): the notes in
// ~/Documents/Notes -- the folder the Super+Shift+N quick note writes to -- as
// a list newest first, each opened and edited right here. A new note is a fresh
// timestamped Markdown file named the way quick-note names them, and is only
// created once it has content. The pad saves itself: a debounced atomic write
// while typing, flushed on back, close and hide. "Open in editor" hands the
// file to the same floating kitty+nvim window quick-note uses; delete asks
// twice. Escape goes back to the list; a second Escape closes the card.
FocusScope {
    id: notes

    required property var band
    property bool shown: false

    readonly property string dir: Paths.home + "/Documents/Notes"
    // The list is as tall as its notes (three rows at least), the editor always
    // the full height, so a short list is not a mostly empty sheet.
    readonly property real fullHeight: 440
    readonly property real listHeight: 38 + 10 + 24 + 4 + Math.max(3, model.count) * 54 - 4
    implicitHeight: notes.mode === "edit" ? notes.fullHeight : Math.min(notes.fullHeight, notes.listHeight)
    Behavior on implicitHeight { enabled: notes.band.animate; NumberAnimation { duration: Motion.rowReveal; easing.type: Motion.rowRevealCurve } }

    // "list" or "edit"
    property string mode: "list"
    property string editName: ""
    property bool editNew: false
    property bool dirty: false
    property bool adopting: false
    property bool confirmDelete: false
    property bool listing: false

    onShownChanged: {
        if (notes.shown) {
            notes.refresh();
        } else {
            notes.flush();
            notes.confirmDelete = false;
        }
    }
    Component.onDestruction: notes.flush()

    // Escape steps back: the editor returns to the list, the list closes the
    // card. Handled here on the scope, so it holds whichever child has focus.
    Keys.onEscapePressed: (event) => {
        if (notes.mode === "edit")
            notes.back();
        else
            notes.band.closeTool();
        event.accepted = true;
    }
    Connections {
        target: notes.band
        function onNewNoteRequested() { notes.newNote(); }
    }

    // ── listing ───────────────────────────────────────────────────────────────
    ListModel { id: model }

    // mtime, name and the first non-blank line of every .md / .txt, newest first.
    readonly property string listScript:
        'd="$1"; mkdir -p "$d" 2>/dev/null; cd "$d" 2>/dev/null || exit 0; shopt -s nullglob; '
        + 'for f in *.md *.txt; do [ -f "$f" ] || continue; '
        + 't=$(grep -m1 -v "^[[:space:]]*$" -- "$f" 2>/dev/null | head -c 160); '
        + 'printf "%s\\t%s\\t%s\\n" "$(stat -c %Y -- "$f")" "$f" "$t"; done | sort -rn'
    Process {
        id: lister
        command: ["bash", "-c", notes.listScript, "notes-list", notes.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                notes.parseList(this.text);
                notes.listing = false;
            }
        }
    }
    function refresh() {
        if (notes.listing)
            return;
        notes.listing = true;
        lister.running = false;
        lister.running = true;
    }
    function parseList(text) {
        model.clear();
        const lines = String(text).split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const line = lines[i];
            if (!line)
                continue;
            const a = line.indexOf("\t");
            if (a < 0)
                continue;
            const b = line.indexOf("\t", a + 1);
            if (b < 0)
                continue;
            const mtime = parseInt(line.substring(0, a), 10);
            const name = line.substring(a + 1, b);
            let title = line.substring(b + 1).replace(/^[#\s\u2022\-\*]+/, "").replace(/\s+/g, " ").trim();
            if (title === "")
                title = name.replace(/\.(md|txt)$/, "");
            model.append({ name: name, title: title, mtime: isFinite(mtime) ? mtime : 0 });
        }
    }
    function when(mtime) {
        if (!mtime)
            return "";
        const d = new Date(mtime * 1000), now = new Date();
        if (d.toDateString() === now.toDateString())
            return I18n.tr("Today") + " " + Qt.formatTime(d, "HH:mm");
        return Qt.formatDateTime(d, "d MMM yyyy, HH:mm");
    }

    // ── the file under the pad ────────────────────────────────────────────────
    FileView {
        id: file
        blockLoading: true
        atomicWrites: true
        printErrors: false
        watchChanges: false
    }
    function openNote(name, isNew) {
        notes.flush();
        notes.editName = name;
        notes.editNew = isNew;
        notes.confirmDelete = false;
        file.path = notes.dir + "/" + name;
        notes.adopting = true;
        pad.text = isNew ? "# " : file.text();
        notes.adopting = false;
        notes.dirty = false;
        notes.mode = "edit";
        pad.cursorPosition = pad.text.length;
        flick.contentY = 0;
        pad.forceActiveFocus();
    }
    function save() {
        if (!notes.dirty || notes.mode !== "edit" || file.path === "")
            return;
        const t = pad.text;
        // A note that is still only its "# " seed (or blank) is never written.
        if (notes.editNew && t.replace(/^[#\s]+$/, "") === "")
            return;
        file.setText(t);
        notes.dirty = false;
        notes.editNew = false;
    }
    function flush() {
        if (debounce.running)
            debounce.stop();
        notes.save();
    }
    Timer {
        id: debounce
        interval: 600
        onTriggered: notes.save()
    }
    function back() {
        notes.flush();
        notes.mode = "list";
        notes.confirmDelete = false;
        notes.refresh();
        listView.forceActiveFocus();
    }
    function newNote() {
        notes.openNote(Qt.formatDateTime(new Date(), "yyyy-MM-dd_HHmmss") + ".md", true);
    }
    function openExternal() {
        notes.flush();
        if (notes.editNew)
            return;
        Quickshell.execDetached(["kitty", "--class", "quick-note", "--title", notes.editName,
                                 "-d", notes.dir, "nvim", notes.dir + "/" + notes.editName]);
        notes.band.closeTool();
    }
    function removeNote() {
        if (!notes.confirmDelete) {
            notes.confirmDelete = true;
            confirmTimer.restart();
            return;
        }
        notes.confirmDelete = false;
        confirmTimer.stop();
        debounce.stop();
        notes.dirty = false;
        notes.mode = "list";
        if (notes.editNew) {
            notes.refresh();
            return;
        }
        remover.command = ["rm", "-f", "--", notes.dir + "/" + notes.editName];
        remover.running = true;
    }
    Process {
        id: remover
        onExited: notes.refresh()
    }
    Timer {
        id: confirmTimer
        interval: 3000
        onTriggered: notes.confirmDelete = false
    }

    // A round icon button for the toolbars.
    component IconBtn: Item {
        id: ib
        property string glyph: ""
        property color tint: Theme.onSurface
        signal tap()
        width: 28
        height: 28
        Rectangle {
            anchors.fill: parent
            radius: 8
            color: ibHover.hovered
                ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10)
                : "transparent"
        }
        MaterialIcon {
            anchors.centerIn: parent
            width: 20
            height: 20
            font.pixelSize: 18
            text: ib.glyph
            color: ib.tint
        }
        HoverHandler { id: ibHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onSingleTapped: ib.tap() }
    }

    // ── list ──────────────────────────────────────────────────────────────────
    Item {
        id: listView
        anchors.fill: parent
        visible: notes.mode === "list"

        Rectangle {
            id: newBtn
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 38
            radius: Motion.rTile
            color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, newHover.hovered ? 0.32 : 0.22)
            border.width: 1
            border.color: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.45)
            Behavior on color { enabled: notes.band.animate; ColorAnimation { duration: Motion.thumbHover } }
            Row {
                anchors.centerIn: parent
                spacing: 8
                MaterialIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    font.pixelSize: 18
                    text: "note_add"
                    color: Theme.onSurface
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: I18n.tr("New note")
                    color: Theme.onSurface
                    font.family: Theme.fontPrimary
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
            }
            HoverHandler { id: newHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onSingleTapped: notes.newNote() }
        }

        Item {
            id: subhead
            anchors.top: newBtn.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            height: 24
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: model.count + " " + (model.count === 1 ? I18n.tr("note") : I18n.tr("notes"))
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: 11
                font.weight: Font.Medium
                font.letterSpacing: 0.4
            }
            IconBtn {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                glyph: "refresh"
                tint: Theme.onSurfaceVariant
                onTap: notes.refresh()
            }
        }

        ListView {
            id: list
            anchors.top: subhead.bottom
            anchors.topMargin: 4
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            model: model
            spacing: 4
            boundsBehavior: Flickable.StopAtBounds
            delegate: Rectangle {
                id: row
                required property string name
                required property string title
                required property real mtime
                width: list.width
                height: 50
                radius: Motion.rTile - 3
                color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, rowHover.hovered ? 0.10 : 0.05)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.06)
                Behavior on color { enabled: notes.band.animate; ColorAnimation { duration: Motion.thumbHover } }

                MaterialIcon {
                    id: rowIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    font.pixelSize: 18
                    text: "description"
                    color: Theme.onSurfaceVariant
                }
                Column {
                    anchors.left: rowIcon.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        text: row.title
                        color: Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: notes.when(row.mtime)
                        color: Theme.onSurfaceVariant
                        font.family: Theme.fontPrimary
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onSingleTapped: notes.openNote(row.name, false) }
            }

            Text {
                anchors.centerIn: parent
                visible: model.count === 0 && !notes.listing
                text: I18n.tr("No notes yet")
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: 12
            }
        }
    }

    // ── editor ────────────────────────────────────────────────────────────────
    Item {
        id: editView
        anchors.fill: parent
        visible: notes.mode === "edit"

        Item {
            id: toolbar
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28

            IconBtn {
                id: backBtn
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                glyph: "arrow_back"
                onTap: notes.back()
            }
            Text {
                anchors.left: backBtn.right
                anchors.leftMargin: 6
                anchors.right: confirmText.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: notes.editName
                color: Theme.onSurfaceVariant
                font.family: Theme.mono
                font.pixelSize: 10
                elide: Text.ElideMiddle
            }
            Text {
                id: confirmText
                anchors.right: openBtn.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                visible: notes.confirmDelete
                width: visible ? implicitWidth : 0
                text: I18n.tr("Delete?")
                color: Theme.error
                font.family: Theme.fontPrimary
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
            IconBtn {
                id: openBtn
                anchors.right: delBtn.left
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                glyph: "open_in_new"
                tint: notes.editNew ? Qt.rgba(Theme.onSurfaceVariant.r, Theme.onSurfaceVariant.g, Theme.onSurfaceVariant.b, 0.4) : Theme.onSurfaceVariant
                onTap: notes.openExternal()
            }
            IconBtn {
                id: delBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                glyph: "delete"
                tint: notes.confirmDelete ? Theme.error : Theme.onSurfaceVariant
                onTap: notes.removeNote()
            }
        }

        Rectangle {
            id: padPlate
            anchors.top: toolbar.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: status.top
            anchors.bottomMargin: 8
            radius: Motion.rTile
            color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.05)
            border.width: 1
            border.color: pad.activeFocus
                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5)
                : Qt.rgba(1, 1, 1, 0.07)
            Behavior on border.color { enabled: notes.band.animate; ColorAnimation { duration: Motion.thumbHover } }

            // A non-interactive viewport (NotesWidget's approach): it clips and
            // follows the caret, the wheel scrolls it, and a drag stays a text
            // selection instead of a flick.
            Flickable {
                id: flick
                anchors.fill: parent
                anchors.margins: 10
                clip: true
                interactive: false
                contentWidth: width
                contentHeight: pad.height

                TextEdit {
                    id: pad
                    width: flick.width
                    height: Math.max(implicitHeight, flick.height)
                    focus: true
                    color: Theme.onSurface
                    selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.55)
                    selectedTextColor: Theme.onSurface
                    selectByMouse: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    font.family: Theme.fontPrimary
                    font.pixelSize: 13

                    onTextChanged: {
                        if (notes.adopting || notes.mode !== "edit")
                            return;
                        notes.dirty = true;
                        debounce.restart();
                    }
                    onCursorRectangleChanged: {
                        if (cursorRectangle.y < flick.contentY)
                            flick.contentY = cursorRectangle.y;
                        else if (cursorRectangle.y + cursorRectangle.height > flick.contentY + flick.height)
                            flick.contentY = cursorRectangle.y + cursorRectangle.height - flick.height;
                    }
                    Keys.onPressed: (event) => {
                        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_S) {
                            notes.flush();
                            event.accepted = true;
                        }
                    }

                    Text {
                        anchors.fill: parent
                        visible: pad.text.length === 0
                        text: I18n.tr("Write a note…")
                        color: Theme.onSurfaceVariant
                        font: pad.font
                        wrapMode: Text.Wrap
                    }
                }
            }
            WheelHandler {
                target: null
                onWheel: (event) => {
                    const max = Math.max(0, flick.contentHeight - flick.height);
                    flick.contentY = Math.max(0, Math.min(max, flick.contentY - event.angleDelta.y * 0.6));
                }
            }
        }

        Item {
            id: status
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 16
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: notes.dirty ? I18n.tr("Unsaved") : (notes.editNew ? I18n.tr("Not saved yet") : I18n.tr("Saved"))
                color: notes.dirty ? Theme.primary : Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: 11
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("Esc back · Ctrl+S save")
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: 10
            }
        }
    }
}
