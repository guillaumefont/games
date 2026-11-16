#!/usr/bin/env python3
"""Draws the Perigee icon (a coral moon in its dotted capture ring, with the ship on its orbit)
in the game's colours, and writes web/icon.png and the Android launcher icons.
Run from anywhere: python3 perigee/tools/make_icons.py (needs Pillow)."""
import math
import os
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SPACE, SPACE2 = (20, 22, 52), (29, 33, 80)
CORAL, SAND, INK = (255, 138, 107), (242, 200, 121), (243, 236, 223)


def draw(size):
    S = 4 * size  # draw large, then downscale for smooth edges
    img = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S):  # vertical gradient, as in the game
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(SPACE, SPACE2)))
    # rounded square mask
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=S * 0.22, fill=255)
    img.putalpha(mask)

    c = S / 2
    u = S / 100
    # stars
    for x, y, r in [(18, 20, .8), (80, 14, .6), (86, 74, .7), (12, 82, .5), (70, 88, .5), (28, 60, .4)]:
        d.ellipse([x * u - r * u, y * u - r * u, x * u + r * u, y * u + r * u], fill=INK + (170,))
    # dotted capture ring
    R = 34 * u
    for i in range(36):
        a0 = i / 36 * 2 * math.pi
        a1 = a0 + 2 * math.pi / 36 * 0.35
        d.arc([c - R, c - R, c + R, c + R], math.degrees(a0), math.degrees(a1), fill=SAND, width=round(1.6 * u))
    # moon with glow and shadow crescent
    pr = 17 * u
    for k in range(12, 0, -1):
        rr = pr * (1 + k * 0.06)
        d.ellipse([c - rr, c - rr, c + rr, c + rr], fill=CORAL + (int(10 + 3 * (12 - k)),))
    d.ellipse([c - pr, c - pr, c + pr, c + pr], fill=CORAL)
    moon = Image.new("L", (S, S), 0)
    ImageDraw.Draw(moon).ellipse([c - pr, c - pr, c + pr, c + pr], fill=255)
    shade = Image.new("L", (S, S), 0)
    sx, sy, sr = c + pr * .45, c + pr * .4, pr * 1.05
    ImageDraw.Draw(shade).ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=72)
    shade = Image.composite(shade, Image.new("L", (S, S), 0), moon)
    img.paste(Image.new("RGBA", (S, S), SPACE + (255,)), (0, 0), shade)
    d = ImageDraw.Draw(img)
    # ship and its trail on the orbit
    orb = 25 * u
    for i in range(14):
        a = math.radians(-60 - i * 4.5)
        r = (1 - i / 14) * 2.2 * u
        x, y = c + math.cos(a) * orb, c + math.sin(a) * orb
        d.ellipse([x - r, y - r, x + r, y + r], fill=INK + (int(230 * (1 - i / 14)),))
    a = math.radians(-60)
    x, y = c + math.cos(a) * orb, c + math.sin(a) * orb
    d.ellipse([x - 3 * u, y - 3 * u, x + 3 * u, y + 3 * u], fill=INK)
    return img.resize((size, size), Image.LANCZOS)


draw(512).save(os.path.join(ROOT, "web", "icon.png"), optimize=True)
for name, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    out = os.path.join(ROOT, "android", "res", f"mipmap-{name}")
    os.makedirs(out, exist_ok=True)
    draw(px).save(os.path.join(out, "ic_launcher.png"), optimize=True)
print("icons written")
