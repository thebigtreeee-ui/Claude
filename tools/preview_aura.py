"""Renders an approximate preview of the Limit Breaker aura (Stage 1 and Stage 2 side by side).

This is not Roblox: it is a small particle simulator that uses the real aura textures and the same
emitter numbers as EterniumAuras.lua (rates, lifetimes, speeds, sizes, colours, the helix motion),
so the shapes, motion and colours match closely. Roblox's own lighting and bloom will differ.

    python tools/preview_aura.py OUT_DIR
writes OUT_DIR/LimitBreaker.mp4 and OUT_DIR/LimitBreaker.gif
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

MAIN = (255, 200, 60)
ACCENT = (255, 240, 170)
GLOW = (255, 165, 40)


def tone(c, k):
    t = (255, 255, 255) if k >= 0 else (0, 0, 0)
    k = abs(k)
    return tuple(c[i] + (t[i] - c[i]) * k for i in range(3))


def shade_at(c, keys, x):
    for (t0, k0), (t1, k1) in zip(keys, keys[1:]):
        if t0 <= x <= t1:
            f = (x - t0) / (t1 - t0) if t1 > t0 else 0
            return tone(c, k0 + (k1 - k0) * f)
    return tone(c, keys[-1][1])


def seq(keys, x):
    for (t0, v0), (t1, v1) in zip(keys, keys[1:]):
        if t0 <= x <= t1:
            f = (x - t0) / (t1 - t0) if t1 > t0 else 0
            return v0 + (v1 - v0) * f
    return keys[-1][1]


def project(p):
    x, y, z = p
    c, s = math.cos(YAW), math.sin(YAW)
    xr, zr = c * x + s * z, -s * x + c * z
    depth = CAM_DIST - zr
    k = FOCAL / depth
    return CENTER[0] + xr * k, CENTER[1] - y * k, k, zr


TEXTURES = {}


def tex(name):
    if name not in TEXTURES:
        TEXTURES[name] = Image.open(TEX / f"{name}.png").convert("RGBA")
    return TEXTURES[name]


def splat(canvas, name, center, size_px, color, alpha, rotation=0.0, squash=0.0, flat=False):
    """Additively draws one particle sprite onto a float canvas."""
    if size_px < 1.5 or alpha <= 0.01:
        return
    w = h = size_px
    if squash:
        w, h = size_px / (1 + squash * 0.5), size_px * (1 + squash * 0.5)
    if flat:
        h = size_px * 0.32  # a horizontal ring seen from slightly above
    img = tex(name).resize((max(2, int(w)), max(2, int(h))), Image.BILINEAR)
    if rotation:
        img = img.rotate(rotation, expand=True, resample=Image.BILINEAR)
    arr = np.asarray(img, dtype=np.float32) / 255
    a = arr[..., 3:4] * arr[..., :3] * alpha
    rgb = a * (np.array(color, dtype=np.float32) / 255)
    x0, y0 = int(center[0] - rgb.shape[1] / 2), int(center[1] - rgb.shape[0] / 2)
    x1, y1 = x0 + rgb.shape[1], y0 + rgb.shape[0]
    cx0, cy0, cx1, cy1 = max(0, x0), max(0, y0), min(W, x1), min(H, y1)
    if cx0 >= cx1 or cy0 >= cy1:
        return
    canvas[cy0:cy1, cx0:cx1] += rgb[cy0 - y0:cy1 - y0, cx0 - x0:cx1 - x0]


class Emitter:
    def __init__(self, origin, rate, life, speed, spread, size, transp, texture, color, shade, accel=(0, 0, 0),
                 rotation=None, squash=0.0, locked=False, flat=False, burst=False):
        self.__dict__.update(locals())
        self.particles = []
        self.acc = 0.0
        self.rng = random.Random(hash(texture) + int(origin[1] * 100))

    def emit(self, n):
        for _ in range(n):
            ang = math.radians(self.rng.uniform(-self.spread, self.spread))
            az = self.rng.uniform(0, 2 * math.pi)
            spd = self.rng.uniform(*self.speed)
            v = (math.sin(ang) * math.cos(az) * spd, math.cos(ang) * spd, math.sin(ang) * math.sin(az) * spd)
            rot = self.rng.uniform(0, 360) if self.rotation is None else self.rotation
            self.particles.append({"p": list(self.origin), "v": list(v), "age": 0.0, "life": self.rng.uniform(*self.life), "rot": rot})

    def step(self, dt):
        if not self.burst:
            self.acc += self.rate * dt
            while self.acc >= 1:
                self.acc -= 1
                self.emit(1)
        alive = []
        for q in self.particles:
            q["age"] += dt
            if q["age"] < q["life"]:
                for i in range(3):
                    q["v"][i] += self.accel[i] * dt
                    q["p"][i] += q["v"][i] * dt
                alive.append(q)
        self.particles = alive

    def draw(self, canvas):
        for q in sorted(self.particles, key=lambda q: project(q["p"])[3]):
            x = q["age"] / q["life"]
            sx, sy, k, _ = project(q["p"])
            size = seq(self.size, x) * k
            alpha = 1 - seq(self.transp, x)
            splat(canvas, self.texture, (sx, sy), size, shade_at(self.color, self.shade, x), alpha, q["rot"], self.squash, self.flat)


DEFAULT_SHADE = [(0, 0.35), (0.4, 0), (1, -0.2)]

# an R15-proportioned mannequin, studs, origin at the HumanoidRootPart (feet at y = -3)
BODY = [
    ((0, 1.85, 0), (1.15, 1.15, 1.15)),   # head
    ((0, 0.6, 0), (2.0, 1.6, 1.0)),       # upper torso
    ((0, -0.4, 0), (2.0, 0.4, 1.0)),      # lower torso
    ((-1.5, 0.7, 0), (1.0, 1.2, 1.0)), ((1.5, 0.7, 0), (1.0, 1.2, 1.0)),
    ((-1.5, -0.3, 0), (1.0, 1.0, 1.0)), ((1.5, -0.3, 0), (1.0, 1.0, 1.0)),
    ((-1.5, -0.95, 0), (1.0, 0.3, 1.0)), ((1.5, -0.95, 0), (1.0, 0.3, 1.0)),
    ((-0.5, -1.25, 0), (1.0, 1.2, 1.0)), ((0.5, -1.25, 0), (1.0, 1.2, 1.0)),
    ((-0.5, -2.3, 0), (1.0, 1.0, 1.0)), ((0.5, -2.3, 0), (1.0, 1.0, 1.0)),
    ((-0.5, -2.85, 0), (1.0, 0.3, 1.0)), ((0.5, -2.85, 0), (1.0, 0.3, 1.0)),
]


def draw_body(img, light):
    d = ImageDraw.Draw(img)
    base = np.array([26, 26, 32], dtype=np.float32) + light * np.array(GLOW, dtype=np.float32) * 0.05
    faces = [((1, 3, 7, 5), 1.0), ((4, 6, 7, 5), 0.72), ((0, 2, 6, 4), 0.55), ((0, 1, 3, 2), 0.72), ((2, 3, 7, 6), 1.2), ((0, 4, 5, 1), 0.4)]
    boxes = sorted(BODY, key=lambda b: project(b[0])[3])
    for (cx, cy, cz), (sx, sy, sz) in boxes:
        corners = [(cx + dx * sx / 2, cy + dy * sy / 2, cz + dz * sz / 2) for dx in (-1, 1) for dy in (-1, 1) for dz in (-1, 1)]
        pts = [project(c)[:2] for c in corners]
        for idx, light_k in faces:
            poly = [pts[i] for i in idx]
            area = sum(poly[i][0] * poly[(i + 1) % 4][1] - poly[(i + 1) % 4][0] * poly[i][1] for i in range(4))
            if area < 0:  # facing the camera
                col = tuple(int(min(255, c * light_k)) for c in base)
                d.polygon(poly, fill=col)


def simulate(stage, out_frames, offset_x):
    random.seed(stage)
    ends = [(-1.5, -0.95, 0), (1.5, -0.95, 0), (-0.5, -2.85, 0), (0.5, -2.85, 0)]
    streaks = [Emitter(e, 18, (0.35, 0.6), (7, 11), 12, [(0, 0.7), (1, 0.2)], [(0, 0.2), (1, 1)], "LB_Streak", MAIN, DEFAULT_SHADE,
                       rotation=0, squash=2.0) for e in ends]
    chevrons = Emitter((0, -2.6, 0), 10, (0.8, 1.3), (4, 7), 25, [(0, 0.5), (0.5, 0.65), (1, 0)], [(0, 1), (0.15, 0.1), (1, 1)],
                       "LB_Chevron", ACCENT, DEFAULT_SHADE, rotation=0)
    haze = Emitter((0, 0.6, 0), 6, (0.6, 0.9), (0, 0), 0, [(0, 3.5), (1, 4.5)], [(0, 1), (0.3, 0.8), (1, 1)], "Glow", GLOW, DEFAULT_SHADE)
    rings = Emitter((0, -2.9, 0), 0, (0.6, 0.6), (0.01, 0.01), 0, [(0, 1), (1, 9)], [(0, 0), (1, 1)], "LB_Ring", ACCENT, DEFAULT_SHADE,
                    rotation=0, flat=True, burst=True)
    flare = Emitter((0, 0.6, 0.6), 0, (0.35, 0.35), (0, 0), 0, [(0, 1), (0.3, 6), (1, 0)], [(0, 0), (1, 1)], "LB_Flare", ACCENT, DEFAULT_SHADE,
                    burst=True)
    emitters = streaks + [chevrons, haze, rings, flare]
    flare.emit(1)
    rings.emit(2)

    strands = 8 if stage == 2 else 4
    speed = 1.25 if stage == 2 else 1.0
    height = 7.2 if stage == 2 else 6.0
    histories = [[] for _ in range(strands)]
    offsets = [(i % 4) / 4 + (0.125 if i >= 4 else 0) for i in range(strands)]
    phases = [(i % 4) * math.pi / 2 + (math.pi / 4 if i >= 4 else 0) + offsets[i] * (5 / 0.75) for i in range(strands)]
    last = [0.0] * strands
    next_ring = 0.0

    dt = 1 / FPS
    frames = int(SECONDS * FPS)
    warmup = int(1.0 * FPS)  # let the emitters fill up before the clip starts (the flare still plays)
    for f in range(-warmup, frames):
        t = (f + warmup) * dt
        for e in emitters:
            e.step(dt)
        if stage == 2 and t >= next_ring:
            rings.emit(1)
            next_ring = t + 0.8
        for i in range(strands):
            cycle = (t * 0.75 * speed + offsets[i]) % 1
            if cycle < last[i]:
                histories[i] = []
            last[i] = cycle
            radius = 1.6 - 0.6 * cycle
            angle = phases[i] + t * 5 * speed
            y = -2.8 + cycle * height
            p = (math.cos(angle) * radius, y, math.sin(angle) * radius)
            histories[i].append((t, p, 0.08 + 0.14 * (1 - cycle)))
            histories[i] = [h for h in histories[i] if t - h[0] <= 0.6]
        if f < 0:
            continue
        if f == 0 and stage == 1:
            flare.emit(1)  # replay the ignite flash at the start of the clip
        light = 1.4 + 0.8 * math.sin(t * math.pi * 4)

        bg = np.zeros((H, W, 3), dtype=np.float32)
        y, x = np.mgrid[0:H, 0:W]
        bx, by, _, _ = project((0, 0.4, 0))
        glow = np.exp(-(((x - bx) / 170) ** 2 + ((y - by) / 230) ** 2)) * 0.10 * light
        bg += np.dstack([np.full((H, W), c / 255) for c in (14, 15, 20)])
        bg += glow[..., None] * (np.array(GLOW) / 255)
        base = Image.fromarray(np.clip(bg * 255, 0, 255).astype(np.uint8))
        draw_body(base, light)
        canvas = np.asarray(base, dtype=np.float32) / 255

        add = np.zeros((H, W, 3), dtype=np.float32)
        # ground rings and the haze go behind the helix; the trails are drawn as glowing ribbons
        rings.draw(add)
        haze.draw(add)
        trail_layer = Image.new("RGB", (W, H), (0, 0, 0))
        td = ImageDraw.Draw(trail_layer)
        core_layer = Image.new("RGB", (W, H), (0, 0, 0))
        cd = ImageDraw.Draw(core_layer)
        for hist in histories:
            for (t0, p0, w0), (t1, p1, w1) in zip(hist, hist[1:]):
                age = (t - t1) / 0.6
                fade = max(0.0, 1 - age)
                s0, s1 = project(p0), project(p1)
                width = max(1, int(w1 * s1[2] * fade))
                col = shade_at(MAIN, [(0, 0.55), (1, 0)], age)
                td.line([s0[:2], s1[:2]], fill=tuple(int(c * fade) for c in col), width=width * 2)
                cd.line([s0[:2], s1[:2]], fill=tuple(int(255 * fade ** 2) for _ in range(3)), width=max(1, width // 2))
        add += np.asarray(trail_layer.filter(ImageFilter.GaussianBlur(5)), dtype=np.float32) / 255 * 1.1
        add += np.asarray(trail_layer, dtype=np.float32) / 255 * 0.55
        add += np.asarray(core_layer.filter(ImageFilter.GaussianBlur(1)), dtype=np.float32) / 255 * 0.5
        for e in streaks + [chevrons, flare]:
            e.draw(add)
        # a soft bloom on the bright parts, like Roblox's glow on LightEmission particles
        bloom = Image.fromarray(np.clip(add * 255, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(9))
        add += np.asarray(bloom, dtype=np.float32) / 255 * 0.6
        frame = np.clip(canvas + add, 0, 1)
        out_frames[f][:, offset_x:offset_x + W] = (frame * 255).astype(np.uint8)


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else ".")
    frames_dir = out / "lb_frames"
    frames_dir.mkdir(parents=True, exist_ok=True)
    n = int(SECONDS * FPS)
    frames = [np.zeros((H + 40, W * 2, 3), dtype=np.uint8) for _ in range(n)]
    for f in frames:
        f[:] = (14, 15, 20)
    simulate(1, [f[40:] for f in frames], 0)
    simulate(2, [f[40:] for f in frames], W)
    for i, f in enumerate(frames):
        img = Image.fromarray(f)
        d = ImageDraw.Draw(img)
        d.text((W / 2 - 60, 12), "LIMIT BREAKER - STAGE 1", fill=(230, 230, 235))
        d.text((W + W / 2 - 60, 12), "LIMIT BREAKER - STAGE 2", fill=(230, 230, 235))
        img.save(frames_dir / f"{i:04d}.png")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", str(frames_dir / "%04d.png"),
                    "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "18", str(out / "LimitBreaker.mp4")], check=True)
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(FPS), "-i", str(frames_dir / "%04d.png"),
                    "-vf", "fps=20,scale=720:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=200[p];[b][p]paletteuse=dither=sierra2_4a",
                    str(out / "LimitBreaker.gif")], check=True)
    print("wrote", out / "LimitBreaker.mp4", out / "LimitBreaker.gif")


if __name__ == "__main__":
    main()
