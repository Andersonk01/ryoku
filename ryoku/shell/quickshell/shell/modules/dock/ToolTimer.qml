pragma ComponentBehavior: Bound

import QtQuick
import shell.services
import Ryoku.Ui.Singletons
import "../../components"

// The dock's timer tool (user_edits fork, 2026-10-23): three clocks on one
// sheet -- a countdown with minute presets, a stopwatch with laps, and a
// pomodoro cycle (focus / short break / long break after N rounds, with a tally
// for the day). The state is the band's ToolTimerEngine, so everything keeps
// running when the card closes and the tile draws a ring meanwhile. Keys once
// the card has the keyboard: Space starts/pauses, R resets, L laps, S skips a
// pomodoro phase, 1/2/3 pick the clock, + and - (or Up/Down) add or take a
// minute from the countdown.
FocusScope {
    id: tt

    required property var band
    property bool shown: false
    readonly property var eng: tt.band.timer
    readonly property string mode: tt.eng.mode
    property bool showSettings: false

    implicitHeight: col.implicitHeight

    // Opening the tool acknowledges a rung countdown (the tile stops pulsing).
    onShownChanged: if (tt.shown && tt.eng.timerDone) tt.eng.timerDone = false

    Keys.onPressed: (event) => {
        const k = event.key;
        if (k === Qt.Key_Space || k === Qt.Key_Return || k === Qt.Key_Enter) tt.eng.toggle();
        else if (k === Qt.Key_R) tt.eng.reset();
        else if (k === Qt.Key_L && tt.mode === "stopwatch") tt.eng.swLap();
        else if (k === Qt.Key_S && tt.mode === "pomodoro") tt.eng.pomSkip();
        else if (k === Qt.Key_1) tt.eng.setMode("timer");
        else if (k === Qt.Key_2) tt.eng.setMode("stopwatch");
        else if (k === Qt.Key_3) tt.eng.setMode("pomodoro");
        else if ((k === Qt.Key_Plus || k === Qt.Key_Equal || k === Qt.Key_Up) && tt.mode === "timer") tt.eng.timerAdjust(60000);
        else if ((k === Qt.Key_Minus || k === Qt.Key_Down) && tt.mode === "timer") tt.eng.timerAdjust(-60000);
        else return;
        event.accepted = true;
    }

    readonly property color wash: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.08)
    readonly property color washHi: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.14)
    readonly property color hairline: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12)
    readonly property color primaryTint: Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.22)

    // ── small parts ───────────────────────────────────────────────────────────
    // A tiny square button (steppers, the gear).
    component Mini: Item {
        id: mini
        property string glyph: ""
        signal tap()
        width: 24
        height: 24
        Rectangle {
            anchors.fill: parent
            radius: 6
            color: miniHover.hovered ? tt.washHi : tt.wash
        }
        MaterialIcon {
            anchors.centerIn: parent
            width: 16
            height: 16
            font.pixelSize: 14
            text: mini.glyph
            color: Theme.onSurface
        }
        HoverHandler { id: miniHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onSingleTapped: mini.tap() }
    }
    // A chip: text in a pill, tinted when `on`.
    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool on: false
        property bool mono: true
        signal tap()
        implicitWidth: Math.max(30, chipText.implicitWidth + 14)
        height: 24
        radius: 12
        color: chip.on ? tt.primaryTint : (chipHover.hovered ? tt.wash : "transparent")
        border.width: 1
        border.color: chip.on ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.5) : tt.hairline
        Behavior on color { enabled: tt.band.animate; ColorAnimation { duration: Motion.thumbHover } }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: Theme.onSurface
            font.family: chip.mono ? Theme.mono : Theme.fontPrimary
            font.pixelSize: 11
            font.weight: Font.DemiBold
        }
        HoverHandler { id: chipHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onSingleTapped: chip.tap() }
    }
    // A transport button; `primary` is the big filled one in the middle.
    component Ctl: Rectangle {
        id: ctl
        property string glyph: ""
        property string label: ""
        property bool primary: false
        property bool can: true
        signal tap()
        width: ctl.primary ? 76 : 56
        height: ctl.primary ? 48 : 44
        radius: Motion.rTile
        color: ctl.primary ? Theme.primary : ((ctlHover.hovered && ctl.can) ? tt.washHi : tt.wash)
        opacity: ctl.can ? 1 : 0.4
        Behavior on color { enabled: tt.band.animate; ColorAnimation { duration: Motion.thumbHover } }
        MaterialIcon {
            visible: ctl.glyph !== ""
            anchors.centerIn: parent
            width: 28
            height: 28
            font.pixelSize: ctl.primary ? 26 : 22
            text: ctl.glyph
            fill: 1
            color: ctl.primary ? Theme.onPrimary : Theme.onSurface
        }
        Text {
            visible: ctl.glyph === ""
            anchors.centerIn: parent
            text: ctl.label
            color: Theme.onSurface
            font.family: Theme.mono
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        HoverHandler { id: ctlHover; cursorShape: ctl.can ? Qt.PointingHandCursor : Qt.ArrowCursor }
        TapHandler { enabled: ctl.can; onSingleTapped: ctl.tap() }
    }
    // A thin progress rule showing what is left.
    component Bar: Item {
        id: bar
        property real value: 0
        property color ink: Theme.primary
        height: 4
        Rectangle { anchors.fill: parent; radius: 2; color: tt.wash }
        Rectangle {
            width: Math.max(0, Math.min(1, bar.value)) * bar.width
            height: bar.height
            radius: 2
            color: bar.ink
            Behavior on width { enabled: tt.band.animate; NumberAnimation { duration: 220 } }
        }
    }
    // Label over a - value + row, for the pomodoro lengths.
    component Stepper: Item {
        id: st
        property string label: ""
        property int value: 0
        signal change(int delta)
        width: 76
        height: 44
        Text {
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            text: st.label
            color: Theme.onSurfaceVariant
            font.family: Theme.fontPrimary
            font.pixelSize: 10
            font.weight: Font.DemiBold
        }
        Row {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 2
            Mini { glyph: "remove"; onTap: st.change(-1) }
            Text {
                width: 24
                height: 24
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: st.value
                color: Theme.onSurface
                font.family: Theme.mono
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Mini { glyph: "add"; onTap: st.change(1) }
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 12

        // ── which clock ───────────────────────────────────────────────────────
        Rectangle {
            id: seg
            width: parent.width
            height: 34
            radius: Motion.rTile
            color: tt.wash
            border.width: 1
            border.color: tt.hairline
            Row {
                anchors.fill: parent
                anchors.margins: 3
                spacing: 3
                Repeater {
                    model: [
                        { id: "timer", label: I18n.tr("Timer") },
                        { id: "stopwatch", label: I18n.tr("Stopwatch") },
                        { id: "pomodoro", label: I18n.tr("Pomodoro") }
                    ]
                    delegate: Rectangle {
                        id: segItem
                        required property var modelData
                        readonly property bool on: tt.mode === segItem.modelData.id
                        width: (seg.width - 12) / 3
                        height: seg.height - 6
                        radius: Motion.rTile - 2
                        color: segItem.on ? Theme.primary : (segHover.hovered ? tt.wash : "transparent")
                        Behavior on color { enabled: tt.band.animate; ColorAnimation { duration: Motion.thumbHover } }
                        Text {
                            anchors.centerIn: parent
                            text: segItem.modelData.label
                            color: segItem.on ? Theme.onPrimary : Theme.onSurface
                            font.family: Theme.fontPrimary
                            font.pixelSize: 12
                            font.weight: Font.DemiBold
                        }
                        HoverHandler { id: segHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onSingleTapped: tt.eng.setMode(segItem.modelData.id) }
                    }
                }
            }
        }

        // ── the clock face ────────────────────────────────────────────────────
        Item {
            id: body
            width: parent.width
            height: (tt.mode === "pomodoro" && tt.showSettings) ? 236 : 196
            Behavior on height { enabled: tt.band.animate; NumberAnimation { duration: Motion.rowReveal; easing.type: Motion.rowRevealCurve } }
            clip: true

            // countdown
            Item {
                anchors.fill: parent
                visible: tt.mode === "timer"
                readonly property bool rang: tt.eng.timerLeft === 0 && !tt.eng.timerRunning
                Text {
                    id: tDigits
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 24
                    text: tt.eng.fmtClock(tt.eng.timerLeft)
                    color: parent.rang ? Theme.error : Theme.onSurface
                    font.family: Theme.mono
                    font.pixelSize: 50
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: tDigits.bottom
                    anchors.topMargin: 2
                    text: tt.eng.timerRunning
                        ? I18n.tr("Ends at %1").arg(Qt.formatTime(new Date(tt.eng.timerEndAt), "HH:mm"))
                        : (parent.rang ? I18n.tr("Time's up")
                            : (tt.eng.timerLeft === tt.eng.timerTotal ? I18n.tr("Ready: %1").arg(tt.eng.fmtMinutes(tt.eng.timerTotal)) : I18n.tr("Paused")))
                    color: parent.rang ? Theme.error : Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: 11
                }
                Bar {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: 122
                    value: tt.eng.timerTotal > 0 ? tt.eng.timerLeft / tt.eng.timerTotal : 0
                    ink: parent.rang ? Theme.error : Theme.primary
                }
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 12
                    spacing: 5
                    Mini { glyph: "remove"; onTap: tt.eng.timerAdjust(-60000) }
                    Repeater {
                        model: [5, 10, 15, 25, 45]
                        delegate: Chip {
                            required property int modelData
                            label: String(modelData)
                            on: tt.eng.timerTotal === modelData * 60000
                            onTap: tt.eng.timerSet(modelData * 60000)
                        }
                    }
                    Mini { glyph: "add"; onTap: tt.eng.timerAdjust(60000) }
                }
            }

            // stopwatch
            Item {
                anchors.fill: parent
                visible: tt.mode === "stopwatch"
                Text {
                    id: swDigits
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 12
                    text: tt.eng.fmtStopwatch(tt.eng.swElapsed)
                    color: Theme.onSurface
                    font.family: Theme.mono
                    font.pixelSize: 42
                    font.weight: Font.DemiBold
                }
                Rectangle {
                    anchors.top: swDigits.bottom
                    anchors.topMargin: 10
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    radius: Motion.rTile
                    color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.05)
                    border.width: 1
                    border.color: tt.hairline
                    ListView {
                        id: lapList
                        anchors.fill: parent
                        anchors.margins: 6
                        clip: true
                        spacing: 2
                        model: tt.eng.laps
                        delegate: Item {
                            required property var modelData
                            width: lapList.width
                            height: 22
                            Text {
                                anchors.left: parent.left
                                anchors.leftMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: "#" + parent.modelData.n
                                color: Theme.onSurfaceVariant
                                font.family: Theme.mono
                                font.pixelSize: 11
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                text: tt.eng.fmtStopwatch(parent.modelData.lap)
                                color: Theme.onSurface
                                font.family: Theme.mono
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            Text {
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                text: tt.eng.fmtStopwatch(parent.modelData.total)
                                color: Theme.onSurfaceVariant
                                font.family: Theme.mono
                                font.pixelSize: 11
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: tt.eng.laps.length === 0
                        text: I18n.tr("Laps land here: the flag, or L")
                        color: Theme.onSurfaceVariant
                        font.family: Theme.fontPrimary
                        font.pixelSize: 11
                    }
                }
            }

            // pomodoro
            Item {
                id: pom
                anchors.fill: parent
                visible: tt.mode === "pomodoro"
                readonly property bool focusPhase: tt.eng.pomPhase === "focus"
                readonly property color ink: pom.focusPhase ? Theme.primary : Theme.tertiary
                readonly property int duration: tt.eng.pomDuration(tt.eng.pomPhase)

                Row {
                    anchors.top: parent.top
                    anchors.left: parent.left
                    spacing: 8
                    Rectangle {
                        height: 24
                        width: phaseText.implicitWidth + 18
                        radius: 12
                        color: Qt.rgba(pom.ink.r, pom.ink.g, pom.ink.b, 0.22)
                        border.width: 1
                        border.color: Qt.rgba(pom.ink.r, pom.ink.g, pom.ink.b, 0.5)
                        Behavior on color { enabled: tt.band.animate; ColorAnimation { duration: Motion.thumbHover } }
                        Text {
                            id: phaseText
                            anchors.centerIn: parent
                            text: pom.focusPhase ? I18n.tr("Focus")
                                : (tt.eng.pomPhase === "short" ? I18n.tr("Short break") : I18n.tr("Long break"))
                            color: Theme.onSurface
                            font.family: Theme.fontPrimary
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5
                        Repeater {
                            model: tt.eng.pomRounds
                            delegate: Rectangle {
                                required property int index
                                width: 8
                                height: 8
                                radius: 4
                                color: index < tt.eng.pomDone ? Theme.primary : tt.wash
                                border.width: 1
                                border.color: index < tt.eng.pomDone ? Theme.primary : tt.hairline
                            }
                        }
                    }
                }
                Row {
                    anchors.top: parent.top
                    anchors.right: parent.right
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Today: %1").arg(tt.eng.todayCount)
                        color: Theme.onSurfaceVariant
                        font.family: Theme.fontPrimary
                        font.pixelSize: 11
                    }
                    Mini { glyph: "tune"; onTap: tt.showSettings = !tt.showSettings }
                }
                Text {
                    id: pDigits
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 40
                    text: tt.eng.fmtClock(tt.eng.pomLeft)
                    color: Theme.onSurface
                    font.family: Theme.mono
                    font.pixelSize: 50
                    font.weight: Font.DemiBold
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: pDigits.bottom
                    anchors.topMargin: 2
                    text: tt.eng.pomRunning
                        ? I18n.tr("Ends at %1").arg(Qt.formatTime(new Date(tt.eng.pomEndAt), "HH:mm"))
                        : (tt.eng.pomLeft === pom.duration
                            ? I18n.tr("Round %1 of %2").arg(Math.min(tt.eng.pomRounds, tt.eng.pomDone + 1)).arg(tt.eng.pomRounds)
                            : I18n.tr("Paused"))
                    color: Theme.onSurfaceVariant
                    font.family: Theme.fontPrimary
                    font.pixelSize: 11
                }
                Bar {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: 138
                    value: pom.duration > 0 ? tt.eng.pomLeft / pom.duration : 0
                    ink: pom.ink
                }
                // lengths and switches, behind the tune mark
                Item {
                    visible: tt.showSettings
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: 156
                    height: 72
                    Row {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        spacing: 6
                        Stepper { label: I18n.tr("Focus"); value: tt.eng.pomFocus; onChange: (d) => tt.eng.pomSetMinutes("focus", tt.eng.pomFocus + d) }
                        Stepper { label: I18n.tr("Short"); value: tt.eng.pomShort; onChange: (d) => tt.eng.pomSetMinutes("short", tt.eng.pomShort + d) }
                        Stepper { label: I18n.tr("Long"); value: tt.eng.pomLong; onChange: (d) => tt.eng.pomSetMinutes("long", tt.eng.pomLong + d) }
                    }
                    Column {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        spacing: 4
                        Chip { label: I18n.tr("Auto"); mono: false; on: tt.eng.pomAuto; onTap: { tt.eng.pomAuto = !tt.eng.pomAuto; tt.eng.saveSoon(); } }
                        Chip { label: I18n.tr("Sound"); mono: false; on: tt.eng.sound; onTap: { tt.eng.sound = !tt.eng.sound; tt.eng.saveSoon(); } }
                    }
                }
            }
        }

        // ── transport ─────────────────────────────────────────────────────────
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10
            Ctl {
                anchors.verticalCenter: parent.verticalCenter
                glyph: tt.mode === "stopwatch" ? "flag" : "restart_alt"
                can: tt.mode !== "stopwatch" || tt.eng.swRunning || tt.eng.swElapsed > 0
                onTap: { if (tt.mode === "stopwatch") tt.eng.swLap(); else tt.eng.reset(); }
            }
            Ctl {
                anchors.verticalCenter: parent.verticalCenter
                primary: true
                glyph: tt.eng.running ? "pause" : "play_arrow"
                onTap: tt.eng.toggle()
            }
            Ctl {
                anchors.verticalCenter: parent.verticalCenter
                glyph: tt.mode === "stopwatch" ? "restart_alt" : (tt.mode === "pomodoro" ? "skip_next" : "")
                label: "+1"
                can: tt.mode !== "stopwatch" || tt.eng.swElapsed > 0
                onTap: {
                    if (tt.mode === "stopwatch") tt.eng.swReset();
                    else if (tt.mode === "pomodoro") tt.eng.pomSkip();
                    else tt.eng.timerAdjust(60000);
                }
            }
        }
    }
}
