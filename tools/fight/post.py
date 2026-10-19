"""Post-processing for the rendered fight frames: bloom, grade, camera shake, anime impact frames, speed
lines, white-out, fade and the logo card. Then encodes the MP4.

    python post.py FRAMES_DIR OUT.mp4 [--step N]

FRAMES_DIR holds f0001.png ... (rendered with 10% overscan) and post.json (the cues from choreo.py).
"""
import json
import math
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1280, 720
FPS = 30
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"


def t_of(frame):
    return (frame - 1) / FPS


def noise1(x, seed):
    """Smooth 1D value noise in [-1, 1]."""
    i = math.floor(x)
    f = x - i

    def h(n):
        return math.sin(n * 127.1 + seed * 311.7) * 43758.5453 % 1.0 * 2 - 1

    u = f * f * (3 - 2 * f)
    return h(i) * (1 - u) + h(i + 1) * u


def shake_offset(t, cues):
    amp = 0.0
    for t0, a, dur in cues:
        if t0 <= t <= t0 + dur:
            k = (t - t0) / dur
            amp += a * (1 - k) ** 2 if dur < 1.5 else a  # long cues are a steady rumble
    px = 22 * amp
    return noise1(t * 38, 1) * px, noise1(t * 38, 2) * px * 0.8


def bloom(img):
    bright = np.clip(img - 0.62, 0, None)
    pil = Image.fromarray(np.clip(bright * 255 * 1.3, 0, 255).astype(np.uint8))
    out = np.zeros_like(img)
    for scale, radius, weight in ((4, 3, 0.55), (8, 6, 0.45), (16, 8, 0.35)):
        small = pil.resize((pil.width // scale, pil.height // scale), Image.BILINEAR).filter(ImageFilter.GaussianBlur(radius))
        out += np.asarray(small.resize(pil.size, Image.BILINEAR), np.float32) / 255 * weight / 1.3
    return img + out


def grade(img, vig):
    img = img * 1.32  # exposure lift: the render is graded dark on purpose for the glow to read
    lum = img @ np.array([0.299, 0.587, 0.114], np.float32)
    img = lum[..., None] + (img - lum[..., None]) * 1.12  # a touch more saturation
    img = img / (1 + img * 0.35) * 1.3  # soft shoulder so the glows roll off instead of clipping
    img = np.clip(img, 0, 1)
    img = img * img * (3 - 2 * img) * 0.35 + img * 0.65  # gentle S-curve
    return img * vig


def impact(img, k):
    """Anime impact frame: inverted, high-contrast monochrome with a violet tint."""
    lum = img @ np.array([0.299, 0.587, 0.114], np.float32)
    if k == 0:
        m = 1 - np.clip((lum - 0.15) * 3, 0, 1)
        return np.stack([m * 0.95, m * 0.85, m], axis=2)
    m = np.clip((lum - 0.2) * 4, 0, 1)
    return np.stack([m, m * 0.9, m * 1.0], axis=2) * 0.9 + np.array([0.08, 0.0, 0.14]) * (1 - m[..., None])


def speed_lines(img, kind, t, rng_seed):
    rng = np.random.default_rng(int(t * 1000) + rng_seed)
    layer = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(layer)
    if kind == "radial":
        cx, cy = W / 2, H / 2
        for _ in range(70):
            a = rng.uniform(0, 2 * math.pi)
            r0 = rng.uniform(260, 420)
            r1 = r0 + rng.uniform(250, 600)
            d.line([(cx + math.cos(a) * r0, cy + math.sin(a) * r0), (cx + math.cos(a) * r1, cy + math.sin(a) * r1)],
                   fill=int(rng.uniform(90, 200)), width=int(rng.uniform(1, 4)))
    else:
        for _ in range(40):
            y = rng.uniform(0, H)
            if abs(y - H * 0.55) < H * 0.2 and rng.random() < 0.7:
                continue  # keep the action band clearer
            x0 = rng.uniform(-200, W)
            d.line([(x0, y), (x0 + rng.uniform(200, 700), y)], fill=int(rng.uniform(70, 170)), width=int(rng.uniform(1, 3)))
    a = np.asarray(layer.filter(ImageFilter.GaussianBlur(0.8)), np.float32)[..., None] / 255
    return img * (1 - a * 0.5) + a * 0.85


def logo_card(t, t0, t1):
    """The ETERNIUM title on black, glowing violet-to-cyan, easing in."""
    k = min(1.0, (t - t0) / 0.6)
    k = k * k * (3 - 2 * k)
    font = ImageFont.truetype(FONT, 118)
    text = "ETERNIUM"
    spacing = 18 + 10 * (1 - k)
    widths = [font.getlength(c) for c in text]
    total = sum(widths) + spacing * (len(text) - 1)
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(mask)
    x = (W - total) / 2
    for c, w in zip(text, widths):
        d.text((x, H / 2 - 78), c, font=font, fill=255)
        x += w + spacing
    m = np.asarray(mask, np.float32) / 255
    glow = np.asarray(mask.filter(ImageFilter.GaussianBlur(14)), np.float32) / 255
    glow2 = np.asarray(mask.filter(ImageFilter.GaussianBlur(40)), np.float32) / 255
    xs = np.linspace(0, 1, W)[None, :, None]
    tint = np.array([0.62, 0.32, 1.0]) * (1 - xs) + np.array([0.24, 0.9, 0.95]) * xs
    img = glow2[..., None] * tint * 0.9 + glow[..., None] * tint * 1.4 + m[..., None] * (0.75 + 0.25 * tint)
    # a thin line under the title
    y = int(H / 2 + 72)
    half = int(260 * k)
    img[y:y + 2, W // 2 - half:W // 2 + half] += tint[0, W // 2 - half:W // 2 + half] * 1.2
    return np.clip(img * k, 0, 1)


def main():
    src, out = sys.argv[1], sys.argv[2]
    step = int(sys.argv[sys.argv.index("--step") + 1]) if "--step" in sys.argv else 1
    cues = json.load(open(os.path.join(src, "post.json")))
    files = sorted(f for f in os.listdir(src) if f.startswith("f") and f.endswith(".png"))
    tmp = os.path.join(src, "post")
    os.makedirs(tmp, exist_ok=True)
    yy, xx = np.mgrid[0:H, 0:W]
    vig = (1 - 0.32 * (((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2) ** 1.5)[..., None].astype(np.float32)
    impacts = {}
    for t0, n in cues["impact"]:
        f0 = 1 + round(t0 * FPS)
        for k in range(n):
            impacts[f0 + k] = k
    n_out = 0
    for name in files:
        frame = int(name[1:5])
        t = t_of(frame)
        src_img = Image.open(os.path.join(src, name)).convert("RGB")
        ow, oh = src_img.size
        cw, ch = round(ow / 1.1), round(oh / 1.1)
        dx, dy = shake_offset(t, cues["shake"])
        scale = ow / 1408
        x0 = (ow - cw) / 2 + dx * scale
        y0 = (oh - ch) / 2 + dy * scale
        x0 = min(max(x0, 0), ow - cw)
        y0 = min(max(y0, 0), oh - ch)
        crop = src_img.crop((round(x0), round(y0), round(x0) + cw, round(y0) + ch)).resize((W, H), Image.LANCZOS)
        img = np.asarray(crop, np.float32) / 255
        img = grade(bloom(img), vig)
        for t0, t1, kind in cues["speed"]:
            if t0 <= t <= t1:
                img = speed_lines(img, kind, t, 7)
        if frame in impacts:
            img = impact(img, impacts[frame])
        for t0, peak, dur in cues["white"]:
            if t0 <= t <= t0 + dur + peak:
                k = 1.0 if t < t0 + peak else 1 - (t - t0 - peak) / dur
                img = img * (1 - k) + k
        for t0, t1 in cues["fade"]:
            if t >= t0:
                k = min(1.0, (t - t0) / (t1 - t0))
                img = img * (1 - k)
        if cues["logo"] and t >= cues["logo"][0]:
            img = logo_card(t, *cues["logo"])
        Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)).save(os.path.join(tmp, f"{n_out:04d}.png"))
        n_out += 1
    rate = FPS / step
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(rate), "-i", os.path.join(tmp, "%04d.png"),
                    "-c:v", "libx264", "-preset", "slow", "-crf", "17", "-pix_fmt", "yuv420p", "-r", "30",
                    "-movflags", "+faststart", out], check=True)
    print("wrote", out, n_out, "frames")


if __name__ == "__main__":
    main()
