"""Generates the particle / beam / trail textures for Eternium's auras.

Every texture is white-on-transparent (with grey shading for detail), so a ParticleEmitter's,
Beam's or Trail's Color tints it to whatever the player picks. Run from the repo root:
    python tools/build_aura_textures.py
Writes Auras/textures/<name>.png plus Auras/textures/_contact_sheet.png.
"""
import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "Auras" / "textures"
S = 256  # final size
SS = 4  # supersampling for clean edges


def canvas(w=S, h=S):
    return Image.new("L", (w * SS, h * SS), 0)


def finish(alpha, shade=None, w=S, h=S, blur=0.0):
    """alpha: supersampled L image (coverage). shade: optional L image (brightness), else white."""
    a = alpha.resize((w, h), Image.LANCZOS)
    if blur:
        a = a.filter(ImageFilter.GaussianBlur(blur))
    if shade is None:
        rgb = Image.new("L", (w, h), 255)
    else:
        rgb = shade.resize((w, h), Image.LANCZOS)
    return Image.merge("RGBA", (rgb, rgb, rgb, a))


def radial(w=S, h=S, power=2.0, cx=0.5, cy=0.5, sx=0.5, sy=0.5):
    y, x = np.mgrid[0:h, 0:w]
    d = np.sqrt(((x / w - cx) / sx) ** 2 + ((y / h - cy) / sy) ** 2)
    return np.clip(1 - d, 0, 1) ** power


def to_img(arr):
    return Image.fromarray(np.clip(arr * 255, 0, 255).astype(np.uint8), "L")


