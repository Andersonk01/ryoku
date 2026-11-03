pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import shell.services
import Ryoku.Ui.Singletons
import "../../components"

// The dock's tool card (user_edits fork, 2026-10-22): one frosted sheet the
// surface places beside the band, hosting whichever tool tile is open -- notes,
// calculator, timer, flashcards, translate or cheat sheet. A tool stays loaded
// once first opened (the calculator keeps its tape, the notes their place) and
// only the open one shows. Escape closes the card when the keyboard is here; the surface closes
// it on an outside click; the header's close mark and the tile itself always do.
FocusScope {
    id: card

    required property var band
    readonly property string tool: card.band.activeTool
    readonly property var meta: card.band.toolMeta(card.tool)
    readonly property real pad: 12

    implicitWidth: 304
    implicitHeight: header.height + card.pad + bodyHost.implicitHeight + card.pad
    width: implicitWidth
    height: implicitHeight

    // The open tool's Loader; kept across a close so the sheet holds its height
    // while it fades out.
    property var activeLoader: null
    onToolChanged: card.arm()
    Component.onCompleted: card.arm()
    function loaderFor(id) {
        for (let i = 0; i < loaders.count; ++i) {
            const l = loaders.itemAt(i);
            if (l && l.toolId === id)
                return l;
        }
        return null;
    }
    function arm() {
        const l = card.loaderFor(card.tool);
        if (!l)
            return;
        l.wanted = true;
        card.activeLoader = l;
        Qt.callLater(card.focusTool);
    }
    function focusTool() {
        const l = card.activeLoader;
        if (l && l.item)
            l.item.forceActiveFocus();
    }
    function componentFor(id) {
        switch (id) {
        case "notes": return notesC;
        case "calc": return calcC;
        case "timer": return timerC;
        case "cards": return cardsC;
        case "translate": return translateC;
        case "cheat": return cheatC;
        }
        return null;
    }

    Keys.onEscapePressed: (event) => {
        card.band.closeTool();
        event.accepted = true;
    }

    // Enter: fade and a short slide in from the band's side.
    opacity: card.band.toolOpen ? 1 : 0
    Behavior on opacity { enabled: card.band.animate; NumberAnimation { duration: Motion.rowFade; easing.type: Motion.rowRevealCurve } }
    transform: Translate {
        readonly property real d: card.band.toolOpen ? 0 : 10
        x: card.band.horizontal ? 0 : (card.band.edge === "right" ? d : -d)
        y: card.band.horizontal ? (card.band.edge === "bottom" ? d : -d) : 0
        Behavior on x { enabled: card.band.animate; NumberAnimation { duration: Motion.menuSlide; easing.type: Motion.menuSlideCurve } }
        Behavior on y { enabled: card.band.animate; NumberAnimation { duration: Motion.menuSlide; easing.type: Motion.menuSlideCurve } }
    }

    Rectangle {
        id: plateRect
        anchors.fill: parent
        radius: card.band.radius + 6
        // Denser than the islands' frost: the sheet carries text. The
        // hypr/user.lua blur rule for the ryoku-dock layer frosts what shows
        // through; without it the body is still dark enough to read over a
        // bright window.
        color: Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, card.band.frost ? 0.8 : 0.97)
        border.width: 1
        border.color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.14)

        RectangularShadow {
            anchors.fill: parent
            radius: plateRect.radius
            blur: 18
            spread: 0
            offset: Qt.vector2d(0, 4)
            color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.45)
            visible: card.band.shadow && !Perf.shadowsDisabled
            z: -1
        }

        // A light sheen falling from the top, as the sidebar's glass has.
        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(0, plateRect.radius - 1)
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.05) }
                GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0) }
            }
        }
    }

    // Stray presses on the sheet stop here, never reaching the band behind it.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: (mouse) => { mouse.accepted = true; }
    }

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: card.pad
        anchors.rightMargin: card.pad
        height: 44

        MaterialIcon {
            id: headIcon
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            font.pixelSize: 20
            text: card.meta.icon
            fill: 1
            color: Theme.onSurface
        }
        Text {
            anchors.left: headIcon.right
            anchors.leftMargin: 8
            anchors.right: closeBtn.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: card.meta.label
            color: Theme.onSurface
            font.family: Theme.fontPrimary
            font.pixelSize: 13
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        Item {
            id: closeBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 26
            height: 26
            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: closeHover.hovered
                    ? Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10)
                    : "transparent"
            }
            MaterialIcon {
                anchors.centerIn: parent
                width: 18
                height: 18
                font.pixelSize: 16
                text: "close"
                color: Theme.onSurface
            }
            HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onSingleTapped: card.band.closeTool() }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.right: parent.right
            height: 1
            color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.10)
        }
    }

    Item {
        id: bodyHost
        anchors.top: header.bottom
        anchors.topMargin: card.pad
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: card.pad
        anchors.rightMargin: card.pad
        implicitHeight: (card.activeLoader && card.activeLoader.item) ? card.activeLoader.item.implicitHeight : 0
        height: implicitHeight

        // One Loader per tile, in the band's order; a tool loads on its first
        // open and stays loaded.
        Repeater {
            id: loaders
            model: card.band.tools
            delegate: Loader {
                id: slot
                required property string modelData
                readonly property string toolId: slot.modelData
                property bool wanted: false
                active: slot.wanted
                visible: card.tool === slot.toolId
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                sourceComponent: card.componentFor(slot.toolId)
            }
        }
    }

    Component {
        id: notesC
        ToolNotes {
            band: card.band
            shown: card.tool === "notes" && card.band.toolOpen
        }
    }
    Component {
        id: calcC
        ToolCalculator {
            band: card.band
            shown: card.tool === "calc" && card.band.toolOpen
        }
    }
    Component {
        id: timerC
        ToolTimer {
            band: card.band
            shown: card.tool === "timer" && card.band.toolOpen
        }
    }
    Component {
        id: cardsC
        ToolCards {
            band: card.band
            shown: card.tool === "cards" && card.band.toolOpen
        }
    }
    Component {
        id: translateC
        ToolTranslate {
            band: card.band
            shown: card.tool === "translate" && card.band.toolOpen
        }
    }
    Component {
        id: cheatC
        ToolCheat {
            band: card.band
            shown: card.tool === "cheat" && card.band.toolOpen
        }
    }
}
