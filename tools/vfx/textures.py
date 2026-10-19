"""Hand-drawn-style (toon-banded) textures and flipbooks for Eternium's element VFX, v2.

Every texture is greyscale on transparent: white = the brightest band. ParticleEmitter / Beam colours
tint them, so every effect stays recolourable. Toon look: brightness comes in hard bands (core, body,
rim) instead of smooth gradients, with crisp anti-aliased edges.

    python tools/vfx/textures.py        -> ElementVFX/textures/<name>.png + _contact_sheet.png

Flipbooks are square grids (Roblox FlipbookLayout Grid4x4 / Grid8x8) of 1024 px at most.
"""
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parents[2] / "ElementVFX" / "textures"
SS = 2  # supersampling


# ---------------------------------------------------------------- basics


def smooth(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def tile_noise(h, w, scale, seed, octaves=3):
    """Seamlessly tileable fractal noise in [0, 1] (built in frequency space)."""
    rng = np.random.default_rng(seed)
    out = np.zeros((h, w))
    amp, total = 1.0, 0.0
    for o in range(octaves):
        f = scale * 2 ** o
        spec = np.zeros((h, w), complex)
        fy = np.fft.fftfreq(h) * h
        fx = np.fft.fftfreq(w) * w
        FX, FY = np.meshgrid(fx, fy)
        r = np.sqrt(FX ** 2 + FY ** 2)
        band = np.exp(-((r - f) ** 2) / (2 * (f * 0.5 + 0.5) ** 2))
        spec = band * np.exp(2j * np.pi * rng.random((h, w)))
        n = np.real(np.fft.ifft2(spec))
        n = (n - n.min()) / (n.max() - n.min() + 1e-9)
        out += n * amp
        total += amp
        amp *= 0.5
    return out / total


def loop_noise(h, w, scale, seed, u):
    """Tileable noise that loops over u in [0, 1) (for looping flipbooks)."""
    a = tile_noise(h, w, scale, seed)
    b = tile_noise(h, w, scale, seed + 1)
    c, s = math.cos(2 * math.pi * u), math.sin(2 * math.pi * u)
    n = (a - 0.5) * c + (b - 0.5) * s
    return n / 0.7 + 0.5


def toon(field, levels, values, soft=0.02):
    """Hard brightness bands: field > levels[i] gives values[i] (anti-aliased by `soft`)."""
    lum = np.zeros_like(field)
    for lv, val in zip(levels, values):
        lum = np.maximum(lum, smooth(field, lv - soft, lv + soft) * val)
    alpha = smooth(field, levels[0] - soft, levels[0] + soft)
    return lum, alpha


def rgba(lum, alpha, size=None):
    lum = np.clip(lum, 0, 1)
    alpha = np.clip(alpha, 0, 1)
    # premultiply-safe: where alpha is 0 keep lum white so edges don't darken when filtered
    img = Image.merge("RGBA", [Image.fromarray((lum * 255).astype(np.uint8))] * 3 + [Image.fromarray((alpha * 255).astype(np.uint8))])
    if size:
        img = img.resize(size, Image.LANCZOS)
    return img


def grid(frames, n):
    """Packs n*n frames into a flipbook sheet (row-major, top-left first, as Roblox reads it)."""
    w, h = frames[0].size
    sheet = Image.new("RGBA", (w * n, h * n), (255, 255, 255, 0))
    # a transparent margin round every frame so mip filtering never bleeds neighbours in
    m = max(2, w // 32)
    edge = np.ones((h, w))
    edge[:m, :] = edge[-m:, :] = 0
    edge[:, :m] = edge[:, -m:] = 0
    edge = np.asarray(Image.fromarray((edge * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(m / 2)), float) / 255
    framed = []
    for f in frames:
        r, g, bch, a = f.split()
        a = Image.fromarray((np.asarray(a, float) * edge).astype(np.uint8))
        framed.append(Image.merge("RGBA", (r, g, bch, a)))
    frames = framed
    for i, f in enumerate(frames):
        sheet.paste(f, ((i % n) * w, (i // n) * h))
    return sheet


def coords(px):
    y, x = np.mgrid[0:px, 0:px] / px
    return x - 0.5, 0.5 - y  # centred, y up


def save(img, name):
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / f"{name}.png")
    print(f"  {name:<14} {img.size[0]}x{img.size[1]}")
    return img


# ---------------------------------------------------------------- FIRE


def fire_burst(n=8, px=128, seed=1):
    """A fire puff for particles: a teardrop of flame that rises, breaks into licking tongues at the top
    and burns out from the edges in."""
    frames = []
    P = px * SS
    tongues = tile_noise(P, P, 3, seed)
    tongues = np.asarray(Image.fromarray((tongues * 255).astype(np.uint8)).resize((P // 3, P), Image.BICUBIC).resize((P, P), Image.BICUBIC), float) / 255
    fine = tile_noise(P, P, 9, seed + 3)
    for i in range(n * n):
        u = i / (n * n - 1)
        x, y = coords(P)
        grow = float(smooth(np.array(u), 0, 0.22))
        cy = -0.2 + 0.1 * u
        yy = y - cy
        stretch = np.where(yy > 0, 1 / (1.3 + 0.8 * u), 1.0)
        d = np.sqrt(x ** 2 + (yy * stretch) ** 2)
        R = 0.14 + 0.24 * grow
        f = (R - d) / R
        shift = int(u * P * 1.2)
        tn = np.roll(tongues, -shift, axis=0) - 0.5
        fn = np.roll(fine, -shift * 2, axis=0) - 0.5
        f += tn * 1.6 * smooth(yy, -0.05, 0.35) + fn * 0.35
        f -= u ** 1.5 * 0.9
        f -= smooth(np.maximum(np.abs(x), np.abs(y)), 0.4, 0.49) * 3  # stay inside the frame
        lum, a = toon(f, [0.0, 0.3, 0.6], [0.5, 0.78, 1.0], soft=0.05)
        lum = lum * (1 - 0.3 * float(smooth(np.array(u), 0.55, 1.0)))
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


def fire_tongue(n=4, px=128, seed=3):
    """A looping, flickering flame tongue (ground fire, flames along the beam)."""
    frames = []
    P = px * SS
    for i in range(n * n):
        u = i / (n * n)
        x, y = coords(P)
        nz = loop_noise(P, P, 4, seed, u) - 0.5
        nz2 = loop_noise(P, P, 8, seed + 5, u) - 0.5
        yy = y + 0.46
        width = 0.36 * np.clip(1 - yy / 0.92, 0, 1) ** 0.85 * smooth(yy, -0.02, 0.14)
        xx = x - 0.08 * np.sin(yy * 7 + u * 2 * math.pi) * yy - nz * 0.16 * yy
        f = (width - np.abs(xx)) / 0.3 + nz2 * 0.45 * yy
        lum, a = toon(f + 0.4, [0.45, 0.75, 1.05], [0.5, 0.8, 1.0], soft=0.04)
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


def smoke(n=4, px=128, seed=5, dark=0.32):
    """A toon smoke puff that swells and thins out (two soft bands)."""
    frames = []
    P = px * SS
    rng = random.Random(seed)
    blobs = [(rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), rng.uniform(0.12, 0.2)) for _ in range(6)]
    warp = tile_noise(P, P, 4, seed)
    for i in range(n * n):
        u = i / (n * n - 1)
        x, y = coords(P)
        f = np.zeros_like(x)
        for bx, by, r in blobs:
            rr = r * (0.5 + 0.7 * u)
            f += rr ** 2 / ((x - bx * (1 + u)) ** 2 + (y - by * (1 + u) - u * 0.1) ** 2 + 1e-4)
        f = f * (1 + 0.8 * (np.roll(warp, int(u * P * 0.3), 0) - 0.5)) - u * 0.6
        lum, a = toon(f, [0.6, 1.1], [dark, dark + 0.18], soft=0.06)
        a = a * (1 - smooth(np.array(u), 0.6, 1.0) * 0.85)
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


def explosion(n=8, px=128, seed=7):
    """A blast: a white flash that expands into a spiky fire ring with a hot core, then breaks up."""
    frames = []
    P = px * SS
    warp = tile_noise(P, P, 6, seed)
    for i in range(n * n):
        u = i / (n * n - 1)
        x, y = coords(P)
        r = np.sqrt(x ** 2 + y ** 2)
        ang = np.arctan2(y, x)
        spikes = 0.5 + 0.5 * np.cos(ang * 9 + warp * 6)
        R = 0.06 + 0.36 * (1 - (1 - u) ** 3)
        ring_w = 0.08 + 0.08 * spikes * (1 - u)
        ring = 1 - np.abs(r - R) / ring_w
        core = (0.3 * (1 - u) ** 2 - r) / 0.12
        f = np.maximum(ring, core) + (warp - 0.5) * 0.8 - u * 0.7
        lum, a = toon(f, [0.0, 0.35, 0.75], [0.5, 0.78, 1.0], soft=0.05)
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


def flame_stream(w=512, h=128, seed=9):
    """Beam texture, tileable along U: flame streaks flowing along the beam, hottest at the centre."""
    W, H = w * SS, h * SS
    y = np.linspace(-1, 1, H)[:, None]
    n1 = tile_noise(H, W, 3, seed)
    n2 = tile_noise(H, W, 7, seed + 1)
    streak = tile_noise(H // 8 or 2, W, 6, seed + 2)
    streak = np.asarray(Image.fromarray((streak * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), float) / 255
    edge = 1 - np.abs(y) ** 1.4
    f = edge * 1.25 + (n1 - 0.5) * 0.9 + (n2 - 0.5) * 0.4 + (streak - 0.5) * 0.8
    lum, a = toon(f, [0.35, 0.7, 1.05], [0.5, 0.8, 1.0], soft=0.04)
    return rgba(lum, a, (w, h))


def fire_core(w=256, h=64, seed=11):
    """A white-hot core strip with a wavering edge (beam centre)."""
    W, H = w * SS, h * SS
    y = np.linspace(-1, 1, H)[:, None]
    n = tile_noise(H, W, 4, seed)
    f = (1 - np.abs(y)) * 1.4 + (n - 0.5) * 0.6
    lum, a = toon(f, [0.45, 0.8], [0.85, 1.0], soft=0.05)
    return rgba(lum, a, (w, h))


def ember(px=64):
    P = px * SS
    x, y = coords(P)
    star = 0.06 / (np.abs(x * y) * 30 + np.sqrt(x ** 2 + y ** 2) * 0.6 + 0.02)
    lum, a = toon(star, [0.6, 1.4], [0.8, 1.0], soft=0.1)
    return rgba(lum, a, (px, px))


def ring(px=256, seed=13, jag=0.0, width=0.07):
    """A shockwave ring (toon), optionally jagged."""
    P = px * SS
    x, y = coords(P)
    r = np.sqrt(x ** 2 + y ** 2)
    ang = np.arctan2(y, x)
    n = tile_noise(P, P, 8, seed)
    R = 0.4 + jag * (n - 0.5) * 0.1
    f = 1 - np.abs(r - R) / (width * (1 + jag * (n - 0.5)))
    lum, a = toon(f, [0.0, 0.45], [0.7, 1.0], soft=0.06)
    return rgba(lum, a, (px, px))


def glow(px=128):
    P = px * SS
    x, y = coords(P)
    r = np.sqrt(x ** 2 + y ** 2) * 2
    a = np.clip(1 - r, 0, 1) ** 2.2
    return rgba(np.ones_like(a), a, (px, px))


# ---------------------------------------------------------------- ELECTRIC


def bolt_path(rng, length, amp, depth=6, tile=True):
    """Midpoint-displacement lightning between (0, y0) and (length, y0): starts and ends level so it tiles."""
    pts = [(0.0, 0.0), (length, 0.0)]
    a = amp
    for _ in range(depth):
        out = [pts[0]]
        for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
            out += [((x0 + x1) / 2, (y0 + y1) / 2 + rng.uniform(-a, a)), (x1, y1)]
        pts = out
        a *= 0.55
    return pts


def draw_bolt(d, pts, core, glow_w, scale=SS, branches=0, rng=None, fill_core=255):
    """Draws a bolt as stacked strokes: a wide dim glow band, a body band and a white core."""
    P = [(x * scale, y * scale) for x, y in pts]
    d.line(P, fill=110, width=int(glow_w * scale), joint="curve")
    d.line(P, fill=190, width=int(max(1, glow_w * 0.45) * scale), joint="curve")
    d.line(P, fill=fill_core, width=int(max(1, core) * scale), joint="curve")
    if branches and rng:
        for _ in range(branches):
            i = rng.randrange(2, len(pts) - 2)
            x0, y0 = pts[i]
            bp = bolt_path(rng, rng.uniform(25, 60), 12, depth=4)
            ang = rng.uniform(-1.0, 1.0) + (0 if rng.random() < 0.5 else math.pi)
            ca, sa = math.cos(ang), math.sin(ang)
            pts2 = [(x0 + bx * ca - by * sa, y0 + bx * sa + by * ca) for bx, by in bp]
            draw_bolt(d, pts2, core * 0.6, glow_w * 0.5)


def bolt_strip(seed, w=512, h=96):
    """Beam texture, tileable along U: a single jagged bolt with branches, white core, toon glow bands."""
    rng = random.Random(seed)
    img = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(img)
    pts = [(x, h / 2 + y) for x, y in bolt_path(rng, w, h * 0.28)]
    draw_bolt(d, pts, 3.2, 16, branches=5, rng=rng)
    # repeat the left/right edges so the strip wraps seamlessly
    a = np.asarray(img.filter(ImageFilter.GaussianBlur(0.6 * SS)), float) / 255
    lum = np.where(a > 0.62, 1.0, np.where(a > 0.33, 0.78, 0.55))
    alpha = np.clip(a * 1.6, 0, 1)
    return rgba(lum, alpha, (w, h))


def plasma_strip(w=512, h=128, seed=21):
    """Beam texture, tileable along U: a crackling plasma core with filaments running through it."""
    W, H = w * SS, h * SS
    rng = random.Random(seed)
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    for k in range(7):
        pts = [(x, h / 2 + y * (0.4 + 0.12 * k)) for x, y in bolt_path(rng, w, h * 0.22, depth=6)]
        P = [(x * SS, y * SS) for x, y in pts]
        d.line(P, fill=120 + 18 * (k % 3), width=int((1.5 + rng.random() * 1.5) * SS))
    fil = np.asarray(img.filter(ImageFilter.GaussianBlur(1.2 * SS)), float) / 255
    y = np.linspace(-1, 1, H)[:, None]
    body = (1 - np.abs(y) ** 1.6)
    n = tile_noise(H, W, 6, seed)
    f = body * 0.9 + fil * 1.4 + (n - 0.5) * 0.35
    lum, a = toon(f, [0.45, 0.85, 1.25], [0.5, 0.8, 1.0], soft=0.05)
    return rgba(lum, a, (w, h))


def spark_flip(n=4, px=128, seed=31, arms=(3, 5), reach=0.45):
    """Random-frame branching zaps radiating from the centre (use FlipbookMode Random)."""
    frames = []
    rng = random.Random(seed)
    for i in range(n * n):
        img = Image.new("L", (px * SS, px * SS), 0)
        d = ImageDraw.Draw(img)
        c = px / 2
        for _ in range(rng.randint(*arms)):
            ang = rng.uniform(0, 2 * math.pi)
            L = px * reach * rng.uniform(0.6, 1.0)
            bp = bolt_path(rng, L, L * 0.12, depth=5)
            ca, sa = math.cos(ang), math.sin(ang)
            pts = [(c + bx * ca - by * sa, c + bx * sa + by * ca) for bx, by in bp]
            draw_bolt(d, pts, 1.6, 7, branches=1, rng=rng)
        a = np.asarray(img.filter(ImageFilter.GaussianBlur(0.5 * SS)), float) / 255
        lum = np.where(a > 0.62, 1.0, np.where(a > 0.33, 0.78, 0.55))
        frames.append(rgba(lum, np.clip(a * 1.6, 0, 1), (px, px)))
    return grid(frames, n)


def arc_burst(n=8, px=128, seed=41):
    """An electric impact: a flash, a jagged expanding ring and bolts flying outward, fading."""
    frames = []
    rng = random.Random(seed)
    arms = [(rng.uniform(0, 2 * math.pi), rng.uniform(0.7, 1.0)) for _ in range(9)]
    paths = [bolt_path(random.Random(seed + k), 1.0, 0.12, depth=5) for k in range(9)]
    for i in range(n * n):
        u = i / (n * n - 1)
        img = Image.new("L", (px * SS, px * SS), 0)
        d = ImageDraw.Draw(img)
        c = px / 2
        R = px * (0.05 + 0.42 * (1 - (1 - u) ** 2.5))
        flick = 1.0 if (i % 3) else 0.7
        for (ang, lf), bp in zip(arms, paths):
            ca, sa = math.cos(ang), math.sin(ang)
            pts = [(c + bx * R * lf * ca - by * R * sa, c + bx * R * lf * sa + by * R * ca) for bx, by in bp]
            draw_bolt(d, pts, 1.8 * (1 - u) + 0.6, 8 * (1 - u) + 2, fill_core=int(255 * flick))
        ring_pts = [(c + math.cos(2 * math.pi * j / 48) * R * (1 + rng.uniform(-0.06, 0.06)), c + math.sin(2 * math.pi * j / 48) * R * (1 + rng.uniform(-0.06, 0.06))) for j in range(49)]
        d.line([(x * SS, y * SS) for x, y in ring_pts], fill=int(170 * (1 - u)), width=int(max(1, 3 * (1 - u)) * SS))
        if u < 0.2:
            fl = (1 - u / 0.2)
            d.ellipse([(c - px * 0.18 * fl) * SS, (c - px * 0.18 * fl) * SS, (c + px * 0.18 * fl) * SS, (c + px * 0.18 * fl) * SS], fill=255)
        a = np.asarray(img.filter(ImageFilter.GaussianBlur(0.5 * SS)), float) / 255
        lum = np.where(a > 0.62, 1.0, np.where(a > 0.33, 0.78, 0.55))
        frames.append(rgba(lum, np.clip(a * 1.6, 0, 1) * (1 - smooth(np.array(u), 0.75, 1.0)), (px, px)))
    return grid(frames, n)


def orb_flip(n=4, px=128, seed=51):
    """Ball lightning: a bright sphere crawling with filaments (looping)."""
    frames = []
    for i in range(n * n):
        u = i / (n * n)
        rng = random.Random(seed + i)
        P = px * SS
        x, y = coords(P)
        r = np.sqrt(x ** 2 + y ** 2)
        img = Image.new("L", (P, P), 0)
        d = ImageDraw.Draw(img)
        c = px / 2
        for _ in range(6):
            ang = rng.uniform(0, 2 * math.pi)
            L = px * 0.42
            bp = bolt_path(rng, L, L * 0.15, depth=5)
            ca, sa = math.cos(ang), math.sin(ang)
            pts = [(c + (bx - L / 2) * ca - by * sa, c + (bx - L / 2) * sa + by * ca) for bx, by in bp]
            P2 = [(px_ * SS, py_ * SS) for px_, py_ in pts]
            d.line(P2, fill=255, width=int(1.4 * SS))
        fil = np.asarray(img.filter(ImageFilter.GaussianBlur(0.8 * SS)), float) / 255
        body = np.clip((0.3 - r) / 0.06, 0, 1)
        core = np.clip((0.12 - r) / 0.06, 0, 1)
        lum = np.maximum.reduce([body * 0.5, np.where(fil > 0.3, 1.0, 0) * (r < 0.44), core * 0.85])
        a = np.clip(np.maximum(body, (fil > 0.15) * (r < 0.44) * 1.0), 0, 1)
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


def cloud_flip(n=4, px=128, seed=61):
    """A dark, churning storm-cloud puff (looping) with a lighter rim."""
    frames = []
    P = px * SS
    rng = random.Random(seed)
    blobs = [(rng.uniform(-0.18, 0.18), rng.uniform(-0.08, 0.08), rng.uniform(0.07, 0.11)) for _ in range(8)]
    for i in range(n * n):
        u = i / (n * n)
        x, y = coords(P)
        f = np.zeros_like(x)
        for k, (bx, by, r) in enumerate(blobs):
            ph = 2 * math.pi * (u + k / len(blobs))
            f += r ** 2 / ((x - bx - 0.02 * math.cos(ph)) ** 2 + (y - by - 0.02 * math.sin(ph)) ** 2 + 1e-4)
        nz = loop_noise(P, P, 5, seed, u) - 0.5
        f = f * (1 + 0.6 * nz) * np.clip(1.4 - np.sqrt(x ** 2 + y ** 2) * 2.6, 0, 1)
        lum, a = toon(f, [0.7, 1.3, 2.6], [0.3, 0.4, 0.22], soft=0.06)
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


# ---------------------------------------------------------------- build


def contact_sheet():
    files = sorted(p for p in OUT.glob("*.png") if not p.name.startswith("_"))
    cell = 200
    cols = 6
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 18)), (28, 24, 34))
    d = ImageDraw.Draw(sheet)
    for i, p in enumerate(files):
        im = Image.open(p).convert("RGBA")
        im.thumbnail((cell - 10, cell - 10))
        bg = Image.new("RGBA", im.size, (28, 24, 34, 255))
        bg.alpha_composite(im)
        x, y = (i % cols) * cell, (i // cols) * (cell + 18)
        sheet.paste(bg.convert("RGB"), (x + 5, y + 5))
        d.text((x + 6, y + cell - 4), p.stem, fill=(220, 220, 230))
    sheet.save(OUT / "_contact_sheet.png")


def main():
    print("Fire")
    save(fire_burst(), "F_Burst8")
    save(fire_tongue(), "F_Tongue4")
    save(smoke(seed=5, dark=0.32), "F_Smoke4")
    save(explosion(), "F_Explode8")
    save(flame_stream(), "F_Stream")
    save(fire_core(), "F_Core")
    save(ember(), "F_Ember")
    save(ring(seed=13, jag=1.0, width=0.08), "F_Ring")
    print("Electric")
    for k in range(3):
        save(bolt_strip(71 + k), f"E_Bolt{k + 1}")
    save(plasma_strip(), "E_Plasma")
    save(spark_flip(), "E_Spark4")
    save(arc_burst(), "E_Arc8")
    save(orb_flip(), "E_Orb4")
    save(cloud_flip(), "E_Cloud4")
    save(ring(seed=81, jag=2.5, width=0.05), "E_Ring")
    print("Shared")
    save(glow(), "X_Glow")
    contact_sheet()


if __name__ == "__main__":
    main()
