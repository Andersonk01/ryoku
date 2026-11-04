#!/usr/bin/env python3
"""Synthesize the login intro's sound set from scratch (no samples, so no
licences to track). Every file is 48 kHz, 16-bit mono PCM, which is what
QtMultimedia's SoundEffect plays with the lowest latency.

    python3 make-sounds.py [outdir]      # defaults to this file's directory

The output is deterministic (fixed seed), so a rerun reproduces the set.
"""
import math
import os
import sys
import wave

import numpy as np

SR = 48000
rng = np.random.default_rng(0xA11CE)


def n_of(dur):
    return int(round(dur * SR))


def t_axis(n):
    return np.arange(n) / SR


def decay(n, tau, at=0.0):
    t = t_axis(n) - at
    e = np.exp(-np.maximum(t, 0.0) / tau)
    e[t < 0] = 0.0
    return e


def ramp_in(x, ms=0.4):
    k = max(1, n_of(ms / 1000))
    x[:k] *= np.linspace(0, 1, k)
    return x


def ramp_out(x, ms=2.0):
    k = max(1, n_of(ms / 1000))
    x[-k:] *= np.linspace(1, 0, k)
    return x


def biquad(x, kind, f0, q=0.707):
    """RBJ cookbook biquad, causal, so transients keep a clean attack."""
    w0 = 2 * math.pi * f0 / SR
    c, s = math.cos(w0), math.sin(w0)
    a = s / (2 * q)
    if kind == "lp":
        b0, b1, b2 = (1 - c) / 2, 1 - c, (1 - c) / 2
    elif kind == "hp":
        b0, b1, b2 = (1 + c) / 2, -(1 + c), (1 + c) / 2
    else:  # band-pass, 0 dB peak
        b0, b1, b2 = a, 0.0, -a
    a0, a1, a2 = 1 + a, -2 * c, 1 - a
    b0, b1, b2, a1, a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
    out = np.empty(len(x))
    x1 = x2 = y1 = y2 = 0.0
    for i, xi in enumerate(x.tolist()):
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        out[i] = yi
    return out


def sweep_lp(x, f_of_t):
    """One-pole low-pass whose cutoff follows f_of_t (Hz per sample)."""
    out = np.empty(len(x))
    y = 0.0
    k = 1 - np.exp(-2 * np.pi * np.asarray(f_of_t) / SR)
    for i, (xi, ki) in enumerate(zip(x.tolist(), k.tolist())):
        y += ki * (xi - y)
        out[i] = y
    return out


def osc(freq, n, shape="sine", phase0=0.0):
    f = np.broadcast_to(np.asarray(freq, dtype=float), (n,))
    ph = phase0 + 2 * np.pi * np.cumsum(f) / SR
    if shape == "sine":
        return np.sin(ph)
    if shape == "square":
        return np.sign(np.sin(ph))
    if shape == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    raise ValueError(shape)


def place(dst, src, at):
    i = n_of(at)
    j = min(len(dst), i + len(src))
    if j > i:
        dst[i:j] += src[: j - i]


def crush(x, bits):
    q = 2 ** (bits - 1)
    return np.round(x * q) / q


