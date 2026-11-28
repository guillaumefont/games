#!/usr/bin/env python3
"""Vantage's radio callouts (tools/audio/voice_lines.tsv), rendered to res://audio/voice/<key>.ogg.

The voice is AI-generated with Kokoro-82M (Apache 2.0 weights) through kokoro-onnx (MIT), the same pipeline as
aurite-front/godot/tools/voice.py; the radio (narrow band, a little grit, a squelch at either end) is added here
with ffmpeg and numpy. Nothing but the .ogg files ships in the game, and those are the project's own.

Setup (once, outside the repo):
  pip install kokoro-onnx soundfile
  curl -LO https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
  curl -LO https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin
Run:
  python3 vantage/tools/audio/voice.py --model <dir with the two files> [--only key,key]
"""
import argparse, csv, os, subprocess, tempfile

import numpy as np

SR = 24000
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# The squadron controller: a calm American voice, a touch quick, on a field radio.
VOICE, LANG, SPEED = "am_michael", "en-us", 1.08
RADIO = ("highpass=f=300,lowpass=f=3600,acompressor=threshold=-20dB:ratio=5:attack=3:release=60,"
         "acrusher=bits=11:mix=0.2")
# every clip ends at the same loudness; scripts/sound.gd sets the overall level
NORM = "loudnorm=I=-16:TP=-1.5:LRA=7"


def lines():
    with open(os.path.join(ROOT, "tools", "audio", "voice_lines.tsv"), newline="") as f:
        rows = [r for r in csv.reader((l for l in f if not l.startswith("#")), delimiter="\t") if r]
    return [dict(zip(rows[0], r)) for r in rows[1:]]


def squelch(n, rng, level):
    """A burst of band-limited hiss that dies away: the radio opening or closing."""
    x = rng.standard_normal(n)
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    X[(f < 900) | (f > 3800)] = 0
    x = np.fft.irfft(X, n)
    x /= np.max(np.abs(x)) + 1e-9
    return x * np.exp(-np.arange(n) / (0.25 * n)) * level


def keyed(audio, rng):
    """The line between a short key-up click and a squelch tail, with faint hiss under it."""
    audio = np.asarray(audio, dtype=np.float64)
    audio /= np.max(np.abs(audio)) + 1e-9
    pad = int(0.04 * SR)
    body = np.concatenate([np.zeros(pad), audio, np.zeros(pad)])
    hiss = rng.standard_normal(len(body)) * 0.006
    return np.concatenate([squelch(int(0.05 * SR), rng, 0.35), body + hiss, squelch(int(0.12 * SR), rng, 0.3)])


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    import soundfile as sf
    from kokoro_onnx import Kokoro
    k = Kokoro(os.path.join(a.model, "kokoro-v1.0.onnx"), os.path.join(a.model, "voices-v1.0.bin"))
    only = set(filter(None, a.only.split(",")))
    out_dir = os.path.join(ROOT, "audio", "voice")
    os.makedirs(out_dir, exist_ok=True)
    tmp = tempfile.mkdtemp()
    for row in lines():
        if only and row["key"] not in only:
            continue
        audio, sr = k.create(row["line"], voice=VOICE, speed=SPEED, lang=LANG)
        voiced = os.path.join(tmp, "voiced.wav")
        sf.write(voiced, audio, sr)
        radio = os.path.join(tmp, "radio.wav")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", voiced, "-af", RADIO, "-ar", str(SR), radio],
                       check=True)
        rng = np.random.default_rng(sum(map(ord, row["key"])))
        x, _ = sf.read(radio)
        keyedwav = os.path.join(tmp, "keyed.wav")
        sf.write(keyedwav, keyed(x, rng).astype(np.float32), SR)
        dst = os.path.join(out_dir, row["key"] + ".ogg")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", keyedwav, "-af", NORM + ",aresample=24000",
                        "-ac", "1", "-ar", str(SR), "-c:a", "libvorbis", "-q:a", "4", dst], check=True)
        print(dst)


if __name__ == "__main__":
    main()
