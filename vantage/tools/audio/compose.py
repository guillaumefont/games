#!/usr/bin/env python3
"""Vantage's music, synthesised from scratch in code (oscillators, FM, noise). Nothing is sampled,
so every note is original and owned by the project. DSP helpers follow perigee/tools/audio/compose.py.

    python3 vantage/tools/audio/compose.py            # writes vantage/audio/music/*.ogg (numpy + ffmpeg)
    python3 vantage/tools/audio/compose.py --wav DIR  # also keep the raw WAVs
    python3 vantage/tools/audio/compose.py city ice   # only these tracks ("sfx" for the effects)

  music/sortie.ogg   "Glass Coast"  128 BPM, A minor, i-VI-III-VII: four-on-the-floor kick, pumping
                     offbeat saw bass, a bright pluck arpeggio and a lead hook over airy pads. The hangar
                     and the vertical stage.
  music/carrier.ogg  "Carrier"      140 BPM, D minor, i-VI-VII-v with a driving 16th bass, toms, a
                     stabbing brass-like lead and a rising siren. The mid-bosses.
  music/dunes.ogg    "Ember Dunes"  112 BPM, E Phrygian: hand drums, an oud-like pluck, a snaking lead.
  music/city.ogg     "Iron Sprawl"  132 BPM, F# minor electro: pulse bass, gated stabs, square lead.
  music/ice.ogg      "Frost Shelf"  108 BPM, B minor: cascading FM bells, round bass, broken beat.
  music/volcano.ogg  "Cinder Reach" 150 BPM, C minor: driven bass, power chords, double kicks.
  music/fortress.ogg "Fortress"     84 BPM half time, G minor: huge drums, choir pads, horn call. The
                     final boss of every level.
Glass Coast plays sortie.ogg; scripts/sound.gd maps each world's theme to its track.
Sound effects (audio/sfx/): shot, missile, hit, shield, pop, boom, crash, hurt, scrap, buy, launch, swoop,
warning, clear, down, tap.
Every track is 16 bars, rendered so every tail (delay, reverb) wraps round the end: they loop without a
seam (loop=true on import).
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



def hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)




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




# ------------------------------------------------------------------ drums and synths
def kick(punch=1.0):
    n = int(0.42 * SR)
    t = secs(n)
    f = 46.0 + 110.0 * np.exp(-t / 0.035)
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(ph) * np.exp(-t / 0.2)
    click = band(noise(n, 3) * np.exp(-t / 0.004), lo=2500.0) * 0.25
    return (body + click) * punch


def snare(seed=5):
    n = int(0.3 * SR)
    t = secs(n)
    tone = np.sin(2 * np.pi * 190.0 * t) * np.exp(-t / 0.05) * 0.5
    sn = band(noise(n, seed), lo=1200.0, hi=9000.0) * np.exp(-t / 0.09)
    return tone + sn * 0.8


def hat(seed, open_=False):
    n = int((0.25 if open_ else 0.06) * SR)
    t = secs(n)
    return band(noise(n, seed), lo=7000.0) * np.exp(-t / (0.08 if open_ else 0.014))


def tom(f):
    n = int(0.35 * SR)
    t = secs(n)
    ff = f * (1.0 + 0.6 * np.exp(-t / 0.03))
    return np.sin(2 * np.pi * np.cumsum(ff) / SR) * np.exp(-t / 0.16)


def pluck(m, dur, cutoff, tau, detune=7.0, seed=0):
    n = int(dur * SR)
    s = soft_saw(hz(m), n, cutoff, -detune, seed) + soft_saw(hz(m), n, cutoff, detune, seed + 1)
    return s * env(n, 0.004, tau)


def pumped(L, depth=0.65):
    """Sidechain feel: every beat the music ducks under the kick and swells back."""
    t = secs(L.n)
    ph = (t % L.beat) / L.beat
    return 1.0 - depth * np.exp(-ph * 9.0)


def pads(L, chords, bars_each, gain, cutoff=1400.0):
    for c in range(int(round(L.n / SR / (L.bar * bars_each)))):
        voicing = chords[c % len(chords)][1]
        t0 = L.t(c * bars_each)
        dur = L.bar * bars_each
        n = int((dur + 1.5) * SR)
        t = secs(n)
        e = np.clip(t / 0.6, 0, 1) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.5))
        for i, m in enumerate(voicing):
            s = np.zeros(n)
            for d in (-11.0, 0.0, 10.0):
                s += soft_saw(hz(m), n, cutoff, d, seed=c * 10 + i)
            L.add(t0, s * e, gain, pan=(i - 1.5) * 0.4, wet=0.6)


# ------------------------------------------------------------------ the tracks
def compose_sortie():
    bpm, bars = 128, 16
    L = Loop(bpm, bars)
    # Am - F - C - G, two bars each (roots, pad voicings in MIDI)
    prog = [(45, [57, 60, 64, 69]), (41, [57, 60, 65, 69]), (48, [55, 60, 64, 67]), (43, [55, 59, 62, 67])]
    pads(L, prog, 2, 0.022)
    music = np.zeros_like(L.buf)
    # everything pitched goes through the pump; drums are added after
    for bar in range(bars):
        root, voicing = prog[(bar // 2) % 4]
        # offbeat bass, an octave jump on the last eighth
        for k in range(4):
            m = root - 12 + (12 if k == 3 and bar % 2 else 0)
            L.add(L.t(bar, k + 0.5), pluck(m, 0.4, 700.0, 0.14, seed=bar), 0.2, wet=0.05)
        # arpeggio in 16ths through the chord, an octave up, from bar 2
        if bar >= 2:
            notes = voicing + [voicing[1] + 12]
            for s16 in range(16):
                m = notes[(s16 * 3 + bar) % len(notes)] + 12
                L.add(L.t(bar, s16 * 0.25), pluck(m, 0.25, 2600.0, 0.07, 4.0, seed=s16), 0.05,
                      pan=0.5 * np.sin(s16 * 0.8), wet=0.45)
        # lead hook on bars 8-15: a short call, answered
        if bar >= 8:
            hook = [(0, 76, 1.0), (1, 74, 0.5), (1.5, 72, 0.5), (2, 71, 1.0), (3, 72, 0.75)] if bar % 2 == 0 else \
                   [(0, 69, 1.5), (2, 67, 0.5), (2.5, 69, 0.5), (3, 72, 1.0)]
            if (bar // 2) % 4 == 3:
                hook = [(b, m - 1 if m in (72, 76) else m, d) for b, m, d in hook]   # over G: B and D colour
            for b, m, d in hook:
                n = int((d * L.beat + 0.3) * SR)
                s = bell(hz(m), n / SR, ratio=2.0, index=1.4, tau=0.35) * 0.6 + \
                    pluck(m, n / SR, 3200.0, 0.3, 5.0, seed=int(m)) * 0.5
                L.add(L.t(bar, b), s, 0.07, pan=0.15, wet=0.5)
    music = (L.buf + L.reverb(2.6) * 0.45 + L.delay(L.beat * 0.75, 0.35) * 0.3) * pumped(L)
    D = Loop(bpm, bars)
    for bar in range(bars):
        for beat in range(4):
            D.add(D.t(bar, beat), kick(), 0.55, wet=0.02)
            D.add(D.t(bar, beat + 0.5), hat(bar * 9 + beat, open_=True), 0.05, pan=0.3, wet=0.1)
            for q in (0.25, 0.75):
                D.add(D.t(bar, beat + q), hat(bar * 31 + beat * 3 + int(q * 4)), 0.035, pan=-0.3, wet=0.05)
        for beat in (1, 3):
            if bar >= 4:
                D.add(D.t(bar, beat), snare(bar), 0.28, wet=0.25)
        if bar % 4 == 3:
            for k in range(4):
                D.add(D.t(bar, 3 + k * 0.25), snare(bar * 5 + k), 0.12 + 0.04 * k, wet=0.25)
    return music + D.buf + D.reverb(1.2) * 0.25


def compose_carrier():
    bpm, bars = 140, 16
    L = Loop(bpm, bars)
    # Dm - Bb - C - Am
    prog = [(38, [62, 65, 69, 74]), (46, [62, 65, 70, 74]), (48, [60, 64, 67, 72]), (45, [60, 64, 69, 72])]
    pads(L, prog, 2, 0.018, cutoff=1100.0)
    for bar in range(bars):
        root, voicing = prog[(bar // 2) % 4]
        # driving 16th bass with accents
        for s16 in range(16):
            m = root - 12 + (12 if s16 in (6, 14) else 0)
            acc = 1.0 if s16 % 4 == 0 else 0.7
            L.add(L.t(bar, s16 * 0.25), pluck(m, 0.2, 900.0, 0.08, 9.0, seed=s16), 0.16 * acc, wet=0.04)
        # brass-like stabs on the offbeats of 2 and 4
        for b in (1.5, 3.5):
            for m in voicing[1:]:
                L.add(L.t(bar, b), pluck(m + 12, 0.3, 3000.0, 0.12, 12.0, seed=m), 0.03, pan=0.3 if m % 2 else -0.3,
                      wet=0.4)
        # lead on bars 4-15: a tense rising line
        if bar >= 4:
            line = [74, 77, 76, 74, 72, 74, 69, 72] if bar % 2 == 0 else [74, 77, 79, 81, 79, 77, 76, 72]
            for k, m in enumerate(line):
                n = int(0.5 * L.beat * SR + 0.15 * SR)
                s = pluck(m, n / SR, 2400.0, 0.18, 6.0, seed=k) * 0.7 + bell(hz(m), n / SR, 1.0, 0.9, 0.2) * 0.4
                L.add(L.t(bar, k * 0.5), s, 0.05, pan=-0.1, wet=0.45)
    # a siren rising over the last 4 bars
    n = int(4 * L.bar * SR)
    t = secs(n)
    f = hz(74) * 2.0 ** (t / (4 * L.bar))
    siren = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.clip(t / (4 * L.bar), 0, 1) ** 2
    L.add(L.t(12), band(siren, hi=3000.0), 0.03, wet=0.6)
    music = (L.buf + L.reverb(2.2) * 0.4 + L.delay(L.beat * 0.5, 0.3) * 0.25) * pumped(L, 0.5)
    D = Loop(bpm, bars)
    for bar in range(bars):
        for beat in range(4):
            D.add(D.t(bar, beat), kick(1.1), 0.55, wet=0.02)
            for q in (0.0, 0.25, 0.5, 0.75):
                D.add(D.t(bar, beat + q), hat(bar * 17 + beat * 4 + int(q * 4)), 0.03 if q else 0.045,
                      pan=0.25, wet=0.05)
        for beat in (1, 3):
            D.add(D.t(bar, beat), snare(bar * 3), 0.3, wet=0.25)
        if bar % 2 == 1:
            for k, f in enumerate((180.0, 150.0, 120.0, 95.0)):
                D.add(D.t(bar, 3 + k * 0.25), tom(f), 0.22, pan=0.4 - 0.25 * k, wet=0.2)
    return music + D.buf + D.reverb(1.0) * 0.25


# ------------------------------------------------------------------ the world tracks
def drive(x, amount):
    """Soft saturation: grit for bass and power chords."""
    return np.tanh(x * amount) / np.tanh(amount)


def square(f, n, cutoff, width=0.5, seed=0):
    """A band-limited pulse wave (odd and even harmonics by width), gently low-passed."""
    t = secs(n)
    ph = np.random.default_rng(seed).uniform(0, 6.28)
    out = np.zeros(n)
    for k in range(1, int(min(30, (SR / 2.2) / f)) + 1):
        a = np.sin(np.pi * k * width) / k
        g = 1.0 / np.sqrt(1.0 + (k * f / cutoff) ** 4)
        if g < 2e-3:
            break
        out += a * g * np.cos(2 * np.pi * k * f * t + ph * k)
    return out * 0.8


def drum_kit(L, bars, kick_beats, snare_beats, hats=4, kick_gain=0.55, snare_gain=0.28, from_bar=0, seed=0):
    """A plain kit: kicks and snares on the given beats of every bar, `hats` closed hats a beat."""
    for bar in range(bars):
        for b in kick_beats:
            L.add(L.t(bar, b), kick(), kick_gain, wet=0.02)
        if bar >= from_bar:
            for b in snare_beats:
                L.add(L.t(bar, b), snare(seed + bar), snare_gain, wet=0.25)
        for beat in range(4):
            for q in range(hats):
                L.add(L.t(bar, beat + q / hats), hat(seed * 7 + bar * 31 + beat * 5 + q), 0.03 if q else 0.042,
                      pan=0.3 if q % 2 else -0.2, wet=0.05)


def compose_dunes():
    """"Ember Dunes": 112 BPM, E Phrygian over a drone. A rolling hand-drum groove, a plucked
    oud-like voice and a snaking lead that leans on the flat second (F against E)."""
    bpm, bars = 112, 16
    L = Loop(bpm, bars)
    # E drone with Em - F - Dm - Em colours
    prog = [(40, [52, 59, 64, 67]), (41, [53, 57, 60, 65]), (38, [50, 57, 62, 65]), (40, [52, 59, 64, 71])]
    pads(L, prog, 4, 0.016, cutoff=900.0)
    # a low drone fifth all the way through, breathing
    n = L.n
    t = secs(n)
    drone = (soft_saw(hz(28), n, 300.0, -6, 1) + soft_saw(hz(35), n, 300.0, 6, 2) * 0.6) * \
        (0.75 + 0.25 * np.sin(2 * np.pi * t / (L.bar * 2)))
    L.add(0.0, drone, 0.05, wet=0.2)
    for bar in range(bars):
        root, voicing = prog[(bar // 4) % 4]
        # the oud: a syncopated plucked pattern on low strings
        for b, d in ((0, 0), (0.75, 7), (1.5, 12), (2, 0), (2.75, 7), (3.25, 10), (3.5, 12)):
            m = root + d
            s = over(bell(hz(m), 0.5, ratio=1.0, index=1.8, tau=0.22, attack=0.002) * 0.6,
                     pluck(m, 0.4, 1800.0, 0.15, 4.0, seed=bar) * 0.5)
            L.add(L.t(bar, b), s, 0.09, pan=-0.25, wet=0.25)
        # a snaking lead from bar 4: phrygian runs, the last bar of each four held
        if bar >= 4:
            phrase = [
                [(0, 76, 0.5), (0.5, 77, 0.5), (1, 76, 0.5), (1.5, 74, 0.5), (2, 72, 1.0), (3, 71, 1.0)],
                [(0, 72, 0.5), (0.5, 71, 0.5), (1, 69, 1.0), (2, 71, 0.5), (2.5, 72, 0.5), (3, 71, 1.0)],
                [(0, 76, 0.75), (0.75, 77, 0.25), (1, 79, 1.0), (2, 77, 0.5), (2.5, 76, 0.5), (3, 74, 1.0)],
                [(0, 76, 3.0), (3, 77, 0.25), (3.25, 76, 0.75)],
            ][bar % 4]
            for b, m, d in phrase:
                nn = int((d * L.beat + 0.25) * SR)
                tt = secs(nn)
                vib = 0.004 * np.sin(2 * np.pi * 5.5 * tt) * np.clip(tt / 0.3, 0, 1)
                ph = 2 * np.pi * np.cumsum(hz(m) * (1 + vib)) / SR
                s = (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.18 * np.sin(3 * ph)) * \
                    env(nn, 0.02, d * L.beat * 0.9 + 0.1)
                L.add(L.t(bar, b), s, 0.05, pan=0.2, wet=0.5)
    music = L.buf + L.reverb(2.8) * 0.5 + L.delay(L.beat * 0.75, 0.3) * 0.3
    D = Loop(bpm, bars)
    for bar in range(bars):
        # doum-tek: low toms on the doum, a snappy rim on the tek
        for b in (0, 1.5, 2.5):
            D.add(D.t(bar, b), tom(85.0), 0.42, wet=0.08)
        D.add(D.t(bar, 0), kick(0.8), 0.35, wet=0.02)
        for b in (1, 3):
            D.add(D.t(bar, b), snare(bar), 0.18, pan=0.2, wet=0.2)
        for s16 in range(16):
            if s16 % 4 in (1, 3) or (s16 % 4 == 2 and bar % 2):
                D.add(D.t(bar, s16 * 0.25), tom(330.0 + 40 * (s16 % 3)), 0.06, pan=-0.35 + 0.05 * (s16 % 5), wet=0.1)
            D.add(D.t(bar, s16 * 0.25), hat(bar * 19 + s16), 0.022 if s16 % 2 else 0.032, pan=0.35, wet=0.05)
        if bar % 4 == 3:
            for k in range(6):
                D.add(D.t(bar, 3 + k / 6), tom(200.0 - 15 * k), 0.2, pan=0.3 - 0.12 * k, wet=0.15)
    return music + D.buf + D.reverb(1.2) * 0.3


def compose_city():
    """"Iron Sprawl": 132 BPM, F# minor electro. A syncopated pulse bass, metallic FM hits,
    gated chord stabs and a square-wave lead; claps on the backbeat."""
    bpm, bars = 132, 16
    L = Loop(bpm, bars)
    # F#m - D - A - E
    prog = [(42, [57, 61, 66, 69]), (38, [57, 62, 66, 69]), (45, [57, 61, 64, 69]), (40, [56, 59, 64, 68])]
    for bar in range(bars):
        root, voicing = prog[(bar // 2) % 4]
        # bass: 16th syncopation, octave pops
        for s16, oct_ in ((0, 0), (3, 0), (6, 12), (8, 0), (10, 0), (11, 12), (14, 0)):
            m = root - 12 + oct_
            s = drive(square(hz(m), int(0.22 * SR), 1100.0, 0.3, s16), 1.6) * env(int(0.22 * SR), 0.003, 0.1)
            L.add(L.t(bar, s16 * 0.25), s, 0.17, wet=0.04)
        # gated stabs: the chord chopped in 16ths with a pattern
        gate = [1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1]
        if bar >= 2:
            for s16, g in enumerate(gate):
                if g:
                    for m in voicing:
                        L.add(L.t(bar, s16 * 0.25), pluck(m, 0.12, 2200.0, 0.04, 10.0, seed=m), 0.028,
                              pan=0.4 if m % 2 else -0.4, wet=0.3)
        # metallic hits on the "and" of 4
        L.add(L.t(bar, 3.5), bell(hz(root + 24), 0.6, ratio=1.41, index=3.0, tau=0.25), 0.07, pan=-0.5, wet=0.5)
        # square lead from bar 8
        if bar >= 8:
            line = [(0, 73, 0.75), (0.75, 76, 0.75), (1.5, 78, 0.5), (2, 76, 0.5), (2.5, 73, 0.5), (3, 71, 1.0)] \
                if bar % 2 == 0 else [(0, 69, 0.5), (0.5, 71, 0.5), (1, 73, 1.5), (2.5, 76, 0.5), (3, 73, 1.0)]
            if (bar // 2) % 4 == 3:
                line = [(b, m - 1 if m in (73, 78) else m, d) for b, m, d in line]   # over E: G# and E
            for b, m, d in line:
                nn = int((d * L.beat + 0.2) * SR)
                s = square(hz(m), nn, 2800.0, 0.25, int(m)) * env(nn, 0.005, d * L.beat * 0.8)
                L.add(L.t(bar, b), s, 0.065, pan=0.1, wet=0.45)
    music = (L.buf + L.reverb(1.8) * 0.4 + L.delay(L.beat * 0.75, 0.4) * 0.35) * pumped(L, 0.45)
    D = Loop(bpm, bars)
    for bar in range(bars):
        for b in (0, 1, 2, 3) if bar >= 4 else (0, 2):
            D.add(D.t(bar, b), kick(1.05), 0.55, wet=0.02)
        if bar % 2:
            D.add(D.t(bar, 2.75), kick(0.8), 0.35, wet=0.02)
        for b in (1, 3):
            # clap: three quick noise bursts
            for k in range(3):
                D.add(D.t(bar, b) + k * 0.011, snare(bar * 3 + k), 0.13, pan=0.1 * (k - 1), wet=0.35)
        for s16 in range(16):
            open_ = s16 % 4 == 2
            D.add(D.t(bar, s16 * 0.25), hat(bar * 13 + s16, open_), 0.045 if open_ else 0.026,
                  pan=0.3 if s16 % 2 else -0.3, wet=0.05)
    return music + D.buf + D.reverb(0.9) * 0.25


def compose_ice():
    """"Frost Shelf": 108 BPM, B minor with a raised sixth (Dorian shine). Glassy FM bells
    cascading in a wide space, a slow round bass, a light broken beat and a soaring pad line."""
    bpm, bars = 108, 16
    L = Loop(bpm, bars)
    # Bm - G - D - A (with added ninths)
    prog = [(47, [59, 61, 62, 66]), (43, [59, 62, 66, 69]), (50, [57, 62, 64, 66]), (45, [57, 61, 64, 68])]
    pads(L, prog, 2, 0.024, cutoff=1800.0)
    for bar in range(bars):
        root, voicing = prog[(bar // 2) % 4]
        # round sine bass, long notes
        for b, d, oct_ in ((0, 1.5, 0), (1.5, 1.0, 0), (2.5, 1.5, 12)):
            nn = int((d * L.beat + 0.2) * SR)
            tt = secs(nn)
            m = root - 12 + oct_
            s = (np.sin(2 * np.pi * hz(m) * tt) + 0.2 * np.sin(4 * np.pi * hz(m) * tt)) * env(nn, 0.01, d * L.beat)
            L.add(L.t(bar, b), s, 0.22, wet=0.05)
        # bells cascading down the chord in 8th triplets, two octaves up
        notes = sorted(voicing, reverse=True)
        for k in range(12):
            m = notes[(k + bar) % 4] + 24 - (12 if k >= 6 else 0)
            L.add(L.t(bar, k / 3.0), bell(hz(m), 1.2, ratio=3.5, index=1.6, tau=0.6), 0.03,
                  pan=0.7 * np.sin(k * 1.3 + bar), wet=0.7)
        # a soaring line from bar 4, long tones
        if bar >= 4:
            line = [(0, 78, 2.0), (2, 76, 1.0), (3, 74, 1.0)] if bar % 2 == 0 else \
                   [(0, 73, 1.5), (1.5, 74, 0.5), (2, 71, 2.0)]
            if bar >= 12:
                line = [(b, m + 12 if b == 0 else m, d) for b, m, d in line]
            for b, m, d in line:
                nn = int((d * L.beat + 0.6) * SR)
                tt = secs(nn)
                vib = 0.003 * np.sin(2 * np.pi * 5.0 * tt) * np.clip(tt / 0.5, 0, 1)
                ph = 2 * np.pi * np.cumsum(hz(m) * (1 + vib)) / SR
                s = (np.sin(ph) + 0.25 * np.sin(2 * ph)) * env(nn, 0.12, d * L.beat * 0.8 + 0.2)
                L.add(L.t(bar, b), s, 0.04, pan=-0.1, wet=0.6)
    music = L.buf + L.reverb(3.5) * 0.55 + L.delay(L.beat * 0.666, 0.4) * 0.3
    D = Loop(bpm, bars)
    for bar in range(bars):
        for b in ((0, 1.75, 2.5) if bar % 2 == 0 else (0, 2.25, 2.75)):
            D.add(D.t(bar, b), kick(0.9), 0.45, wet=0.02)
        if bar >= 2:
            D.add(D.t(bar, 1), snare(bar), 0.22, wet=0.35)
            D.add(D.t(bar, 3), snare(bar + 50), 0.22, wet=0.35)
            if bar % 4 == 3:
                D.add(D.t(bar, 3.75), snare(bar + 70), 0.1, wet=0.35)
        for s16 in range(16):
            D.add(D.t(bar, s16 * 0.25), hat(bar * 23 + s16), 0.03 if s16 % 2 == 0 else 0.016,
                  pan=0.4 * np.sin(s16), wet=0.15)
    return music + D.buf + D.reverb(1.5) * 0.3


def compose_volcano():
    """"Cinder Reach": 150 BPM, C minor. Gritty driven bass in 8ths, power-chord saw stabs,
    double kicks and a fierce rising lead; the hottest world gets the hardest track."""
    bpm, bars = 150, 16
    L = Loop(bpm, bars)
    # Cm - Ab - Eb - Bb, then Cm - Ab - Bb - G
    prog = [(36, 0), (32, 0), (39, 0), (34, 0), (36, 0), (32, 0), (34, 0), (31, 1)]
    for bar in range(bars):
        root, maj = prog[bar % 8]
        # driven bass: 8ths, a fifth flick at the end of the bar
        for e in range(8):
            m = root + (7 if e == 7 else 0)
            nn = int(0.2 * SR)
            s = drive(soft_saw(hz(m), nn, 900.0, -8, e) + soft_saw(hz(m), nn, 900.0, 8, e + 1), 3.0)
            L.add(L.t(bar, e * 0.5), s * env(nn, 0.002, 0.12), 0.11, wet=0.03)
        # power chords (root, fifth, octave) stabbed: 1, the and of 2, 4
        for b in (0, 1.5, 3):
            for d in (0, 7, 12):
                m = root + 12 + d
                nn = int(0.35 * SR)
                s = drive(soft_saw(hz(m), nn, 2500.0, -12, d) + soft_saw(hz(m), nn, 2500.0, 12, d + 3), 2.5)
                L.add(L.t(bar, b), s * env(nn, 0.003, 0.18), 0.022, pan=-0.45 if d == 7 else 0.45, wet=0.25)
        # lead from bar 4: fierce, climbs in the second half
        if bar >= 4:
            up = 0 if bar < 12 else 3
            line = [(0, 72, 0.5), (0.5, 75, 0.5), (1, 79, 1.0), (2, 77, 0.5), (2.5, 75, 0.5), (3, 74, 1.0)] \
                if bar % 2 == 0 else [(0, 75, 0.5), (0.5, 74, 0.5), (1, 72, 0.5), (1.5, 70, 0.5), (2, 72, 2.0)]
            if prog[bar % 8][1]:
                line = [(b, 71 if m == 70 else m, d) for b, m, d in line]   # over G: the leading tone
            for b, m, d in line:
                nn = int((d * L.beat + 0.15) * SR)
                s = drive(pluck(m + up, nn / SR, 3500.0, d * L.beat, 9.0, seed=int(m)), 2.0)
                L.add(L.t(bar, b), s, 0.035, pan=0.05, wet=0.4)
    n = int(4 * L.bar * SR)
    t = secs(n)
    riser = band(noise(n, 99), lo=800.0, hi=7000.0) * (t / (4 * L.bar)) ** 3
    L.add(L.t(12), riser, 0.04, wet=0.5)
    music = (L.buf + L.reverb(1.6) * 0.35 + L.delay(L.beat * 0.5, 0.25) * 0.2) * pumped(L, 0.4)
    D = Loop(bpm, bars)
    for bar in range(bars):
        for b in (0, 0.75, 1.5, 2, 2.75, 3.5):
            D.add(D.t(bar, b), kick(1.15), 0.5 if b in (0, 2) else 0.38, wet=0.02)
        for b in (1, 3):
            D.add(D.t(bar, b), snare(bar * 7), 0.32, wet=0.25)
        for e in range(8):
            D.add(D.t(bar, e * 0.5), hat(bar * 11 + e, e % 2 == 1), 0.04 if e % 2 else 0.03, pan=0.3, wet=0.05)
        if bar % 4 == 3:
            for k, f in enumerate((200.0, 170.0, 140.0, 115.0, 95.0, 80.0)):
                D.add(D.t(bar, 2.5 + k * 0.25), tom(f), 0.25, pan=0.5 - 0.2 * k, wet=0.2)
    return music + D.buf + D.reverb(1.0) * 0.25


def compose_fortress():
    """"Fortress": 84 BPM in half time, G minor with a harmonic seventh. The final boss: huge
    slow drums, a low brass-like ostinato, choir-like pads swelling and a heroic horn call, with a
    16th pulse underneath so it still drives."""
    bpm, bars = 84, 16
    L = Loop(bpm, bars)
    # Gm - Eb - Cm - D (the D major chord pulls back to Gm)
    prog = [(43, [55, 58, 62, 67]), (39, [55, 58, 63, 67]), (36, [55, 60, 63, 67]), (38, [54, 57, 62, 66])]
    # choir: many detuned voices, slow attack, filtered
    for c in range(bars // 2):
        voicing = prog[c % 4][1]
        t0 = L.t(c * 2)
        dur = L.bar * 2
        nn = int((dur + 1.5) * SR)
        t = secs(nn)
        e = np.clip(t / 1.0, 0, 1) * np.where(t < dur, 1.0, np.exp(-(t - dur) / 0.6))
        for i, m in enumerate(voicing + [voicing[0] + 12]):
            s = np.zeros(nn)
            for d in (-14.0, -5.0, 4.0, 13.0):
                s += soft_saw(hz(m), nn, 1000.0 + 600.0 * (c >= 4), d, seed=c * 10 + i)
            L.add(t0, s * e, 0.012, pan=(i - 2) * 0.35, wet=0.7)
    for bar in range(bars):
        root, voicing = prog[(bar // 2) % 4]
        # 16th pulse low strings
        for s16 in range(16):
            m = root - 12 + (12 if s16 % 8 == 6 else 0)
            L.add(L.t(bar, s16 * 0.25), pluck(m, 0.16, 800.0, 0.07, 8.0, seed=s16), 0.12 * (1.0 if s16 % 4 == 0 else 0.7),
                  wet=0.08)
        # brass ostinato: root-root-fifth-flat sixth
        for b, d in ((0, 0), (0.75, 0), (1.5, 7), (2.5, 8 if (bar // 2) % 4 != 3 else 7), (3, 7)):
            m = root + d
            nn = int(0.6 * SR)
            s = drive(soft_saw(hz(m), nn, 1400.0, -6, int(b * 4)) + soft_saw(hz(m), nn, 1400.0, 6, d), 1.5) * env(nn, 0.02, 0.3)
            L.add(L.t(bar, b), s, 0.05, wet=0.3)
        # horn call from bar 8
        if bar >= 8:
            call = [(0, 67, 1.5), (1.5, 70, 0.5), (2, 74, 2.0)] if bar % 2 == 0 else \
                   [(0, 75, 1.0), (1, 74, 1.0), (2, 72, 0.5), (2.5, 70, 0.5), (3, 69, 1.0)]
            if (bar // 2) % 4 == 3 and bar % 2:
                call = [(0, 74, 1.0), (1, 72, 1.0), (2, 69, 1.0), (3, 66, 1.0)]   # down to the F# of D
            for b, m, d in call:
                nn = int((d * L.beat + 0.3) * SR)
                s = drive(soft_saw(hz(m), nn, 2000.0, -5, int(m)) + soft_saw(hz(m - 12), nn, 1200.0, 5, int(m)) * 0.6,
                          1.4) * env(nn, 0.05, d * L.beat * 0.9 + 0.1)
                L.add(L.t(bar, b), s, 0.04, pan=0.15, wet=0.55)
    music = L.buf + L.reverb(3.2) * 0.5 + L.delay(L.beat * 0.75, 0.25) * 0.15
    D = Loop(bpm, bars)
    for bar in range(bars):
        # half-time: a huge kick on 1, a big snare on 3 with a long tail, taiko-like toms
        D.add(D.t(bar, 0), kick(1.3), 0.6, wet=0.05)
        D.add(D.t(bar, 1.75), kick(1.0), 0.35, wet=0.05)
        D.add(D.t(bar, 2), snare(bar), 0.36, wet=0.5)
        for b in (0.5, 1.0, 3.0, 3.5):
            D.add(D.t(bar, b), tom(70.0), 0.3, pan=-0.3, wet=0.3)
        for s16 in range(16):
            D.add(D.t(bar, s16 * 0.25), hat(bar * 29 + s16), 0.025 if s16 % 2 else 0.035, pan=0.3, wet=0.1)
        if bar % 4 == 3:
            for k in range(8):
                D.add(D.t(bar, 2 + k * 0.25), tom(140.0 - 8 * k), 0.18 + 0.02 * k, pan=0.4 - 0.1 * k, wet=0.3)
    return music + D.buf + D.reverb(1.8) * 0.35


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



def sweep(f0, f1, dur, shape="saw", tau=None):
    n = int(dur * SR)
    t = secs(n)
    f = f0 * (f1 / f0) ** (t / dur)
    ph = 2 * np.pi * np.cumsum(f) / SR
    s = np.sin(ph) if shape == "sine" else (2.0 / np.pi) * np.arcsin(np.sin(ph)) if shape == "tri" else         sum(np.sin(k * ph) / k for k in range(1, 8))
    return s * env(n, 0.003, tau or dur * 0.4)


def boom(dur, seed, lo_hz, rumble):
    n = int(dur * SR)
    t = secs(n)
    crack = band(noise(n, seed), lo=lo_hz, hi=lo_hz * 8) * np.exp(-t / (dur * 0.25))
    body = band(noise(n, seed + 1), hi=400.0) * np.exp(-t / (dur * 0.4)) * 2.5
    sub = np.sin(2 * np.pi * np.cumsum(rumble * (1 + np.exp(-t / 0.05))) / SR) * np.exp(-t / (dur * 0.35))
    return crack * 0.6 + body + sub * 0.8


def sfx_all():
    out = {}
    # the cannon fires several times a second: a short, soft, high tick that never tires
    out["shot"] = fx(band(sweep(1900, 900, 0.06, "tri"), lo=500) * 0.25)
    out["missile"] = fx(over(band(noise(int(0.35 * SR), 4), lo=900, hi=5000) * env(int(0.35 * SR), 0.03, 0.12) * 0.35,
                             sweep(300, 900, 0.3, "saw") * 0.12))
    out["hit"] = fx(over(band(noise(int(0.05 * SR), 9), lo=2500) * env(int(0.05 * SR), 0.001, 0.012) * 0.45,
                         sweep(900, 600, 0.05, "sine") * 0.25))
    out["shield"] = fx(bell(hz(91), 0.3, 1.41, 2.0, 0.08) * 0.3)
    out["pop"] = fx(boom(0.45, 11, 1500.0, 70.0) * 0.5)
    out["boom"] = fx(boom(1.2, 21, 700.0, 45.0) * 0.6)
    # a whole section or ship going: two booms and a falling groan
    big = over(boom(1.6, 31, 500.0, 38.0), np.concatenate([np.zeros(int(0.25 * SR)), boom(1.3, 41, 900.0, 50.0) * 0.7]),
               sweep(220, 55, 1.8, "saw", 0.9) * 0.25)
    out["crash"] = fx(big * 0.55)
    out["hurt"] = fx(over(boom(0.5, 51, 1200.0, 90.0) * 0.5, sweep(700, 180, 0.4, "saw") * 0.35))
    out["scrap"] = fx(over(bell(hz(88), 0.25, 2.0, 1.2, 0.07), np.concatenate([np.zeros(int(0.05 * SR)),
                                                                           bell(hz(93), 0.3, 2.0, 1.2, 0.08)])) * 0.18)
    out["buy"] = fx(over(*[np.concatenate([np.zeros(int(k * 0.07 * SR)), bell(hz(m), 0.4, 2.0, 1.4, 0.15)])
                           for k, m in enumerate((69, 73, 76, 81))]) * 0.2)
    out["launch"] = fx(over(band(noise(int(1.2 * SR), 61), lo=300, hi=4000) * env(int(1.2 * SR), 0.4, 0.4) * 0.4,
                            sweep(110, 440, 1.2, "saw", 0.6) * 0.2))
    out["swoop"] = fx(over(band(noise(int(1.6 * SR), 71), lo=200, hi=3000) * env(int(1.6 * SR), 0.6, 0.5) * 0.45,
                           sweep(600, 120, 1.6, "saw", 0.8) * 0.15))
    n = int(1.6 * SR)
    t = secs(n)
    out["warning"] = fx(np.sin(2 * np.pi * np.cumsum(
        660 + 220 * np.sign(np.sin(2 * np.pi * 2.5 * t))) / SR) * env(n, 0.02, 1.2) * 0.22)
    out["clear"] = fx(over(*[np.concatenate([np.zeros(int(k * 0.13 * SR)), over(bell(hz(m), 1.2, 2.0, 1.5, 0.45),
                                                  pluck(m, 1.0, 3000.0, 0.4, 6.0, k) * 0.5)])
                             for k, m in enumerate((62, 65, 69, 74, 77))]) * 0.2)
    out["down"] = fx(over(sweep(440, 110, 1.4, "saw", 0.7) * 0.3, boom(1.0, 81, 800.0, 50.0) * 0.4))
    out["tap"] = fx(bell(hz(84), 0.12, 2.0, 0.8, 0.03) * 0.2)
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


MUSIC = {
    "sortie": compose_sortie, "carrier": compose_carrier, "dunes": compose_dunes, "city": compose_city,
    "ice": compose_ice, "volcano": compose_volcano, "fortress": compose_fortress}


def level_to(st, rms):
    """Scales a track to the loudness `rms`, then rounds off any peak above 0.95 so tracks match in level."""
    st = st * (rms / np.sqrt(np.mean(st ** 2)))
    over_ = np.abs(st) > 0.8
    st[over_] = np.sign(st[over_]) * (0.8 + 0.15 * np.tanh((np.abs(st[over_]) - 0.8) / 0.15))
    return st


def main():
    wav_dir = sys.argv[sys.argv.index("--wav") + 1] if "--wav" in sys.argv else None
    only = [a for a in sys.argv[1:] if not a.startswith("--") and a != wav_dir]
    if wav_dir:
        os.makedirs(wav_dir, exist_ok=True)
    os.makedirs(os.path.join(OUT, "music"), exist_ok=True)
    ref = compose_sortie()
    ref = ref * (0.9 / np.abs(ref).max())
    rms = np.sqrt(np.mean(ref ** 2))
    for name, fn in MUSIC.items():
        if only and name not in only:
            continue
        st = ref if name == "sortie" else fn()
        if name in ("sortie", "carrier"):
            write(os.path.join(OUT, "music", name + ".ogg"), st, wav_dir, normalize=0.9)
        else:
            write(os.path.join(OUT, "music", name + ".ogg"), level_to(st, rms), wav_dir)
    if only and "sfx" not in only:
        return
    os.makedirs(os.path.join(OUT, "sfx"), exist_ok=True)
    for name, st in sfx_all().items():
        write(os.path.join(OUT, "sfx", name + ".ogg"), st, wav_dir)


if __name__ == "__main__":
    main()
