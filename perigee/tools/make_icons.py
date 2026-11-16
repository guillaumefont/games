#!/usr/bin/env python3
"""Draws the Perigee icon (a coral moon in its dotted capture ring, with the ship on its orbit)
in the game's colours, and writes icon.png (Godot project icon), icons/ (Android launcher icon
and adaptive icon layers) and web/icon.png (the web prototype).
Run from anywhere: python3 perigee/tools/make_icons.py (needs Pillow)."""
import math
import os
from PIL import Image, ImageDraw

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SPACE, SPACE2 = (20, 22, 52), (29, 33, 80)
CORAL, SAND, INK = (255, 138, 107), (242, 200, 121), (243, 236, 223)


def draw(size, background=True, rounded=True, art=True, zoom=1.0):
    S = 4 * size  # draw large, then downscale for smooth edges
    img = Image.new("RGBA", (S, S))
    d = ImageDraw.Draw(img)
    for y in range(S if background else 0):  # vertical gradient, as in the game
        t = y / (S - 1)
        d.line([(0, y), (S, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(SPACE, SPACE2)))
    # rounded square mask
    if rounded:
        mask = Image.new("L", (S, S), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, S - 1, S - 1], radius=S * 0.22, fill=255)
        img.putalpha(mask)

    c = S / 2
    u = S / 100
    # stars
    for x, y, r in [] if not background else [(18, 20, .8), (80, 14, .6), (86, 74, .7), (12, 82, .5), (70, 88, .5), (28, 60, .4)]:
        d.ellipse([x * u - r * u, y * u - r * u, x * u + r * u, y * u + r * u], fill=INK + (170,))
    if not art:
        return img.resize((size, size), Image.LANCZOS)
    u *= zoom
    # dotted capture ring
    R = 34 * u
    for i in range(36):
        a0 = i / 36 * 2 * math.pi
        a1 = a0 + 2 * math.pi / 36 * 0.35
        d.arc([c - R, c - R, c + R, c + R], math.degrees(a0), math.degrees(a1), fill=SAND, width=round(1.6 * u))
    # moon with glow and shadow crescent
    pr = 17 * u
    glow = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(glow)
    for k in range(12, 0, -1):  # drawn on its own layer, then blended (not punched into the icon)
        rr = pr * (1 + k * 0.06)
        gd.ellipse([c - rr, c - rr, c + rr, c + rr], fill=CORAL + (int(10 + 3 * (12 - k)),))
    img.alpha_composite(glow)
    d = ImageDraw.Draw(img)
    d.ellipse([c - pr, c - pr, c + pr, c + pr], fill=CORAL)
    moon = Image.new("L", (S, S), 0)
    ImageDraw.Draw(moon).ellipse([c - pr, c - pr, c + pr, c + pr], fill=255)
    shade = Image.new("L", (S, S), 0)
    sx, sy, sr = c + pr * .45, c + pr * .4, pr * 1.05
    ImageDraw.Draw(shade).ellipse([sx - sr, sy - sr, sx + sr, sy + sr], fill=72)
    shade = Image.composite(shade, Image.new("L", (S, S), 0), moon)
    img.paste(Image.new("RGBA", (S, S), SPACE + (255,)), (0, 0), shade)
    if not background:  # keep the shadow opaque on a transparent layer
        a = img.getchannel("A")
        img.putalpha(Image.composite(Image.new("L", (S, S), 255), a, moon))
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
draw(512).save(os.path.join(ROOT, "icon.png"), optimize=True)
ICONS = os.path.join(ROOT, "icons")
os.makedirs(ICONS, exist_ok=True)
draw(192).save(os.path.join(ICONS, "icon-192.png"), optimize=True)
# Android adaptive icon: 108 dp layers, only the middle 66 dp circle is sure to show, so the art
# is drawn smaller on the foreground layer.
draw(432, rounded=False, art=False).save(os.path.join(ICONS, "adaptive-background-432.png"), optimize=True)
fg = draw(432, background=False, rounded=False, zoom=0.8)
fg.save(os.path.join(ICONS, "adaptive-foreground-432.png"), optimize=True)
mono = Image.new("RGBA", fg.size, (255, 255, 255, 0))
mono.putalpha(fg.getchannel("A"))
mono.save(os.path.join(ICONS, "adaptive-monochrome-432.png"), optimize=True)
print("icons written")
