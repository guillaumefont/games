"""Generates the tileable surface textures in assets/tex (run from star-breaker/).

Everything is made from noise here: there is no painted or photographed art in the game.
Ground textures pack a normal (R, G), an albedo shade (B) and a cavity mask (A).
"""
import numpy as np
from PIL import Image

N = 512
rng = np.random.default_rng(7)


def spectral(beta, seed, lo=1.0, hi=1e9):
    """Periodic fractal noise in 0..1 with a 1/f^beta spectrum between two frequencies."""
    r = np.random.default_rng(seed)
    f = np.fft.fftfreq(N) * N
    fx, fy = np.meshgrid(f, f)
    k = np.hypot(fx, fy)
    amp = np.where((k >= lo) & (k <= hi), 1.0 / np.maximum(k, 1.0) ** (beta / 2.0), 0.0)
    spec = amp * np.exp(2j * np.pi * r.random((N, N)))
    h = np.real(np.fft.ifft2(spec))
    return (h - h.min()) / (h.max() - h.min())


def blur(h, s):
    f = np.fft.fftfreq(N)
    fx, fy = np.meshgrid(f, f)
    return np.real(np.fft.ifft2(np.fft.fft2(h) * np.exp(-2 * (np.pi * s) ** 2 * (fx ** 2 + fy ** 2))))


def cells(n, seed, warp=None):
    """Periodic Voronoi: distance to the nearest point and to the second nearest, in pixels."""
    r = np.random.default_rng(seed)
    pts = r.random((n, 2)) * N
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    if warp is not None:
        x = x + warp[0]
        y = y + warp[1]
    d1 = np.full((N, N), 1e9, np.float32)
    d2 = np.full((N, N), 1e9, np.float32)
    for p in pts:
        dx = np.abs(x - p[0]) % N
        dy = np.abs(y - p[1]) % N
        d = np.hypot(np.minimum(dx, N - dx), np.minimum(dy, N - dy))
        d2 = np.where(d < d1, d1, np.minimum(d2, d))
        d1 = np.minimum(d1, d)
    return d1, d2


def normal(h, strength):
    gx = (np.roll(h, -1, 1) - np.roll(h, 1, 1)) * strength
    gy = (np.roll(h, -1, 0) - np.roll(h, 1, 0)) * strength
    n = np.stack([-gx, gy, np.ones_like(h)], -1)
    return n / np.linalg.norm(n, axis=-1, keepdims=True)


def norm01(a):
    return (a - a.min()) / (a.max() - a.min())


def bumps(n, seed, r0, r1, pit=False):
    """Scattered pebbles (or small pits with a raised rim) as a periodic height field."""
    r = np.random.default_rng(seed)
    h = np.zeros((N, N), np.float32)
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    for _ in range(n):
        px, py, rad = r.random() * N, r.random() * N, r0 + (r1 - r0) * r.random() ** 2
        dx = np.abs(x - px) % N
        dy = np.abs(y - py) % N
        d = np.hypot(np.minimum(dx, N - dx), np.minimum(dy, N - dy)) / rad
        if pit:
            h += np.where(d < 1.35, -np.clip(1 - d * d, 0, 1) * 0.8 + np.exp(-((d - 1.0) / 0.22) ** 2) * 0.35, 0) * rad / r1
        else:
            h = np.maximum(h, np.sqrt(np.clip(1 - d * d, 0, 1)) * rad / r1)
    return h


def pack(name, h, shade, strength):
    n = normal(h, strength)
    cav = np.clip(0.5 + (h - blur(h, 6.0)) * 3.0, 0, 1)
    img = np.stack([n[..., 0] * 0.5 + 0.5, n[..., 1] * 0.5 + 0.5, np.clip(shade, 0, 1), cav], -1)
    Image.fromarray((img * 255).astype(np.uint8), "RGBA").save("assets/tex/%s.png" % name)


def rgb(name, a):
    Image.fromarray((np.clip(a, 0, 1) * 255).astype(np.uint8), "RGB").save("assets/tex/%s.png" % name)


