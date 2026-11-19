"""App icon from the game's own sloop (store/ship.png, rendered by tools/icon_shots.gd):
misty sea-green gradient, faceted waves, the ship in the middle. Writes icon.png (project icon
and web favicon, rounded), icons/ (Android launcher and adaptive layers) and store/icon-512.png.
"""
from PIL import Image, ImageDraw, ImageFilter

FOG = (167, 184, 185)
SEA = (74, 110, 120)
DEEP = (52, 82, 92)


def background(n):
    im = Image.new("RGB", (n, n))
    d = ImageDraw.Draw(im)
    for y in range(n):
        t = y / n
        c = tuple(int(FOG[i] + (SEA[i] - FOG[i]) * min(1, t * 1.25)) for i in range(3))
        d.line([(0, y), (n, y)], fill=c)
    # faceted swell
    k = n / 432
    for row, (y0, col) in enumerate([(300, (84, 122, 131)), (338, (66, 100, 110)), (380, DEEP)]):
        pts = [(0, n)]
        for i in range(9):
            x = i * 432 / 8
            pts.append((x * k, (y0 + (10 if (i + row) % 2 else -8)) * k))
        pts.append((n, n))
        d.polygon(pts, fill=col)
    return im


def ship(n, scale):
    src = Image.open("store/ship.png").convert("RGBA")
    box = src.getbbox()
    src = src.crop(box)
    s = n * scale / max(src.size)
    return src.resize((int(src.width * s), int(src.height * s)), Image.LANCZOS)


def compose(n, scale=0.62, dy=-0.02):
    bg = background(n).convert("RGBA")
    sh = ship(n, scale)
    x = (n - sh.width) // 2
    y = int((n - sh.height) / 2 + dy * n)
    shadow = Image.new("RGBA", bg.size, (0, 0, 0, 0))
    a = sh.split()[3].point(lambda v: v * 0.35)
    shadow.paste((20, 30, 34, 255), (x + n // 60, y + n // 40), a)
    bg = Image.alpha_composite(bg, shadow.filter(ImageFilter.GaussianBlur(n / 80)))
    bg.alpha_composite(sh, (x, y))
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
fg = Image.new("RGBA", (432, 432), (0, 0, 0, 0))
sh = ship(432, 0.5)
fg.alpha_composite(sh, ((432 - sh.width) // 2, (432 - sh.height) // 2))
fg.save("icons/adaptive-foreground-432.png")
mono = Image.new("RGBA", (432, 432), (255, 255, 255, 0))
mono.putalpha(fg.split()[3].point(lambda v: 255 if v > 40 else 0))
mono.save("icons/adaptive-monochrome-432.png")
print("icons written")
