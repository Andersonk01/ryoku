pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import shell.services
import Ryoku.Ui.Singletons
import "../../components"

// The dock's calculator tool (user_edits fork, 2026-10-22): a four-column pad
// over a two-line display. The tape is a list of number and operator tokens
// plus the number being typed; the big line shows what is being typed, or the
// running result, and the small line the whole expression. Evaluation honours
// precedence (× ÷ before + −) through a tiny shunting-yard, so 2 + 3 × 4 is 14.
// Keys work once the card has the keyboard (any click in it): digits, + - * /,
// . or , for the point, % , Enter or = , Backspace, Delete or C to clear,
// Ctrl+C copies. A tap on the display copies the shown value (wl-copy).
FocusScope {
    id: calc

    required property var band
    property bool shown: false

    implicitHeight: col.implicitHeight

    // ── state ─────────────────────────────────────────────────────────────────
    property var tape: []          // ["12", "+", "3"] -- numbers and operators
    property string cur: ""        // the number being typed
    property bool justEvaluated: false
    property string lastResult: ""

    function isOp(t) { return t === "+" || t === "−" || t === "×" || t === "÷"; }
    readonly property var allTokens: (calc.cur !== "" && calc.cur !== "-") ? calc.tape.concat([calc.cur]) : calc.tape
    readonly property var live: calc.evaluate(calc.allTokens)
    readonly property string exprLine: {
        const parts = calc.tape.slice();
        if (calc.cur !== "") parts.push(calc.cur);
        const s = parts.join(" ");
        return calc.justEvaluated ? s + " =" : s;
    }
    readonly property string display: {
        if (calc.justEvaluated) return calc.lastResult;
        if (calc.cur !== "") return calc.cur;
        if (calc.live.ok) return calc.fmt(calc.live.value);
        return "0";
    }

    // ── evaluation ────────────────────────────────────────────────────────────
    function evaluate(tokens) {
        const t = tokens.slice();
        while (t.length && calc.isOp(t[t.length - 1]))
            t.pop();
        if (t.length === 0)
            return { ok: false, value: 0 };
        const prec = { "+": 1, "−": 1, "×": 2, "÷": 2 };
        const out = [], ops = [];
        for (let i = 0; i < t.length; ++i) {
            const tok = t[i];
            if (calc.isOp(tok)) {
                while (ops.length && prec[ops[ops.length - 1]] >= prec[tok])
                    out.push(ops.pop());
                ops.push(tok);
            } else {
                const n = parseFloat(tok);
                if (!isFinite(n))
                    return { ok: false, value: 0 };
                out.push(n);
            }
        }
        while (ops.length)
            out.push(ops.pop());
        const st = [];
        for (let j = 0; j < out.length; ++j) {
            const tok = out[j];
            if (typeof tok === "number") { st.push(tok); continue; }
            const b = st.pop(), a = st.pop();
            if (a === undefined || b === undefined)
                return { ok: false, value: 0 };
            let r;
            switch (tok) {
            case "+": r = a + b; break;
            case "−": r = a - b; break;
            case "×": r = a * b; break;
            case "÷": r = b === 0 ? NaN : a / b; break;
            }
            st.push(r);
        }
        const v = st.length === 1 ? st[0] : NaN;
        return { ok: isFinite(v), value: v };
    }
    function fmt(n) {
        if (!isFinite(n))
            return I18n.tr("Error");
        const a = Math.abs(n);
        if (a !== 0 && (a >= 1e12 || a < 1e-9))
            return n.toExponential(6).replace(/\.?0+e/, "e");
        return String(Number(n.toPrecision(12)));
    }

    // ── input ─────────────────────────────────────────────────────────────────
    function restartAfterResult(keepResult) {
        if (!calc.justEvaluated)
            return;
        const r = parseFloat(calc.lastResult);
        calc.tape = (keepResult && isFinite(r)) ? [calc.lastResult] : [];
        calc.cur = "";
        calc.justEvaluated = false;
    }
    function pressDigit(d) {
        calc.restartAfterResult(false);
        if (calc.cur === "0") calc.cur = d;
        else if (calc.cur === "-0") calc.cur = "-" + d;
        else if (calc.cur.length < 16) calc.cur += d;
    }
    function pressDot() {
        calc.restartAfterResult(false);
        if (calc.cur.indexOf(".") >= 0)
            return;
        if (calc.cur === "") calc.cur = "0.";
        else if (calc.cur === "-") calc.cur = "-0.";
        else calc.cur += ".";
    }
    function pressOp(op) {
        calc.restartAfterResult(true);
        if (calc.cur !== "" && calc.cur !== "-") {
            calc.tape = calc.tape.concat([calc.cur, op]);
            calc.cur = "";
            return;
        }
        if (calc.tape.length === 0) {
            if (op === "−") calc.cur = "-";
            return;
        }
        const last = calc.tape[calc.tape.length - 1];
        if (calc.isOp(last)) {
            // "5 × −" starts a negative number; any other operator replaces the
            // pending one.
            if (op === "−" && calc.cur === "") { calc.cur = "-"; return; }
            const t = calc.tape.slice();
            t[t.length - 1] = op;
            calc.tape = t;
        } else {
            calc.tape = calc.tape.concat([op]);
        }
    }
    function pressPercent() {
        if (calc.justEvaluated) {
            const r = parseFloat(calc.lastResult);
            calc.tape = [];
            calc.cur = isFinite(r) ? calc.fmt(r / 100) : "";
            calc.justEvaluated = false;
            return;
        }
        if (calc.cur !== "" && calc.cur !== "-")
            calc.cur = calc.fmt(parseFloat(calc.cur) / 100);
    }
    function pressNegate() {
        if (calc.justEvaluated) {
            const r = parseFloat(calc.lastResult);
            calc.tape = [];
            calc.cur = isFinite(r) ? calc.fmt(-r) : "";
            calc.justEvaluated = false;
            return;
        }
        if (calc.cur === "") { calc.cur = "-"; return; }
        calc.cur = calc.cur.charAt(0) === "-" ? calc.cur.substring(1) : "-" + calc.cur;
    }
    function pressBackspace() {
        if (calc.justEvaluated) { calc.clear(); return; }
        if (calc.cur !== "") { calc.cur = calc.cur.slice(0, -1); return; }
        if (calc.tape.length === 0)
            return;
        const t = calc.tape.slice();
        const last = t.pop();
        calc.tape = t;
        if (!calc.isOp(last))
            calc.cur = last;
    }
    function clear() {
        calc.tape = [];
        calc.cur = "";
        calc.justEvaluated = false;
        calc.lastResult = "";
    }
    function pressEquals() {
        if (calc.justEvaluated)
            return;
        const toks = calc.allTokens.slice();
        while (toks.length && calc.isOp(toks[toks.length - 1]))
            toks.pop();
        if (toks.length === 0)
            return;
        const r = calc.evaluate(toks);
        calc.lastResult = r.ok ? calc.fmt(r.value) : I18n.tr("Error");
        calc.tape = toks;
        calc.cur = "";
        calc.justEvaluated = true;
    }
    function copy() {
        const v = calc.display;
        if (v === "" || v === I18n.tr("Error"))
            return;
        Quickshell.execDetached(["wl-copy", "--", v]);
        copiedTimer.restart();
    }
    function press(label) {
        switch (label) {
        case "C": calc.clear(); break;
        case "⌫": calc.pressBackspace(); break;
        case "%": calc.pressPercent(); break;
        case "±": calc.pressNegate(); break;
        case ".": calc.pressDot(); break;
        case "=": calc.pressEquals(); break;
        case "+": case "−": case "×": case "÷": calc.pressOp(label); break;
        default: calc.pressDigit(label);
        }
    }

    Keys.onPressed: (event) => {
        const k = event.key;
        if (k >= Qt.Key_0 && k <= Qt.Key_9) {
            calc.pressDigit(String(k - Qt.Key_0));
            event.accepted = true;
            return;
        }
        switch (k) {
        case Qt.Key_Period: case Qt.Key_Comma: calc.pressDot(); break;
        case Qt.Key_Plus: calc.pressOp("+"); break;
        case Qt.Key_Minus: calc.pressOp("−"); break;
        case Qt.Key_Asterisk: case Qt.Key_X: calc.pressOp("×"); break;
        case Qt.Key_Slash: calc.pressOp("÷"); break;
        case Qt.Key_Percent: calc.pressPercent(); break;
        case Qt.Key_Return: case Qt.Key_Enter: case Qt.Key_Equal: calc.pressEquals(); break;
        case Qt.Key_Backspace: calc.pressBackspace(); break;
        case Qt.Key_Delete: calc.clear(); break;
        case Qt.Key_C:
            if (event.modifiers & Qt.ControlModifier) calc.copy();
            else calc.clear();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    Timer { id: copiedTimer; interval: 1200 }

    Column {
        id: col
        width: parent.width
        spacing: 10

        // ── display ────────────────────────────────────────────────────────────
        Rectangle {
            id: screen
            width: parent.width
            height: 86
            radius: Motion.rTile
            color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, screenHover.hovered ? 0.09 : 0.06)
            border.width: 1
            border.color: Qt.rgba(1, 1, 1, 0.08)
            Behavior on color { enabled: calc.band.animate; ColorAnimation { duration: Motion.thumbHover } }

            Text {
                anchors.top: parent.top
                anchors.topMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                text: calc.exprLine
                color: Theme.onSurfaceVariant
                font.family: Theme.mono
                font.pixelSize: 12
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideLeft
            }
            Text {
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                height: 34
                text: calc.display
                color: Theme.onSurface
                font.family: Theme.mono
                font.pixelSize: 28
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignRight
                verticalAlignment: Text.AlignVCenter
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 14
            }
            Text {
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: 12
                anchors.bottomMargin: 10
                visible: copiedTimer.running
                text: I18n.tr("Copied")
                color: Theme.primary
                font.family: Theme.fontPrimary
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
            HoverHandler { id: screenHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                onSingleTapped: {
                    calc.forceActiveFocus();
                    calc.copy();
                }
            }
        }

        // ── keys ───────────────────────────────────────────────────────────────
        Grid {
            id: grid
            width: parent.width
            columns: 4
            columnSpacing: 8
            rowSpacing: 8
            readonly property real cell: (width - columnSpacing * 3) / 4

            Repeater {
                model: ["C", "⌫", "%", "÷",
                        "7", "8", "9", "×",
                        "4", "5", "6", "−",
                        "1", "2", "3", "+",
                        "±", "0", ".", "="]
                delegate: Item {
                    id: key
                    required property string modelData
                    readonly property bool isOp: calc.isOp(key.modelData)
                    readonly property bool isEq: key.modelData === "="
                    readonly property bool isFn: key.modelData === "C" || key.modelData === "⌫"
                        || key.modelData === "%" || key.modelData === "±"
                    width: grid.cell
                    height: 44

                    Rectangle {
                        anchors.fill: parent
                        radius: Motion.rTile
                        color: key.isEq
                            ? (keyHover.hovered ? Qt.lighter(Theme.primary, 1.1) : Theme.primary)
                            : key.isOp
                                ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, keyHover.hovered ? 0.32 : 0.22)
                                : Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b,
                                          key.isFn ? (keyHover.hovered ? 0.14 : 0.10) : (keyHover.hovered ? 0.10 : 0.06))
                        border.width: 1
                        border.color: key.isEq
                            ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.6)
                            : (key.isOp ? Qt.rgba(Theme.primary.r, Theme.primary.g, Theme.primary.b, 0.4) : Qt.rgba(1, 1, 1, 0.07))
                        scale: keyTap.pressed ? 0.95 : 1
                        Behavior on scale { enabled: calc.band.animate; NumberAnimation { duration: Motion.hover; easing.type: Motion.easeStandard } }
                        Behavior on color { enabled: calc.band.animate; ColorAnimation { duration: Motion.thumbHover } }
                    }
                    MaterialIcon {
                        visible: key.modelData === "⌫"
                        anchors.centerIn: parent
                        width: 22
                        height: 22
                        font.pixelSize: 20
                        text: "backspace"
                        color: Theme.onSurface
                    }
                    Text {
                        visible: key.modelData !== "⌫"
                        anchors.centerIn: parent
                        text: key.modelData
                        color: key.isEq ? Theme.onPrimary : Theme.onSurface
                        font.family: Theme.fontPrimary
                        font.pixelSize: (key.isOp || key.isEq) ? 20 : 17
                        font.weight: Font.Medium
                    }
                    HoverHandler { id: keyHover; cursorShape: Qt.PointingHandCursor }
                    TapHandler {
                        id: keyTap
                        onSingleTapped: {
                            calc.forceActiveFocus();
                            calc.press(key.modelData);
                        }
                    }
                }
            }
        }
    }
}
