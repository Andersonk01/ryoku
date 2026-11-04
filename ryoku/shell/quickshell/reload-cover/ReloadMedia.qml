import QtQuick
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property var descriptor: ({ path: "", name: "", kind: "default", bytes: 0, enabled: true })
    property bool active: true
    property bool forceDefault: false
    onMediaPathChanged: {
        orientationKnown = false
        imageTall = false
    }

    readonly property string mediaPath: descriptor && typeof descriptor.path === "string" ? descriptor.path : ""
    readonly property string mediaKind: descriptor && typeof descriptor.kind === "string" ? descriptor.kind : "default"
    readonly property bool customEnabled: !descriptor || descriptor.enabled !== false
    // [user fork] the animated intro (HackerIntro.qml) takes the place of the
    // wordmark and of any custom asset while ~/.config/ryoku/intro.json has
    // "enabled": true. Its own loader falls back to the wordmark on any error.
    //
    // showMode "once" plays it on one login only: the first boot cover that
    // shows it writes its own token to $XDG_STATE_HOME/ryoku/intro-seen, and
    // a later cover with another token falls back to the wordmark. Matching
    // the token (not just "file exists") keeps every monitor of that first
    // cover on the intro. The Hub preview (no cover mode) always shows it;
    // the Hub's SHOW AGAIN empties the marker.
    readonly property string coverMode: Quickshell.env("RYOKU_RELOAD_COVER_MODE") || ""
    readonly property string coverToken: Quickshell.env("RYOKU_RELOAD_COVER_TOKEN") || ""
    readonly property string seenPath: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/ryoku/intro-seen"
    readonly property string introPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/ryoku/intro.json"
    FileView {
        id: introFile
        path: root.introPath
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }
    // parsed in one piece: a JsonAdapter applies keys one by one, so the
    // loader would see "enabled" before "showMode" and decide on half a file
    readonly property var introCfg: {
        try {
            return JSON.parse(introFile.text() || "{}") || ({});
        } catch (e) {
            return ({});
        }
    }
    readonly property bool introEnabled: introCfg.enabled === true
    readonly property string introShowMode: introCfg.showMode === "once" ? "once" : "always"
    FileView {
        id: seenFile
        path: root.seenPath
        blockLoading: true
        printErrors: false
    }
    readonly property string seenToken: (seenFile.text() || "").trim()
    readonly property bool introAllowed: root.coverMode === ""
        || root.introShowMode !== "once"
        || root.seenToken === ""
        || (root.coverToken !== "" && root.seenToken === root.coverToken)
    readonly property bool wantsIntro: introEnabled && introAllowed
    function markIntroSeen(): void {
        if (root.coverMode === "boot" && root.introShowMode === "once"
                && root.coverToken !== "" && root.seenToken !== root.coverToken)
            seenFile.setText(root.coverToken + "\n");
    }
    readonly property bool introReady: wantsIntro && !forceDefault
        && introLoader.status === Loader.Ready && introLoader.item !== null
    // a replay asked for by the user (the Hub's REPLAY) may sound; the
    // preview's own restarts, after an edit, stay silent
    function replayIntro(): void {
        if (introLoader.item)
            introLoader.item.restart(true);
    }

    readonly property bool wantsVideo: !wantsIntro && customEnabled && mediaPath !== "" && mediaKind === "video"
    readonly property bool wantsImage: !wantsIntro && customEnabled && mediaPath !== "" && (mediaKind === "image" || mediaKind === "animated")
    // brand.json stores an absolute path today, but a hand-edited or ported
    // config may carry a ~ (the shell expands it for the brand mark too); a bare
    // "file://~/..." resolves to nothing and silently falls back to the default
    // cover, so expand it here before building the URL.
    readonly property string homeDir: Quickshell.env("HOME") || ""
    readonly property string resolvedPath: mediaPath === "~"
        ? root.homeDir
        : (mediaPath.indexOf("~/") === 0 ? root.homeDir + mediaPath.substring(1) : mediaPath)
    readonly property string imageSource: resolvedPath.indexOf("://") >= 0 ? resolvedPath : "file://" + resolvedPath
    readonly property size orientationProbeSize: Qt.size(64, 64)
    property bool orientationKnown: false
    property bool imageTall: false
    readonly property bool probeReady: imageProbeLoader.status === Loader.Ready
        && imageProbeLoader.item
        && imageProbeLoader.item.status === Image.Ready
    readonly property bool probeFailed: imageProbeLoader.status === Loader.Ready
        && imageProbeLoader.item
        && imageProbeLoader.item.status === Image.Error
    readonly property bool probeReleased: wantsImage && orientationKnown
        && imageProbeLoader.status === Loader.Null
    readonly property bool imageReady: wantsImage
        && customImageLoader.status === Loader.Ready
        && customImageLoader.item
        && customImageLoader.item.status === Image.Ready
    readonly property bool videoReady: videoLoader.status === Loader.Ready && videoLoader.item && videoLoader.item.ready
    readonly property bool customReady: introReady || (customEnabled && !forceDefault && (imageReady || videoReady))
    readonly property bool mediaError: wantsImage
        ? probeFailed
            || (orientationKnown && (customImageLoader.status === Loader.Error
                || (customImageLoader.status === Loader.Ready
                    && customImageLoader.item
                    && customImageLoader.item.status === Image.Error)))
        : (wantsVideo && (videoLoader.status === Loader.Error
            || (videoLoader.status === Loader.Ready && videoLoader.item && videoLoader.item.failed)))
    readonly property string mediaErrorText: wantsVideo && videoLoader.status === Loader.Ready && videoLoader.item
        ? videoLoader.item.errorText
        : ""
    readonly property bool showingDefault: forceDefault || !customReady
    readonly property real defaultLogoWidth: Math.min(width * 0.58, 928)
    readonly property real defaultLogoHeight: defaultLogoWidth * 160 / 928

    // The bundled wordmark with its loading light sweep: the cue that the
    // cover is working, not frozen. Lost in the ReloadMedia refactor merge;
    // restored here where the default mark now lives.
    Item {
        id: defaultLogo
        anchors.centerIn: parent
        width: root.defaultLogoWidth
        height: root.defaultLogoHeight
        visible: root.showingDefault

        Image {
            id: logo
            anchors.fill: parent
            source: "assets/logo.png"
            sourceSize.width: Math.round(root.defaultLogoWidth)
            fillMode: Image.PreserveAspectFit
        }

        Item {
            id: loadingSweep
            x: defaultLogo.width
            width: Math.max(36, defaultLogo.width * 0.24)
            height: defaultLogo.height
            clip: true

            ColorOverlay {
                x: -loadingSweep.x
                width: defaultLogo.width
                height: defaultLogo.height
                source: logo
                color: "#e2f0ff"
                opacity: 0.28
            }

            NumberAnimation on x {
                from: defaultLogo.width
                to: -loadingSweep.width
                duration: 1200
                running: defaultLogo.visible && root.active
                loops: Animation.Infinite
            }
        }
    }

    Loader {
        id: introLoader
        anchors.fill: parent
        active: root.wantsIntro && !root.forceDefault
        visible: root.introReady
        source: active ? Qt.resolvedUrl("HackerIntro.qml") : ""
        onLoaded: {
            if (status === Loader.Ready && item) {
                item.active = Qt.binding(() => root.active && !root.forceDefault)
                // the cover's fade in and out, which the intro's sound beds follow
                item.presence = Qt.binding(() => root.opacity)
                root.markIntroSeen()
            }
        }
    }

    Component {
        id: orientationProbe
        Image {
            objectName: "imageProbe"
            source: root.imageSource
            fillMode: Image.PreserveAspectFit
            sourceSize: root.orientationProbeSize
            asynchronous: true
            cache: false
            onStatusChanged: {
                if (status === Image.Ready) {
                    root.imageTall = implicitHeight > implicitWidth
                    root.orientationKnown = true
                }
            }
        }
    }

    Loader {
        id: imageProbeLoader
        objectName: "imageProbeLoader"
        active: root.wantsImage && !root.orientationKnown && !root.forceDefault
        sourceComponent: orientationProbe
    }

    Component {
        id: wideImage
        AnimatedImage {
            objectName: "customImage"
            anchors.fill: parent
            source: root.imageSource
            sourceSize.width: Math.max(1, Math.ceil(width))
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            playing: root.active && root.imageReady && !root.forceDefault && status === Image.Ready
        }
    }

    Component {
        id: tallImage
        AnimatedImage {
            objectName: "customImage"
            anchors.fill: parent
            source: root.imageSource
            sourceSize.height: Math.max(1, Math.ceil(height))
            fillMode: Image.PreserveAspectFit
            asynchronous: true
            cache: false
            playing: root.active && root.imageReady && !root.forceDefault && status === Image.Ready
        }
    }

    Loader {
        id: customImageLoader
        anchors.fill: parent
        active: root.wantsImage && root.orientationKnown && !root.forceDefault
        visible: root.imageReady && !root.forceDefault
        sourceComponent: root.imageTall ? tallImage : wideImage
    }

    Loader {
        id: videoLoader
        anchors.fill: parent
        active: root.active && root.wantsVideo && !root.forceDefault
        source: active ? Qt.resolvedUrl("ReloadVideo.qml") : ""
        onLoaded: {
            if (status === Loader.Ready && item) {
                item.path = Qt.binding(() => root.resolvedPath)
                item.active = Qt.binding(() => root.active && !root.forceDefault)
            }
        }
    }
}
