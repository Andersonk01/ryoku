pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// [user] The after-unlock intro, ready before the unlock.
//
// Raising a cover only after the unlock always showed the desktop for about a
// second first: the lock leaves within ~0.1 s, a fresh qs needs ~0.4 s to map
// and the iris another 0.5 s to close. So unlock-watch.sh starts this the
// moment qylock publishes its lock proof, while the screen is already locked:
// it maps one opaque cover per screen under the lock surface, with the intro
// paused on its first frame (all black). logind's Session.Unlock starts the
// intro, so when the lock surface goes the intro is already playing. After
// the intro's minimum hold (3 s when it is OFF) the iris opens and it quits.
//
// Covers are mapped only while the session is locked, take no input (empty
// mask, no keyboard focus) and always end: a missed signal still releases on
// the lock proof vanishing, a dead monitor quits, and a released cover quits
// by its own ceiling.
ShellRoot {
    id: root

    readonly property string sessionPath: Quickshell.env("RYOKU_INTRO_SESSION_PATH") || ""
    readonly property string marker: Quickshell.env("RYOKU_INTRO_LOCK_MARKER") || ""
    // testing (unlock-watch.sh --now): release by itself after this long
    readonly property int autoRelease: Number(Quickshell.env("RYOKU_INTRO_AUTORELEASE_MS") || 0)
    property bool released: false
    property bool opening: false

    readonly property string introPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/intro.json"
    FileView {
        path: root.introPath
        blockLoading: true
        printErrors: false
        JsonAdapter {
            id: introA
            property real minHold: 3
        }
    }
    readonly property int holdMs: {
        var s = Math.max(0, Math.min(10, Number(introA.minHold) || 0));
        return Math.round((s > 0 ? s : 3) * 1000);
    }

    function release(why: string): void {
        if (released) return;
        released = true;
        console.info("intro-unlock: released (" + why + ")");
        holdTimer.start();
    }

    // logind's unlock, the one signal that means "show it now". stdbuf keeps
    // gdbus line-buffered on a pipe, so the line arrives when it is printed.
    Process {
        id: monitor
        running: true
        command: ["stdbuf", "-oL", "gdbus", "monitor", "--system", "--dest", "org.freedesktop.login1"]
            .concat(root.sessionPath !== "" ? ["--object-path", root.sessionPath] : [])
        stdout: SplitParser {
            onRead: (line) => {
                if (line.indexOf(".Session.Unlock (") >= 0)
                    root.release("unlock signal");
            }
        }
        onExited: if (!root.released) Qt.quit()
    }

    // Fallback: the unlock clears the lock proof a moment before it signals.
    // If the proof stays gone and no signal came, release anyway (behind a
    // lock that is restarting this plays unseen, which is harmless).
    FileView {
        path: root.marker
        printErrors: false
        watchChanges: root.marker !== ""
        onFileChanged: reload()
        onLoaded: proofGone.stop()
        onLoadFailed: if (!root.released) proofGone.restart()
    }
    Timer {
        id: proofGone
        interval: 1500
        onTriggered: root.release("lock proof gone")
    }
    Timer {
        interval: Math.max(1, root.autoRelease)
        running: root.autoRelease > 0
        onTriggered: root.release("test")
    }

    Timer {
        id: holdTimer
        interval: root.holdMs
        onTriggered: root.opening = true
    }
    Timer {
        interval: 560
        running: root.opening
        onTriggered: Qt.quit()
    }
    // ceiling once released: the longest hold plus the iris, with room
    Timer {
        interval: 13000
        running: root.released
        onTriggered: Qt.quit()
    }

    IpcHandler {
        target: "intro-unlock"
        function release(): void { root.release("ipc"); }
        function status(): string { return root.opening ? "opening" : (root.released ? "released" : "standby"); }
    }

    Variants {
        model: Quickshell.screens
        delegate: Component {
            PanelWindow {
                id: cover
                required property var modelData

                screen: modelData
                color: "transparent"
                exclusionMode: ExclusionMode.Ignore
                exclusiveZone: 0
                WlrLayershell.namespace: "ryoku-intro-unlock"
                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                anchors { top: true; bottom: true; left: true; right: true }
                mask: Region {}

                readonly property real diagonal: Math.sqrt(width * width + height * height)
                property real iris: 0
                readonly property real mediaOpacity: root.opening ? Math.max(0, 1 - iris / (diagonal * 0.38)) : 1

                Connections {
                    target: root
                    function onOpeningChanged() {
                        if (root.opening) {
                            cover.iris = 0;
                            openAnim.restart();
                        }
                    }
                }
                NumberAnimation {
                    id: openAnim
                    target: cover
                    property: "iris"
                    from: 0
                    to: cover.diagonal
                    duration: 520
                    easing.type: Easing.InOutCubic
                }

                Rectangle {
                    anchors.fill: parent
                    color: "black"
                    visible: !root.opening
                }
                // the same iris as ReloadCover's, opening onto the desktop
                Shape {
                    anchors.fill: parent
                    visible: root.opening
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: "black"
                        strokeColor: "transparent"
                        fillRule: ShapePath.OddEvenFill
                        PathRectangle { x: 0; y: 0; width: cover.width; height: cover.height }
                        PathSvg {
                            path: {
                                const r = Math.max(0.001, cover.iris);
                                const x = cover.width / 2 - r;
                                const y = cover.height / 2;
                                return "M " + x + " " + y
                                    + " A " + r + " " + r + " 0 1 0 " + (x + r * 2) + " " + y
                                    + " A " + r + " " + r + " 0 1 0 " + x + " " + y + " Z";
                            }
                        }
                    }
                }

                ReloadMedia {
                    anchors.fill: parent
                    // paused on its first (black) frame until the unlock
                    active: root.released && cover.backingWindowVisible
                    opacity: cover.mediaOpacity
                    scale: opacity < 1 ? 0.94 + opacity * 0.06 : 1
                }
            }
        }
    }
}