def noise(w, h, scale, seed):
    rng = np.random.default_rng(seed)
    small = rng.random((max(2, h // scale), max(2, w // scale)))
    img = Image.fromarray((small * 255).astype(np.uint8), "L").resize((w, h), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32) / 255


def poly(draw, pts, fill=255):
    draw.polygon([(x * SS, y * SS) for x, y in pts], fill=fill)


def line(draw, pts, width, fill=255):
    draw.line([(x * SS, y * SS) for x, y in pts], fill=fill, width=int(width * SS), joint="curve")


def flame_shape(cx, base, height, width, lean=0.0, wobble=0.0, seed=0, n=48):
    """Outline of a flame tongue: a rounded bulb at the bottom tapering to a curling tip.
    `wobble` adds smooth waves to the sides (no jitter)."""
    left, right = [], []
    for i in range(n + 1):
        t = i / n
        bulb = math.sqrt(max(0.0, 1 - ((t - 0.22) / 0.22) ** 2)) if t < 0.22 else 1.0
        w = width / 2 * bulb * (1 - t) ** 1.1 * (1 + 0.12 * math.sin(t * math.pi * 3 + seed) * (wobble / 4))
        x = cx + lean * height * t ** 2.2 + wobble * math.sin(t * math.pi * 2.5 + seed) * t
        y = base - t * height
        left.append((x - w, y))
        right.append((x + w, y))
    return left + right[::-1]


def flame_cluster(d, cx, base, height, width, lean, seed, fill=255):
    """A main tongue with two smaller licks curling off its sides."""
    poly(d, flame_shape(cx, base, height, width, lean, 4, seed), fill)
    poly(d, flame_shape(cx - width * 0.28, base - height * 0.08, height * 0.55, width * 0.45, lean - 0.25, 3, seed + 1), fill)
    poly(d, flame_shape(cx + width * 0.3, base - height * 0.05, height * 0.65, width * 0.42, lean + 0.3, 3, seed + 2), fill)


# ---------------------------------------------------------------- shared

def glow():
    return finish(to_img(radial(power=2.2)).resize((S * SS, S * SS)))


# ---------------------------------------------------------------- Limit Breaker: rising helix of power

def lb_trail():
    """Trail texture (U along the trail): a bright head streaking into fine fading filaments."""
    w, h = 512, 64
    y, x = np.mgrid[0:h, 0:w]
    u = x / w
    v = np.abs(y / h - 0.5) * 2
    core = np.clip(1 - v / 0.35, 0, 1) ** 1.5
    fil = 0.0
    rng = np.random.default_rng(3)
    for _ in range(7):
        off = rng.uniform(-0.7, 0.7)
        fil = np.maximum(fil, np.clip(1 - np.abs(v * np.sign(y / h - 0.5) - off) / 0.06, 0, 1) * rng.uniform(0.4, 1))
    a = np.maximum(core, fil * 0.8) * (u ** 0.6)
    shade = 0.55 + 0.45 * core
    img = Image.merge("RGBA", (to_img(shade), to_img(shade), to_img(shade), to_img(a)))
    return img


def lb_streak():
    """Particle texture for VelocityParallel particles: a vertical streak, brightest at the top."""
    return lb_trail().rotate(90, expand=True).resize((128, 512))


def lb_chevron():
    img = canvas()
    d = ImageDraw.Draw(img)
    poly(d, [(128, 40), (200, 130), (172, 130), (128, 80), (84, 130), (56, 130)])
    poly(d, [(128, 120), (180, 190), (160, 190), (128, 150), (96, 190), (76, 190)], 150)
    return finish(img, blur=1.2)


def lb_ring():
    a = radial(power=1)
    r = np.clip(1 - np.abs(a - 0.12) / 0.06, 0, 1) ** 1.5
    r += np.clip(1 - np.abs(a - 0.2) / 0.025, 0, 1) * 0.5
    return finish(to_img(np.clip(r, 0, 1)).resize((S * SS, S * SS)))


def lb_flare():
    y, x = np.mgrid[0:S, 0:S]
    dx, dy = np.abs(x / S - 0.5), np.abs(y / S - 0.5)
    star = np.clip(1 - (dx * 18) ** 0.6 - dy * 2.1, 0, 1) + np.clip(1 - (dy * 18) ** 0.6 - dx * 2.1, 0, 1)
    a = np.clip(star + radial(power=6) * 0.9, 0, 1)
    return finish(to_img(a).resize((S * SS, S * SS)))


# ---------------------------------------------------------------- Void Current: dark flame drawn down into a pool

def vc_flame():
    img = canvas()
    d = ImageDraw.Draw(img)
    flame_cluster(d, 128, 248, 230, 130, 0.08, 1)
    a = img.filter(ImageFilter.GaussianBlur(3 * SS))
    # dark core, lighter rim: so a black Glow-edge colour can sit round a coloured body
    inner = np.asarray(img.resize((S, S)).filter(ImageFilter.GaussianBlur(22)), dtype=np.float32) / 255
    shade = to_img(0.3 + 0.7 * (1 - inner ** 1.5))
    return finish(a, shade.resize((S * SS, S * SS)))


def vc_tendril():
    """Beam texture: a writhing ribbon of shadow."""
    w, h = 512, 96
    y, x = np.mgrid[0:h, 0:w]
    u, v = x / w, y / h
    centre = 0.5 + 0.18 * np.sin(u * math.pi * 6) * np.sin(u * math.pi)
    width = 0.12 + 0.18 * np.sin(u * math.pi) ** 0.5
    a = np.clip(1 - np.abs(v - centre) / width, 0, 1) ** 1.2
    a *= 0.6 + 0.4 * noise(w, h, 24, 5)
    return Image.merge("RGBA", (to_img(a * 0 + 1), to_img(a * 0 + 1), to_img(a * 0 + 1), to_img(a)))


def vc_drip():
    img = canvas()
    d = ImageDraw.Draw(img)
    pts = []
    for i in range(41):
        t = i / 40
        ang = math.pi * 2 * t
        r = 40 * (1 - 0.65 * max(0, math.cos(ang - math.pi / 2)) ** 3)
        pts.append((128 + r * math.cos(ang), 160 + r * math.sin(ang) - (70 if math.sin(ang) < -0.97 else 0)))
    d.ellipse([88 * SS, 120 * SS, 168 * SS, 200 * SS], fill=255)
    poly(d, [(110, 140), (146, 140), (128, 30)])
    return finish(img, blur=2)


# ---------------------------------------------------------------- Azure Surge: arcing electricity

def as_bolt():
    """Beam texture: a jagged bolt with a soft glow, tiling along U."""
    w, h = 512, 96
    rng = random.Random(7)
    img = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(img)
    pts, y = [], h / 2
    for i in range(17):
        x = i * w / 16
        if 0 < i < 16:
            y = h / 2 + rng.uniform(-h * 0.32, h * 0.32)
        else:
            y = h / 2
        pts.append((x, y))
    d.line([(x * SS, y * SS) for x, y in pts], fill=255, width=4 * SS)
    for _ in range(5):
        i = rng.randrange(2, 14)
        x0, y0 = pts[i]
        d.line([(x0 * SS, y0 * SS), ((x0 + rng.uniform(15, 40)) * SS, (y0 + rng.uniform(-30, 30)) * SS)], fill=200, width=2 * SS)
    core = img.resize((w, h), Image.LANCZOS)
    halo = core.filter(ImageFilter.GaussianBlur(7))
    a = np.maximum(np.asarray(core, np.float32), np.asarray(halo, np.float32) * 1.6) / 255
    shade = np.asarray(core, np.float32) / 255 * 0.5 + 0.5
    return Image.merge("RGBA", (to_img(shade), to_img(shade), to_img(shade), to_img(np.clip(a, 0, 1))))


def as_spark():
    img = canvas()
    d = ImageDraw.Draw(img)
    rng = random.Random(9)
    for k in range(9):
        ang = 2 * math.pi * k / 9 + rng.uniform(-0.2, 0.2)
        pts = [(128, 128)]
        r = 0
        while r < 110:
            r += rng.uniform(14, 26)
            a2 = ang + rng.uniform(-0.35, 0.35)
            pts.append((128 + r * math.cos(a2), 128 + r * math.sin(a2)))
        line(d, pts, 3.2 - k * 0.15)
    d.ellipse([112 * SS, 112 * SS, 144 * SS, 144 * SS], fill=255)
    return finish(img, blur=0.8)


def as_static():
    img = canvas()
    d = ImageDraw.Draw(img)
    rng = random.Random(11)
    pts = [(30, 128)]
    for i in range(1, 12):
        pts.append((30 + i * 18, 128 + rng.uniform(-50, 50)))
    line(d, pts, 4)
    return finish(img, blur=1.5)


# ---------------------------------------------------------------- Frost Crown: ice shards, a crown of crystals, frost wind

def fc_shard():
    img, shade = canvas(), canvas()
    d, ds = ImageDraw.Draw(img), ImageDraw.Draw(shade)
    outline = [(128, 12), (160, 70), (150, 230), (128, 248), (104, 228), (96, 72)]
    poly(d, outline)
    poly(ds, outline, 170)
    poly(ds, [(128, 12), (160, 70), (150, 230), (128, 248)], 255)  # the lit facet
    poly(ds, [(128, 12), (128, 248), (118, 160)], 120)  # a dark seam
    return finish(img, shade.filter(ImageFilter.GaussianBlur(3)), blur=0.6)


def fc_flake():
    img = canvas()
    d = ImageDraw.Draw(img)
    for k in range(6):
        ang = math.pi / 3 * k
        c, s = math.cos(ang), math.sin(ang)
        tip = (128 + 112 * c, 128 + 112 * s)
        line(d, [(128, 128), tip], 7)
        for r, l in ((45, 28), (75, 22), (98, 12)):
            base = (128 + r * c, 128 + r * s)
            for side in (-1, 1):
                a2 = ang + side * 0.75
                line(d, [base, (base[0] + l * math.cos(a2), base[1] + l * math.sin(a2))], 5)
    d.ellipse([110 * SS, 110 * SS, 146 * SS, 146 * SS], fill=255)
    return finish(img, blur=0.7)


def fc_glint():
    y, x = np.mgrid[0:S, 0:S]
    dx, dy = np.abs(x / S - 0.5), np.abs(y / S - 0.5)
    cross = np.clip(1 - dx * 40, 0, 1) * np.clip(1 - dy * 2.2, 0, 1) + np.clip(1 - dy * 40, 0, 1) * np.clip(1 - dx * 2.2, 0, 1)
    diag = np.clip(1 - np.abs(dx - dy) * 30, 0, 1) * np.clip(1 - (dx + dy) * 3.5, 0, 1) * 0.5
    a = np.clip(cross + diag + radial(power=8), 0, 1)
    return finish(to_img(a).resize((S * SS, S * SS)))


def fc_wind():
    """Trail texture: thin wisps of frosty wind."""
    w, h = 512, 64
    y, x = np.mgrid[0:h, 0:w]
    u, v = x / w, y / h
    a = 0
    rng = np.random.default_rng(13)
    for _ in range(6):
        c = rng.uniform(0.2, 0.8)
        a = np.maximum(a, np.clip(1 - np.abs(v - c - 0.06 * np.sin(u * 12 + c * 9)) / 0.035, 0, 1) * rng.uniform(0.5, 1))
    a *= u ** 0.8 * (0.6 + 0.4 * noise(w, h, 16, 14))
    return Image.merge("RGBA", (to_img(a * 0 + 1),) * 3 + (to_img(a),))


# ---------------------------------------------------------------- Verdant Bloom: petals, leaves, ripples, spirit flame

def vb_petal():
    img, shade = canvas(), canvas()
    d, ds = ImageDraw.Draw(img), ImageDraw.Draw(shade)
    pts = []
    for i in range(61):
        t = i / 60 * 2 * math.pi
        r = 100 * (0.55 + 0.45 * math.sin(t / 2)) * (1 - 0.15 * abs(math.sin(t * 2)))
        pts.append((128 + 0.62 * r * math.cos(t), 140 - r * math.sin(t) * 0.95 + 20))
    poly(d, pts)
    poly(ds, pts, 230)
    line(ds, [(128, 230), (128, 80)], 4, 255)
    return finish(img, shade.filter(ImageFilter.GaussianBlur(6)), blur=0.8)


def vb_leaf():
    img, shade = canvas(), canvas()
    d, ds = ImageDraw.Draw(img), ImageDraw.Draw(shade)
    left, right = [], []
    for i in range(31):
        t = i / 30
        w = 70 * math.sin(math.pi * t) ** 0.8 * (1 + 0.08 * math.sin(t * 40))
        y = 240 - t * 220
        left.append((128 - w, y))
        right.append((128 + w, y))
    pts = left + right[::-1]
    poly(d, pts)
    poly(ds, pts, 190)
    line(ds, [(128, 240), (128, 30)], 5, 255)
    for k in range(1, 6):
        y = 220 - k * 32
        line(ds, [(128, y), (128 - 45, y - 30)], 3, 240)
        line(ds, [(128, y), (128 + 45, y - 30)], 3, 240)
    return finish(img, shade.filter(ImageFilter.GaussianBlur(2)), blur=0.7)


def vb_ripple():
    a = radial(power=1)
    r = np.clip(1 - np.abs(a - 0.1) / 0.05, 0, 1) ** 2 + np.clip(1 - np.abs(a - 0.3) / 0.04, 0, 1) ** 2 * 0.45
    return finish(to_img(np.clip(r, 0, 1)).resize((S * SS, S * SS)))


def vb_spiritflame():
    img = canvas()
    d = ImageDraw.Draw(img)
    poly(d, flame_shape(128, 248, 215, 150, 0.0, 2, 4))
    soft = img.filter(ImageFilter.GaussianBlur(5 * SS))
    shade = to_img(0.5 + 0.5 * radial(power=1.2, cy=0.75, sy=0.45)).resize((S * SS, S * SS))
    return finish(soft, shade)


def vb_flower():
    img, shade = canvas(), canvas()
    d, ds = ImageDraw.Draw(img), ImageDraw.Draw(shade)
    for k in range(5):
        ang = 2 * math.pi * k / 5 - math.pi / 2
        cx, cy = 128 + 55 * math.cos(ang), 128 + 55 * math.sin(ang)
        box = [(cx - 50) * SS, (cy - 50) * SS, (cx + 50) * SS, (cy + 50) * SS]
        d.ellipse(box, fill=255)
        ds.ellipse(box, fill=200)
    d.ellipse([100 * SS, 100 * SS, 156 * SS, 156 * SS], fill=255)
    ds.ellipse([100 * SS, 100 * SS, 156 * SS, 156 * SS], fill=255)
    return finish(img, shade.filter(ImageFilter.GaussianBlur(8)), blur=0.6)


# ---------------------------------------------------------------- Umbral Veil: scribbled shadow, glitch, static

def uv_scribble():
    """Beam texture: frantic overlapping scribble strokes."""
    w, h = 512, 128
    img = Image.new("L", (w * SS, h * SS), 0)
    d = ImageDraw.Draw(img)
    rng = random.Random(17)
    for _ in range(14):
        pts = []
        x = rng.uniform(-40, 40)
        while x < w + 40:
            pts.append((x * SS, rng.uniform(h * 0.15, h * 0.85) * SS))
            x += rng.uniform(10, 40)
        d.line(pts, fill=rng.randint(150, 255), width=int(rng.uniform(1.5, 4) * SS))
    a = img.resize((w, h), Image.LANCZOS)
    fade = np.sin(np.linspace(0, math.pi, w))[None, :] ** 0.3
    arr = np.asarray(a, np.float32) / 255 * fade
    return Image.merge("RGBA", (to_img(arr * 0 + 1),) * 3 + (to_img(arr),))


def uv_glitch():
    img = canvas()
    d = ImageDraw.Draw(img)
    rng = random.Random(19)
    for _ in range(16):
        x, y = rng.uniform(20, 200), rng.uniform(20, 230)
        w, h = rng.uniform(12, 70), rng.uniform(4, 18)
        d.rectangle([x * SS, y * SS, (x + w) * SS, (y + h) * SS], fill=rng.randint(110, 255))
    return finish(img)


def uv_star():
    y, x = np.mgrid[0:S, 0:S]
    dx, dy = np.abs(x / S - 0.5), np.abs(y / S - 0.5)
    a = np.clip(1 - (dx * 26) - dy * 2.4, 0, 1) + np.clip(1 - (dy * 26) - dx * 2.4, 0, 1)
    return finish(to_img(np.clip(a + radial(power=10) * 0.8, 0, 1)).resize((S * SS, S * SS)))


def uv_static():
    w, h = 256, 256
    rng = np.random.default_rng(21)
    rows = (rng.random(h) > 0.55).astype(np.float32) * rng.random(h)
    arr = np.repeat(rows[:, None], w, axis=1) * (rng.random((h, w)) > 0.35)
    arr *= radial(power=0.8)
    return Image.merge("RGBA", (to_img(arr * 0 + 1),) * 3 + (to_img(arr),))


# ---------------------------------------------------------------- Radiant Edge: tracing light, halo, shards

def re_edge():
    """Trail texture: a razor-thin bright line with a soft bloom."""
    w, h = 512, 64
    y, x = np.mgrid[0:h, 0:w]
    v = np.abs(y / h - 0.5) * 2
    a = np.clip(1 - v / 0.08, 0, 1) + np.clip(1 - v, 0, 1) ** 4 * 0.6
    a *= (x / w) ** 0.4
    shade = 0.6 + 0.4 * np.clip(1 - v / 0.08, 0, 1)
    return Image.merge("RGBA", (to_img(shade),) * 3 + (to_img(np.clip(a, 0, 1)),))


def re_wisp():
    img = canvas()
    d = ImageDraw.Draw(img)
    pts = [(128 + 40 * math.sin(t * 5) * (1 - t), 240 - t * 225) for t in (i / 40 for i in range(41))]
    for i, (p, q) in enumerate(zip(pts, pts[1:])):
        line(d, [p, q], 22 * (1 - i / 40) + 2)
    return finish(img, blur=4)


def re_halo():
    a = radial(power=1)
    ring = np.clip(1 - np.abs(a - 0.22) / 0.035, 0, 1) ** 1.5
    y, x = np.mgrid[0:S, 0:S]
    ang = np.arctan2(y / S - 0.5, x / S - 0.5)
    rays = (np.cos(ang * 12) * 0.5 + 0.5) ** 30 * np.clip((0.22 - a) / 0.22 * 4, 0, 1) * np.clip(a / 0.05, 0, 1)
    return finish(to_img(np.clip(ring + rays * 0.8, 0, 1)).resize((S * SS, S * SS)))


def re_shard():
    img = canvas()
    d = ImageDraw.Draw(img)
    poly(d, [(128, 10), (150, 128), (128, 246), (106, 128)])
    return finish(img, blur=1.5)


# ---------------------------------------------------------------- Phantom Blaze: hollow ghost fire, smoke, will-o-wisps

def pb_flame():
    img = canvas()
    d = ImageDraw.Draw(img)
    flame_cluster(d, 128, 248, 235, 140, -0.06, 6)
    full = np.asarray(img.filter(ImageFilter.GaussianBlur(1.5 * SS)), np.float32) / 255
    hole = Image.new("L", img.size, 0)
    poly(ImageDraw.Draw(hole), flame_shape(128, 236, 165, 90, -0.04, 2, 7))
    hole = np.asarray(hole.filter(ImageFilter.GaussianBlur(5 * SS)), np.float32) / 255
    # bright, crisp edges with a smoky, see-through hollow inside: ghost fire
    return finish(to_img(full * (1 - 0.72 * hole)))


def pb_smoke():
    a = radial(power=1.4) * (0.5 + 0.5 * noise(S, S, 18, 23)) * (0.6 + 0.4 * noise(S, S, 6, 24))
    return finish(to_img(np.clip(a * 1.6, 0, 1)).resize((S * SS, S * SS)))


def pb_wisp():
    a = radial(power=3, cy=0.7, sx=0.22, sy=0.22) + radial(power=2, cy=0.45, sx=0.12, sy=0.45) * 0.7
    return finish(to_img(np.clip(a, 0, 1)).resize((S * SS, S * SS)), blur=1)


# ---------------------------------------------------------------- Dusk Wings: energy wings, feathers, light slashes

def dw_rib():
    """Beam texture across the width: a bright spine with a soft falloff."""
    w, h = 256, 64
    y, x = np.mgrid[0:h, 0:w]
    v = np.abs(y / h - 0.5) * 2
    a = np.clip(1 - v / 0.18, 0, 1) + np.clip(1 - v, 0, 1) ** 3 * 0.5
    a *= np.sin(np.pi * x / w) ** 0.2
    return Image.merge("RGBA", (to_img(a * 0 + 1),) * 3 + (to_img(np.clip(a, 0, 1)),))


def dw_membrane():
    """Beam texture: a see-through sheet of light with faint veins."""
    w, h = 256, 256
    y, x = np.mgrid[0:h, 0:w]
    u, v = x / w, y / h
    veins = sum(np.clip(1 - np.abs(v - (k / 6 + 0.04 * np.sin(u * 8 + k))) / 0.012, 0, 1) for k in range(1, 6))
    a = 0.28 * (1 - np.abs(v - 0.5) * 1.2) + 0.5 * veins
    a *= np.sin(np.pi * u) ** 0.5
    return Image.merge("RGBA", (to_img(a * 0 + 1),) * 3 + (to_img(np.clip(a, 0, 1)),))


def dw_feather():
    img, shade = canvas(), canvas()
    d, ds = ImageDraw.Draw(img), ImageDraw.Draw(shade)
    left, right = [], []
    for i in range(31):
        t = i / 30
        w = 48 * math.sin(math.pi * min(1, t * 1.1)) ** 0.6
        y = 240 - t * 225
        left.append((128 - w * 0.8 + 8 * t, y))
        right.append((128 + w + 8 * t, y))
    pts = left + right[::-1]
    poly(d, pts)
    poly(ds, pts, 180)
    line(ds, [(128, 245), (136, 20)], 4, 255)
    for k in range(10):
        y = 220 - k * 20
        line(ds, [(130, y), (178, y - 22)], 1.5, 120)
    return finish(img, shade.filter(ImageFilter.GaussianBlur(1)), blur=0.8)


def dw_slash():
    a = radial(power=1, cx=0.5, cy=0.95, sx=0.75, sy=0.75)
    arc = np.clip(1 - np.abs(a - 0.25) / 0.06, 0, 1) ** 1.3
    y, x = np.mgrid[0:S, 0:S]
    taper = np.clip(1 - np.abs(x / S - 0.5) * 2.2, 0, 1) ** 0.7
    return finish(to_img(np.clip(arc * taper, 0, 1)).resize((S * SS, S * SS)), blur=0.6)


# ---------------------------------------------------------------- Silver Sheen: flowing sheen, motes, mercury ripples, flares

def ss_band():
    y, x = np.mgrid[0:S, 0:S]
    v = np.abs(y / S - 0.5) * 2
    band = np.clip(1 - v / 0.5, 0, 1) ** 2
    hl = np.clip(1 - np.abs(y / S - 0.42) / 0.02, 0, 1) * 0.8
    a = (band * 0.6 + hl) * np.sin(np.pi * x / S) ** 0.8
    return finish(to_img(np.clip(a, 0, 1)).resize((S * SS, S * SS)))


def ss_mote():
    a = radial(power=4)
    y, x = np.mgrid[0:S, 0:S]
    dx, dy = np.abs(x / S - 0.5), np.abs(y / S - 0.5)
    a = a + (np.clip(1 - dx * 60, 0, 1) + np.clip(1 - dy * 60, 0, 1)) * np.clip(1 - np.maximum(dx, dy) * 3, 0, 1) * 0.6
    return finish(to_img(np.clip(a, 0, 1)).resize((S * SS, S * SS)))


def ss_ripple():
    a = radial(power=1)
    r = np.clip(1 - np.abs(a - 0.08) / 0.015, 0, 1) + np.clip(1 - np.abs(a - 0.13) / 0.012, 0, 1) * 0.6
    return finish(to_img(np.clip(r, 0, 1)).resize((S * SS, S * SS)))


def ss_flare():
    y, x = np.mgrid[0:S, 0:S]
    dx, dy = x / S - 0.5, y / S - 0.5
    ang = np.arctan2(dy, dx)
    d = np.sqrt(dx * dx + dy * dy)
    rays = (np.abs(np.cos(ang * 3)) ** 40) * np.clip(1 - d * 2.2, 0, 1)
    a = np.clip(rays + radial(power=6) + np.clip(1 - np.abs(d - 0.3) / 0.01, 0, 1) * 0.3, 0, 1)
    return finish(to_img(a).resize((S * SS, S * SS)))


TEXTURES = {
    "Glow": glow,
    "LB_Trail": lb_trail, "LB_Streak": lb_streak, "LB_Chevron": lb_chevron, "LB_Ring": lb_ring, "LB_Flare": lb_flare,
    "VC_Flame": vc_flame, "VC_Tendril": vc_tendril, "VC_Drip": vc_drip,
    "AS_Bolt": as_bolt, "AS_Spark": as_spark, "AS_Static": as_static,
    "FC_Shard": fc_shard, "FC_Flake": fc_flake, "FC_Glint": fc_glint, "FC_Wind": fc_wind,
    "VB_Petal": vb_petal, "VB_Leaf": vb_leaf, "VB_Ripple": vb_ripple, "VB_SpiritFlame": vb_spiritflame, "VB_Flower": vb_flower,
    "UV_Scribble": uv_scribble, "UV_Glitch": uv_glitch, "UV_Star": uv_star, "UV_Static": uv_static,
    "RE_Edge": re_edge, "RE_Wisp": re_wisp, "RE_Halo": re_halo, "RE_Shard": re_shard,
    "PB_Flame": pb_flame, "PB_Smoke": pb_smoke, "PB_Wisp": pb_wisp,
    "DW_Rib": dw_rib, "DW_Membrane": dw_membrane, "DW_Feather": dw_feather, "DW_Slash": dw_slash,
    "SS_Band": ss_band, "SS_Mote": ss_mote, "SS_Ripple": ss_ripple, "SS_Flare": ss_flare,
}


def contact_sheet(images):
    cols = 8
    cell = 128
    rows = (len(images) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * cell, rows * (cell + 16)), (24, 26, 32))
    d = ImageDraw.Draw(sheet)
    for i, (name, img) in enumerate(images.items()):
        thumb = img.copy()
        thumb.thumbnail((cell - 8, cell - 8))
        x, y = (i % cols) * cell, (i // cols) * (cell + 16)
        bg = Image.new("RGB", thumb.size, (24, 26, 32))
        bg.paste(thumb, (0, 0), thumb)
        sheet.paste(bg, (x + (cell - thumb.width) // 2, y + 4 + (cell - 8 - thumb.height) // 2))
        d.text((x + 6, y + cell), name, fill=(200, 200, 210))
    return sheet


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    images = {}
    for name, make in TEXTURES.items():
        img = make()
        img.save(OUT / f"{name}.png")
        images[name] = img
    contact_sheet(images).save(OUT / "_contact_sheet.png")
    print(f"Wrote {len(images)} textures to {OUT}")


if __name__ == "__main__":
    main()
