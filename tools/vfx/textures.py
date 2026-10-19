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




# ====================================================================== batch 2: eight more elements


def facet_strip(w=512, h=128, seed=101, facets=14):
    """Rift: a crystal beam strip, tileable along U: angular facets with bright edges, white heart."""
    rng = random.Random(seed)
    W, H = w * SS, h * SS
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    xs = sorted(rng.uniform(0, w) for _ in range(facets))
    for i, x in enumerate(xs):
        x2 = xs[(i + 1) % facets] + (w if i == facets - 1 else 0)
        top = rng.uniform(0.15, 0.3) * h
        bot = rng.uniform(0.7, 0.85) * h
        shade = rng.choice((120, 160, 200))
        for off in (0, w, -w):
            d.polygon([((x + off) * SS, h / 2 * SS), ((x + (x2 - x) * 0.5 + off) * SS, top * SS), ((x2 + off) * SS, h / 2 * SS), ((x + (x2 - x) * 0.5 + off) * SS, bot * SS)], fill=shade)
            d.line([((x + off) * SS, h / 2 * SS), ((x + (x2 - x) * 0.5 + off) * SS, top * SS)], fill=255, width=2 * SS)
    a = np.asarray(img, float) / 255
    y = np.linspace(-1, 1, H)[:, None]
    heart = np.clip(1 - np.abs(y) / 0.18, 0, 1)
    lum = np.maximum(a, heart)
    alpha = np.clip(np.maximum(a * 1.4, heart), 0, 1)
    lum = np.where(lum > 0.85, 1.0, np.where(lum > 0.55, 0.78, 0.55))
    return rgba(lum, alpha, (w, h))


def crack_strip(seed, w=512, h=96):
    """Rift: an angular crack running along the strip (straight segments, sharp turns), tileable."""
    rng = random.Random(seed)
    img = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(img)
    pts, x, y = [(0, h / 2)], 0, h / 2
    while x < w - 40:
        x += rng.uniform(25, 60)
        y = h / 2 + rng.uniform(-0.3, 0.3) * h
        pts.append((x, y))
    pts.append((w, h / 2))
    P = [(px * SS, py * SS) for px, py in pts]
    d.line(P, fill=120, width=10 * SS)
    d.line(P, fill=255, width=3 * SS)
    for px, py in pts[1:-1]:
        if rng.random() < 0.6:
            ang = rng.uniform(0, 6.28)
            L = rng.uniform(10, 26)
            d.line([(px * SS, py * SS), ((px + math.cos(ang) * L) * SS, (py + math.sin(ang) * L) * SS)], fill=200, width=2 * SS)
    a = np.asarray(img.filter(ImageFilter.GaussianBlur(0.5 * SS)), float) / 255
    lum = np.where(a > 0.62, 1.0, np.where(a > 0.33, 0.8, 0.55))
    return rgba(lum, np.clip(a * 1.6, 0, 1), (w, h))


def shard_flip(n=4, px=128, seed=111, long=False, glass=True):
    """A tumbling shard catching the light (Rift glass / Ice shards): a diamond seen at changing angles."""
    frames = []
    rng = random.Random(seed)
    for i in range(n * n):
        u = i / (n * n)
        P = px * SS
        img = Image.new("L", (P, P), 0)
        d = ImageDraw.Draw(img)
        c = P / 2
        turn = math.cos(2 * math.pi * u)
        L = P * (0.42 if long else 0.34)
        wdt = P * (0.1 if long else 0.18) * (0.25 + 0.75 * abs(turn))
        ang = 2 * math.pi * u * 0.5 + 0.6
        ca, sa = math.cos(ang), math.sin(ang)
        pts = [(0, -L), (wdt, -L * 0.1), (0, L), (-wdt, L * 0.15)]
        poly = [(c + x * ca - y * sa, c + x * sa + y * ca) for x, y in pts]
        d.polygon(poly, fill=150 if glass else 170)
        half = [poly[0], poly[1], poly[2]] if turn > 0 else [poly[0], poly[3], poly[2]]
        d.polygon(half, fill=210)
        d.line(poly + [poly[0]], fill=255, width=2 * SS)
        a = np.asarray(img, float) / 255
        glint = 1.0 if abs(turn) > 0.92 else 0.0
        lum = np.where(a > 0.95, 1.0, np.where(a > 0.7, 0.85, 0.6)) + glint * 0.15
        frames.append(rgba(np.clip(lum, 0, 1), np.clip(a * 1.5, 0, 1), (px, px)))
    return grid(frames, n)


