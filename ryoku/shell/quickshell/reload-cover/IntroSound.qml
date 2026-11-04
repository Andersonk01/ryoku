pragma ComponentBehavior: Bound

import QtQuick
import QtMultimedia
import Quickshell

// The login intro's sound set: sounds/*.wav, synthesized by
// sounds/make-sounds.py. HackerIntro calls these from its timeline; this item
// only owns the players and their levels. It is loaded on demand, so a muted
// intro never pulls QtMultimedia in.
Item {
    id: snd

    property real volume: 0.7       // master, 0..1
    property real presence: 1       // the cover's fade; the beds follow it
    property bool typing: true
    property bool decode: true
    property bool granted: true
    property bool glitch: true
    property bool ambience: true
    property bool boot: true
    // a test harness can pin an output (RYOKU_INTRO_AUDIO_DEVICE: part of a
    // sink's id); otherwise the default sink, followed live
    property var device: null
    readonly property string deviceHint: Quickshell.env("RYOKU_INTRO_AUDIO_DEVICE") || ""

    MediaDevices { id: devices }
    readonly property var hinted: {
        if (snd.deviceHint === "") return null;
        var outs = devices.audioOutputs;
        for (var i = 0; i < outs.length; i++)
            if (String(outs[i].id).indexOf(snd.deviceHint) >= 0) return outs[i];
        return null;
    }
    readonly property var output: snd.device || snd.hinted || devices.defaultAudioOutput

    function lv(g) { return Math.max(0, Math.min(1, g * snd.volume)); }
    function url(name) { return Qt.resolvedUrl("sounds/" + name + ".wav"); }

    // A player asked to start before its file has decoded plays the moment it
    // is ready, unless that is too late to still match the picture.
    function fire(fx) {
        if (!fx) return;
        if (fx.status === SoundEffect.Ready) {
            fx.play();
        } else {
            fx.queuedAt = Date.now();
        }
    }
    component Fx: SoundEffect {
        property real queuedAt: 0
        onStatusChanged: {
            if (status === SoundEffect.Ready && queuedAt > 0) {
                if (Date.now() - queuedAt < 250) play();
                queuedAt = 0;
            }
        }
    }

    // ── one-shots ────────────────────────────────────────────────────────
    property list<QtObject> keyFx: [
        Fx { source: snd.url("key1"); volume: snd.lv(0.50); audioDevice: snd.output },
        Fx { source: snd.url("key2"); volume: snd.lv(0.50); audioDevice: snd.output },
        Fx { source: snd.url("key3"); volume: snd.lv(0.46); audioDevice: snd.output },
        Fx { source: snd.url("key4"); volume: snd.lv(0.50); audioDevice: snd.output }
    ]
    Fx { id: spaceFx; source: snd.url("space"); volume: snd.lv(0.46); audioDevice: snd.output }
    property list<QtObject> tickFx: [
        Fx { source: snd.url("tick1"); volume: snd.lv(0.24); audioDevice: snd.output },
        Fx { source: snd.url("tick2"); volume: snd.lv(0.24); audioDevice: snd.output },
        Fx { source: snd.url("tick3"); volume: snd.lv(0.26); audioDevice: snd.output },
        Fx { source: snd.url("tick4"); volume: snd.lv(0.24); audioDevice: snd.output },
        Fx { source: snd.url("tick5"); volume: snd.lv(0.22); audioDevice: snd.output }
    ]
    Fx { id: grantedFx; source: snd.url("granted"); volume: snd.lv(0.55); audioDevice: snd.output }
    Fx { id: glitchFx; source: snd.url("glitch"); volume: snd.lv(0.30); audioDevice: snd.output }
    Fx { id: bootFx; source: snd.url("boot"); volume: snd.lv(0.62); audioDevice: snd.output }
    Fx { id: blipFx; source: snd.url("blip"); volume: snd.lv(0.18); audioDevice: snd.output }
    Fx { id: readyFx; source: snd.url("ready"); volume: snd.lv(0.26); audioDevice: snd.output }

    // ── beds: loops that fade in and out ─────────────────────────────────
    property real dataLevel: 0
    property real humLevel: 0
    Fx {
        id: dataFx
        source: snd.url("data")
        loops: SoundEffect.Infinite
        volume: snd.lv(0.15) * snd.dataLevel * snd.presence
        audioDevice: snd.output
    }
    Fx {
        id: humFx
        source: snd.url("hum")
        loops: SoundEffect.Infinite
        volume: snd.lv(0.14) * snd.humLevel * snd.presence
        audioDevice: snd.output
    }
    NumberAnimation { id: dataIn; target: snd; property: "dataLevel"; to: 1; duration: 120 }
    SequentialAnimation {
        id: dataOut
        NumberAnimation { target: snd; property: "dataLevel"; to: 0; duration: 140 }
        ScriptAction { script: dataFx.stop() }
    }
    NumberAnimation { id: humIn; target: snd; property: "humLevel"; to: 1; duration: 700; easing.type: Easing.OutCubic }
    SequentialAnimation {
        id: humOut
        NumberAnimation { target: snd; property: "humLevel"; to: 0; duration: 1100; easing.type: Easing.InOutQuad }
        ScriptAction { script: humFx.stop() }
    }

    // ── what the timeline calls ──────────────────────────────────────────
    property int lastKey: -1
    function key(ch) {
        if (!snd.typing) return;
        if (ch === " ") {
            snd.fire(spaceFx);
            return;
        }
        var i = Math.floor(Math.random() * 3);
        if (i >= snd.lastKey) i += 1;   // never the same switch twice running
        snd.lastKey = i;
        snd.fire(snd.keyFx[i]);
    }
    function tick(i) {
        if (snd.decode) snd.fire(snd.tickFx[((i % 5) + 5) % 5]);
    }
    function dataStart() {
        if (!snd.decode) return;
        dataOut.stop();
        snd.fire(dataFx);
        dataIn.restart();
    }
    function dataStop() {
        dataIn.stop();
        if (dataFx.playing || snd.dataLevel > 0) dataOut.restart();
    }
    function accessGranted() { if (snd.granted) snd.fire(grantedFx); }
    function glitchHit() { if (snd.glitch) snd.fire(glitchFx); }
    function bootHit() { if (snd.boot) snd.fire(bootFx); }
    function logLine() { if (snd.boot) snd.fire(blipFx); }
    function readyHit() { if (snd.boot) snd.fire(readyFx); }
    function humStart() {
        if (!snd.ambience) return;
        humOut.stop();
        snd.fire(humFx);
        humIn.restart();
    }
    function humStop() {
        humIn.stop();
        if (humFx.playing || snd.humLevel > 0) humOut.restart();
    }
    function stopAll() {
        dataIn.stop(); dataOut.stop(); humIn.stop(); humOut.stop();
        snd.dataLevel = 0;
        snd.humLevel = 0;
        var all = [spaceFx, grantedFx, glitchFx, bootFx, blipFx, readyFx, dataFx, humFx];
        for (var i = 0; i < snd.keyFx.length; i++) all.push(snd.keyFx[i]);
        for (var j = 0; j < snd.tickFx.length; j++) all.push(snd.tickFx[j]);
        for (var k = 0; k < all.length; k++) {
            all[k].queuedAt = 0;
            all[k].stop();
        }
    }
    onAmbienceChanged: if (!ambience) humStop()
    onDecodeChanged: if (!decode) dataStop()
}
