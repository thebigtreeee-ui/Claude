"""Renders approximate previews of Eternium auras (Stage 1 and Stage 2 side by side).

This is not Roblox: it is a small particle / beam simulator that uses the real aura textures and the
same numbers as EterniumAuras.lua (rates, lifetimes, speeds, sizes, colours, motion), so shapes, motion
and colours match closely. Roblox's own lighting and bloom will differ.

    python tools/preview_aura.py OUT_DIR [LimitBreaker AzureSurge ...]
writes OUT_DIR/<Aura>.mp4 for each aura
"""
import math
import random
import subprocess
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

TEX = Path(__file__).resolve().parent.parent / "Auras" / "textures"
W, H = 480, 640
FPS = 30
SECONDS = 4.0
YAW = math.radians(25)
CAM_DIST = 13.0
FOCAL = 640.0
CENTER = (W / 2, H * 0.56)

# body slots in root space (studs), matching an R15 character with the root at the origin
SLOTS = {
    "Root": (0, 0, 0), "Head": (0, 1.85, 0), "Torso": (0, 0.6, 0), "Lower": (0, -0.4, 0),
    "LeftArm": (-1.5, 0.7, 0), "RightArm": (1.5, 0.7, 0), "LeftForearm": (-1.5, -0.3, 0), "RightForearm": (1.5, -0.3, 0),
    "LeftHand": (-1.5, -0.95, 0), "RightHand": (1.5, -0.95, 0), "LeftLeg": (-0.5, -1.25, 0), "RightLeg": (0.5, -1.25, 0),
    "LeftShin": (-0.5, -2.3, 0), "RightShin": (0.5, -2.3, 0), "LeftFoot": (-0.5, -2.85, 0), "RightFoot": (0.5, -2.85, 0),
}
BODY = [
    ((0, 1.85, 0), (1.15, 1.15, 1.15)), ((0, 0.6, 0), (2.0, 1.6, 1.0)), ((0, -0.4, 0), (2.0, 0.4, 1.0)),
    ((-1.5, 0.7, 0), (1.0, 1.2, 1.0)), ((1.5, 0.7, 0), (1.0, 1.2, 1.0)), ((-1.5, -0.3, 0), (1.0, 1.0, 1.0)), ((1.5, -0.3, 0), (1.0, 1.0, 1.0)),
    ((-1.5, -0.95, 0), (1.0, 0.3, 1.0)), ((1.5, -0.95, 0), (1.0, 0.3, 1.0)), ((-0.5, -1.25, 0), (1.0, 1.2, 1.0)), ((0.5, -1.25, 0), (1.0, 1.2, 1.0)),
    ((-0.5, -2.3, 0), (1.0, 1.0, 1.0)), ((0.5, -2.3, 0), (1.0, 1.0, 1.0)), ((-0.5, -2.85, 0), (1.0, 0.3, 1.0)), ((0.5, -2.85, 0), (1.0, 0.3, 1.0)),
]