def tear_flip(n=8, px=128, seed=121):
    """Rift: space tearing open, a ragged lens slit that rips wide (white inside, bright edge), then snaps shut."""
    frames = []
    rng = random.Random(seed)
    jag = [1 + rng.uniform(-0.15, 0.1) for _ in range(40)]
    for i in range(n * n):
        u = i / (n * n - 1)
        P = px * SS
        x, y = coords(P)
        openk = smooth(np.array(u), 0.0, 0.3) * (1 - smooth(np.array(u), 0.8, 0.98))
        ang = np.arctan2(y, x)
        j = np.interp((ang + np.pi) / (2 * np.pi) * 40, np.arange(41), jag + [jag[0]])
        half_w = 0.02 + 0.16 * float(openk)
        lens = (1 - (y / 0.42) ** 2).clip(0, 1) ** 0.6 * half_w * j
        f = (lens - np.abs(x)) / 0.02
        inner = np.clip(f, 0, 1)
        edge = np.clip(1 - np.abs(f) / 1.6, 0, 1)
        lum = np.maximum(inner * 1.0, edge * 0.85)
        a = np.clip(np.maximum(inner, edge), 0, 1)
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


def glint(px=64, thin=0.05):
    """A sharp four-point glint (long thin cross)."""
    P = px * SS
    x, y = coords(P)
    f = thin / (np.abs(x) + 0.004) * np.clip(1 - np.abs(y) * 2.2, 0, 1) + thin / (np.abs(y) + 0.004) * np.clip(1 - np.abs(x) * 2.2, 0, 1)
    lum, a = toon(f, [0.8, 2.5], [0.8, 1.0], soft=0.2)
    return rgba(lum, a, (px, px))


def polygon_ring(sides=6, px=256, width=0.06):
    """A polygonal ring (Rift hex gate)."""
    P = px * SS
    x, y = coords(P)
    ang = np.arctan2(y, x)
    r = np.sqrt(x ** 2 + y ** 2)
    k = math.pi / sides
    rp = r * np.cos(((ang + k) % (2 * k)) - k) / math.cos(k)
    f = 1 - np.abs(rp - 0.4) / width
    lum, a = toon(f, [0.0, 0.5], [0.75, 1.0], soft=0.06)
    return rgba(lum, a, (px, px))


def dark_strip(w=512, h=128, seed=131):
    """Void: dark matter flowing along the strip: a near-black body with bright violet edges and streaks."""
    W, H = w * SS, h * SS
    y = np.linspace(-1, 1, H)[:, None]
    n1 = tile_noise(H, W, 3, seed)
    n2 = tile_noise(H, W, 8, seed + 1)
    edge = 1 - np.abs(y)
    f = edge * 1.3 + (n1 - 0.5) * 0.7
    body = smooth(f, 0.3, 0.36)
    rim = body * (1 - smooth(f, 0.42, 0.5))
    streak = (n2 > 0.72) * body
    lum = 0.08 * body + 0.85 * np.maximum(rim, streak * 0.8)
    return rgba(lum, body, (w, h))


def swirl_flip(n=8, px=128, seed=141, arms=4, implode=True):
    """A vortex: spiral arms turning and tightening into the centre (Void swirl / Wind swirl)."""
    frames = []
    for i in range(n * n):
        u = i / (n * n - 1)
        P = px * SS
        x, y = coords(P)
        r = np.sqrt(x ** 2 + y ** 2) + 1e-4
        ang = np.arctan2(y, x)
        tight = 4 + 6 * u if implode else 5
        spiral = np.cos(arms * ang + tight * np.log(r * 6) * 2 - u * 10)
        R = (0.46 * (1 - 0.6 * u) if implode else 0.44)
        env = np.clip(1 - r / R, 0, 1) * smooth(r, 0.02, 0.06)
        f = (spiral * 0.5 + 0.5) * env * 2.2
        lum, a = toon(f, [0.35, 0.8], [0.6, 1.0], soft=0.06)
        if implode:
            a = a * (1 - smooth(np.array(u), 0.8, 1.0))
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


