#!/usr/bin/env python3
"""Renders the announcer lines (tools/voice_lines.tsv) to res://voice/<faction>/<key>.ogg.

The voices are AI-generated with Kokoro-82M (Apache 2.0 weights) through kokoro-onnx (MIT); the faction character
(radio band, crackle, octave shadow, echo) is added with ffmpeg. Nothing here ships in the app except the .ogg files.

Setup (once, outside the repo):
  pip install kokoro-onnx soundfile
  curl -LO https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx
  curl -LO https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin
Run from godot/:
  python3 tools/voice.py . --model <dir with the two files> [--only key,key] [--fac choir]
"""
import argparse, csv, os, subprocess, tempfile

SR = 24000
# voice, language, speed, ffmpeg chain (-af) or None for the Choir's layered graph
FACTIONS = {
    # Vanguard: clipped officer on a clean comm link (high tech, flown in from the fleet)
    "vanguard": ("bf_emma", "en-gb", 1.05,
                 "highpass=f=260,lowpass=f=7000,acompressor=threshold=-18dB:ratio=4,aecho=0.8:0.5:22:0.18"),
    # Ashen Pact: gruff foreman on a crackly field radio (raw power)
    "ashen": ("bm_george", "en-gb", 1.0,
              "asetrate=24000*0.92,aresample=24000,atempo=1.06,highpass=f=320,lowpass=f=3400,"
              "acrusher=bits=10:mix=0.25,acompressor=threshold=-20dB:ratio=6"),
    # Hollow Choir: a whisper with an octave shadow under it. Guillaume (2026-11-28): "a bit less delay" than the samples.
    "choir": ("af_nicole", "en-us", 0.88, None),
}
CHOIR_GRAPH = ("[0:a]asplit=3[a][b][c];"
               "[b]asetrate=24000*0.75,aresample=24000,atempo=1.3333,volume=0.55[bl];"
               "[c]asetrate=24000*1.02,aresample=24000,atempo=0.98,highpass=f=1500,volume=0.3,adelay=12[cl];"
               "[a][bl][cl]amix=inputs=3:normalize=0,chorus=0.6:0.8:18|26:0.35|0.25:0.3|0.4:2|1.3,"
               "aecho=0.8:0.5:55|110:0.22|0.12,lowpass=f=6500[o]")
# every clip ends at the same loudness; the game sets the overall voice level (scripts/voice.gd)
NORM = "loudnorm=I=-18:TP=-2:LRA=7"


def lines(path):
    with open(path, newline="") as f:
        rows = [r for r in csv.reader((l for l in f if not l.startswith("#")), delimiter="\t")]
    head, body = rows[0], rows[1:]
    return [dict(zip(head, r)) for r in body if r]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("project")
    ap.add_argument("--model", required=True)
    ap.add_argument("--only", default="")
    ap.add_argument("--fac", default="")
    a = ap.parse_args()
    import soundfile as sf
    from kokoro_onnx import Kokoro
    k = Kokoro(os.path.join(a.model, "kokoro-v1.0.onnx"), os.path.join(a.model, "voices-v1.0.bin"))
    only = set(filter(None, a.only.split(",")))
    tmp = tempfile.mkdtemp()
    for row in lines(os.path.join(a.project, "tools", "voice_lines.tsv")):
        if only and row["key"] not in only: continue
        for fac, (voice, lang, speed, chain) in FACTIONS.items():
            if a.fac and fac != a.fac: continue
            text = row.get(fac, "-").strip()
            if text in ("", "-"): continue
            audio, sr = k.create(text, voice=voice, speed=speed, lang=lang)
            raw = os.path.join(tmp, "raw.wav"); sf.write(raw, audio, sr)
            out_dir = os.path.join(a.project, "voice", fac); os.makedirs(out_dir, exist_ok=True)
            dst = os.path.join(out_dir, row["key"] + ".ogg")
            if chain is None:
                fx = ["-filter_complex", CHOIR_GRAPH.replace("[o]", "[m];[m]" + NORM + ",aresample=24000[o]"), "-map", "[o]"]
            else:
                fx = ["-af", chain + "," + NORM + ",aresample=24000"]
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw, *fx, "-ac", "1", "-ar", str(SR),
                            "-c:a", "libvorbis", "-q:a", "4", dst], check=True)
            print(dst)


if __name__ == "__main__":
    main()
