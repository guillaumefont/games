"""App icon for Vantage: a sky-to-sea gradient, the fighter seen from above, and the cockpit
reticle round it (the two halves of the game). Writes icon.png (project icon and web
favicon, rounded), icons/ (Android launcher and adaptive layers) and store/icon-512.png.
Run from the vantage folder: python3 tools/icon.py
"""
from PIL import Image, ImageDraw

SKY = (156, 212, 238)
SEA = (31, 92, 134)
STEEL = (236, 242, 248)
CYAN = (61, 214, 245)
NAVY = (36, 52, 74)


def background(n):
    im = Image.new("RGB", (n, n))
    d = ImageDraw.Draw(im)
    for y in range(n):
        t = y / n
        d.line([(0, y), (n, y)], fill=tuple(int(SKY[i] + (SEA[i] - SKY[i]) * t) for i in range(3)))
    return im


def fighter(n, scale, ring=True):
    """The fighter (nose up) and the reticle, drawn at 4x then reduced for smooth edges."""
    s = n * 4
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = s / 2
    k = s * scale / 3.4

    def P(x, y):
        return (c + x * k, c + y * k)

    if ring:
        r = 1.55 * k
        d.ellipse([c - r, c - r, c + r, c + r], outline=CYAN, width=int(k * 0.12))
        for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
            d.line([P(dx * 1.35, dy * 1.35), P(dx * 1.8, dy * 1.8)], fill=CYAN, width=int(k * 0.12))
    for sx in (1, -1):
        d.polygon([P(0.3 * sx, 0.0), P(1.55 * sx, 0.75), P(1.55 * sx, 1.0), P(0.3 * sx, 1.05)], fill=STEEL)
        d.polygon([P(0.25 * sx, -0.75), P(0.75 * sx, -0.55), P(0.75 * sx, -0.42), P(0.25 * sx, -0.4)], fill=(190, 200, 212))
        d.polygon([P(1.38 * sx, 0.76), P(1.55 * sx, 0.76), P(1.55 * sx, 1.0), P(1.38 * sx, 1.0)], fill=CYAN)
    d.polygon([P(0, -1.5), P(0.28, -0.7), P(0.34, 0.9), P(0.22, 1.25), P(-0.22, 1.25), P(-0.34, 0.9), P(-0.28, -0.7)], fill=STEEL)
    d.polygon([P(0, -0.9), P(0.15, -0.45), P(0.13, 0.0), P(-0.13, 0.0), P(-0.15, -0.45)], fill=CYAN)
    for sx in (1, -1):
        d.rectangle([P(0.06 * sx if sx > 0 else -0.26, 1.13), P(0.26 if sx > 0 else -0.06, 1.33)], fill=NAVY)
    return im.resize((n, n), Image.LANCZOS)


def compose(n):
    bg = background(n).convert("RGBA")
    bg.alpha_composite(fighter(n, 0.62))
    return bg


def rounded(im, r):
    m = Image.new("L", im.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, im.width - 1, im.height - 1], r, fill=255)
    im.putalpha(m)
    return im


rounded(compose(256), 46).save("icon.png")
rounded(compose(512), 92).save("store/icon-512.png")
rounded(compose(192), 34).save("icons/icon-192.png")
background(432).save("icons/adaptive-background-432.png")
fg = fighter(432, 0.42)
fg.save("icons/adaptive-foreground-432.png")
mono = Image.new("RGBA", (432, 432), (255, 255, 255, 0))
mono.putalpha(fg.split()[3].point(lambda v: 255 if v > 40 else 0))
mono.save("icons/adaptive-monochrome-432.png")
print("icons written")