def rim_smoke(n=4, px=128, seed=151):
    """Void: black smoke with a violet rim (the rim band takes the colour)."""
    frames = []
    P = px * SS
    rng = random.Random(seed)
    blobs = [(rng.uniform(-0.14, 0.14), rng.uniform(-0.14, 0.14), rng.uniform(0.1, 0.18)) for _ in range(6)]
    warp = tile_noise(P, P, 5, seed)
    for i in range(n * n):
        u = i / (n * n - 1)
        x, y = coords(P)
        f = np.zeros_like(x)
        for bx, by, r in blobs:
            rr = r * (0.5 + 0.7 * u)
            f += rr ** 2 / ((x - bx * (1 + u)) ** 2 + (y - by * (1 + u)) ** 2 + 1e-4)
        f = f * (1 + 0.8 * (np.roll(warp, int(u * P * 0.3), 0) - 0.5)) - u * 0.6
        body = smooth(f, 0.58, 0.64)
        rim = body * (1 - smooth(f, 0.8, 0.9))
        lum = 0.06 + 0.8 * rim
        frames.append(rgba(lum, body * (1 - smooth(np.array(u), 0.6, 1.0) * 0.85), (px, px)))
    return grid(frames, n)


def mote(px=64):
    """A soft mote with a bright ring (Void / spores)."""
    P = px * SS
    x, y = coords(P)
    r = np.sqrt(x ** 2 + y ** 2)
    ring = np.clip(1 - np.abs(r - 0.18) / 0.05, 0, 1)
    core = np.clip(1 - r / 0.12, 0, 1)
    halo = np.clip(1 - r / 0.45, 0, 1) ** 2 * 0.5
    lum = np.maximum.reduce([ring, core * 0.7, halo])
    return rgba(np.where(lum > 0.6, 1.0, np.where(lum > 0.3, 0.75, 0.5)), np.clip(np.maximum.reduce([ring, core, halo]), 0, 1), (px, px))


def leaf_flip(n=4, px=128, petal=False, seed=161):
    """A leaf (or petal) spinning in the air: the outline narrows and flips as it turns."""
    frames = []
    for i in range(n * n):
        u = i / (n * n)
        P = px * SS
        x, y = coords(P)
        ang = 2 * math.pi * u * 0.5 + 0.4
        ca, sa = math.cos(ang), math.sin(ang)
        lx, ly = x * ca + y * sa, -x * sa + y * ca
        flip = 0.2 + 0.8 * abs(math.cos(2 * math.pi * u))
        if petal:
            f = 1 - ((lx / (0.18 * flip)) ** 2 + ((ly + 0.05) / 0.3) ** 2) - 0.6 * np.clip(ly - 0.2, 0, 1)
        else:
            L = 0.38
            half = 0.16 * flip * np.clip(1 - (ly / L) ** 2, 0, 1) ** 0.8
            f = (half - np.abs(lx)) / 0.04
        vein = (np.abs(lx) < 0.012 * SS / 2) * (np.abs(ly) < 0.32) if not petal else np.zeros_like(lx, bool)
        side = lx * math.cos(2 * math.pi * u) > 0
        lum = np.where(side, 0.85, 0.65)
        lum = np.where(vein, 1.0, lum)
        a = smooth(f, 0, 0.3)
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


def vine_strip(w=512, h=128, seed=171):
    """Nature: a flowing green stream with a twisting vine line and leaves budding off it, tileable."""
    rng = random.Random(seed)
    W, H = w * SS, h * SS
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    pts = [((x / 200) * w, h / 2 + math.sin(2 * math.pi * x / 200 * 2) * h * 0.22) for x in range(201)]
    d.line([(px_ * SS, py_ * SS) for px_, py_ in pts], fill=255, width=4 * SS)
    for k in range(10):
        x0 = (k + rng.random()) * w / 10
        y0 = h / 2 + math.sin(2 * math.pi * x0 / w * 2) * h * 0.22
        side = 1 if k % 2 else -1
        leaf = [(x0, y0), (x0 + 14, y0 + side * 10), (x0 + 30, y0 + side * 6), (x0 + 16, y0 + side * 2)]
        d.polygon([(a * SS, b * SS) for a, b in leaf], fill=200)
    a = np.asarray(img, float) / 255
    y = np.linspace(-1, 1, H)[:, None]
    n1 = tile_noise(H, W, 4, seed)
    body = smooth((1 - np.abs(y)) * 1.2 + (n1 - 0.5) * 0.5, 0.35, 0.42)
    lum = np.maximum(body * 0.55, a)
    lum = np.where(lum > 0.9, 1.0, np.where(lum > 0.6, 0.8, lum))
    return rgba(lum, np.clip(np.maximum(body * 0.85, a), 0, 1), (w, h))


