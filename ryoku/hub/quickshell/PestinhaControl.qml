pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons

// [user] Pestinha, the desktop pet (~/Projects/pestinha, Hyprland port on the
// `hyprland` branch): turn it on or off, pick the character (each one described
// by its pets/<id>.json) and choose what it may do. docs/pestinha.md. Everything goes through `ryoku-pestinha`: with the pet
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
    readonly property bool isOn: st.enabled === true
    readonly property bool panico: running && st.ativo === false
    readonly property var perms: st.perms || ({})
    readonly property var pets: Array.isArray(st.pets) && st.pets.length ? st.pets : ["bryan"]
    // {id: {nome, descricao: {language: text}}}, read from each pets/<id>.json
    readonly property var petInfo: st.pet_info || ({})
    readonly property string currentPet: String(st.pet || "bryan")
    readonly property bool canTune: installed && (running || st.configured === true) && pending === ""

    function petName(id) {
        var info = control.petInfo[id] || {};
        return String(info.nome || id);
    }
    // the description in the desktop's language: exact (pt_BR), its base (pt), English, then any
    function describe(id) {
        var d = (control.petInfo[id] || {}).descricao || {};
        var lang = String(I18n.lang || "en");
        var order = [lang, lang.split("_")[0], "en"];
        for (var i = 0; i < order.length; i++)
            if (d[order[i]])
                return String(d[order[i]]);
        for (var k in d)
            if (d[k])
                return String(d[k]);
        return "";
    }
    // a new character restarts a running pet, or is saved for its next start
    function choosePet(k) {
        if (k === control.currentPet)
            return;
        control.st = Object.assign({}, control.st, { pet: k });
        control.run(["pet", k]);
    }
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
    // a pick between options (style, volume): same path as a switch, with the option as the value
    function setChoice(key, value) {
        if (control.choice(key) === value)
            return;
        var p = Object.assign({}, control.perms);
        p[key] = value;
        control.st = Object.assign({}, control.st, { perms: p });
        control.run(["set", key + "=" + value]);
    }
    // a pet saved by an older version has no value for the newer keys yet: show the pet's default
    readonly property var defaults: ({ notebook: true, sons: true, digitacao: true, estilo: "original", volume: "medio" })
    function perm(key) {
        return (key in control.perms ? control.perms[key] : control.defaults[key]) === true;
    }
    function choice(key) {
        return String(control.perms[key] || control.defaults[key] || "");
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
                on: control.isOn
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
            id: grid
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
                            m[control.pets[i]] = control.petName(control.pets[i]).toUpperCase();
                        return m;
                    }
                    current: control.currentPet
                    onChose: (k) => control.choosePet(k)
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.s1
                enabled: control.canTune
                opacity: enabled ? 1 : 0.5
                PLabel { text: I18n.tr("STYLE · APPLIES AT ONCE") }
                Seg {
                    Layout.fillWidth: true
                    implicitHeight: Tokens.ctlH
                    options: ["original", "rosa", "cyber", "matrix", "ambar"]
                    labels: ({ original: I18n.tr("ORIGINAL"), rosa: I18n.tr("PINK"), cyber: I18n.tr("CYBER"),
                               matrix: I18n.tr("MATRIX"), ambar: I18n.tr("AMBER") })
                    current: control.choice("estilo")
                    onChose: (k) => control.setChoice("estilo", k)
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
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.s1
                enabled: control.canTune && control.perm("sons")
                opacity: enabled ? 1 : 0.5
                PLabel { text: I18n.tr("SOUND VOLUME") }
                Seg {
                    Layout.fillWidth: true
                    implicitHeight: Tokens.ctlH
                    options: ["baixo", "medio", "alto"]
                    labels: ({ baixo: I18n.tr("LOW"), medio: I18n.tr("MEDIUM"), alto: I18n.tr("HIGH") })
                    current: control.choice("volume")
                    onChose: (k) => control.setChoice("volume", k)
                }
            }

            PLabel {
                Layout.columnSpan: grid.columns
                Layout.topMargin: Tokens.s2
                text: I18n.tr("THE CHARACTERS · WHO EACH ONE IS")
                color: Tokens.ink
            }
            Repeater {
                model: control.pets
                delegate: Rectangle {
                    id: card
                    required property string modelData
                    readonly property bool current: modelData === control.currentPet
                    readonly property string about: control.describe(modelData)
                    Layout.columnSpan: grid.columns
                    Layout.fillWidth: true
                    implicitHeight: cardCol.implicitHeight + 2 * Tokens.s3
                    radius: Tokens.radius
                    color: "transparent"
                    border.width: Tokens.border
                    border.color: current ? Tokens.sun : Tokens.lineSoft

                    ColumnLayout {
                        id: cardCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: Tokens.s3
                        spacing: Tokens.s1
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Tokens.s2
                            PLabel {
                                text: control.petName(card.modelData).toUpperCase()
                                color: card.current ? Tokens.sun : Tokens.ink
                            }
                            Item { Layout.fillWidth: true }
                            Btn {
                                text: card.current ? I18n.tr("CHOSEN") : I18n.tr("CHOOSE")
                                compact: true
                                armed: !card.current && control.installed && control.pending === ""
                                onAct: control.choosePet(card.modelData)
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: card.about !== "" ? card.about
                                : I18n.tr("No description yet: add \"descricao\" to pets/%1.json.").arg(card.modelData)
                            color: card.about !== "" ? Tokens.inkMuted : Tokens.inkFaint
                            font.family: Tokens.ui
                            font.pixelSize: Tokens.fSmall
                            wrapMode: Text.WordWrap
                        }
                    }
                }
            }

            PLabel {
                Layout.columnSpan: grid.columns
                Layout.topMargin: Tokens.s2
                text: I18n.tr("WHAT IT MAY DO")
                color: Tokens.ink
            }
            PermSwitch { label: I18n.tr("LAND ON WINDOWS"); key: "pousar_janelas" }
            PermSwitch { label: I18n.tr("BALL"); key: "bolinha" }
            PermSwitch { label: I18n.tr("NOTEBOOK · WORKS WHILE YOU CODE"); key: "notebook" }
            PermSwitch { label: I18n.tr("SOUNDS · BEEPS & REACTIONS"); key: "sons" }
            PermSwitch { label: I18n.tr("TYPING SOUND AT THE NOTEBOOK"); key: "digitacao"; dim: !control.perm("sons") }
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
