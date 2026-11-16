#!/usr/bin/env python3
"""Perigee's music and sound effects, synthesised from scratch in code (oscillators, FM, noise).
Nothing is sampled, so every sound is original and owned by the project.

    python3 perigee/tools/audio/compose.py            # writes perigee/audio/**/*.ogg (numpy + ffmpeg)
    python3 perigee/tools/audio/compose.py --wav DIR  # also keep the raw WAVs

Music
  music/drift.ogg  "Low Orbit"  72 BPM, D major pentatonic over a slow I-vi-IV-V drift: soft pads,
                   FM bells, a sub bass and sparse ticks. 16 bars, rendered so every tail (delay,
                   reverb) wraps round the end: the file loops without a seam (loop=true on import).
Sound effects (all in D major pentatonic, so they sit on the music)
  catch0..11  a moon's bell, one pentatonic step higher per hop
  perigee     a bright two-bell chime        leap     a rising sparkle arpeggio
  spark       a glassy ping                  graze    a soft filtered swish
  launch      a breathy whoosh               revisit  a muted bell
  die         a falling, detuned drop        toggle   a soft blip
  clear       the sector-clear fanfare       star     one star landing on the clear card
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "audio")
PENTA = [0, 2, 4, 7, 9]  # D major pentatonic, from D


def hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def penta(i, base=62):
    """The i-th note of D major pentatonic above MIDI `base` (62 = D4)."""
    return base + 12 * (i // 5) + PENTA[i % 5]


# ------------------------------------------------------------------ DSP
def secs(n):
    return np.arange(n) / SR


def env(n, attack, decay_tau):
    t = secs(n)
    e = np.exp(-t / decay_tau)
    a = max(attack, 1e-4)
    e[t < a] *= t[t < a] / a
    return e


def band(x, lo=None, hi=None):
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1.0 / SR)
    g = np.ones_like(f)
    if lo:
        g *= 1.0 / np.sqrt(1.0 + (lo / np.maximum(f, 1.0)) ** 4)
    if hi:
        g *= 1.0 / np.sqrt(1.0 + (f / hi) ** 4)
    return np.fft.irfft(X * g, len(x))


def noise(n, seed):
    return np.random.default_rng(seed).standard_normal(n)


def bell(f, dur, ratio=3.5, index=2.2, tau=0.5, attack=0.003):
    """FM bell: the modulator's depth decays faster than the tone, so it starts bright and mellows."""
    n = int(dur * SR)
    t = secs(n)
    mod = index * np.exp(-t / (tau * 0.35)) * np.sin(2 * np.pi * f * ratio * t)
    return np.sin(2 * np.pi * f * t + mod) * env(n, attack, tau)


def over(*parts):
    """Sum signals of different lengths."""
    out = np.zeros(max(len(p) for p in parts))
    for p in parts:
        out[: len(p)] += p
    return out


def soft_saw(f, n, cutoff, detune=0.0, seed=0):
    """A band-limited saw with a gentle low-pass, built from harmonics."""
    t = secs(n)
    fr = f * 2.0 ** (detune / 1200.0)
    ph = np.random.default_rng(seed).uniform(0, 6.28)
    out = np.zeros(n)
    for k in range(1, int(min(40, (SR / 2.2) / fr)) + 1):
        g = 1.0 / np.sqrt(1.0 + (k * fr / cutoff) ** 4)
        if g < 2e-3:
            break
        out += g * np.sin(2 * np.pi * k * fr * t + ph * k) / k
    return out * 0.6


# ------------------------------------------------------------------ the loop
class Loop:
    """A stereo buffer exactly `bars` long; anything running past the end wraps to the start."""

    def __init__(self, bpm, bars):
        self.beat = 60.0 / bpm
        self.bar = self.beat * 4
        self.n = int(round(bars * self.bar * SR))
        self.buf = np.zeros((2, self.n))
        self.send = np.zeros((2, self.n))  # into the reverb and delay

    def t(self, bar, beat=0.0):
        return bar * self.bar + beat * self.beat

    def add(self, t, sig, gain=1.0, pan=0.0, wet=0.3):
        start = int(round(t * SR)) % self.n
        l = np.cos((pan + 1) * np.pi / 4) * gain
        r = np.sin((pan + 1) * np.pi / 4) * gain
        idx = (start + np.arange(len(sig))) % self.n
        for buf, w in ((self.buf, 1.0), (self.send, wet)):
            np.add.at(buf[0], idx, sig * l * w)
            np.add.at(buf[1], idx, sig * r * w)

    def reverb(self, seconds, seed=7):
        m = min(int(seconds * SR), self.n)
        out = np.zeros_like(self.send)
        for ch in range(2):
            ir = noise(m, seed + ch) * np.exp(-secs(m) * 6.9 / seconds)
            ir = band(ir, lo=200.0, hi=5000.0)
            ir[: int(0.03 * SR)] = 0.0
            ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
            pad = np.zeros(self.n)
            pad[:m] = ir
            out[ch] = np.fft.irfft(np.fft.rfft(self.send[ch]) * np.fft.rfft(pad), self.n)
        return out

    def delay(self, seconds, feedback, taps=6):
        out = np.zeros_like(self.send)
        d = int(seconds * SR)
        src = np.vstack([band(self.send[0], 250, 4000), band(self.send[1], 250, 4000)])
        for k in range(1, taps + 1):
            a = 0 if k % 2 else 1
            out[0] += np.roll(src[a], d * k) * feedback ** k
            out[1] += np.roll(src[1 - a], d * k) * feedback ** k
        return out