def bloom_flip(n=8, px=128, petals=8):
    """Nature: a flower of light blooming open, then its petals scattering away."""
    frames = []
    for i in range(n * n):
        u = i / (n * n - 1)
        P = px * SS
        x, y = coords(P)
        r = np.sqrt(x ** 2 + y ** 2)
        ang = np.arctan2(y, x)
        openk = float(smooth(np.array(u), 0, 0.35))
        scatter = float(smooth(np.array(u), 0.55, 1.0))
        R = 0.12 + 0.24 * openk + 0.12 * scatter
        petal = np.cos(petals * ang / 2) ** 2
        shape = R * (0.45 + 0.55 * petal) - r
        gap = 0.06 * scatter * (np.cos(petals * ang / 2) ** 2 < 0.5)
        f = shape / 0.03 - gap * 40
        centre = np.clip(1 - r / (0.06 + 0.02 * openk), 0, 1)
        lum = np.where(centre > 0, 1.0, np.where(r < R * 0.6, 0.85, 0.65))
        a = np.clip(np.maximum(smooth(f, 0, 0.5), centre), 0, 1) * (1 - smooth(np.array(u), 0.8, 1.0))
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


def ice_strip(w=512, h=128, seed=181):
    """Ice: a freezing stream: sharp diagonal crystal streaks over a pale frosted body, tileable."""
    rng = random.Random(seed)
    W, H = w * SS, h * SS
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    for _ in range(40):
        x0 = rng.uniform(0, w)
        y0 = rng.uniform(0.2, 0.8) * h
        L = rng.uniform(20, 60)
        ang = rng.choice((0.35, -0.35)) + rng.uniform(-0.1, 0.1)
        for off in (0, w, -w):
            d.line([((x0 + off) * SS, y0 * SS), ((x0 + off + math.cos(ang) * L) * SS, (y0 + math.sin(ang) * L * 0.4) * SS)], fill=255, width=2 * SS)
    a = np.asarray(img, float) / 255
    y = np.linspace(-1, 1, H)[:, None]
    n1 = tile_noise(H, W, 6, seed)
    body = smooth((1 - np.abs(y)) * 1.25 + (n1 - 0.5) * 0.45, 0.38, 0.45)
    lum = np.maximum(body * (0.6 + 0.2 * (n1 > 0.55)), a)
    lum = np.where(lum > 0.9, 1.0, lum)
    return rgba(lum, np.clip(np.maximum(body * 0.8, a), 0, 1), (w, h))


def frost_flip(n=8, px=128, arms=6, seed=191):
    """Ice: a frost burst: crystalline spikes shooting out like a snowflake, then crumbling away."""
    frames = []
    rng = random.Random(seed)
    lens = [rng.uniform(0.7, 1.0) for _ in range(arms * 2)]
    for i in range(n * n):
        u = i / (n * n - 1)
        P = px * SS
        img = Image.new("L", (P, P), 0)
        d = ImageDraw.Draw(img)
        c = P / 2
        grow = float(smooth(np.array(u), 0, 0.35))
        for k in range(arms * 2):
            ang = math.pi * 2 * k / (arms * 2)
            L = P * 0.44 * lens[k] * grow * (1 if k % 2 == 0 else 0.55)
            wdt = P * 0.03 * (1 if k % 2 == 0 else 0.6)
            tip = (c + math.cos(ang) * L, c + math.sin(ang) * L)
            sideA = (c + math.cos(ang + 1.57) * wdt, c + math.sin(ang + 1.57) * wdt)
            sideB = (c - math.cos(ang + 1.57) * wdt, c - math.sin(ang + 1.57) * wdt)
            d.polygon([sideA, tip, sideB], fill=220)
            if k % 2 == 0:
                for b in (0.45, 0.7):
                    bp = (c + math.cos(ang) * L * b, c + math.sin(ang) * L * b)
                    for s_ in (0.7, -0.7):
                        d.line([bp, (bp[0] + math.cos(ang + s_) * L * 0.22, bp[1] + math.sin(ang + s_) * L * 0.22)], fill=255, width=2 * SS)
        d.ellipse([c - P * 0.07 * grow, c - P * 0.07 * grow, c + P * 0.07 * grow, c + P * 0.07 * grow], fill=255)
        a = np.asarray(img, float) / 255
        n_ = tile_noise(P, P, 10, seed + i % 3)
        crumble = float(smooth(np.array(u), 0.6, 1.0))
        a = a * (n_ > crumble * 0.9)
        lum = np.where(a > 0.95, 1.0, 0.8)
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