def add3(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def tone(c, k):
    t = (255, 255, 255) if k >= 0 else (0, 0, 0)
    return tuple(c[i] + (t[i] - c[i]) * abs(k) for i in range(3))


def seq(keys, x):
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t0 <= x <= t1:
            return v0 + (v1 - v0) * ((x - t0) / (t1 - t0) if t1 > t0 else 0)
    return keys[-1][1]


def project(p):
    x, y, z = p
    c, s = math.cos(YAW), math.sin(YAW)
    xr, zr = c * x + s * z, -s * x + c * z
    k = FOCAL / (CAM_DIST - zr)
    return CENTER[0] + xr * k, CENTER[1] - y * k, k, zr


_tex = {}


def tex(name):
    if name not in _tex:
        _tex[name] = Image.open(TEX / f"{name}.png").convert("RGBA")
    return _tex[name]


def blit(canvas, img, center, color, alpha):
    arr = np.asarray(img, dtype=np.float32) / 255
    rgb = arr[..., 3:4] * arr[..., :3] * alpha * (np.array(color, dtype=np.float32) / 255)
    x0, y0 = int(center[0] - rgb.shape[1] / 2), int(center[1] - rgb.shape[0] / 2)
    x1, y1 = x0 + rgb.shape[1], y0 + rgb.shape[0]
    cx0, cy0, cx1, cy1 = max(0, x0), max(0, y0), min(W, x1), min(H, y1)
    if cx0 < cx1 and cy0 < cy1:
        canvas[cy0:cy1, cx0:cx1] += rgb[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0]


def splat(canvas, name, center, size_px, color, alpha, rotation=0.0, squash=0.0, flat=False):
    if size_px < 1.5 or alpha <= 0.01:
        return
    w = h = size_px
    if squash:  # Roblox Squash: positive values make the particle narrower and taller
        w, h = size_px / (1 + squash * 0.5), size_px * (1 + squash * 0.5)
    if flat:
        h = size_px * 0.32
    img = tex(name).resize((max(2, int(w)), max(2, int(h))), Image.BILINEAR)
    if rotation:
        img = img.rotate(rotation, expand=True, resample=Image.BILINEAR)
    blit(canvas, img, center, color, alpha)


def beam(canvas, name, p0, p1, width, color, alpha, offset=0.0, flip=False):
    """A camera-facing textured beam between two world points (texture U runs along the beam)."""
    s0, s1 = project(p0), project(p1)
    dx, dy = s1[0] - s0[0], s1[1] - s0[1]
    length = math.hypot(dx, dy)
    if length < 2:
        return
    img = tex(name)
    if offset:
        arr = np.roll(np.asarray(img), int(offset * img.width), axis=1)
        img = Image.fromarray(arr)
    if flip:
        img = img.transpose(Image.FLIP_TOP_BOTTOM)
    wpx = max(2, int(width * (s0[2] + s1[2]) / 2))
    img = img.resize((int(length), wpx), Image.BILINEAR).rotate(-math.degrees(math.atan2(dy, dx)), expand=True, resample=Image.BILINEAR)
    blit(canvas, img, ((s0[0] + s1[0]) / 2, (s0[1] + s1[1]) / 2), color, alpha)


class Emitter:
    """One ParticleEmitter: settings mirror EterniumAuras.lua."""

    def __init__(self, origin, texture, color, shade, rate=0, life=(0.5, 0.5), speed=(0, 0), spread=0, size=((0, 1), (1, 1)),
                 transp=((0, 0), (1, 1)), accel=(0, 0, 0), rotation=None, squash=0.0, flat=False, parallel=False, drag=0.0,
                 spread_flat=False, scale=1.0):
        self.__dict__.update(locals())
        self.particles, self.acc = [], 0.0
        self.rng = random.Random(hash((texture, origin)))

    def emit(self, n):
        for _ in range(n):
            ang = math.radians(self.rng.uniform(-self.spread, self.spread))
            az = self.rng.uniform(0, 2 * math.pi)
            spd = self.rng.uniform(*self.speed)
            if self.spread_flat:  # SpreadAngle (x, small): fans out sideways along the ground
                v = (math.sin(ang) * math.cos(az) * spd * 1.6, math.cos(ang) * spd * 0.3, math.sin(ang) * math.sin(az) * spd * 1.6)
            else:
                v = (math.sin(ang) * math.cos(az) * spd, math.cos(ang) * spd, math.sin(ang) * math.sin(az) * spd)
            rot = self.rng.uniform(0, 360) if self.rotation is None else self.rotation
            self.particles.append({"p": list(self.origin), "v": list(v), "age": 0.0, "life": self.rng.uniform(*self.life), "rot": rot})

    def step(self, dt):
        self.acc += self.rate * dt
        while self.acc >= 1:
            self.acc -= 1
            self.emit(1)
        alive = []
        for q in self.particles:
            q["age"] += dt
            if q["age"] < q["life"]:
                for i in range(3):
                    q["v"][i] = q["v"][i] * (1 - self.drag * dt) + self.accel[i] * dt
                    q["p"][i] += q["v"][i] * dt
                alive.append(q)
        self.particles = alive

    def draw(self, canvas):
        for q in self.particles:
            x = q["age"] / q["life"]
            sx, sy, k, _ = project(q["p"])
            rot = q["rot"]
            if self.parallel:  # VelocityParallel: the texture's up axis follows the velocity on screen
                v = q["v"]
                ex = project(add3(q["p"], (v[0] * 0.05, v[1] * 0.05, v[2] * 0.05)))
                rot = math.degrees(math.atan2(ex[0] - sx, -(ex[1] - sy))) * -1
            color = tone(self.color, seq(self.shade, x))
            splat(canvas, self.texture, (sx, sy), seq(self.size, x) * self.scale * k, color, 1 - seq(self.transp, x),
                  rot, seq(self.squash, x) if isinstance(self.squash, tuple) else self.squash, self.flat)


def draw_body(img, glow, light):
    d = ImageDraw.Draw(img)
    base = np.array([26, 26, 32], dtype=np.float32) + light * np.array(glow, dtype=np.float32) * 0.05
    faces = [((1, 3, 7, 5), 1.0), ((4, 6, 7, 5), 0.72), ((0, 2, 6, 4), 0.55), ((0, 1, 3, 2), 0.72), ((2, 3, 7, 6), 1.2), ((0, 4, 5, 1), 0.4)]
    for (cx, cy, cz), (sx, sy, sz) in sorted(BODY, key=lambda b: project(b[0])[3]):
        corners = [(cx + dx * sx / 2, cy + dy * sy / 2, cz + dz * sz / 2) for dx in (-1, 1) for dy in (-1, 1) for dz in (-1, 1)]
        pts = [project(c)[:2] for c in corners]
        for idx, k in faces:
            poly = [pts[i] for i in idx]
            area = sum(poly[i][0] * poly[(i + 1) % 4][1] - poly[(i + 1) % 4][0] * poly[i][1] for i in range(4))
            if area < 0:
                d.polygon(poly, fill=tuple(int(min(255, c * k)) for c in base))


def compose(glow, light, behind, front):
    """Background + light pool + body, then the additive aura layers with a soft bloom."""
    y, x = np.mgrid[0:H, 0:W]
    bx, by, _, _ = project((0, 0.4, 0))
    pool = np.exp(-(((x - bx) / 170) ** 2 + ((y - by) / 230) ** 2)) * 0.11 * light
    bg = np.dstack([np.full((H, W), c / 255) for c in (14, 15, 20)]) + pool[..., None] * (np.array(glow) / 255)
    base = Image.fromarray(np.clip(bg * 255, 0, 255).astype(np.uint8))
    draw_body(base, glow, light)
    canvas = np.asarray(base, dtype=np.float32) / 255
    add = behind + front
    bloom = Image.fromarray(np.clip(add * 255, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(9))
    add = add + np.asarray(bloom, dtype=np.float32) / 255 * 0.6
    return np.clip(canvas + add, 0, 1)


# ---------------------------------------------------------------- Limit Breaker (Super Saiyan)

LB_SOURCES = [("Torso", (0, 0.3, 0), 1.25), ("Torso", (0, -0.4, 0), 1.2), ("Lower", (0, 0, 0), 1.1), ("Head", (0, 0, 0), 1.15),
              ("LeftArm", (0, 0, 0), 1), ("RightArm", (0, 0, 0), 1), ("LeftForearm", (0, 0, 0), 0.9), ("RightForearm", (0, 0, 0), 0.9),
              ("LeftLeg", (0, 0, 0), 1), ("RightLeg", (0, 0, 0), 1), ("LeftShin", (0, 0, 0), 0.9), ("RightShin", (0, 0, 0), 0.9)]


def limit_breaker(stage):
    MAIN, ACCENT, GLOW = (255, 205, 60), (170, 220, 255), (255, 170, 40)
    s2 = stage == 2
    k = 1.2 if s2 else 1.0
    flames = [Emitter(add3(SLOTS[slot], off), "LB_Aura", MAIN, [(0, 0.65), (0.45, 0.1), (1, -0.1)], rate=30 if s2 else 20,
                      life=(0.28, 0.42), speed=(5 * k * 1.05, 9 * k * 1.05), spread=16, size=[(0, 0.7), (0.4, 1.5), (1, 0.5)],
                      transp=[(0, 1), (0.12, 0.1), (0.7, 0.35), (1, 1)], rotation=0, squash=((0, 1.2), (1, 1.8)), parallel=True,
                      scale=sc * k) for slot, off, sc in LB_SOURCES]
    outer = [Emitter((x, -1.6, 0), "LB_Aura", MAIN, [(0, 0.3), (1, -0.15)], rate=14 if s2 else 9, life=(0.38, 0.55), speed=(7, 11),
                     spread=8, size=[(0, 1.2), (0.5, 2.6), (1, 0.8)], transp=[(0, 1), (0.15, 0.4), (0.75, 0.6), (1, 1)], rotation=0,
                     squash=((0, 1.5), (1, 2.2)), parallel=True, scale=k) for x in (-1.25, -0.6, 0.6, 1.25)]
    haze = Emitter(SLOTS["Torso"], "Glow", GLOW, [(0, 0.35), (0.4, 0), (1, -0.2)], rate=8, life=(0.5, 0.8), size=[(0, 5.5), (1, 6.5)],
                   transp=[(0, 1), (0.3, 0.78), (1, 1)])
    embers = [Emitter(SLOTS[s], "LB_Ember", MAIN, [(0, 0.7), (1, 0.2)], rate=10 if s2 else 6, life=(0.5, 0.9), speed=(10, 16), spread=22,
                      size=[(0, 0.22), (1, 0.08)], rotation=0) for s in ("LeftFoot", "RightFoot", "Lower", "LeftHand", "RightHand")]
    dust = Emitter((0, -2.8, 0), "LB_Dust", GLOW, [(0, -0.35), (1, -0.55)], rate=7, life=(0.8, 1.3), speed=(4, 7), spread=85,
                   size=[(0, 1), (1, 3.5)], transp=[(0, 1), (0.2, 0.6), (1, 1)], accel=(0, 1, 0), drag=3, spread_flat=True)
    sparks = [Emitter(SLOTS[s], "LB_Spark", ACCENT, [(0, 0.5), (1, 0.2)], rate=9, life=(0.05, 0.1), size=[(0, 1.1), (1, 1.3)],
                      transp=[(0, 0), (1, 0.4)]) for s in ("Torso", "Head", "LeftArm", "RightArm", "LeftLeg", "RightLeg", "Lower")] if s2 else []
    rings = Emitter((0, -2.9, 0), "LB_Ring", MAIN, [(0, 0.5), (1, 0)], life=(0.6, 0.6), size=[(0, 1), (1, 9)], transp=[(0, 0), (1, 1)],
                    rotation=0, flat=True)
    flare = Emitter(add3(SLOTS["Torso"], (0, 0, 0.6)), "LB_Flare", MAIN, [(0, 0.6), (1, 0.3)], life=(0.35, 0.35),
                    size=[(0, 1), (0.3, 7), (1, 0)], transp=[(0, 0), (1, 1)])
    state = {"next_ring": 0.0}
    emitters = flames + outer + [haze] + embers + [dust] + sparks + [rings, flare]

    def step(t, dt):
        for e in emitters:
            e.step(dt)
        if s2 and t >= state["next_ring"]:
            rings.emit(1)
            state["next_ring"] = t + 0.8

    def draw(t):
        light = (2 if s2 else 1.5) + 0.8 * math.sin(t * math.pi * 4)
        behind, front = np.zeros((H, W, 3), np.float32), np.zeros((H, W, 3), np.float32)
        for e in [rings, dust, haze] + outer:
            e.draw(behind)
        for e in flames + embers + sparks + [flare]:
            e.draw(front)
        return compose(GLOW, light, behind, front)

    return step, draw, (lambda: (flare.emit(1), rings.emit(2)))


# ---------------------------------------------------------------- Azure Surge (raw electricity)


def azure_surge(stage):
    MAIN, ACCENT, GLOW = (90, 185, 255), (225, 245, 255), (40, 120, 255)
    s2 = stage == 2
    rng = random.Random(5 + stage)
    nodes = [SLOTS[s] for s in ("LeftHand", "RightHand", "LeftFoot", "RightFoot", "Head", "Torso", "LeftArm", "RightArm", "Lower")]
    forks = [Emitter(SLOTS[s], "AS_Fork", MAIN, [(0, 0.55), (1, 0.4)], rate=10 if s2 else 5, life=(0.06, 0.11), size=[(0, 3.2), (1, 3.6)],
                     transp=[(0, 0), (1, 0.3)]) for s in ("Torso", "Head", "LeftArm", "RightArm", "LeftForearm", "RightForearm", "LeftLeg", "RightLeg", "Lower")]
    parts = ("LeftArm", "RightArm", "LeftForearm", "RightForearm", "LeftLeg", "RightLeg", "LeftShin", "RightShin", "Torso", "Head")
    plasma = [Emitter(SLOTS[s], "AS_Plasma", GLOW, [(0, 0.3), (1, 0)], rate=9, life=(0.12, 0.22), size=[(0, 2.2), (1, 2.8)],
                      transp=[(0, 0.35), (1, 1)]) for s in parts]
    static = [Emitter(SLOTS[s], "AS_Static", ACCENT, [(0, 0.5), (1, 0.2)], rate=12, life=(0.06, 0.14), size=[(0, 0.5), (1, 0.3)]) for s in parts]
    sparks = Emitter(SLOTS["Torso"], "AS_Spark", ACCENT, [(0, 0.35), (0.4, 0), (1, -0.2)], rate=22, life=(0.25, 0.5), speed=(12, 22), spread=180,
                     size=[(0, 0.35), (1, 0.1)], accel=(0, -30, 0), parallel=True)
    bursts = [Emitter(SLOTS[s], "AS_Spark", ACCENT, [(0, 0.35), (0.4, 0), (1, -0.2)], life=(0.12, 0.2), size=[(0, 0.5), (0.2, 1.8), (1, 0)])
              for s in ("LeftHand", "RightHand", "Torso", "Head")]
    flashes = Emitter((0, -2.95, 0), "AS_Plasma", GLOW, [(0, 0.5), (1, 0)], life=(0.18, 0.18), size=[(0, 1), (1, 2.6)], transp=[(0, 0), (1, 1)], flat=True)
    halo = [Emitter((0, 0, 0), "AS_Static", ACCENT, [(0, 0.35), (0.4, 0), (1, -0.2)], rate=22, life=(0.1, 0.2), size=[(0, 0.6), (1, 0.3)])
            for _ in range(6)] if s2 else []
    arcs = [{"next": 0.0, "a": 0, "b": 1, "off": 0.0, "on": True, "flip": False} for _ in range(4)]
    strikes = [{"next": i * 0.07, "on": False, "off": 0.0, "src": 0, "dst": (0, -2.95, 2), "o": 0.0} for i in range(6 if s2 else 3)]
    state = {"next_burst": 0.0, "light": 1.5}
    conduits = []
    if s2:
        for sx in (-1.5, 1.5):
            chain = [(sx, 1.0, 0), (sx, -0.1, 0), (sx, -0.95, 0)]
            for a, b in zip(chain, chain[1:]):
                conduits += [(a, b, 0.5, MAIN, 6), (a, b, 0.25, ACCENT, -9)]
    emitters = forks + plasma + static + [sparks] + bursts + [flashes] + halo

    def step(t, dt):
        for i, h in enumerate(halo):
            ang = i * math.pi / 3 + t * 4
            h.origin = (math.cos(ang), SLOTS["Head"][1] + 1.1, math.sin(ang))
        for e in emitters:
            e.step(dt)
        for arc in arcs:
            if t >= arc["next"]:
                arc["a"] = rng.randrange(len(nodes))
                arc["b"] = (arc["a"] + rng.randrange(1, len(nodes))) % len(nodes)
                arc["off"], arc["flip"] = rng.random(), rng.random() < 0.5
                arc["on"] = rng.random() > 0.15
                arc["next"] = t + 0.05 + rng.random() * 0.1
        for st in strikes:
            if t >= st["next"]:
                ang, reach = rng.random() * math.pi * 2, 2 + rng.random() * 2.5
                st["dst"] = (math.cos(ang) * reach, -2.95, math.sin(ang) * reach)
                st["src"], st["o"] = rng.randrange(len(nodes)), rng.random()
                st["on"], st["off"] = True, t + 0.07
                flashes.origin = st["dst"]
                flashes.emit(1)
                st["next"] = t + 0.18 + rng.random() * (0.25 if s2 else 0.45)
            elif st["on"] and t >= st["off"]:
                st["on"] = False
        if t >= state["next_burst"]:
            rng.choice(bursts).emit(1)
            state["next_burst"] = t + 0.1 + rng.random() * 0.15
        state["light"] = (2 if s2 else 1.2) + rng.random() * (3 if s2 else 2)

    def draw(t):
        behind, front = np.zeros((H, W, 3), np.float32), np.zeros((H, W, 3), np.float32)
        flashes.draw(behind)
        for e in plasma:
            e.draw(behind)
        for e in forks + static + [sparks] + bursts + halo:
            e.draw(front)
        for arc in arcs:
            if arc["on"]:
                beam(front, "AS_Bolt", nodes[arc["a"]], nodes[arc["b"]], 0.35, tone(MAIN, 0.4), 1, arc["off"], arc["flip"])
        for st in strikes:
            if st["on"]:
                beam(front, "AS_Bolt", nodes[st["src"]], st["dst"], 0.45, tone(MAIN, 0.4), 1, st["o"])
        for a, b, w, col, speed in conduits:
            beam(front, "AS_Bolt", a, b, w, tone(col, 0.3), 1, (t * speed / 1.2) % 1, rng.random() < 0.5)
        return compose(GLOW, state["light"] * 0.8, behind, front)

    return step, draw, (lambda: [b.emit(2) for b in bursts])


SCENES = {"LimitBreaker": ("LIMIT BREAKER", limit_breaker), "AzureSurge": ("AZURE SURGE", azure_surge)}


def render(name, out):
    title, make = SCENES[name]
    frames_dir = out / f"{name}_frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    n = int(SECONDS * FPS)
    frames = [np.full((H + 40, W * 2, 3), (14, 15, 20), dtype=np.uint8) for _ in range(n)]
    dt = 1 / FPS
    for stage, ox in ((1, 0), (2, W)):
        random.seed(stage)
        step, draw, ignite = make(stage)
        warm = int(FPS)
        for f in range(-warm, n):
            t = (f + warm) * dt
            step(t, dt)
            if f == 0:
                ignite()
            if f >= 0:
                frames[f][40:, ox:ox + W] = (draw(t) * 255).astype(np.uint8)
    for i, f in enumerate(frames):
        img = Image.fromarray(f)
        d = ImageDraw.Draw(img)
        d.text((W / 2 - 55, 12), f"{title} - STAGE 1", fill=(230, 230, 235))
        d.text((W + W / 2 - 55, 12), f"{title} - STAGE 2", fill=(230, 230, 235))
        img.save(frames_dir / f"{i:04d}.png")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", str(frames_dir / "%04d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", str(out / f"{name}.mp4")], check=True)
    print("wrote", out / f"{name}.mp4")


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    for name in sys.argv[2:] or list(SCENES):
        render(name, out)


if __name__ == "__main__":
    main()
