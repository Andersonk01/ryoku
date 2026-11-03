pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import shell.services
import Ryoku.Ui.Singletons
import "../../components"

// The dock's flashcards tool (user_edits fork, 2026-10-23): spaced repetition
// over plain Markdown decks in ~/Documents/Flashcards, one card per line as
// `front :: back` (a side wrapped in backticks shows in monospace, for syntax;
// a literal \n breaks a line). A review takes the cards due today plus up to 15
// new ones; Again / Hard / Good / Easy move a card through Leitner-style boxes
// (1, 2, 4, 7, 15, 30, 60, 120 days) kept in ~/.local/state/ryoku-dock/cards.json
// keyed by deck and front, so the deck files stay editable anywhere. Decks and
// cards are made here; the translate tool drops words into the `vocab` deck.
// Keys: Space or Enter reveals (then Enter = Good), 1-4 grade, Escape steps back.
FocusScope {
    id: fc

    required property var band
    property bool shown: false

    readonly property string dir: Paths.home + "/Documents/Flashcards"
    readonly property string stateDir: Paths.home + "/.local/state/ryoku-dock"
    readonly property var intervals: [1, 2, 4, 7, 15, 30, 60, 120]
    readonly property int newLimit: 15

    // decks | review | add | done
    property string mode: "decks"
    property string addFrom: "decks"
    property var decks: []        // [{ name, cards: [{ front, back }] }]
    property var store: ({})      // deck -> front -> { b: box, d: due day, n: reviews }
    property string deck: ""
    property var queue: []
    property int qi: 0
    property bool flipped: false
    property int reviewed: 0
    property int againCount: 0
    property bool listing: false
    property string hint: ""

    readonly property real fullHeight: 440
    readonly property real decksHeight: 36 + 10 + Math.max(3, fc.decks.length) * 54 - 4
    implicitHeight: fc.mode === "decks" ? Math.min(fc.fullHeight, fc.decksHeight)
        : fc.mode === "review" ? 268
        : fc.mode === "add" ? 196 : 190
    Behavior on implicitHeight { enabled: fc.band.animate; NumberAnimation { duration: Motion.rowReveal; easing.type: Motion.rowRevealCurve } }

    onShownChanged: {
        if (fc.shown) {
            fc.loadStore();
            fc.refresh();
        }
    }

    function todayNum() { return Math.floor(Date.now() / 86400000); }

    Keys.onPressed: (event) => {
        const k = event.key;
        if (k === Qt.Key_Escape) {
            if (fc.mode === "decks") fc.band.closeTool();
            else if (fc.mode === "add") fc.leaveAdd();
            else fc.toDecks();
            event.accepted = true;
            return;
        }
        if (fc.mode !== "review")
            return;
        if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) {
            if (!fc.flipped) fc.flipped = true;
            else fc.grade(2);
        } else if (fc.flipped && k >= Qt.Key_1 && k <= Qt.Key_4) {
            fc.grade(k - Qt.Key_1);
        } else {
            return;
        }
        event.accepted = true;
    }

    // ── decks on disk ─────────────────────────────────────────────────────────
    // One line per deck (name, empty front) then one per card: name, front, back.
    readonly property string listScript:
        "d=\"$1\"; mkdir -p \"$d\" 2>/dev/null; cd \"$d\" 2>/dev/null || exit 0; shopt -s nullglob; "
        + "for f in *.md; do n=\"${f%.md}\"; printf '%s\\t\\t\\n' \"$n\"; "
        + "awk -v n=\"$n\" '{ i = index($0, \" :: \"); if (i > 0) { a = substr($0, 1, i - 1); b = substr($0, i + 4); "
        + "gsub(/^[ \\t]+|[ \\t]+$/, \"\", a); gsub(/^[ \\t]+|[ \\t]+$/, \"\", b); if (a != \"\") print n \"\\t\" a \"\\t\" b } }' \"./$f\"; done"
    Process {
        id: lister
        command: ["bash", "-c", fc.listScript, "cards-list", fc.dir]
        stdout: StdioCollector {
            onStreamFinished: {
                fc.parseList(this.text);
                fc.listing = false;
            }
        }
    }
    function refresh() {
        if (lister.running)
            return;
        fc.listing = true;
        lister.running = true;
    }
    function parseList(txt) {
        const map = {};
        const order = [];
        for (const line of txt.split("\n")) {
            if (line === "")
                continue;
            const p = line.split("\t");
            const name = p[0];
            if (!name)
                continue;
            if (!map[name]) {
                map[name] = { name: name, cards: [] };
                order.push(name);
            }
            if (p.length >= 3 && p[1] !== "")
                map[name].cards.push({ front: p[1], back: p.slice(2).join("\t") });
        }
        fc.decks = order.map(n => map[n]);
    }
    function deckByName(name) {
        for (const d of fc.decks)
            if (d.name === name)
                return d;
        return null;
    }
    function stats(d) {
        const s = fc.store[d.name] || {};
        const t = fc.todayNum();
        let due = 0, fresh = 0;
        for (const c of d.cards) {
            const e = s[c.front];
            if (!e) fresh++;
            else if (e.d <= t) due++;
        }
        return { n: d.cards.length, due: due, fresh: fresh };
    }

    // Appends and deck files go through one short bash; the list refreshes after.
    Process {
        id: writer
        onExited: fc.refresh()
    }
    function runWrite(args) {
        writer.command = args;
        writer.running = true;
    }
    function createDeck(name) {
        name = name.replace(/[\/\\:]/g, "-").replace(/\s+/g, " ").trim();
        if (name === "" || name.startsWith("."))
            return;
        fc.runWrite(["bash", "-c", "mkdir -p \"$(dirname \"$1\")\"; [ -e \"$1\" ] || printf '# %s\\n\\n' \"$2\" > \"$1\"",
            "deck-new", fc.dir + "/" + name + ".md", name]);
    }
    function addCard(front, back) {
        front = front.replace(/\s+/g, " ").trim();
        back = back.replace(/\s+/g, " ").trim();
        if (front === "" || back === "" || fc.deck === "")
            return false;
        fc.runWrite(["bash", "-c", "printf '%s :: %s\\n' \"$1\" \"$2\" >> \"$3\"",
            "cards-add", front, back, fc.dir + "/" + fc.deck + ".md"]);
        return true;
    }
    function openExternal(name) {
        Quickshell.execDetached(["kitty", "--class", "quick-note", "--title", name + ".md", "-d", fc.dir, "nvim", fc.dir + "/" + name + ".md"]);
        fc.band.closeTool();
    }

    // ── the schedule store ────────────────────────────────────────────────────
    Process {
        command: ["mkdir", "-p", fc.stateDir]
        running: true
    }
    FileView {
        id: storeFile
        path: fc.stateDir + "/cards.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
        watchChanges: false
    }
    function loadStore() {
        let s = null;
        try {
            const t = storeFile.text();
            if (t && t.trim() !== "")
                s = JSON.parse(t);
        } catch (e) {
            s = null;
        }
        fc.store = (s && typeof s === "object") ? s : {};
    }
    function saveStore() { storeFile.setText(JSON.stringify(fc.store)); }

    // ── a review ──────────────────────────────────────────────────────────────
    function shuffle(a) {
        for (let i = a.length - 1; i > 0; --i) {
            const j = Math.floor(Math.random() * (i + 1));
            const t = a[i]; a[i] = a[j]; a[j] = t;
        }
    }
    function startReview(name) {
        const dk = fc.deckByName(name);
        if (!dk)
            return;
        const s = fc.store[name] || {};
        const t = fc.todayNum();
        const due = [], fresh = [];
        for (const c of dk.cards) {
            const e = s[c.front];
            if (!e) fresh.push(c);
            else if (e.d <= t) due.push(c);
        }
        fc.shuffle(due);
        fc.deck = name;
        fc.queue = due.concat(fresh.slice(0, fc.newLimit));
        fc.qi = 0;
        fc.flipped = false;
        fc.reviewed = 0;
        fc.againCount = 0;
        fc.mode = fc.queue.length ? "review" : "done";
        fc.forceActiveFocus();
    }
    readonly property var cur: (fc.mode === "review" && fc.qi < fc.queue.length) ? fc.queue[fc.qi] : null
    // 0 again, 1 hard, 2 good, 3 easy
    function grade(g) {
        const c = fc.cur;
        if (!c)
            return;
        const s = Object.assign({}, fc.store);
        const d = Object.assign({}, s[fc.deck] || {});
        const e = d[c.front] ? Object.assign({}, d[c.front]) : { b: 0, d: 0, n: 0 };
        const t = fc.todayNum();
        const top = fc.intervals.length - 1;
        e.n += 1;
        if (g === 0) {
            e.b = 0;
            e.d = t;
            fc.againCount += 1;
        } else if (g === 1) {
            e.d = t + 1;
        } else if (g === 2) {
            e.b = Math.min(top, e.b + 1);
            e.d = t + fc.intervals[e.b];
        } else {
            e.b = Math.min(top, e.b + 2);
            e.d = t + Math.round(fc.intervals[e.b] * 1.5);
        }
        d[c.front] = e;
        s[fc.deck] = d;
        fc.store = s;
        fc.saveStore();
        fc.reviewed += 1;
        const q = fc.queue.slice();
        if (g === 0)
            q.push(c);        // asked again before the session ends
        fc.queue = q;
        fc.flipped = false;
        fc.qi += 1;
        if (fc.qi >= fc.queue.length)
            fc.mode = "done";
    }
    // `code` -> monospace; a literal \n breaks the line.
    function side(s) {
        if (s === undefined || s === null)
            return { text: "", mono: false };
        const m = /^`([^`]*)`$/.exec(s);
        if (m)
            return { text: m[1].replace(/\\n/g, "\n"), mono: true };
        return { text: s.replace(/\\n/g, "\n"), mono: false };
    }

    function toDecks() {
        fc.mode = "decks";
        fc.refresh();
        fc.forceActiveFocus();
    }
    function toAdd() {
        if (fc.deck === "")
            return;
        fc.addFrom = fc.mode === "add" ? fc.addFrom : fc.mode;
        fc.mode = "add";
        fc.hint = "";
        Qt.callLater(() => frontField.input.forceActiveFocus());
    }
    function leaveAdd() {
        fc.hint = "";
        if (fc.addFrom === "review" && fc.cur) {
            fc.mode = "review";
            fc.forceActiveFocus();
        } else if (fc.addFrom === "done") {
            fc.mode = "done";
            fc.forceActiveFocus();
        } else {
            fc.toDecks();
        }
    }
    function submitAdd() {
        if (!fc.addCard(frontField.text, backField.text)) {
            fc.hint = I18n.tr("Both sides are needed");
            return;
        }
        frontField.text = "";
        backField.text = "";
        frontField.input.forceActiveFocus();
        fc.hint = I18n.tr("Added to %1").arg(fc.deck);
        hintTimer.restart();
    }
    Timer {
        id: hintTimer
        interval: 1600
        onTriggered: fc.hint = ""
    }

    readonly property color wash: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.06)
    readonly property color washHi: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12)
    readonly property color hairline: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12)

    // ── small parts ───────────────────────────────────────────────────────────
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
            color: ibHover.hovered ? fc.washHi : "transparent"
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
        // Exclusive on press, so a row's own tap does not fire underneath.
        TapHandler { gesturePolicy: TapHandler.ReleaseWithinBounds; onSingleTapped: ib.tap() }
    }
    component Btn: Rectangle {
        id: b
        property string label: ""
        property string key: ""
        property color tint: Theme.onSurface
        property real alpha: 0.10
        signal tap()
        height: 36
        radius: Motion.rTile
        color: Qt.rgba(b.tint.r, b.tint.g, b.tint.b, bHover.hovered ? b.alpha + 0.10 : b.alpha)
        border.width: 1
        border.color: Qt.rgba(b.tint.r, b.tint.g, b.tint.b, 0.30)
        Behavior on color { enabled: fc.band.animate; ColorAnimation { duration: Motion.thumbHover } }
        Text {
            anchors.centerIn: parent
            text: b.label
            color: Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
        Text {
            visible: b.key !== ""
            anchors.right: parent.right
            anchors.rightMargin: 6
            anchors.top: parent.top
            anchors.topMargin: 3
            text: b.key
            color: Theme.onSurfaceVariant
            font.family: Theme.mono
            font.pixelSize: 9
        }
        HoverHandler { id: bHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onSingleTapped: b.tap() }
    }
    // A one-line text field with a placeholder and an optional trailing glyph.
    component Field: Rectangle {
        id: fld
        property alias text: fin.text
        property alias input: fin
        property string placeholder: ""
        property string glyph: ""
        signal submit()
        signal glyphTap()
        height: 36
        radius: Motion.rTile
        color: fc.wash
        border.width: 1
        border.color: fin.activeFocus ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6) : fc.hairline
        TextInput {
            id: fin
            anchors.left: parent.left
            anchors.right: fld.glyph !== "" ? fglyph.left : parent.right
            anchors.leftMargin: 10
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: 12
            selectByMouse: true
            selectionColor: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4)
            clip: true
            Keys.onReturnPressed: fld.submit()
            Keys.onEnterPressed: fld.submit()
            Text {
                anchors.fill: parent
                visible: fin.text === ""
                text: fld.placeholder
                color: Theme.onSurfaceVariant
                font: fin.font
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
        }
        IconBtn {
            id: fglyph
            visible: fld.glyph !== ""
            anchors.right: parent.right
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            glyph: fld.glyph
            onTap: fld.glyphTap()
        }
    }

    // ── decks ─────────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: fc.mode === "decks"

        Field {
            id: newDeck
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            placeholder: I18n.tr("New deck name, Enter to create")
            glyph: "add"
            onSubmit: { fc.createDeck(newDeck.text); newDeck.text = ""; }
            onGlyphTap: { fc.createDeck(newDeck.text); newDeck.text = ""; }
        }
        ListView {
            id: deckList
            anchors.top: newDeck.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            clip: true
            spacing: 4
            model: fc.decks
            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property var st: fc.stats(row.modelData)
                width: deckList.width
                height: 50
                radius: Motion.rTile
                color: rowHover.hovered ? fc.washHi : fc.wash
                Behavior on color { enabled: fc.band.animate; ColorAnimation { duration: Motion.thumbHover } }
                MaterialIcon {
                    id: dIcon
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22
                    font.pixelSize: 20
                    text: "style"
                    fill: 1
                    color: row.st.due > 0 ? Theme.primary : Theme.onSurfaceVariant
                }
                Column {
                    anchors.left: dIcon.right
                    anchors.leftMargin: 10
                    anchors.right: acts.left
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text {
                        width: parent.width
                        text: row.modelData.name
                        color: Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    Text {
                        width: parent.width
                        text: I18n.tr("%1 cards · %2 due · %3 new").arg(row.st.n).arg(row.st.due).arg(row.st.fresh)
                        color: Theme.onSurfaceVariant
                        font.family: Theme.fontPrimary
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
                Row {
                    id: acts
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    IconBtn { glyph: "add"; onTap: { fc.deck = row.modelData.name; fc.addFrom = "decks"; fc.toAdd(); } }
                    IconBtn { glyph: "open_in_new"; onTap: fc.openExternal(row.modelData.name) }
                }
                HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onSingleTapped: fc.startReview(row.modelData.name) }
            }
        }
        Text {
            anchors.centerIn: deckList
            width: deckList.width - 24
            visible: fc.decks.length === 0 && !fc.listing
            text: I18n.tr("No decks yet. Name one above, or drop a .md file in ~/Documents/Flashcards with one card per line: front :: back")
            color: Theme.onSurfaceVariant
            font.family: Theme.fontPrimary
            font.pixelSize: 11
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ── review ────────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: fc.mode === "review"

        Item {
            id: rHead
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28
            IconBtn { id: rBack; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; glyph: "arrow_back"; onTap: fc.toDecks() }
            Text {
                anchors.left: rBack.right
                anchors.leftMargin: 6
                anchors.right: rAdd.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                text: fc.deck + "  ·  " + Math.min(fc.qi + 1, fc.queue.length) + "/" + fc.queue.length
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            IconBtn { id: rAdd; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; glyph: "add"; onTap: fc.toAdd() }
        }
        Rectangle {
            id: cardPlate
            anchors.top: rHead.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            height: 184
            radius: fc.band.radius
            color: fc.wash
            border.width: 1
            border.color: fc.hairline
            readonly property var front: fc.side(fc.cur ? fc.cur.front : "")
            readonly property var back: fc.side(fc.cur ? fc.cur.back : "")
            Column {
                anchors.centerIn: parent
                width: parent.width - 28
                spacing: 10
                Text {
                    width: parent.width
                    text: cardPlate.front.text
                    color: Theme.onSurface
                    font.family: cardPlate.front.mono ? Theme.mono : Theme.fontPrimary
                    font.pixelSize: cardPlate.front.mono ? 14 : 16
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    maximumLineCount: 4
                    elide: Text.ElideRight
                }
                Rectangle { visible: fc.flipped; width: parent.width; height: 1; color: fc.hairline }
                Text {
                    visible: fc.flipped
                    width: parent.width
                    text: cardPlate.back.text
                    color: Theme.onSurface
                    font.family: cardPlate.back.mono ? Theme.mono : Theme.fontPrimary
                    font.pixelSize: cardPlate.back.mono ? 13 : 15
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    maximumLineCount: 5
                    elide: Text.ElideRight
                }
                Text {
                    visible: !fc.flipped
                    width: parent.width
                    text: I18n.tr("Tap or Space to reveal")
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                }
            }
            HoverHandler { cursorShape: fc.flipped ? Qt.ArrowCursor : Qt.PointingHandCursor }
            TapHandler { onSingleTapped: if (!fc.flipped) fc.flipped = true }
        }
        Row {
            anchors.top: cardPlate.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            visible: fc.flipped
            spacing: 6
            readonly property real w: (width - 18) / 4
            Btn { width: parent.w; label: I18n.tr("Again"); key: "1"; tint: Theme.error; alpha: 0.18; onTap: fc.grade(0) }
            Btn { width: parent.w; label: I18n.tr("Hard"); key: "2"; onTap: fc.grade(1) }
            Btn { width: parent.w; label: I18n.tr("Good"); key: "3"; tint: Theme.primary; alpha: 0.22; onTap: fc.grade(2) }
            Btn { width: parent.w; label: I18n.tr("Easy"); key: "4"; tint: Theme.tertiary; alpha: 0.20; onTap: fc.grade(3) }
        }
        Btn {
            anchors.top: cardPlate.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            visible: !fc.flipped
            label: I18n.tr("Show answer")
            tint: Theme.primary
            alpha: 0.22
            onTap: fc.flipped = true
        }
    }

    // ── add a card ────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: fc.mode === "add"

        Item {
            id: aHead
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            height: 28
            IconBtn { id: aBack; anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; glyph: "arrow_back"; onTap: fc.leaveAdd() }
            Text {
                anchors.left: aBack.right
                anchors.leftMargin: 6
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: I18n.tr("New card in %1").arg(fc.deck)
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: 12
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
        }
        Field {
            id: frontField
            anchors.top: aHead.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            placeholder: I18n.tr("Front: the question, word or prompt")
            onSubmit: backField.input.forceActiveFocus()
        }
        Field {
            id: backField
            anchors.top: frontField.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            placeholder: I18n.tr("Back: the answer, `code` for monospace")
            onSubmit: fc.submitAdd()
        }
        Btn {
            id: addBtn
            anchors.top: backField.bottom
            anchors.topMargin: 10
            anchors.left: parent.left
            anchors.right: parent.right
            label: I18n.tr("Add card")
            tint: Theme.primary
            alpha: 0.22
            onTap: fc.submitAdd()
        }
        Text {
            anchors.top: addBtn.bottom
            anchors.topMargin: 6
            anchors.horizontalCenter: parent.horizontalCenter
            text: fc.hint !== "" ? fc.hint : I18n.tr("Enter moves on · Esc goes back")
            color: Theme.onSurfaceVariant
            font.family: Theme.fontPrimary
            font.pixelSize: 11
        }
    }

    // ── done ──────────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        visible: fc.mode === "done"
        Column {
            anchors.centerIn: parent
            width: parent.width
            spacing: 8
            MaterialIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 40
                height: 40
                font.pixelSize: 36
                text: fc.queue.length === 0 ? "event_available" : "check_circle"
                fill: 1
                color: Theme.primary
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: fc.queue.length === 0 ? I18n.tr("Nothing due in %1 today").arg(fc.deck) : I18n.tr("Session complete")
                color: Theme.onSurface
                font.family: Theme.fontPrimary
                font.pixelSize: 14
                font.weight: Font.DemiBold
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: I18n.tr("%1 reviewed · %2 again").arg(fc.reviewed).arg(fc.againCount)
                color: Theme.onSurfaceVariant
                font.family: Theme.fontPrimary
                font.pixelSize: 11
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                Btn { width: 120; label: I18n.tr("Decks"); onTap: fc.toDecks() }
                Btn { width: 120; label: I18n.tr("Add cards"); tint: Theme.primary; alpha: 0.22; onTap: fc.toAdd() }
            }
        }
    }
}