def snowflake(px=64):
    P = px * SS
    img = Image.new("L", (P, P), 0)
    d = ImageDraw.Draw(img)
    c = P / 2
    for k in range(6):
        ang = math.pi / 3 * k
        e = (c + math.cos(ang) * P * 0.42, c + math.sin(ang) * P * 0.42)
        d.line([(c, c), e], fill=255, width=3 * SS)
        for b in (0.5, 0.75):
            bp = (c + math.cos(ang) * P * 0.42 * b, c + math.sin(ang) * P * 0.42 * b)
            for s_ in (0.8, -0.8):
                d.line([bp, (bp[0] + math.cos(ang + s_) * P * 0.12, bp[1] + math.sin(ang + s_) * P * 0.12)], fill=230, width=2 * SS)
    a = np.asarray(img, float) / 255
    return rgba(np.where(a > 0.95, 1.0, 0.85), a, (px, px))


def gust_strip(w=512, h=128, seed=201):
    """Wind: thin streaks of rushing air (broken lines at different heights), tileable."""
    rng = random.Random(seed)
    img = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(img)
    for _ in range(26):
        y0 = rng.uniform(0.15, 0.85) * h
        x0 = rng.uniform(0, w)
        L = rng.uniform(60, 220)
        curve = rng.uniform(-8, 8)
        pts = [(x0 + L * t, y0 + curve * math.sin(math.pi * t)) for t in np.linspace(0, 1, 12)]
        for off in (0, w, -w):
            d.line([((px_ + off) * SS, py_ * SS) for px_, py_ in pts], fill=rng.choice((160, 220, 255)), width=int(rng.uniform(1.5, 3.5) * SS))
    a = np.asarray(img.filter(ImageFilter.GaussianBlur(0.6 * SS)), float) / 255
    y = np.linspace(-1, 1, h * SS)[:, None]
    a = a * np.clip(1.3 - np.abs(y) * 1.2, 0, 1)
    return rgba(np.where(a > 0.7, 1.0, 0.75), np.clip(a * 1.4, 0, 1), (w, h))


def crescent_flip(n=8, px=128):
    """Wind: a crescent slash sweeping round and thinning away."""
    frames = []
    for i in range(n * n):
        u = i / (n * n - 1)
        P = px * SS
        x, y = coords(P)
        r = np.sqrt(x ** 2 + y ** 2)
        ang = np.arctan2(y, x)
        sweep = -2.6 + 4.2 * float(smooth(np.array(u), 0, 0.4))
        a0 = -2.6
        inside = (ang > a0) & (ang < sweep)
        t = np.clip((ang - a0) / (sweep - a0 + 1e-4), 0, 1)
        thick = 0.07 * np.sin(np.pi * t) * (1 - 0.8 * float(smooth(np.array(u), 0.5, 1.0)))
        f = (thick - np.abs(r - 0.36)) / 0.01 * inside
        lum = np.where(np.abs(r - 0.36) < thick * 0.4, 1.0, 0.75)
        a = smooth(f, 0, 0.6) * (1 - float(smooth(np.array(u), 0.75, 1.0)))
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


def dust_flip(n=4, px=128, seed=211, tone_=(0.55, 0.7)):
    """A soft dust puff (Wind grit / Earth dust): two gentle bands, billowing and thinning."""
    frames = []
    P = px * SS
    rng = random.Random(seed)
    blobs = [(rng.uniform(-0.16, 0.16), rng.uniform(-0.1, 0.12), rng.uniform(0.1, 0.17)) for _ in range(7)]
    warp = tile_noise(P, P, 5, seed)
    for i in range(n * n):
        u = i / (n * n - 1)
        x, y = coords(P)
        f = np.zeros_like(x)
        for bx, by, r in blobs:
            rr = r * (0.45 + 0.75 * u)
            f += rr ** 2 / ((x - bx * (1 + 1.2 * u)) ** 2 + (y - by * (1 + u) - u * 0.06) ** 2 + 1e-4)
        f = f * (1 + 0.9 * (np.roll(warp, int(u * P * 0.4), 1) - 0.5)) - u * 0.5
        f -= smooth(np.maximum(np.abs(x), np.abs(y)), 0.38, 0.48) * 3
        lum, a = toon(f, [0.6, 1.0], list(tone_), soft=0.07)
        a = a * (1 - smooth(np.array(u), 0.55, 1.0) * 0.9)
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