def compose_drift():
    bpm, bars = 72, 16
    L = Loop(bpm, bars)
    # I - vi - IV - V in D, two bars each, twice: chord roots and pad voicings (MIDI)
    prog = [(50, [62, 66, 69, 74]), (47, [62, 66, 71, 74]), (43, [62, 67, 71, 74]), (45, [61, 64, 69, 73])]
    rng = np.random.default_rng(2026)
    for c in range(bars // 2):
        root, voicing = prog[c % 4]
        t0 = L.t(c * 2)
        dur = L.bar * 2
        n = int((dur + 2.5) * SR)
        # pad: detuned soft saws, slow swell, gently breathing filter
        for i, m in enumerate(voicing):
            s = np.zeros(n)
            for d in (-9.0, 0.0, 8.0):
                s += soft_saw(hz(m), n, 900.0 + 300.0 * (i % 2), d, seed=c * 10 + i)
            t = secs(n)
            e = np.clip(t / 1.4, 0, 1) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.7))
            e *= 1.0 + 0.15 * np.sin(2 * np.pi * 0.11 * t + i)
            L.add(t0, s * e, 0.045, pan=(i - 1.5) * 0.35, wet=0.7)
        # sub bass: a sine on the root with a soft attack, re-struck each bar
        for b in range(2):
            n2 = int(L.bar * 1.1 * SR)
            t = secs(n2)
            s = np.sin(2 * np.pi * hz(root - 12) * t) + 0.25 * np.sin(2 * np.pi * hz(root) * t)
            e = np.clip(t / 0.08, 0, 1) * np.exp(-t / 1.6)
            L.add(t0 + b * L.bar, s * e, 0.22, wet=0.05)
        # bells: a slow pentatonic arpeggio that wanders, eighth notes with rests
        for step in range(16):
            if rng.random() < 0.35 and step % 4:
                continue
            i = int(rng.integers(5, 12))
            f = hz(penta(i))
            s = bell(f, 1.8, ratio=3.5, index=1.6, tau=0.45)
            L.add(t0 + step * L.beat / 2, s, 0.07 * (1.15 if step % 4 == 0 else 0.8),
                  pan=float(rng.uniform(-0.6, 0.6)), wet=0.55)
    # sparse ticks: filtered noise on the offbeats, from bar 4
    for bar in range(4, bars):
        for beat in (1.5, 3.5):
            n = int(0.08 * SR)
            s = band(noise(n, bar * 7 + int(beat)) * env(n, 0.003, 0.015), lo=6000.0)
            L.add(L.t(bar, beat), s, 0.03, pan=0.4 if beat < 2 else -0.4, wet=0.2)
    out = L.buf + L.reverb(4.0) * 0.55 + L.delay(L.beat * 0.75, 0.38) * 0.35
    return out


# ------------------------------------------------------------------ sound effects
def fx(sig):
    n = len(sig)
    tail = int(0.4 * SR)
    st = np.vstack([np.concatenate([sig, np.zeros(tail)])] * 2)
    # a small room so effects sit in the same space as the music
    m = int(0.35 * SR)
    ir = noise(m, 3) * np.exp(-secs(m) * 6.9 / 0.35)
    ir = band(ir, lo=300.0, hi=6000.0)
    ir /= np.sqrt(np.sum(ir ** 2))
    wet = np.convolve(st[0], ir)[: n + tail] * 0.12
    st = st + wet
    # trim trailing silence
    a = np.abs(st).max(axis=0)
    last = np.nonzero(a > 1e-3)[0]
    return st[:, : (last[-1] + 1 if len(last) else n)]


