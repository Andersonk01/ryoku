pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons

// [user] Pestinha, the desktop pet (~/Projects/pestinha, Hyprland port on the
// `hyprland` branch): turn it on or off, pick the character and choose what it
// may do. Everything goes through `ryoku-pestinha`: with the pet
// open it talks to the pet's local control socket, with the pet closed it edits
// the pet's saved permissions. Saves at once, outside the Hub's Save.
Item {
    id: control

    implicitHeight: col.implicitHeight

    property var st: ({})
    property string pending: ""
    readonly property bool installed: st.installed === true
    readonly property bool running: st.running === true
    readonly property bool starting: st.starting === true && !running
    readonly property bool ligado: st.enabled === true
    readonly property bool panico: running && st.ativo === false
    readonly property var perms: st.perms || ({})
    readonly property var pets: Array.isArray(st.pets) && st.pets.length ? st.pets : ["bryan"]
    readonly property bool canTune: installed && (running || st.configured === true) && pending === ""

    function refresh() {
        if (!statusP.running)
            statusP.running = true;
    }
    function run(args) {
        if (actP.running)
            return;
        control.pending = args[0];
        actP.command = ["ryoku-pestinha"].concat(args);
        actP.running = true;
    }
    // flip the switch at once; the next status read confirms it
    function setPerm(key, value) {
        var p = Object.assign({}, control.perms);
        p[key] = value;
        control.st = Object.assign({}, control.st, { perms: p });
        control.run(["set", key + "=" + (value ? "on" : "off")]);
    }
    function perm(key) {
        return control.perms[key] === true;
    }

    Process {
        id: statusP
        command: ["ryoku-pestinha", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    control.st = JSON.parse(this.text);
                } catch (e) {
                    control.st = { installed: false };
                }
            }
        }
    }
    Process {
        id: actP
        onExited: {
            control.pending = "";
            control.refresh();
        }
    }
    Timer {
        interval: control.starting || control.pending !== "" ? 700 : 2500
        running: control.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: control.refresh()
    }

    component PLabel: Text {
        color: Tokens.inkMuted
        font.family: Tokens.mono
        font.pixelSize: Tokens.fMicro
        font.weight: Font.Medium
        font.letterSpacing: Tokens.trackLabel
    }
    component PermSwitch: RowLayout {
        id: psw
        property string label: ""
        property string key: ""
        property bool dim: false
        Layout.fillWidth: true
        spacing: Tokens.s2
        enabled: control.canTune && !psw.dim
        opacity: enabled ? 1 : 0.5
        PLabel { text: psw.label; color: Tokens.ink }
        Item { Layout.fillWidth: true }
        Sw {
            on: control.perm(psw.key)
            Accessible.name: psw.label
            onToggled: (v) => control.setPerm(psw.key, v)
        }
    }

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Tokens.s3

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.s2
            Text {
                text: I18n.tr("STATUS")
                color: Tokens.ink
                font.family: Tokens.mono
                font.pixelSize: Tokens.fMicro
                font.weight: Font.Medium
                font.letterSpacing: Tokens.trackLabel
            }
            PLabel {
                text: !control.installed ? I18n.tr("NOT INSTALLED")
                    : control.panico ? I18n.tr("PANIC · OFF")
                    : control.running && control.st.pausado === true ? I18n.tr("PAUSED")
                    : control.running && control.st.escondido === true ? I18n.tr("HIDDEN")
                    : control.running ? I18n.tr("RUNNING · %1").arg(String(control.st.nome || "").toUpperCase())
                    : control.starting ? I18n.tr("STARTING")
                    : I18n.tr("CLOSED")
                color: control.panico ? Tokens.alert : control.running ? Tokens.sun : Tokens.inkMuted
            }
            Item { Layout.fillWidth: true }
            Btn {
                text: I18n.tr("PET SETTINGS")
                compact: true
                armed: control.installed && control.pending === ""
                onAct: control.run(["settings"])
            }
            Sw {
                on: control.ligado
                enabled: control.installed && control.pending === ""
                Accessible.name: I18n.tr("Pestinha on")
                onToggled: (v) => {
                    control.st = Object.assign({}, control.st, { enabled: v });
                    control.run([v ? "on" : "off"]);
                }
            }
        }

        Text {
            Layout.fillWidth: true
            text: control.installed
                ? I18n.tr("A small screen pet with a spiking neural network of its own: it falls, walks on top of your windows, plays with a ball and learns from your petting. Changes apply at once.")
                : I18n.tr("Pestinha was not found in %1. Clone it there and create its venv (.venv), or set \"dir\" in ~/.config/ryoku/pestinha.json.").arg(String(control.st.dir || "~/Projects/pestinha"))
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall
            wrapMode: Text.WordWrap
        }

        GridLayout {
            Layout.fillWidth: true
            columns: control.width >= Tokens.px(720) ? 2 : 1
            columnSpacing: Tokens.s5
            rowSpacing: Tokens.s3
            visible: control.installed

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.s1
                enabled: control.installed && control.pending === ""
                opacity: enabled ? 1 : 0.5
                PLabel { text: I18n.tr("CHARACTER") }
                Seg {
                    Layout.fillWidth: true
                    implicitHeight: Tokens.ctlH
                    options: control.pets
                    labels: {
                        var m = {};
                        for (var i = 0; i < control.pets.length; i++)
                            m[control.pets[i]] = String(control.pets[i]).toUpperCase();
                        return m;
                    }
                    current: String(control.st.pet || "bryan")
                    onChose: (k) => {
                        if (k === control.st.pet)
                            return;
                        control.st = Object.assign({}, control.st, { pet: k });
                        control.run(["pet", k]);
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.s1
                PLabel { text: I18n.tr("RIGHT NOW") }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.s2
                    Btn {
                        text: control.st.pausado === true ? I18n.tr("RESUME") : I18n.tr("PAUSE")
                        compact: true
                        armed: control.running && !control.panico && control.pending === ""
                        onAct: control.run(["pause"])
                    }
                    Btn {
                        text: control.st.escondido === true ? I18n.tr("SHOW") : I18n.tr("HIDE")
                        compact: true
                        armed: control.running && !control.panico && control.pending === ""
                        onAct: control.run(["hide"])
                    }
                    Btn {
                        text: control.panico ? I18n.tr("TURN BACK ON") : I18n.tr("PANIC")
                        compact: true
                        armed: control.running && control.pending === ""
                        onAct: control.run([control.panico ? "religar" : "panic"])
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            PLabel {
                Layout.columnSpan: parent.columns
                Layout.topMargin: Tokens.s2
                text: I18n.tr("WHAT IT MAY DO")
                color: Tokens.ink
            }
            PermSwitch { label: I18n.tr("LAND ON WINDOWS"); key: "pousar_janelas" }
            PermSwitch { label: I18n.tr("BALL"); key: "bolinha" }
            PermSwitch { label: I18n.tr("NOTEBOOK · WORKS WHILE YOU CODE"); key: "notebook" }
            PermSwitch { label: I18n.tr("FIREWORKS WHEN HAPPY"); key: "fogos" }
            PermSwitch { label: I18n.tr("PETTING & LEARNING"); key: "carinho" }
            PermSwitch { label: I18n.tr("POKE"); key: "cutucar" }
            PermSwitch { label: I18n.tr("DRAG & THROW"); key: "arrastar" }
            PermSwitch { label: I18n.tr("SHOW OVER FULLSCREEN"); key: "tela_cheia" }
            PermSwitch { label: I18n.tr("MISCHIEF"); key: "travessuras" }
            PermSwitch { label: I18n.tr("MEMES"); key: "memes"; dim: !control.perm("travessuras") }
            PermSwitch { label: I18n.tr("STICKY NOTES"); key: "bilhetes"; dim: !control.perm("travessuras") }
            PermSwitch { label: I18n.tr("PHOTOS"); key: "fotos"; dim: !control.perm("travessuras") }
        }

        Text {
            Layout.fillWidth: true
            visible: control.installed
            text: [
                control.st.atalho === false && control.running
                    ? I18n.tr("The panic shortcut is missing from Hyprland.")
                    : I18n.tr("CTRL + ALT + SHIFT + B is the panic key: everything disappears at once; TURN BACK ON brings it back."),
                control.st.login === true
                    ? I18n.tr("When on, it opens at every login.")
                    : I18n.tr("It does not open by itself at login (no `ryoku-pestinha autostart` hook in the Hyprland config)."),
                (!control.running && control.st.configured !== true)
                    ? I18n.tr("The first time it opens, it asks for its permissions in its own window.")
                    : I18n.tr("A new character restarts the pet; each one keeps its own memory.")
            ].join(" ")
            color: Tokens.inkDim
            font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall
            wrapMode: Text.WordWrap
        }
    }
}