def rock_strip(w=512, h=128, seed=221):
    """Earth: tumbling rock silhouettes with molten cracks glowing through, tileable."""
    rng = random.Random(seed)
    W, H = w * SS, h * SS
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    for _ in range(26):
        cx, cy = rng.uniform(0, w), rng.uniform(0.2, 0.8) * h
        r = rng.uniform(16, 34)
        pts = [(cx + math.cos(a) * r * rng.uniform(0.7, 1.1), cy + math.sin(a) * r * rng.uniform(0.7, 1.1)) for a in np.linspace(0, 6.28, 7)[:-1]]
        for off in (0, w, -w):
            d.polygon([((px_ + off) * SS, py_ * SS) for px_, py_ in pts], fill=rng.choice((90, 110, 130)))
    rock = np.asarray(img, float) / 255
    y = np.linspace(-1, 1, H)[:, None]
    n1 = tile_noise(H, W, 5, seed)
    core = smooth((1 - np.abs(y) / 0.1) + (n1 - 0.5) * 0.6, 0.0, 0.15) * (rock < 0.05)
    lum = np.where(core > 0.5, 1.0, rock * 1.1 + 0.15 * (rock > 0))
    a = np.clip(np.maximum(rock * 1.6, core), 0, 1)
    return rgba(lum, a, (w, h))


def rock_flip(n=4, px=128, seed=231):
    """Earth: a rock chunk tumbling (an irregular polygon turning, with a lit face and a shadow face)."""
    frames = []
    rng = random.Random(seed)
    base = [(math.cos(a) * rng.uniform(0.7, 1.0), math.sin(a) * rng.uniform(0.7, 1.0)) for a in np.linspace(0, 6.28, 8)[:-1]]
    for i in range(n * n):
        u = i / (n * n)
        P = px * SS
        img = Image.new("L", (P, P), 0)
        d = ImageDraw.Draw(img)
        c = P / 2
        ang = 2 * math.pi * u
        sq = 0.7 + 0.3 * math.cos(ang * 2)
        pts = [(c + (x * math.cos(ang) - y * math.sin(ang)) * P * 0.36, c + (x * math.sin(ang) + y * math.cos(ang)) * P * 0.36 * sq) for x, y in base]
        d.polygon(pts, fill=140)
        d.polygon([pts[0], pts[1], pts[2], (c, c)], fill=200)
        d.polygon([pts[4], pts[5], (c, c)], fill=100)
        d.line(pts + [pts[0]], fill=60, width=2 * SS)
        a = np.asarray(img, float) / 255
        frames.append(rgba(a, (a > 0).astype(float), (px, px)))
    return grid(frames, n)


def crack_decal(px=256, seed=241):
    """Earth: radial ground cracks (glowing where the molten band is)."""
    rng = random.Random(seed)
    P = px * SS
    img = Image.new("L", (P, P), 0)
    d = ImageDraw.Draw(img)
    c = P / 2
    for k in range(9):
        ang = 2 * math.pi * k / 9 + rng.uniform(-0.2, 0.2)
        x, y = c, c
        for s_ in range(6):
            ang += rng.uniform(-0.4, 0.4)
            nx, ny = x + math.cos(ang) * P * 0.07, y + math.sin(ang) * P * 0.07
            d.line([(x, y), (nx, ny)], fill=255, width=int((5 - s_ * 0.7) * SS))
            x, y = nx, ny
    a = np.asarray(img.filter(ImageFilter.GaussianBlur(0.6 * SS)), float) / 255
    return rgba(np.where(a > 0.7, 1.0, 0.75), np.clip(a * 1.5, 0, 1), (px, px))


