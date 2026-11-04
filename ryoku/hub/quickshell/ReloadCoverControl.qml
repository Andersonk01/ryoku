pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons
import "ReloadCoverModel.js" as ReloadCoverModel

Item {
    id: control

    property var descriptor: ReloadCoverModel.empty()
    property string errorText: ""
    property bool busy: false
    readonly property var media: ReloadCoverModel.normalize(descriptor)
    readonly property url rendererSource: ReloadCoverModel.rendererSource(
        Quickshell.env("RYOKU_SHELL_DIR"),
        Quickshell.env("XDG_CONFIG_HOME"),
        Quickshell.env("HOME"))

    signal addRequested()
    signal defaultRequested()
    signal enabledToggled(bool enabled)

    implicitHeight: grid.implicitHeight + Tokens.s5 + introPanel.implicitHeight

    // [user fork] the login intro's settings. They write straight to
    // ~/.config/ryoku/intro.json (the cover and this preview both watch it),
    // so they apply at once and do not ride the page's Save bar.
    readonly property string introPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/intro.json"
    FileView {
        id: introFV
        path: control.introPath
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        JsonAdapter {
            id: introA
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
            property string showMode: "always"
            property bool afterUnlock: true
            property bool sound: true
            property real soundVolume: 70
            property bool soundTyping: true
            property bool soundDecode: true
            property bool soundGranted: true
            property bool soundGlitch: true
            property bool soundAmbience: true
            property bool soundBoot: true
        }
    }
    // "once" bookkeeping: the boot cover that first plays the intro writes its
    // token here; emptying it arms the intro for the next login again.
    FileView {
        id: introSeenFV
        path: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku/intro-seen"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }
    readonly property bool introSeen: (introSeenFV.text() || "").trim() !== ""
    function introRearm() {
        introSeenFV.setText("");
    }
    function introSet(key, value) {
        if (introA[key] === value)
            return;
        introA[key] = value;
        introFV.writeAdapter();
    }
    function replayIntro() {
        if (renderer.item && typeof renderer.item.replayIntro === "function")
            renderer.item.replayIntro();
    }

    GridLayout {
        id: grid
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        columns: control.width >= Tokens.px(720) ? 2 : 1
        columnSpacing: Tokens.s5
        rowSpacing: Tokens.s4

        Item {
            id: preview
            readonly property real previewWidth: Math.min(Tokens.px(420), grid.columns === 1
                ? grid.width : Math.max(0, (grid.width - grid.columnSpacing) / 2))

            Layout.maximumWidth: Tokens.px(420)
            Layout.preferredWidth: previewWidth
            Layout.preferredHeight: previewWidth * 9 / 16
            Layout.fillWidth: grid.columns === 1
            Layout.alignment: Qt.AlignHCenter | Qt.AlignTop
            Accessible.ignored: true

            Rectangle {
                anchors.fill: parent
                color: Tokens.keycapDark
                border.width: Tokens.border
                border.color: Tokens.lineStrong
                radius: Tokens.radius
                clip: true

                Loader {
                    id: renderer
                    anchors.fill: parent
                    active: control.visible
                    asynchronous: true
                    source: active ? control.rendererSource : ""
                    onLoaded: {
                        if (status === Loader.Ready && item) {
                            item.descriptor = Qt.binding(() => control.media)
                            item.active = Qt.binding(() => control.visible)
                            item.forceDefault = false
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: renderer.status === Loader.Error
                    text: UiPreferences.brandMark("力")
                    color: Tokens.inkFaint
                    font.family: Tokens.jp
                    font.pixelSize: Tokens.fHero
                }
            }
        }

        ColumnLayout {
            id: details
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            spacing: Tokens.s2

            Rectangle {
                readonly property string kindLabel: introA.enabled ? I18n.tr("INTRO · ANIMATED")
                    : control.media.path !== "" && !control.media.enabled
                    ? I18n.tr("CUSTOM OFF")
                    : (control.media.kind === "video"
                    ? I18n.tr("VIDEO · MUTED")
                    : (control.media.kind === "animated" ? I18n.tr("ANIMATED IMAGE")
                    : (control.media.kind === "image" ? I18n.tr("IMAGE") : I18n.tr("DEFAULT"))))
                Layout.alignment: Qt.AlignLeft
                implicitWidth: kind.implicitWidth + Tokens.s3 * 2
                implicitHeight: Tokens.ctlH
                color: Tokens.tint10
                border.width: Tokens.border
                border.color: Tokens.line
                radius: Tokens.radius

                Text {
                    id: kind
                    anchors.centerIn: parent
                    text: parent.kindLabel
                    color: Tokens.ink
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fMicro
                    font.weight: Font.Medium
                    font.letterSpacing: Tokens.trackLabel
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.s2

                Text {
                    text: I18n.tr("CUSTOM ASSET")
                    color: Tokens.ink
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fMicro
                    font.weight: Font.Medium
                    font.letterSpacing: Tokens.trackLabel
                }

                Item { Layout.fillWidth: true }

                Sw {
                    on: control.media.enabled
                    enabled: !control.busy && control.media.path !== ""
                    Accessible.name: I18n.tr("CUSTOM ASSET")
                    onToggled: (enabled) => control.enabledToggled(enabled)
                }
            }

            Text {
                Layout.fillWidth: true
                // the kind chip above already says DEFAULT when nothing custom is
                // set, so the asset line only speaks when there is an asset
                visible: control.media.path !== ""
                text: control.media.name + (ReloadCoverModel.formatBytes(control.media.bytes) === "" ? "" : " · " + ReloadCoverModel.formatBytes(control.media.bytes))
                color: Tokens.ink
                font.family: Tokens.ui
                font.pixelSize: Tokens.fRow
                font.weight: Font.Medium
                elide: Text.ElideMiddle
            }

            Text {
                Layout.fillWidth: true
                text: I18n.tr("BEST RESULTS · MATCH DISPLAY RATIO · 1920x1080 FOR 16:9 · 2-4 S LOOP · UNDER 20 MB")
                color: Tokens.inkDim
                font.family: Tokens.mono
                font.pixelSize: Tokens.fMicro
                font.letterSpacing: Tokens.trackLabel
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: I18n.tr("Transparent PNG or SVG works best for a centered mark. Use 24-30 FPS H.264 MP4 or WebM for motion.")
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: I18n.tr("The same asset is fitted independently on every monitor.")
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: I18n.tr("The backend rejects files over 64 MiB.")
                color: Tokens.inkMuted
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: control.errorText !== ""
                text: control.errorText
                color: Tokens.ink
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: renderer.status === Loader.Error
                text: I18n.tr("Preview unavailable; reload still falls back to the Ryoku wordmark.")
                color: Tokens.ink
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                visible: renderer.status === Loader.Ready && renderer.item && renderer.item.mediaError
                text: I18n.tr("Couldn't preview this asset; shell reload will use the Ryoku wordmark.")
                color: Tokens.ink
                font.family: Tokens.ui
                font.pixelSize: Tokens.fSmall
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.s2

                Btn {
                    text: I18n.tr("DEFAULT")
                    armed: !control.busy
                    onAct: control.defaultRequested()
                }
                Btn {
                    text: I18n.tr("ADD ASSET…")
                    primary: true
                    armed: !control.busy
                    onAct: control.addRequested()
                }
                Item { Layout.fillWidth: true }
            }
        }
    }

    component IntroLabel: Text {
        color: Tokens.inkMuted
        font.family: Tokens.mono
        font.pixelSize: Tokens.fMicro
        font.weight: Font.Medium
        font.letterSpacing: Tokens.trackLabel
    }
    component IntroSwitch: RowLayout {
        id: isw
        property string label: ""
        property bool on: false
        signal flipped(bool v)
        Layout.fillWidth: true
        spacing: Tokens.s2
        IntroLabel { text: isw.label; color: Tokens.ink }
        Item { Layout.fillWidth: true }
        Sw {
            on: isw.on
            Accessible.name: isw.label
            onToggled: (v) => isw.flipped(v)
        }
    }
    component IntroField: ColumnLayout {
        id: ifl
        property string label: ""
        property string value: ""
        property string hint: ""
        signal valueEdited(string v)
        Layout.fillWidth: true
        spacing: Tokens.s1
        IntroLabel { text: ifl.label }
        Field {
            Layout.fillWidth: true
            placeholder: ifl.hint
            text: ifl.value
            onCommitted: (v) => { if (v !== ifl.value) ifl.valueEdited(v); }
        }
    }

    ColumnLayout {
        id: introPanel
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: grid.bottom
        anchors.topMargin: Tokens.s5
        spacing: Tokens.s3

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Tokens.border
            color: Tokens.line
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.s2
            Text {
                text: I18n.tr("LOGIN INTRO")
                color: Tokens.ink
                font.family: Tokens.mono
                font.pixelSize: Tokens.fMicro
                font.weight: Font.Medium
                font.letterSpacing: Tokens.trackLabel
            }
            Item { Layout.fillWidth: true }
            Btn {
                text: I18n.tr("REPLAY")
                compact: true
                armed: introA.enabled
                onAct: control.replayIntro()
            }
            Sw {
                on: introA.enabled
                Accessible.name: I18n.tr("LOGIN INTRO")
                onToggled: (v) => control.introSet("enabled", v)
            }
        }

        Text {
            Layout.fillWidth: true
            text: I18n.tr("An animated title in place of the wordmark while the desktop loads. Changes save at once and show in the preview above.")
            color: Tokens.inkMuted
            font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall
            wrapMode: Text.WordWrap
        }

        GridLayout {
            Layout.fillWidth: true
            columns: grid.columns
            columnSpacing: Tokens.s5
            rowSpacing: Tokens.s3
            enabled: introA.enabled
            opacity: introA.enabled ? 1 : 0.5

            IntroField { label: I18n.tr("TITLE"); hint: "ANDERSONK"; value: introA.title; onValueEdited: (v) => control.introSet("title", v) }
            IntroField { label: I18n.tr("DESCRIPTION"); hint: "Full Stack Developer"; value: introA.subtitle; onValueEdited: (v) => control.introSet("subtitle", v) }
            IntroField { label: I18n.tr("SECOND LINE"); hint: "React · Next.js · Node.js"; value: introA.tagline; onValueEdited: (v) => control.introSet("tagline", v) }
            IntroField { label: I18n.tr("SEAL"); hint: "ACCESS GRANTED"; value: introA.header; onValueEdited: (v) => control.introSet("header", v) }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.columnSpan: grid.columns
                spacing: Tokens.s1
                IntroLabel { text: I18n.tr("PLAY ON") }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.s3
                    Seg {
                        implicitHeight: Tokens.ctlH
                        options: ["always", "once"]
                        labels: ({ "always": I18n.tr("EVERY LOGIN"), "once": I18n.tr("FIRST LOGIN ONLY") })
                        current: introA.showMode === "once" ? "once" : "always"
                        onChose: (k) => control.introSet("showMode", k)
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: introA.showMode === "once"
                        text: control.introSeen
                            ? I18n.tr("Already played on a login; later logins show the wordmark.")
                            : I18n.tr("Plays on the next login, then the wordmark returns.")
                        color: Tokens.inkMuted
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                        elide: Text.ElideRight
                    }
                    Btn {
                        visible: introA.showMode === "once" && control.introSeen
                        text: I18n.tr("SHOW AGAIN")
                        compact: true
                        onAct: control.introRearm()
                    }
                    // every-login mode can replay after the lock screen too
                    // (unlock-watch.sh, the intro-unlock user service)
                    Item {
                        Layout.fillWidth: true
                        visible: introA.showMode !== "once"
                    }
                    IntroLabel {
                        visible: introA.showMode !== "once"
                        text: I18n.tr("ALSO AFTER UNLOCK")
                        color: Tokens.ink
                    }
                    Sw {
                        visible: introA.showMode !== "once"
                        on: introA.afterUnlock
                        Accessible.name: I18n.tr("ALSO AFTER UNLOCK")
                        onToggled: (v) => control.introSet("afterUnlock", v)
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.s1
                IntroLabel { text: I18n.tr("TITLE STYLE") }
                Seg {
                    Layout.fillWidth: true
                    implicitHeight: Tokens.ctlH
                    options: ["pixel", "terminal"]
                    labels: ({ "pixel": I18n.tr("PIXEL"), "terminal": I18n.tr("TERMINAL") })
                    current: introA.style === "terminal" ? "terminal" : "pixel"
                    onChose: (k) => control.introSet("style", k)
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.s2
                IntroLabel { text: I18n.tr("MINIMUM HOLD") }
                Item { Layout.fillWidth: true }
                Text {
                    text: Math.round(Number(introA.minHold) || 0) === 0 ? I18n.tr("OFF")
                        : I18n.tr("%1 S").arg(Math.round(Number(introA.minHold) || 0))
                    color: Tokens.ink
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fSmall
                    font.weight: Font.Medium
                }
                Step {
                    value: Math.round(Number(introA.minHold) || 0)
                    from: 0
                    to: 10
                    stepBy: 1
                    onModified: (v) => control.introSet("minHold", v)
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.s1
                IntroLabel { text: I18n.tr("ACCENT") }
                ColorField {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    value: introA.accent
                    onChosen: (v) => control.introSet("accent", v)
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Tokens.s1
                IntroLabel { text: I18n.tr("SECOND ACCENT") }
                ColorField {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    value: introA.accent2
                    onChosen: (v) => control.introSet("accent2", v)
                }
            }

            IntroSwitch { label: I18n.tr("CODE RAIN"); on: introA.rain; onFlipped: (v) => control.introSet("rain", v) }
            IntroSwitch { label: I18n.tr("GLITCH"); on: introA.glitch; onFlipped: (v) => control.introSet("glitch", v) }
            IntroSwitch { label: I18n.tr("SCANLINES"); on: introA.scanlines; onFlipped: (v) => control.introSet("scanlines", v) }
            IntroSwitch { label: I18n.tr("BOOT LOG"); on: introA.bootLog; onFlipped: (v) => control.introSet("bootLog", v) }

            // ── sound: in the same grid, so its switches line up ─────────
            RowLayout {
                Layout.fillWidth: true
                Layout.columnSpan: grid.columns
                Layout.topMargin: Tokens.s2
                spacing: Tokens.s2
                Text {
                    text: I18n.tr("SOUND")
                    color: Tokens.ink
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fMicro
                    font.weight: Font.Medium
                    font.letterSpacing: Tokens.trackLabel
                }
                Text {
                    Layout.fillWidth: true
                    text: I18n.tr("Keys typing, decrypt ticks, the access chime and a low drone. REPLAY plays it with sound.")
                    color: Tokens.inkMuted
                    font.family: Tokens.ui
                    font.pixelSize: Tokens.fSmall
                    elide: Text.ElideRight
                }
                Sw {
                    on: introA.sound
                    Accessible.name: I18n.tr("SOUND")
                    onToggled: (v) => control.introSet("sound", v)
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.columnSpan: grid.columns
                spacing: Tokens.s2
                enabled: introA.sound
                opacity: introA.sound ? 1 : 0.5
                IntroLabel { text: I18n.tr("VOLUME") }
                Item { Layout.fillWidth: true }
                Text {
                    text: I18n.tr("%1%").arg(Math.round(Number(introA.soundVolume) || 0))
                    color: Tokens.ink
                    font.family: Tokens.mono
                    font.pixelSize: Tokens.fSmall
                    font.weight: Font.Medium
                }
                Step {
                    value: Math.round(Number(introA.soundVolume) || 0)
                    from: 0
                    to: 100
                    stepBy: 10
                    onModified: (v) => control.introSet("soundVolume", v)
                }
            }
            IntroSwitch { label: I18n.tr("TYPING"); enabled: introA.sound; opacity: introA.sound ? 1 : 0.5; on: introA.soundTyping; onFlipped: (v) => control.introSet("soundTyping", v) }
            IntroSwitch { label: I18n.tr("DECRYPT TICKS"); enabled: introA.sound; opacity: introA.sound ? 1 : 0.5; on: introA.soundDecode; onFlipped: (v) => control.introSet("soundDecode", v) }
            IntroSwitch { label: I18n.tr("ACCESS CHIME"); enabled: introA.sound; opacity: introA.sound ? 1 : 0.5; on: introA.soundGranted; onFlipped: (v) => control.introSet("soundGranted", v) }
            IntroSwitch { label: I18n.tr("GLITCH NOISE"); enabled: introA.sound; opacity: introA.sound ? 1 : 0.5; on: introA.soundGlitch; onFlipped: (v) => control.introSet("soundGlitch", v) }
            IntroSwitch { label: I18n.tr("AMBIENT DRONE"); enabled: introA.sound; opacity: introA.sound ? 1 : 0.5; on: introA.soundAmbience; onFlipped: (v) => control.introSet("soundAmbience", v) }
            IntroSwitch { label: I18n.tr("BOOT & LOG BLIPS"); enabled: introA.sound; opacity: introA.sound ? 1 : 0.5; on: introA.soundBoot; onFlipped: (v) => control.introSet("soundBoot", v) }
        }

        Text {
            Layout.fillWidth: true
            text: I18n.tr("Minimum hold keeps the login cover up until the intro has played; after an unlock it holds that long too (3 s when OFF). Sound plays on login, after an unlock and on REPLAY; shell reloads stay silent and never wait.")
            color: Tokens.inkDim
            font.family: Tokens.ui
            font.pixelSize: Tokens.fSmall
            wrapMode: Text.WordWrap
        }
    }
}
