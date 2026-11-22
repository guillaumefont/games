"""Generates the tileable surface textures in assets/tex (run from star-breaker/).

Only the creatures' hide is generated; rock, ground and metal are scanned CC0 materials
from Poly Haven (see assets/scan/README.md).
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


# Hide and carapace for the creatures: bumps, pores and veins.
d1, d2 = cells(220, 41, [(spectral(2.4, 42, 2, 16) - 0.5) * 30, (spectral(2.4, 43, 2, 16) - 0.5) * 30])
h = np.clip(d1 / 22.0, 0, 1) ** 0.6 * 0.7 + spectral(2.0, 44, 4) * 0.4
vein = np.clip((d2 - d1) / 4.0, 0, 1)
alb = 0.72 + (1 - d1 / d1.max()) * 0.22 - (1 - vein) ** 2 * 0.3 + (spectral(1.0, 45, 20) - 0.5) * 0.2
rgb("hide_n", normal(norm01(h - (1 - vein) ** 2 * 0.25), 14.0) * 0.5 + 0.5)
rgb("hide_a", np.repeat(alb[..., None], 3, -1))