def water_strip(w=512, h=128, seed=251):
    """Water: a rushing stream: deep body, lighter flow bands, white foam streaks and bubbles, tileable."""
    rng = random.Random(seed)
    W, H = w * SS, h * SS
    y = np.linspace(-1, 1, H)[:, None]
    n1 = tile_noise(H, W, 3, seed)
    streak = tile_noise(max(2, H // 10), W, 8, seed + 2)
    streak = np.asarray(Image.fromarray((streak * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), float) / 255
    f = (1 - np.abs(y) ** 1.6) * 1.2 + (n1 - 0.5) * 0.5
    body = smooth(f, 0.3, 0.36)
    lum = 0.55 * body + 0.25 * body * (streak > 0.55) + 0.2 * body * (streak > 0.72)
    img = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(img)
    for _ in range(30):
        bx, by, br = rng.uniform(0, w), rng.uniform(0.25, 0.75) * h, rng.uniform(1.5, 4)
        for off in (0, w, -w):
            d.ellipse([((bx + off - br) * SS), (by - br) * SS, (bx + off + br) * SS, (by + br) * SS], outline=255, width=SS)
    bub = np.asarray(img, float) / 255
    lum = np.maximum(lum, bub)
    return rgba(lum, np.clip(np.maximum(body, bub), 0, 1), (w, h))


def splash_flip(n=8, px=128, seed=261):
    """Water: a crown splash: a cup of water flaring up and out with spiky tips, droplets flicking off
    the rim and falling back."""
    frames = []
    rng = random.Random(seed)
    tips = 9
    drops = [(rng.choice((-1, 1)) * rng.uniform(0.7, 1.0), rng.uniform(0.5, 1.0), rng.uniform(0.018, 0.032)) for _ in range(16)]
    for i in range(n * n):
        u = i / (n * n - 1)
        P = px * SS
        x, y = coords(P)
        rise = math.sin(math.pi * min(1.0, u * 1.15)) if u < 0.87 else 0.0
        w = 0.14 + 0.26 * u
        H = 0.55 * rise
        base = -0.42
        ax = np.abs(x) / w
        spikes = 0.75 + 0.25 * np.cos(x / w * math.pi * tips / 2) ** 8
        top = base + H * np.clip(ax, 0, 1) ** 1.6 * spikes + 0.04 * rise
        sheet = (ax <= 1) & (y >= base) & (y <= top)
        inner = sheet & (y <= base + (top - base) * 0.55) & (ax < 0.85)
        f = sheet.astype(float)
        lum = np.where(inner, 0.7, 0.95)
        for dx, dy, r in drops:
            t = u * 1.3
            px_ = dx * (w + 0.25 * t)
            py_ = base + H * 0.9 + dy * 0.8 * t - 1.3 * t * t
            hit = np.sqrt((x - px_) ** 2 + (y - py_) ** 2) < r
            f = np.maximum(f, hit.astype(float))
            lum = np.where(hit, 1.0, lum)
        a = np.asarray(Image.fromarray((f * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.7 * SS)), float) / 255
        frames.append(rgba(lum, np.clip(a * 1.4, 0, 1) * (1 - smooth(np.array(u), 0.85, 1.0)), (px, px)))
    return grid(frames, n)


def droplet(px=64):
    P = px * SS
    x, y = coords(P)
    f = 1 - ((x / 0.2) ** 2 + ((y + 0.06) / 0.26) ** 2) - 0.8 * np.clip(y, 0, None) ** 2 * 10
    hi = np.clip(1 - ((x + 0.07) ** 2 + (y + 0.0) ** 2) / 0.003, 0, 1)
    lum = np.where(hi > 0.2, 1.0, 0.7)
    return rgba(lum, smooth(f, 0, 0.2), (px, px))


def ki_strip(w=512, h=128, seed=271):
    """Energy: a ki wave: a blazing core with smooth energy filaments streaming along it, tileable."""
    W, H = w * SS, h * SS
    y = np.linspace(-1, 1, H)[:, None]
    x = np.linspace(0, 1, W)[None, :]
    rng = random.Random(seed)
    fil = np.zeros((H, W))
    for k in range(6):
        ph = rng.uniform(0, 6.28)
        amp = rng.uniform(0.25, 0.7)
        yk = amp * np.sin(2 * np.pi * x * rng.choice((1, 2, 3)) + ph)
        fil = np.maximum(fil, np.clip(1 - np.abs(y - yk) / 0.05, 0, 1))
    n1 = tile_noise(H, W, 4, seed)
    body = (1 - np.abs(y) ** 1.3) * 1.2 + (n1 - 0.5) * 0.3
    f = np.maximum(body, fil * 1.1)
    lum, a = toon(f, [0.35, 0.75, 1.05], [0.55, 0.82, 1.0], soft=0.05)
    return rgba(lum, a, (w, h))


def ki_burst(n=8, px=128):
    """Energy: a ki explosion: a white flash swelling into a glowing sphere with a shock ring and rays."""
    frames = []
    for i in range(n * n):
        u = i / (n * n - 1)
        P = px * SS
        x, y = coords(P)
        r = np.sqrt(x ** 2 + y ** 2)
        ang = np.arctan2(y, x)
        R = 0.08 + 0.3 * (1 - (1 - u) ** 2)
        sphere = (R - r) / 0.03
        ring_r = 0.12 + 0.34 * u
        ring = 1 - np.abs(r - ring_r) / (0.03 * (1 - u) + 0.01)
        rays = (np.cos(ang * 12) > 0.93) * np.clip(1 - r / (0.46 * (0.4 + 0.6 * u)), 0, 1) * (1 - u)
        f = np.maximum.reduce([sphere * (1 - u * 0.7), ring, rays * 2])
        lum, a = toon(f, [0.1, 0.6, 1.3], [0.6, 0.85, 1.0], soft=0.06)
        a = a * (1 - smooth(np.array(u), 0.7, 1.0))
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


def twinkle_flip(n=4, px=64):
    """Energy: a soft star that twinkles (looping)."""
    frames = []
    for i in range(n * n):
        u = i / (n * n)
        P = px * SS
        x, y = coords(P)
        k = 0.6 + 0.4 * math.cos(2 * math.pi * u)
        f = 0.03 * k / (np.abs(x * y) * 40 + np.sqrt(x ** 2 + y ** 2) * 0.5 + 0.01)
        lum, a = toon(f, [0.5, 1.5], [0.8, 1.0], soft=0.12)
        frames.append(rgba(lum, a, (px, px)))
    return grid(frames, n)


def energy_orb(n=4, px=128):
    """Energy: an orb with swirling bands (looping), for the Spirit Bomb and ki blasts."""
    frames = []
    for i in range(n * n):
        u = i / (n * n)
        P = px * SS
        x, y = coords(P)
        r = np.sqrt(x ** 2 + y ** 2)
        ang = np.arctan2(y, x)
        bands = np.sin(ang * 3 + r * 18 - 2 * math.pi * u) * 0.5 + 0.5
        body = np.clip((0.42 - r) / 0.03, 0, 1)
        lum = np.where(r < 0.18, 1.0, np.where(bands > 0.6, 0.9, 0.7))
        frames.append(rgba(lum * body + (1 - body) * 0.6, np.clip(body + np.clip(1 - r / 0.5, 0, 1) ** 3 * 0.4, 0, 1), (px, px)))
    return grid(frames, n)


def build_batch2():
    print("Rift")
    save(facet_strip(), "R_Stream")
    save(crack_strip(281), "R_Crack1")
    save(crack_strip(282), "R_Crack2")
    save(shard_flip(seed=111), "R_Shard4")
    save(tear_flip(), "R_Tear8")
    save(glint(thin=0.04), "R_Glint")
    save(polygon_ring(6), "R_Hex")
    print("Void")
    save(dark_strip(), "V_Stream")
    save(swirl_flip(seed=141, arms=4, implode=True), "V_Swirl8")
    save(rim_smoke(), "V_Smoke4")
    save(mote(), "V_Mote")
    save(ring(seed=291, jag=0.0, width=0.03), "V_Ring")
    print("Nature")
    save(leaf_flip(petal=False), "N_Leaf4")
    save(leaf_flip(petal=True, seed=162), "N_Petal4")
    save(vine_strip(), "N_Stream")
    save(bloom_flip(), "N_Bloom8")
    save(mote(48), "N_Spore")
    print("Ice")
    save(ice_strip(), "I_Stream")
    save(shard_flip(seed=301, long=True), "I_Shard4")
    save(frost_flip(), "I_Frost8")
    save(smoke(seed=311, dark=0.72), "I_Mist4")
    save(snowflake(), "I_Flake")
    print("Wind")
    save(gust_strip(), "W_Stream")
    save(swirl_flip(n=4, seed=321, arms=2, implode=False), "W_Swirl4")
    save(crescent_flip(), "W_Crescent8")
    save(dust_flip(seed=331, tone_=(0.62, 0.78)), "W_Dust4")
    save(polygon_ring(24, width=0.025), "W_Ring")
    print("Earth")
    save(rock_strip(), "G_Stream")
    save(rock_flip(), "G_Rock4")
    save(dust_flip(n=8, seed=341, tone_=(0.5, 0.66)), "G_Dust8")
    save(crack_decal(), "G_Crack")
    print("Water")
    save(water_strip(), "A_Stream")
    save(splash_flip(), "A_Splash8")
    save(droplet(), "A_Drop")
    save(swirl_flip(n=4, seed=351, arms=6, implode=False), "A_Foam4")
    save(ring(seed=361, jag=0.4, width=0.04), "A_Ring")
    print("Energy")
    save(ki_strip(), "K_Stream")
    save(ki_burst(), "K_Burst8")
    save(twinkle_flip(), "K_Twinkle4")
    save(energy_orb(), "K_Orb4")
    save(ring(seed=371, jag=0.0, width=0.05), "K_Ring")


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
    build_batch2()
    contact_sheet()


if __name__ == "__main__":
    main()