# Cracked bedrock: broad swells, layered ledges and a web of cracks.
warp = [(spectral(2.4, 21, 2, 16) - 0.5) * 70, (spectral(2.4, 22, 2, 16) - 0.5) * 70]
d1, d2 = cells(22, 3, warp)
crack = np.clip((d2 - d1) / 9.0, 0, 1)
d1b, d2b = cells(90, 4, warp)
crack2 = np.clip((d2b - d1b) / 5.0, 0, 1)
base = spectral(3.0, 1, 2, 28)
ridge = 1.0 - np.abs(spectral(3.0, 2, 2, 36) * 2 - 1)
t = base * 5.0
ledge = (np.floor(t) + np.clip((t % 1.0 - 0.5) * 6.0 + 0.5, 0, 1)) / 5.0
h = blur(ledge, 2.0) * 0.8 + base * 0.3 + ridge ** 2 * 0.3 + spectral(2.4, 5, 10, 70) * 0.06
h = h - (1 - crack) ** 2 * 0.16 - (1 - crack2) ** 2 * 0.05
h = norm01(h)
shade = 0.66 + (spectral(1.6, 6, 16, 120) - 0.5) * 0.22 + (spectral(2.4, 7, 2) - 0.5) * 0.3 - (1 - crack) ** 3 * 0.45 - (1 - crack2) ** 3 * 0.2
pack("rock", h, shade, 22.0)

# Regolith: soft drifts, pebbles and the odd small pit.
peb = bumps(110, 13, 4.0, 14.0)
h = spectral(2.6, 11, 3, 40) * 0.45 + spectral(1.8, 12, 20, 110) * 0.05 + peb * 0.16 + bumps(16, 14, 10.0, 26.0, True) * 0.2
h += (1.0 - np.abs(spectral(2.8, 15, 5, 30) * 2 - 1)) * 0.12
h = norm01(blur(h, 0.8))
shade = 0.66 + (spectral(1.2, 16, 30, 140) - 0.5) * 0.2 + (spectral(2.4, 17, 3) - 0.5) * 0.26 + peb * 0.12
pack("dust", h, shade, 24.0)

# Hull plating: panels with seams, rivets and wear.
h = np.ones((N, N), np.float32)
alb = np.ones((N, N), np.float32) * 0.9
r = np.random.default_rng(31)


def split(x0, y0, x1, y1, depth):
    w, hh = x1 - x0, y1 - y0
    if depth == 0 or min(w, hh) < 56 or (depth < 3 and r.random() < 0.2):
        s = 3
        lift = r.random() * 0.25
        tone = 0.78 + r.random() * 0.22
        for yy in range(y0, y1):
            for_x = slice(x0, x1)
            h[yy % N, for_x] = 0.6 + lift
            alb[yy % N, for_x] = tone
        h[y0:y0 + s, x0:x1] = 0
        h[y0:y1, x0:x0 + s] = 0
        alb[y0:y0 + s, x0:x1] = 0.3
        alb[y0:y1, x0:x0 + s] = 0.3
        if min(w, hh) > 40:
            for cx, cy in [(x0 + 12, y0 + 12), (x1 - 9, y0 + 12), (x0 + 12, y1 - 9), (x1 - 9, y1 - 9)]:
                yy, xx = np.mgrid[cy - 4:cy + 5, cx - 4:cx + 5]
                m = (xx - cx) ** 2 + (yy - cy) ** 2 <= 9
                h[yy[m] % N, xx[m] % N] += 0.3
                alb[yy[m] % N, xx[m] % N] *= 0.7
        return
    if w > hh:
        m = x0 + int(w * (0.35 + 0.3 * r.random()))
        split(x0, y0, m, y1, depth - 1)
        split(m, y0, x1, y1, depth - 1)
    else:
        m = y0 + int(hh * (0.35 + 0.3 * r.random()))
        split(x0, y0, x1, m, depth - 1)
        split(x0, m, x1, y1, depth - 1)


split(0, 0, N, N, 5)
h = blur(h, 1.0)
wear = spectral(1.4, 32, 6)
alb = alb * (0.86 + 0.14 * spectral(0.8, 33, 30)) - np.clip(wear - 0.62, 0, 1) * 0.9
n = normal(h + spectral(1.0, 34, 40) * 0.04, 7.0)
rgb("hull_n", n * 0.5 + 0.5)
rgb("hull_a", np.repeat(alb[..., None], 3, -1))

# Hide and carapace for the creatures: bumps, pores and veins.
d1, d2 = cells(220, 41, [(spectral(2.4, 42, 2, 16) - 0.5) * 30, (spectral(2.4, 43, 2, 16) - 0.5) * 30])
h = np.clip(d1 / 22.0, 0, 1) ** 0.6 * 0.7 + spectral(2.0, 44, 4) * 0.4
vein = np.clip((d2 - d1) / 4.0, 0, 1)
alb = 0.72 + (1 - d1 / d1.max()) * 0.22 - (1 - vein) ** 2 * 0.3 + (spectral(1.0, 45, 20) - 0.5) * 0.2
rgb("hide_n", normal(norm01(h - (1 - vein) ** 2 * 0.25), 14.0) * 0.5 + 0.5)
rgb("hide_a", np.repeat(alb[..., None], 3, -1))
