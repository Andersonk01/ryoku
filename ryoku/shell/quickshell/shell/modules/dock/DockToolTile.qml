pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import shell.services
import "../../components"

// A dock tool tile (user_edits fork, 2026-10-22): one of the band's own panels
// -- the notes pad, the calculator -- shaped exactly like an app island
// (DockItem): the same frosted pill, the same cursor-tracked magnify and pop-in,
// a Material glyph where the app icon would be. An open tool inverts its pill to
// the bone plate the way an active app does. Left click toggles the tool; the
// band owns which one is open and the surface draws its card. The timer tile
// also wears a ring while one of its clocks runs.
Item {
    id: tile

    required property var band
    required property real alongCenter
    required property string toolId

    readonly property var meta: tile.band.toolMeta(tile.toolId)
    readonly property bool isActive: tile.band.activeTool === tile.toolId
    // The timer engine, for the timer tile only.
    readonly property var eng: tile.toolId === "timer" ? tile.band.timer : null
    readonly property string ringState: tile.eng ? tile.eng.tileState : ""
    readonly property color ringInk: (tile.eng && tile.eng.timerDone) ? Theme.error : Theme.primary
    readonly property bool horizontal: tile.band.horizontal
    readonly property string edge: tile.band.edge

    // outer = the screen-edge side; inner is the desktop-facing one.
    readonly property bool outerTop: tile.horizontal && tile.edge === "top"
    readonly property bool outerBottom: tile.horizontal && tile.edge === "bottom"
    readonly property bool outerLeft: !tile.horizontal && tile.edge === "left"
    readonly property bool outerRight: !tile.horizontal && tile.edge === "right"

    // Continuous magnify, DockItem's formula: distance from the cursor along the
    // band with a gaussian-ish falloff, gated on the magnify key and on hover.
    readonly property real mag: {
        if (!tile.band.magnify || !tile.band.hovered)
            return 1;
        const t = Math.max(0, 1 - Math.abs(tile.alongCenter - tile.band.cursorAlong) / tile.band.reach);
        return 1 + (tile.band.maxScale - 1) * t * t;
    }

    // Static chrome for the sheet forms: tanzaku and seal get a plate like an
    // app's (DockItemChrome); rail and ledger ride the band's shared backdrop and
    // only mark the open tool. Islands draw their pill inside the magnified
    // content below.
    Rectangle {
        id: plate
        visible: tile.band.style === "tanzaku" || tile.band.style === "seal"
        anchors.fill: parent
        anchors.topMargin:    (tile.band.style === "tanzaku" && tile.outerTop) ? -tile.band.edgeReach : 0
        anchors.bottomMargin: (tile.band.style === "tanzaku" && tile.outerBottom) ? -tile.band.edgeReach : 0
        anchors.leftMargin:   (tile.band.style === "tanzaku" && tile.outerLeft) ? -tile.band.edgeReach : 0
        anchors.rightMargin:  (tile.band.style === "tanzaku" && tile.outerRight) ? -tile.band.edgeReach : 0
        readonly property real r: tile.band.style === "seal" ? 0 : tile.band.radius
        color: tile.isActive ? tile.band.bone
            : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, tile.band.frost ? 0.6 : 0.94)
        border.width: 1
        border.color: tile.band.hairline
        topLeftRadius:     (tile.outerBottom || tile.outerRight) ? plate.r : 0
        topRightRadius:    (tile.outerBottom || tile.outerLeft) ? plate.r : 0
        bottomLeftRadius:  (tile.outerTop || tile.outerRight) ? plate.r : 0
        bottomRightRadius: (tile.outerTop || tile.outerLeft) ? plate.r : 0
        Behavior on color { enabled: tile.band.animate; ColorAnimation { duration: Motion.thumbHover } }

        RectangularShadow {
            anchors.fill: parent
            radius: plate.r
            blur: 12
            spread: 0
            offset: tile.horizontal
                ? Qt.vector2d(0, tile.edge === "bottom" ? -2 : 2)
                : Qt.vector2d(tile.edge === "right" ? -2 : 2, 0)
            color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.5)
            visible: tile.band.shadow && !Perf.shadowsDisabled
            z: -1
        }
    }
    // Ledger: the open tool inverts its cell; a leading hairline divides cells.
    Rectangle {
        visible: tile.band.style === "ledger" && tile.isActive
        anchors.fill: parent
        color: tile.band.bone
        Behavior on color { enabled: tile.band.animate; ColorAnimation { duration: Motion.thumbHover } }
    }
    Rectangle {
        visible: tile.band.style === "ledger" && tile.alongCenter > tile.band.baseSize
        color: tile.band.hairline
        width: tile.horizontal ? 1 : tile.band.baseSize
        height: tile.horizontal ? tile.band.baseSize : 1
        x: tile.horizontal ? -tile.band.gap / 2 : 0
        y: tile.horizontal ? 0 : -tile.band.gap / 2
    }
    // Rail: a bone underline on the outer edge marks the open tool, like a
    // running app's.
    Rectangle {
        visible: tile.band.style === "rail" && tile.isActive
        color: tile.band.bone
        width: tile.horizontal ? tile.band.baseSize - 10 : 2
        height: tile.horizontal ? 2 : tile.band.baseSize - 10
        anchors.horizontalCenter: tile.horizontal ? parent.horizontalCenter : undefined
        anchors.verticalCenter: tile.horizontal ? undefined : parent.verticalCenter
        anchors.top: tile.outerTop ? parent.top : undefined
        anchors.bottom: tile.outerBottom ? parent.bottom : undefined
        anchors.left: tile.outerLeft ? parent.left : undefined
        anchors.right: tile.outerRight ? parent.right : undefined
    }

    Item {
        id: content
        anchors.fill: parent

        // Pop-in from the dock's edge, as an app island does.
        property bool shown: false
        Component.onCompleted: content.shown = true
        opacity: content.shown ? 1 : 0
        Behavior on opacity {
            enabled: tile.band.animate
            NumberAnimation { duration: Motion.rowFade; easing.type: Motion.rowRevealCurve }
        }
        scale: content.shown ? 1 : 0.3
        transformOrigin: tile.horizontal
            ? (tile.edge === "bottom" ? Item.Bottom : Item.Top)
            : (tile.edge === "right" ? Item.Right : Item.Left)
        Behavior on scale { enabled: tile.band.animate; NumberAnimation { duration: Motion.standard; easing.type: Easing.OutBack } }

        // Magnify anchored on the dock's outer edge, so the tile grows into the
        // headroom and never off the screen.
        transform: Scale {
            origin.x: tile.horizontal ? content.width / 2 : (tile.edge === "right" ? content.width : 0)
            origin.y: tile.horizontal ? (tile.edge === "bottom" ? content.height : 0) : content.height / 2
            xScale: tile.mag
            yScale: tile.mag
            Behavior on xScale { enabled: tile.band.magnify && tile.band.animate; NumberAnimation { duration: Motion.hover; easing.type: Motion.easeStandard } }
            Behavior on yScale { enabled: tile.band.magnify && tile.band.animate; NumberAnimation { duration: Motion.hover; easing.type: Motion.easeStandard } }
        }

        Rectangle {
            id: pill
            visible: tile.band.style === "islands"
            anchors.fill: parent
            radius: tile.band.radius
            readonly property real frostA: tile.band.frost ? 0.6 : 0.94
            color: tile.isActive
                ? Qt.rgba(Theme.inverseSurface.r, Theme.inverseSurface.g, Theme.inverseSurface.b, pill.frostA)
                : Qt.rgba(Theme.surfaceContainer.r, Theme.surfaceContainer.g, Theme.surfaceContainer.b, pill.frostA)
            border.width: 1
            border.color: Qt.rgba(Theme.onSurface.r, Theme.onSurface.g, Theme.onSurface.b, 0.12)
            Behavior on color { enabled: tile.band.animate; ColorAnimation { duration: Motion.thumbHover } }

            RectangularShadow {
                anchors.fill: parent
                radius: parent.radius
                blur: 12
                spread: 0
                offset: tile.horizontal
                    ? Qt.vector2d(0, tile.edge === "bottom" ? -2 : 2)
                    : Qt.vector2d(tile.edge === "right" ? -2 : 2, 0)
                color: Qt.rgba(Theme.shadow.r, Theme.shadow.g, Theme.shadow.b, 0.5)
                visible: tile.band.shadow && !Perf.shadowsDisabled
                z: -1
            }
        }

        MaterialIcon {
            anchors.centerIn: parent
            width: 26
            height: 26
            font.pixelSize: 24
            text: tile.meta.icon
            fill: tile.isActive ? 1 : 0
            // Every form but rail inverts the open tool's plate, so its glyph
            // takes the bone ink; rail marks it with the underline instead. A
            // running clock tints the timer glyph with its ring.
            color: (tile.isActive && tile.band.style !== "rail") ? Theme.inverseOnSurface
                : (tile.ringState !== "" ? tile.ringInk : Theme.onSurface)
            Behavior on color { enabled: tile.band.animate; ColorAnimation { duration: Motion.thumbHover } }
        }

        // The timer's ring: the remaining share of a countdown or pomodoro, a
        // spinning arc for the stopwatch, and a pulsing full ring once a
        // countdown has rung and not yet been seen.
        Shape {
            id: ring
            visible: tile.ringState !== ""
            anchors.centerIn: parent
            width: tile.band.baseSize - 4
            height: width
            preferredRendererType: Shape.CurveRenderer
            readonly property real r: ring.width / 2 - 1.5
            readonly property color ink: (tile.isActive && tile.band.style !== "rail") ? Theme.inverseOnSurface : tile.ringInk
            property real spin: 0
            NumberAnimation on spin {
                running: tile.ringState === "stopwatch" && tile.band.animate
                from: 0
                to: 360
                duration: 1500
                loops: Animation.Infinite
            }
            SequentialAnimation on opacity {
                running: tile.eng !== null && tile.eng.timerDone && tile.band.animate
                loops: Animation.Infinite
                NumberAnimation { to: 0.25; duration: 450 }
                NumberAnimation { to: 1; duration: 450 }
                onRunningChanged: if (!running) ring.opacity = 1
            }
            ShapePath {
                strokeColor: Qt.rgba(ring.ink.r, ring.ink.g, ring.ink.b, 0.22)
                strokeWidth: 2
                fillColor: "transparent"
                PathAngleArc {
                    centerX: ring.width / 2
                    centerY: ring.height / 2
                    radiusX: ring.r
                    radiusY: ring.r
                    startAngle: -90
                    sweepAngle: 360
                }
            }
            ShapePath {
                strokeColor: ring.ink
                strokeWidth: 2
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                PathAngleArc {
                    centerX: ring.width / 2
                    centerY: ring.height / 2
                    radiusX: ring.r
                    radiusY: ring.r
                    startAngle: tile.ringState === "stopwatch" ? ring.spin - 90 : -90
                    sweepAngle: tile.ringState === "stopwatch" ? 100 : 360 * (tile.eng ? tile.eng.tileProgress : 0)
                }
            }
        }
    }

    HoverHandler {
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onSingleTapped: tile.band.toggleTool(tile.toolId)
    }
}