def sfx_all():
    out = {}
    for i in range(12):
        f = hz(penta(i + 5))  # from D5 up two octaves and change
        s = over(bell(f, 0.7, ratio=2.0, index=1.4, tau=0.22), 0.3 * bell(f * 2, 0.4, ratio=3.0, index=0.8, tau=0.1))
        out["catch%d" % i] = fx(s * 0.32)
    a = bell(hz(81), 0.9, 3.5, 2.0, 0.25)
    b = bell(hz(88), 0.9, 3.5, 2.0, 0.3)
    s = np.zeros(int(1.0 * SR))
    s[: len(a)] += a
    o = int(0.08 * SR)
    s[o: o + len(b)][: len(s) - o] += b[: len(s) - o]
    out["perigee"] = fx(s * 0.3)
    s = np.zeros(int(1.0 * SR))
    for j, m in enumerate([penta(10), penta(12), penta(14), penta(15)]):
        o = int(j * 0.055 * SR)
        nb = bell(hz(m), 0.6, 2.0, 1.2, 0.18)
        s[o: o + len(nb)] += nb[: len(s) - o]
    out["leap"] = fx(s * 0.24)
    n = int(0.35 * SR)
    t = secs(n)
    s = np.sin(2 * np.pi * hz(98) * t) * env(n, 0.001, 0.07) + 0.4 * np.sin(2 * np.pi * hz(105) * t) * env(n, 0.001, 0.04)
    out["spark"] = fx(s * 0.18)
    n = int(0.22 * SR)
    sw = band(noise(n, 11), lo=1500.0, hi=5000.0) * np.sin(np.pi * secs(n) / (n / SR)) ** 2
    out["graze"] = fx(sw * 0.07)
    n = int(0.32 * SR)
    t = secs(n)
    wh = band(noise(n, 5), lo=500.0, hi=3000.0) * np.clip(t / 0.03, 0, 1) * np.exp(-t / 0.09)
    f = 300.0 * np.exp(-t * 3.0)
    tone = np.sin(2 * np.pi * np.cumsum(f) / SR) * env(n, 0.004, 0.1)
    out["launch"] = fx(wh * 0.08 + tone * 0.12)
    out["revisit"] = fx(bell(hz(62), 0.5, 2.0, 0.6, 0.12) * 0.2)
    n = int(0.9 * SR)
    t = secs(n)
    f = 260.0 * np.exp(-t * 2.4)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = (np.sin(ph) + 0.6 * np.sin(ph * 1.012) + 0.3 * np.sin(ph * 0.5)) * env(n, 0.005, 0.3)
    s += band(noise(n, 9), hi=900.0) * env(n, 0.002, 0.18) * 0.6
    out["die"] = fx(s * 0.2)
    n = int(0.12 * SR)
    out["toggle"] = fx(np.sin(2 * np.pi * hz(81) * secs(n)) * env(n, 0.002, 0.03) * 0.2)
    s = np.zeros(int(2.2 * SR))
    for j, m in enumerate([62, 66, 69, 74, 78, 81]):
        o = int(j * 0.09 * SR)
        nb = bell(hz(m), 1.9, 2.0, 1.3, 0.55)
        s[o: o + len(nb)] += nb[: len(s) - o] * 0.9
    out["clear"] = fx(s * 0.16)
    out["star"] = fx(bell(hz(86), 0.7, 3.5, 1.8, 0.2) * 0.22)
    return out


# ------------------------------------------------------------------ output
def write(path, st, wav_dir=None, normalize=None):
    st = np.asarray(st)
    peak = np.abs(st).max()
    if normalize:
        st = st * (normalize / peak)
    elif peak > 0.98:
        st = st * (0.98 / peak)
    pcm = (np.clip(st, -1, 1).T * 32767).astype("<i2")
    with tempfile.TemporaryDirectory() as tmp:
        w = os.path.join(wav_dir or tmp, os.path.basename(path).replace(".ogg", ".wav"))
        with wave.open(w, "wb") as f:
            f.setnchannels(2)
            f.setsampwidth(2)
            f.setframerate(SR)
            f.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", w, "-c:a", "libvorbis", "-q:a", "4", path],
                       check=True)
    print("wrote %s (%.1f s, peak %.2f)" % (os.path.relpath(path, ROOT), st.shape[1] / SR, peak))


def main():
    wav_dir = sys.argv[sys.argv.index("--wav") + 1] if "--wav" in sys.argv else None
    if wav_dir:
        os.makedirs(wav_dir, exist_ok=True)
    os.makedirs(os.path.join(OUT, "music"), exist_ok=True)
    os.makedirs(os.path.join(OUT, "sfx"), exist_ok=True)
    write(os.path.join(OUT, "music", "drift.ogg"), compose_drift(), wav_dir, normalize=0.9)
    for name, st in sfx_all().items():
        write(os.path.join(OUT, "sfx", name + ".ogg"), st, wav_dir)


if __name__ == "__main__":
    main()