def hold(x, factor):
    """Sample-rate reduction: repeat every factor-th sample."""
    idx = (np.arange(len(x)) // factor) * factor
    return x[idx]


def norm(x, peak=0.89):
    m = np.max(np.abs(x))
    return x if m == 0 else x * (peak / m)


def write(outdir, name, x):
    x = np.clip(x, -1, 1)
    pcm = (x * 32767).astype("<i2").tobytes()
    with wave.open(os.path.join(outdir, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm)


# ── keys: a mechanical switch, press click + body + thock + bottom-out ──────
def key(click_f, body_f, thock_f, bottom_at, dur=0.085):
    n = n_of(dur)
    t = t_axis(n)
    click = biquad(rng.standard_normal(n), "bp", click_f, 1.3) * decay(n, 0.0011)
    body = biquad(rng.standard_normal(n), "bp", body_f, 0.9) * decay(n, 0.0050)
    glide = thock_f * (1 + 0.55 * np.exp(-t / 0.004))
    thock = osc(glide, n) * decay(n, 0.0095)
    bottom = biquad(rng.standard_normal(n), "bp", click_f * 1.22, 1.6) * decay(n, 0.0008, bottom_at)
    bottom += 0.4 * osc(thock_f * 1.4, n) * decay(n, 0.005, bottom_at)
    x = 1.0 * click + 0.5 * body + 0.55 * thock + 0.32 * bottom
    x = biquad(x, "hp", 90)
    return ramp_out(ramp_in(norm(x)))


def space(dur=0.13):
    n = n_of(dur)
    t = t_axis(n)
    click = biquad(rng.standard_normal(n), "bp", 2500, 1.1) * decay(n, 0.0014)
    body = biquad(rng.standard_normal(n), "bp", 850, 0.8) * decay(n, 0.010)
    thock = osc(150 * (1 + 0.5 * np.exp(-t / 0.006)), n) * decay(n, 0.018)
    rattle = biquad(rng.standard_normal(n), "bp", 3300, 2.0) * (decay(n, 0.0009, 0.011) + 0.7 * decay(n, 0.0009, 0.047))
    x = 0.8 * click + 0.6 * body + 0.8 * thock + 0.35 * rattle
    x = biquad(x, "hp", 70)
    return ramp_out(ramp_in(norm(x)))


# ── decode: one tick per locked letter, a minor-pentatonic run ──────────────
def tick(f, dur=0.07):
    n = n_of(dur)
    t = t_axis(n)
    fm = f * (1 + 0.5 * np.exp(-t / 0.0025))  # a fast downward chirp: "tik"
    x = osc(fm, n) + 0.22 * osc(fm * 2, n) + 0.08 * osc(fm * 3, n, "tri")
    x *= decay(n, 0.012)
    x += 0.25 * biquad(rng.standard_normal(n), "hp", 5000) * decay(n, 0.0006)
    return ramp_out(ramp_in(norm(x)))


def data_loop(dur=1.4):
    """Computer chatter for the scramble: short random beeps, crushed."""
    n = n_of(dur)
    x = np.zeros(n)
    freqs = [1175, 1397, 1568, 1760, 2093, 2349, 2637, 3136, 3520, 4186]
    pos = 0.006
    while pos < dur - 0.05:
        length = rng.uniform(0.008, 0.032)
        k = n_of(length)
        r = rng.random()
        if r < 0.72:
            f = rng.choice(freqs)
            seg = osc(f, k, "square") * 0.55 + osc(f * 2.01, k) * 0.2
        elif r < 0.88:
            f0, f1 = rng.choice(freqs), rng.choice(freqs)
            seg = osc(np.linspace(f0, f1, k), k, "square") * 0.5
        else:
            seg = hold(rng.standard_normal(k), int(rng.integers(6, 16))) * 0.45
        env = np.ones(k)
        e = max(1, n_of(0.0012))
        env[:e] = np.linspace(0, 1, e)
        env[-e:] = np.linspace(1, 0, e)
        place(x, seg * env * rng.uniform(0.35, 1.0), pos)
        pos += length + rng.uniform(0.004, 0.034)
    x = crush(biquad(x, "lp", 7000), 6)
    return norm(x)  # starts and ends on silence: loops without a seam


# ── access granted: E6 → A6 → E7, then a held A6/E7 with a short echo ───────
def granted(dur=1.15):
    n = n_of(dur)
    x = np.zeros(n)

    def note(f, length, tau, amp):
        k = n_of(length)
        s = osc(f, k) + 0.3 * osc(f * 2, k, "tri") + 0.1 * osc(f * 3, k)
        return ramp_in(s * decay(k, tau) * amp, 1.0)

    place(x, note(1318.5, 0.09, 0.05, 0.7), 0.0)
    place(x, note(1760.0, 0.09, 0.05, 0.7), 0.065)
    place(x, note(2637.0, 0.75, 0.21, 0.6), 0.13)
    place(x, note(1760.0, 0.75, 0.26, 0.45), 0.13)
    k = n_of(0.3)
    sub = osc(72, k) * decay(k, 0.09) * 0.8
    place(x, ramp_in(sub, 2.0), 0.13)
    y = x.copy()
    place(y, x * 0.3, 0.14)
    place(y, x * 0.12, 0.28)
    y = biquad(y, "lp", 9000)
    return ramp_out(norm(y), 20)


# ── glitch: three crushed bursts, the same rhythm as the visual glitch ──────
def glitch():
    segments = [(0.0, 0.07), (0.075, 0.125), (0.13, 0.168)]
    n = n_of(0.175)
    x = np.zeros(n)
    for a, b in segments:
        k = n_of(b - a)
        step = n_of(0.008)
        f = np.repeat(rng.uniform(90, 720, size=k // step + 1), step)[:k]
        seg = osc(f, k, "square") * 0.6 + rng.standard_normal(k) * 0.35
        seg = crush(hold(seg, int(rng.integers(4, 12))), 4)
        env = np.ones(k)
        e = n_of(0.001)
        env[:e] = np.linspace(0, 1, e)
        env[-e:] = np.linspace(1, 0, e)
        place(x, seg * env * rng.uniform(0.6, 1.0), a)
    x = biquad(biquad(x, "hp", 140), "lp", 9000)
    return norm(x)


# ── boot: a power-on thump, a sub swell, a rising whoosh and a riser tone ───
def boot(dur=1.6):
    n = n_of(dur)
    t = t_axis(n)
    sub_f = 34 + 44 * (1 - np.exp(-t / 0.35))
    # the 2nd and 3rd harmonics keep the swell audible on small speakers
    sub = (osc(sub_f, n) + 0.35 * osc(sub_f * 2, n) + 0.15 * osc(sub_f * 3, n)) \
        * (1 - np.exp(-t / 0.10)) * np.exp(-np.maximum(t - 0.4, 0) / 0.42)
    thump = biquad(rng.standard_normal(n), "lp", 420) * decay(n, 0.035) * 3.2
    fc = 220 + 5200 * np.exp(-((t - 0.55) / 0.26) ** 2)
    whoosh = sweep_lp(rng.standard_normal(n), fc) * np.exp(-((t - 0.55) / 0.32) ** 2)
    rise_f = 180 * np.exp(np.minimum(t, 0.6) * math.log(9) / 0.6) * (1 + 0.012 * np.sin(2 * np.pi * 7 * t))
    riser = osc(rise_f, n, "tri") * np.exp(-((t - 0.5) / 0.22) ** 2)
    x = 0.9 * sub + 0.55 * thump + 0.5 * whoosh + 0.13 * riser
    x = biquad(x, "hp", 25)
    return ramp_out(ramp_in(norm(x), 1.0), 60)


# ── hum: a low server-room drone, periodic in exactly one second ────────────
def hum(dur=1.0):
    n = n_of(dur)
    t = t_axis(n)
    x = (0.5 * np.sin(2 * np.pi * 55 * t)
         + 0.24 * np.sin(2 * np.pi * 110 * t)
         + 0.13 * np.sin(2 * np.pi * 111 * t)
         + 0.06 * np.sin(2 * np.pi * 165 * t)
         + 0.07 * np.sin(2 * np.pi * 220 * t)
         + 0.05 * np.sin(2 * np.pi * 331 * t)
         + 0.025 * np.sin(2 * np.pi * 441 * t))
    # the harmonics above carry the drone on laptop speakers, which drop 55 Hz
    # periodic noise: random phases on whole-hertz bins of the loop length
    spec = np.zeros(n // 2 + 1, dtype=complex)
    f = np.fft.rfftfreq(n, 1 / SR)
    band = (f > 70) & (f < 420)
    spec[band] = np.exp(1j * rng.uniform(0, 2 * np.pi, band.sum())) / np.sqrt(f[band])
    noise = np.fft.irfft(spec, n)
    x += 0.35 * noise / np.max(np.abs(noise))
    x *= 1 + 0.12 * np.sin(2 * np.pi * 1 * t)
    return norm(x)


# ── log line: a soft two-step blip ──────────────────────────────────────────
def blip():
    n = n_of(0.075)
    x = np.zeros(n)
    for f, at in ((1568, 0.0), (2093, 0.03)):
        k = n_of(0.02)
        s = osc(f, k, "square") * 0.6 + osc(f, k) * 0.4
        place(x, ramp_out(ramp_in(s * decay(k, 0.01), 0.6), 1.5), at)
    return norm(biquad(x, "lp", 6000))


# ── ready: a quiet upward pluck run when the tagline lands ──────────────────
def ready(dur=0.7):
    n = n_of(dur)
    x = np.zeros(n)
    for i, f in enumerate((2349, 2637, 3136, 3951)):
        k = n_of(0.4)
        s = (osc(f, k) + 0.2 * osc(f * 2, k)) * decay(k, 0.08) * (1 - 0.15 * i)
        place(x, ramp_in(s, 0.8), 0.045 * i)
    y = x.copy()
    place(y, x * 0.25, 0.12)
    return ramp_out(norm(biquad(y, "lp", 10000)), 30)


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
    os.makedirs(outdir, exist_ok=True)
    for i, args in enumerate(((3600, 1400, 230, 0.032),
                              (4200, 1700, 262, 0.028),
                              (3150, 1250, 205, 0.037),
                              (4700, 1900, 290, 0.030))):
        write(outdir, f"key{i + 1}.wav", key(*args))
    write(outdir, "space.wav", space())
    for i, f in enumerate((1760, 2093, 2349, 2637, 3136)):
        write(outdir, f"tick{i + 1}.wav", tick(f))
    write(outdir, "data.wav", data_loop())
    write(outdir, "granted.wav", granted())
    write(outdir, "glitch.wav", glitch())
    write(outdir, "boot.wav", boot())
    write(outdir, "hum.wav", hum())
    write(outdir, "blip.wav", blip())
    write(outdir, "ready.wav", ready())


if __name__ == "__main__":
    main()
