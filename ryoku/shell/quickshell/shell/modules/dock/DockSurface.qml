pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Ryoku.Ui.Singletons
import shell.services
import stage
import shell.modules.stage.frame
import "../../components"

// user_edits fork (2026-10-22, ported to 1.0.7 on 2026-11-03): the band's tool
// tiles (DockBand.tools) open a DockToolCard drawn INSIDE this surface, beside
// the band on its inner side. While a tool is open the surface grows by the
// card's depth, takes keyboard focus on demand (typing in the notes, digits in
// the calculator), stays revealed, and a compositor focus grab closes the card
// on an outside click.
//
// The Ryoku dock: a first-class shell surface (namespace ryoku-dock), one per
// monitor and style-agnostic -- it no longer belongs to any bar. A frosted
// island row (DockBand) on the screen edge OPPOSITE the bar, revealed by a peek
// strip when autohide is on.
//
// Reveal is the point of this surface. The band shows when the dock is not
// autohiding, or the pointer is on it, or its workspace is empty, or nothing is
// focused, or a pin is being dragged -- and is forced away under a fullscreen
// window unless the pointer is in the peek strip. Hiding slides the band out by
// its own depth, leaving a 3 px peek inside the input mask; the empty margins
// stay click-through because the mask is only the band rect unioned with that
// strip.
//
// While the Stage Editor frames this monitor the dock is part of the desktop
// preview, so it holds revealed and rises above the lifted desktop.
PanelWindow {
    id: dock

    // ── edge: explicit, or auto (opposite the bar) ───────────────────────────
    readonly property string edge: Dock.resolvedEdge()
    readonly property bool horizontal: dock.edge === "top" || dock.edge === "bottom"

    // ── sizing ────────────────────────────────────────────────────────────────
    readonly property bool autohide: Dock.cfg("autohide", false)
    readonly property real configuredEdgeGap: Math.max(-24, Math.min(64, Number(Dock.cfg("edgeGap", 0))))
    readonly property real edgeGap: Math.max(0, 8 + dock.configuredEdgeGap)
    readonly property real peek: 3
    readonly property real depth: band.baseSize
    // Inner clearance for a magnified icon to rise into, plus room for the hover
    // name label above it; both grow into the desktop, never off the screen edge.
    // Zero when neither is on, so a plain dock reserves nothing extra.
    // Fork (2026-10-26): a vertical band's label sits BESIDE the island, so it
    // needs its full width (band.labelMaxW + its gap), not the 30px that fits a
    // label above a horizontal band; with 30 a long name was cut by the layer's
    // edge. The extra strip is transparent and outside the input mask.
    readonly property real headroom: ((Dock.cfg("magnify", true) && !Perf.reduceMotion) ? 22 : 0)
        + (Dock.cfg("labels", true) ? (dock.horizontal ? 30 : band.labelMaxW + 8) : 0)

    // ── tool card (fork) ─────────────────────────────────────────────────────
    // Extra depth the surface grows by while a tool is open: the card across
    // the band plus the gap between them. Zero when closed, so a plain dock is
    // the shipped geometry exactly.
    readonly property real cardGap: 10
    readonly property real cardMargin: 8
    readonly property real toolExtra: band.toolOpen
        ? (dock.horizontal ? toolCard.height : toolCard.width) + dock.cardGap
        : 0

    // The dock band's along-edge size and centre in screen coordinates (0 size
    // while the dock is off), so a neighbour -- the record island -- can park flush
    // beside the band instead of drifting into a corner. Uses the band's resting
    // geometry, independent of reveal, so an autohiding dock still defines a stable
    // lane. The band is centred on the edge, so the centre is the surface midpoint.
    readonly property real bandSize: dock.visible ? (dock.horizontal ? band.implicitWidth : band.implicitHeight) : 0
    readonly property real bandCenter: dock.horizontal ? (dock.width / 2) : (dock.height / 2)

    // Set by the host: the Stage Editor is framing this monitor.
    property bool stageEditing: false

    color: "transparent"
    visible: Dock.cfg("enabled", false)
    // `screen` is PanelWindow's own property, set per monitor from shell.qml.
    WlrLayershell.namespace: "ryoku-dock"
    WlrLayershell.layer: dock.stageEditing ? WlrLayer.Overlay : (dock.autohide ? WlrLayer.Top : WlrLayer.Bottom)
    // Keyboard only while a tool card is open, and only on demand (a click in
    // the card), so the dock never takes the keyboard from a window by itself.
    WlrLayershell.keyboardFocus: band.toolOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Normal
    // A pinned (non-autohide) dock reserves its depth; an autohiding one floats
    // over the desktop and reserves nothing.
    exclusiveZone: (!dock.autohide && dock.visible) ? Math.max(0, dock.depth + dock.edgeGap) : 0

    anchors {
        left: dock.horizontal || dock.edge === "left"
        right: dock.horizontal || dock.edge === "right"
        top: !dock.horizontal || dock.edge === "top"
        bottom: !dock.horizontal || dock.edge === "bottom"
    }
    implicitHeight: dock.horizontal ? frameLayer.extent : 0
    implicitWidth: dock.horizontal ? 0 : frameLayer.extent

    // ── reveal state machine ──────────────────────────────────────────────────
    readonly property bool monFullscreen: Wm.outputHasFullscreen(dock.screen ? dock.screen.name : "")
    readonly property bool pointerInside: band.hovered || peekHover.hovered
    readonly property string screenName: dock.screen ? dock.screen.name : ""
    readonly property bool workspaceEmpty: {
        if (!Dock.cfg("revealOnEmpty", true)) return false;
        const active = (Wm.workspaces ?? []).find(ws => ws.active && ws.output === dock.screenName);
        return active !== undefined && !(Wm.windows ?? []).some(w => w.workspace === active.id);
    }
    readonly property bool menuHere: Dock.menuOpen && Dock.menuScreen === dock.screenName
    readonly property bool wantReveal: {
        // The editor is showing this dock's settings page: it holds open.
        if (dock.stageEditing)
            return true;
        // Suppress only auto-hide docks; stale fullscreen state would hide pinned docks.
        if (dock.autohide && dock.monFullscreen)
            return dock.pointerInside;
        return !dock.autohide
            || dock.pointerInside
            || dock.workspaceEmpty
            || !Dock.anyFocused
            || band.dragging
            || dock.menuHere
            || band.toolOpen;
    }
    // Fork (2026-10-26): the dock lingers after it stops being wanted (the
    // pointer left): hideDelay of grace, then the islands spring out in reverse
    // order (DockBand.leave) and the band only slides away once most of them
    // are gone (DockBand.departed). Wanted again at any point, it stays and the
    // islands spring back from wherever they were. Over a fullscreen window
    // there is no grace.
    readonly property int hideDelay: 500
    property bool lingering: false
    readonly property bool revealed: dock.wantReveal || dock.lingering
    onWantRevealChanged: {
        if (dock.wantReveal) {
            hideGrace.stop();
            dock.lingering = false;
        } else if (dock.autohide && dock.monFullscreen) {
            dock.lingering = false;
            band.leave();
        } else {
            dock.lingering = true;
            hideGrace.restart();
        }
    }
    Timer {
        id: hideGrace
        interval: dock.hideDelay
        onTriggered: band.leave()
    }
    Connections {
        target: band
        function onDeparted() {
            if (!dock.wantReveal)
                dock.lingering = false;
        }
    }

    // Keep the reported edit edge at its resting depth; reveal and hover
    // animation must not move edit guides under the pointer.
    readonly property real insetDepth: dock.depth + dock.edgeGap
    function publishInset() {
        GlobalStates.setDockInset(dock.screenName,
            dock.stageEditing && dock.visible ? dock.edge : "", dock.insetDepth);
    }
    onStageEditingChanged: dock.publishInset()
    onVisibleChanged: dock.publishInset()
    onEdgeChanged: dock.publishInset()
    onInsetDepthChanged: dock.publishInset()
    Component.onCompleted: dock.publishInset()
    Component.onDestruction: GlobalStates.setDockInset(dock.screenName, "", 0)

    // Perp offset (the axis pointing away from the screen edge) of the band's
    // resting outer corner, and the direction it slides to hide. The far edges
    // (bottom, right) keep headroom before the band; the near edges (top, left)
    // keep the gap.
    readonly property real slideDist: dock.depth + dock.edgeGap - dock.peek
    readonly property real perpRest: (dock.edge === "bottom" || dock.edge === "right") ? dock.headroom : dock.edgeGap
    readonly property int perpSign: (dock.edge === "bottom" || dock.edge === "right") ? 1 : -1
    readonly property real perpPos: dock.perpRest + (dock.revealed ? 0 : dock.perpSign * dock.slideDist)
    // Draw the dock with the desktop when Stage shrinks this output.

    StageFramedLayer {
        id: frameLayer
        screenName: dock.screenName
        edge: dock.edge
        restThickness: dock.depth + dock.edgeGap + dock.headroom + dock.toolExtra
        screenWidth: dock.screen?.width ?? 1920
        screenHeight: dock.screen?.height ?? 1080
        originX: dock.anchors.left ? 0 : screenWidth - dock.width
        originY: dock.anchors.top ? 0 : screenHeight - dock.height

        // The band rides in a host that absorbs the card's extra depth on the far
        // edges (right, bottom) WITHOUT animation, so the band holds its place on
        // screen when the surface grows; the band's own reveal slide stays animated.
        Item {
            id: bandHost
            x: (!dock.horizontal && dock.edge === "right") ? dock.toolExtra : 0
            y: (dock.horizontal && dock.edge === "bottom") ? dock.toolExtra : 0
            width: band.width
            height: band.height

            DockBand {
                id: band
                edge: dock.edge
                screenName: dock.screenName
                reservedDepth: dock.depth + dock.edgeGap
                // drive the islands' spring in and out (fork)
                shown: dock.revealed && dock.visible
                wanted: dock.wantReveal && dock.visible

                // Centre along the band's own axis; slide along the perpendicular one.
                x: dock.horizontal ? Math.round((frameLayer.rest.width - band.implicitWidth) / 2) : dock.perpPos
                y: dock.horizontal ? dock.perpPos : Math.round((frameLayer.rest.height - band.implicitHeight) / 2)
                Behavior on x { enabled: !Perf.reduceMotion; NumberAnimation { duration: Motion.menuSlide; easing.type: Motion.menuSlideCurve } }
                Behavior on y { enabled: !Perf.reduceMotion; NumberAnimation { duration: Motion.menuSlide; easing.type: Motion.menuSlideCurve } }
            }
        }

        // The tool card (fork): off the band's inner side, centred on the open
        // tool's tile along the band and kept inside the surface by cardMargin.
        DockToolCard {
            id: toolCard
            band: band
            visible: band.toolOpen
            readonly property real bx: bandHost.x + band.x
            readonly property real by: bandHost.y + band.y
            x: dock.horizontal
                ? Math.max(dock.cardMargin, Math.min(frameLayer.rest.width - width - dock.cardMargin, toolCard.bx + band.activeToolCenter - width / 2))
                : (dock.edge === "right" ? toolCard.bx - dock.cardGap - width : toolCard.bx + band.width + dock.cardGap)
            y: dock.horizontal
                ? (dock.edge === "bottom" ? toolCard.by - dock.cardGap - height : toolCard.by + band.height + dock.cardGap)
                : Math.max(dock.cardMargin, Math.min(frameLayer.rest.height - height - dock.cardMargin, toolCard.by + band.activeToolCenter - height / 2))
        }

        // The peek strip: a thin always-masked band at the very screen edge, so a
        // hidden dock can still be revealed by pointer proximity. It tracks the band
        // along the axis but stays pinned to the edge across it.
        Item {
            id: peekStrip
            x: dock.horizontal ? bandHost.x + band.x : (dock.edge === "left" ? 0 : parent.width - dock.edgeGap)
            y: dock.horizontal ? (dock.edge === "top" ? 0 : parent.height - dock.edgeGap) : bandHost.y + band.y
            width: dock.horizontal ? band.width : dock.edgeGap
            height: dock.horizontal ? dock.edgeGap : band.height
            HoverHandler { id: peekHover }
        }
    }

    // An outside click closes the card (Hyprland's focus-grab protocol; without
    // it the card still closes on Escape, its own close mark, or the tile).
    FocusGrab {
        active: band.toolOpen && dock.visible
        windows: [dock]
        onCleared: band.closeTool()
    }

    // `qs ipc call dock-<monitor> tool <id>|new|close` opens a tool from a
    // keybind or a script, so the card is reachable without the pointer; `new`
    // opens the notes tool straight on a fresh note. `timer toggle|reset|lap|
    // skip|timer|stopwatch|pomodoro` drives the clocks without opening anything.
    // `tools notes,calc,timer` sets which tiles show (persisted in shell.json
    // as dock.tools); `tools default` restores them all; `tools ""` just lists.
    IpcHandler {
        target: "dock-" + dock.screenName
        // `peek music|<app-class>|off` opens the now-playing card or an app's
        // window-preview strip as if its island were hovered, so their look can
        // be checked without the pointer (e.g. `peek music`, `peek kitty`).
        function peek(what: string): void {
            MusicPreview.hovered = false;
            DockPreview.hoveredClass = "";
            if (what === "off")
                return;
            const g = band.mapToGlobal(band.baseSize / 2, band.height / 2);
            if (what === "music") {
                MusicPreview.gx = g.x;
                MusicPreview.gy = g.y;
                MusicPreview.edge = band.edge;
                MusicPreview.margin = band.reservedDepth + 14;
                MusicPreview.hovered = true;
            } else {
                DockPreview.gx = g.x;
                DockPreview.gy = g.y;
                DockPreview.edge = band.edge;
                DockPreview.margin = band.reservedDepth + 14;
                DockPreview.hoveredClass = what;
            }
        }
        function tool(name: string): void {
            if (name === "close")
                band.closeTool();
            else if (name === "new")
                band.newNote();
            else if (band.tools.indexOf(name) >= 0)
                band.toggleTool(name);
        }
        function timer(action: string): void {
            const e = band.timer;
            if (action === "toggle")
                e.toggle();
            else if (action === "reset")
                e.reset();
            else if (action === "lap")
                e.swLap();
            else if (action === "skip")
                e.pomSkip();
            else
                e.setMode(action);
        }
        function tools(list: string): string {
            if (list === "default")
                Dock.setCfg("tools", null);
            else if (list !== "")
                Dock.setCfg("tools", list.split(",").map(s => s.trim()).filter(s => s !== ""));
            return band.tools.join(",");
        }
    }

    readonly property rect bandInputRect: frameLayer.maskRect(bandHost.x + band.x, bandHost.y + band.y, band.width, band.height)
    // The open tool card takes input too (fork); zero-sized when closed.
    readonly property rect toolInputRect: frameLayer.maskRect(toolCard.x, toolCard.y,
        band.toolOpen ? toolCard.width : 0, band.toolOpen ? toolCard.height : 0)
    readonly property rect peekInputRect: frameLayer.maskRect(peekStrip.x, peekStrip.y,
        peekStrip.width, peekStrip.height)
    // Input mask = band rect ∪ peek strip, so the empty margins and the magnify
    // headroom stay click-through.
    mask: Region {
        Region {
            x: Math.round(dock.bandInputRect.x)
            y: Math.round(dock.bandInputRect.y)
            width: Math.round(dock.bandInputRect.width)
            height: Math.round(dock.bandInputRect.height)
        }
        Region {
            x: Math.round(dock.toolInputRect.x)
            y: Math.round(dock.toolInputRect.y)
            width: Math.round(dock.toolInputRect.width)
            height: Math.round(dock.toolInputRect.height)
        }
        Region {
            x: Math.round(dock.peekInputRect.x)
            y: Math.round(dock.peekInputRect.y)
            width: Math.round(dock.peekInputRect.width)
            height: Math.round(dock.peekInputRect.height)
        }
    }
}
