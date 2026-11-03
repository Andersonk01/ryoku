pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import shell.services
import Ryoku.Ui.Singletons

// The dock's timer engine (user_edits fork, 2026-10-23): the state behind the
// timer tool -- countdown, stopwatch and pomodoro -- kept on the band rather
// than in the card, so a running clock keeps running with the card closed and
// the tile can draw its progress. One ticker runs only while something runs
// (fast for the stopwatch's centiseconds, slow otherwise); every clock is a
// wall-clock deadline, not a counted tick, so it never drifts. The settings and
// the pomodoro tally persist in ~/.local/state/ryoku-dock/timer.json. A finished
// clock rings through notify-send and a freedesktop sound (pw-play).
Item {
    id: eng
    visible: false
    width: 0
    height: 0

    // ── settings (persisted) ──────────────────────────────────────────────────
    property string mode: "timer"          // timer | stopwatch | pomodoro
    property int timerTotal: 10 * 60000    // ms
    property int pomFocus: 25              // minutes
    property int pomShort: 5
    property int pomLong: 15
    property int pomRounds: 4
    property bool pomAuto: false           // start the next phase by itself
    property bool sound: true

    // ── countdown ─────────────────────────────────────────────────────────────
    property bool timerRunning: false
    property int timerLeft: 10 * 60000
    property double timerEndAt: 0
    // Rang and not yet seen: the tile pulses until the tool is opened.
    property bool timerDone: false

    // ── stopwatch ─────────────────────────────────────────────────────────────
    property bool swRunning: false
    property int swElapsed: 0
    property int swBase: 0
    property double swStartAt: 0
    property var laps: []                  // [{ n, lap, total }], newest first

    // ── pomodoro ──────────────────────────────────────────────────────────────
    property string pomPhase: "focus"      // focus | short | long
    property int pomDone: 0                // focus rounds finished this cycle
    property int pomToday: 0
    property string pomDay: ""
    property bool pomRunning: false
    property int pomLeft: 25 * 60000
    property double pomEndAt: 0

    readonly property bool anyRunning: eng.timerRunning || eng.swRunning || eng.pomRunning
    // What the tile's ring shows: the pomodoro first, then a countdown (running
    // or rung), then a running stopwatch.
    readonly property string tileState: eng.pomRunning ? "pomodoro"
        : (eng.timerRunning || eng.timerDone) ? "timer"
        : eng.swRunning ? "stopwatch" : ""
    // Remaining fraction for the ring (1 = full).
    readonly property real tileProgress: eng.tileState === "pomodoro"
        ? eng.pomLeft / Math.max(1, eng.pomDuration(eng.pomPhase))
        : eng.tileState === "timer" ? (eng.timerDone ? 1 : eng.timerLeft / Math.max(1, eng.timerTotal))
        : 0
    readonly property int todayCount: eng.pomDay === eng.today() ? eng.pomToday : 0

    function today() { return Qt.formatDate(new Date(), "yyyy-MM-dd"); }

    // ── ticker ────────────────────────────────────────────────────────────────
    Timer {
        interval: eng.swRunning ? 41 : 250
        repeat: true
        running: eng.anyRunning
        onTriggered: eng.tickNow()
    }
    function tickNow() {
        const now = Date.now();
        if (eng.swRunning)
            eng.swElapsed = eng.swBase + Math.round(now - eng.swStartAt);
        if (eng.timerRunning) {
            eng.timerLeft = Math.max(0, Math.round(eng.timerEndAt - now));
            if (eng.timerLeft === 0)
                eng.finishTimer();
        }
        if (eng.pomRunning) {
            eng.pomLeft = Math.max(0, Math.round(eng.pomEndAt - now));
            if (eng.pomLeft === 0)
                eng.finishPom();
        }
    }

    // ── countdown ─────────────────────────────────────────────────────────────
    function timerStart() {
        if (eng.timerLeft <= 0)
            eng.timerLeft = eng.timerTotal;
        eng.timerDone = false;
        eng.timerEndAt = Date.now() + eng.timerLeft;
        eng.timerRunning = true;
    }
    function timerPause() {
        eng.tickNow();
        eng.timerRunning = false;
    }
    function timerToggle() { if (eng.timerRunning) eng.timerPause(); else eng.timerStart(); }
    function timerReset() {
        eng.timerRunning = false;
        eng.timerDone = false;
        eng.timerLeft = eng.timerTotal;
    }
    // Sets the preset (1 min .. 24 h) and rewinds to it.
    function timerSet(ms) {
        ms = Math.max(60000, Math.min(24 * 3600000, Math.round(ms / 1000) * 1000));
        eng.timerTotal = ms;
        eng.timerRunning = false;
        eng.timerDone = false;
        eng.timerLeft = ms;
        eng.saveSoon();
    }
    // Running: moves the deadline; idle: changes the preset.
    function timerAdjust(deltaMs) {
        if (eng.timerRunning) {
            eng.timerEndAt = Math.max(Date.now() + 1000, eng.timerEndAt + deltaMs);
            eng.tickNow();
        } else {
            eng.timerSet(eng.timerTotal + deltaMs);
        }
    }
    function finishTimer() {
        eng.timerRunning = false;
        eng.timerLeft = 0;
        eng.timerDone = true;
        eng.alarm(I18n.tr("Time's up"), I18n.tr("The %1 timer has finished").arg(eng.fmtMinutes(eng.timerTotal)), "alarm-clock-elapsed.oga");
    }

    // ── stopwatch ─────────────────────────────────────────────────────────────
    function swStart() {
        eng.swStartAt = Date.now();
        eng.swRunning = true;
    }
    function swPause() {
        eng.tickNow();
        eng.swBase = eng.swElapsed;
        eng.swRunning = false;
    }
    function swToggle() { if (eng.swRunning) eng.swPause(); else eng.swStart(); }
    function swReset() {
        eng.swRunning = false;
        eng.swBase = 0;
        eng.swElapsed = 0;
        eng.laps = [];
    }
    function swLap() {
        if (!eng.swRunning && eng.swElapsed === 0)
            return;
        eng.tickNow();
        const prev = eng.laps.length ? eng.laps[0].total : 0;
        const l = eng.laps.slice();
        l.unshift({ n: l.length + 1, lap: eng.swElapsed - prev, total: eng.swElapsed });
        eng.laps = l;
    }

    // ── pomodoro ──────────────────────────────────────────────────────────────
    function pomDuration(phase) {
        const m = phase === "focus" ? eng.pomFocus : (phase === "short" ? eng.pomShort : eng.pomLong);
        return Math.max(1, m) * 60000;
    }
    function pomStart() {
        if (eng.pomLeft <= 0)
            eng.pomLeft = eng.pomDuration(eng.pomPhase);
        eng.pomEndAt = Date.now() + eng.pomLeft;
        eng.pomRunning = true;
    }
    function pomPause() {
        eng.tickNow();
        eng.pomRunning = false;
    }
    function pomToggle() { if (eng.pomRunning) eng.pomPause(); else eng.pomStart(); }
    function pomReset() {
        eng.pomRunning = false;
        eng.pomPhase = "focus";
        eng.pomDone = 0;
        eng.pomLeft = eng.pomDuration("focus");
        eng.saveSoon();
    }
    // Skip moves on without counting the round.
    function pomSkip() {
        eng.pomRunning = false;
        eng.pomAdvance(false);
    }
    function finishPom() {
        eng.pomRunning = false;
        eng.pomAdvance(true);
    }
    function pomAdvance(counted) {
        let next;
        if (eng.pomPhase === "focus") {
            if (counted) {
                eng.pomDone += 1;
                const d = eng.today();
                if (eng.pomDay !== d) {
                    eng.pomDay = d;
                    eng.pomToday = 0;
                }
                eng.pomToday += 1;
            }
            next = eng.pomDone >= eng.pomRounds ? "long" : "short";
            if (counted)
                eng.alarm(I18n.tr("Focus complete"),
                    next === "long" ? I18n.tr("Take a long break: %1 min").arg(eng.pomLong)
                                    : I18n.tr("Take a short break: %1 min").arg(eng.pomShort),
                    "complete.oga");
        } else {
            if (eng.pomPhase === "long")
                eng.pomDone = 0;
            next = "focus";
            if (counted)
                eng.alarm(I18n.tr("Break over"), I18n.tr("Back to focus: %1 min").arg(eng.pomFocus), "bell.oga");
        }
        eng.pomPhase = next;
        eng.pomLeft = eng.pomDuration(next);
        eng.saveSoon();
        if (counted && eng.pomAuto)
            eng.pomStart();
    }
    // Changing a phase length while idle in that phase rewinds it to the new value.
    function pomSetMinutes(which, minutes) {
        minutes = Math.max(1, Math.min(180, Math.round(minutes)));
        if (which === "focus") eng.pomFocus = minutes;
        else if (which === "short") eng.pomShort = minutes;
        else eng.pomLong = minutes;
        if (!eng.pomRunning && eng.pomPhase === which)
            eng.pomLeft = eng.pomDuration(which);
        eng.saveSoon();
    }

    // ── for the current mode (keyboard and IPC) ───────────────────────────────
    function setMode(m) {
        if (m !== "timer" && m !== "stopwatch" && m !== "pomodoro")
            return;
        eng.mode = m;
        eng.saveSoon();
    }
    function toggle() {
        if (eng.mode === "timer") eng.timerToggle();
        else if (eng.mode === "stopwatch") eng.swToggle();
        else eng.pomToggle();
    }
    function reset() {
        if (eng.mode === "timer") eng.timerReset();
        else if (eng.mode === "stopwatch") eng.swReset();
        else eng.pomReset();
    }
    readonly property bool running: eng.mode === "timer" ? eng.timerRunning
        : eng.mode === "stopwatch" ? eng.swRunning : eng.pomRunning

    // ── ring ──────────────────────────────────────────────────────────────────
    function alarm(title, body, soundFile) {
        Quickshell.execDetached(["notify-send", "-a", "Ryoku", "-i", "alarm", "-u", "normal", title, body]);
        if (eng.sound)
            Quickshell.execDetached(["pw-play", "/usr/share/sounds/freedesktop/stereo/" + soundFile]);
    }

    // ── formatting ────────────────────────────────────────────────────────────
    function pad2(n) { return (n < 10 ? "0" : "") + n; }
    // mm:ss, or h:mm:ss past an hour; a countdown rounds up so 00:00 means zero.
    function fmtClock(ms) {
        const s = Math.ceil(Math.max(0, ms) / 1000);
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
        return (h > 0 ? h + ":" + eng.pad2(m) : eng.pad2(m)) + ":" + eng.pad2(sec);
    }
    // mm:ss.cc for the stopwatch.
    function fmtStopwatch(ms) {
        const cs = Math.floor(Math.max(0, ms) / 10) % 100;
        const s = Math.floor(Math.max(0, ms) / 1000);
        const h = Math.floor(s / 3600), m = Math.floor((s % 3600) / 60), sec = s % 60;
        return (h > 0 ? h + ":" + eng.pad2(m) : eng.pad2(m)) + ":" + eng.pad2(sec) + "." + eng.pad2(cs);
    }
    function fmtMinutes(ms) {
        const m = Math.round(ms / 60000);
        if (m >= 60 && m % 60 === 0)
            return (m / 60) + " h";
        return m + " min";
    }

    // ── persistence ───────────────────────────────────────────────────────────
    readonly property string stateDir: Paths.home + "/.local/state/ryoku-dock"
    Process {
        command: ["mkdir", "-p", eng.stateDir]
        running: true
    }
    FileView {
        id: store
        path: eng.stateDir + "/timer.json"
        blockLoading: true
        atomicWrites: true
        printErrors: false
        watchChanges: false
    }
    Timer {
        id: saveTimer
        interval: 800
        onTriggered: eng.save()
    }
    function saveSoon() { saveTimer.restart(); }
    function save() {
        store.setText(JSON.stringify({
            mode: eng.mode, timerTotal: eng.timerTotal,
            pomFocus: eng.pomFocus, pomShort: eng.pomShort, pomLong: eng.pomLong, pomRounds: eng.pomRounds,
            pomAuto: eng.pomAuto, sound: eng.sound,
            pomDay: eng.pomDay, pomToday: eng.pomToday, pomDone: eng.pomDone, pomPhase: eng.pomPhase
        }));
    }
    function load() {
        let s = null;
        try {
            const t = store.text();
            if (t && t.trim() !== "")
                s = JSON.parse(t);
        } catch (e) {
            s = null;
        }
        if (!s || typeof s !== "object")
            return;
        const num = (v, lo, hi, d) => (typeof v === "number" && isFinite(v)) ? Math.max(lo, Math.min(hi, Math.round(v))) : d;
        if (s.mode === "timer" || s.mode === "stopwatch" || s.mode === "pomodoro")
            eng.mode = s.mode;
        eng.timerTotal = num(s.timerTotal, 60000, 24 * 3600000, eng.timerTotal);
        eng.pomFocus = num(s.pomFocus, 1, 180, eng.pomFocus);
        eng.pomShort = num(s.pomShort, 1, 180, eng.pomShort);
        eng.pomLong = num(s.pomLong, 1, 180, eng.pomLong);
        eng.pomRounds = num(s.pomRounds, 1, 12, eng.pomRounds);
        if (typeof s.pomAuto === "boolean") eng.pomAuto = s.pomAuto;
        if (typeof s.sound === "boolean") eng.sound = s.sound;
        if (typeof s.pomDay === "string") eng.pomDay = s.pomDay;
        eng.pomToday = num(s.pomToday, 0, 999, 0);
        eng.pomDone = num(s.pomDone, 0, eng.pomRounds, 0);
        if (s.pomPhase === "focus" || s.pomPhase === "short" || s.pomPhase === "long")
            eng.pomPhase = s.pomPhase;
        eng.timerLeft = eng.timerTotal;
        eng.pomLeft = eng.pomDuration(eng.pomPhase);
    }
    Component.onCompleted: eng.load()
    Component.onDestruction: if (saveTimer.running) eng.save()
}
