"""Original sound effects for every Eternium element move, synthesised from scratch (numpy only).

Each element gets its own palette of sounds so no two sound alike:
  Fire: roaring flame, crackle, whoomph   Electric: buzz, zap, thunder      Rift: glass shimmer, tearing
  Void: deep drone, suction, implosion    Nature: rustle, chimes, wood       Ice: frost hiss, crack, shatter
  Wind: gusts, whooshes, clap             Earth: rumble, grind, rock smash   Water: rush, splash, bubbles
  Energy: ki hum, charge, bright boom

Per element: Beam_Start, Beam_Loop (seamless), Blast_Cast, Blast_Hit, Ultimate (timed to the effect),
plus Electric_Strike (played on every lightning strike).

    python tools/vfx/sounds.py   -> ElementVFX/sounds/<Element>_<Move>.ogg (mono, 44.1 kHz)
"""
import math
import subprocess
import tempfile
import wave
from pathlib import Path

import numpy as np

SR = 44100
OUT = Path(__file__).resolve().parents[2] / "ElementVFX" / "sounds"
rng = np.random.default_rng(2024)


# ---------------------------------------------------------------- DSP basics


def T(sec):
    return np.arange(int(sec * SR)) / SR


def white(sec):
    return rng.standard_normal(int(sec * SR))


def spectral(x, gain_fn):
    """Static filter: multiply the spectrum by gain_fn(freqs)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * gain_fn(f), len(x))


def lowpass(x, fc, order=2):
    return spectral(x, lambda f: 1 / np.sqrt(1 + (f / fc) ** (2 * order)))


def highpass(x, fc, order=2):
    return spectral(x, lambda f: 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** (2 * order)))


def bandpass(x, fc, q=1.0):
    return spectral(x, lambda f: np.exp(-0.5 * (np.log2(np.maximum(f, 1) / fc) * q * 2) ** 2))


def pink(sec):
    return spectral(white(sec), lambda f: 1 / np.sqrt(np.maximum(f, 20)))


def brown(sec):
    return spectral(white(sec), lambda f: 1 / np.maximum(f, 20))


def moving_band(x, fc_fn, q_fn, n=2048, hop=512):
    """Time-varying band-pass via STFT: centre fc_fn(t) Hz, sharpness q_fn(t)."""
    win = np.hanning(n)
    out = np.zeros(len(x) + n)
    norm = np.zeros(len(x) + n)
    f = np.fft.rfftfreq(n, 1 / SR)
    for start in range(0, len(x), hop):
        seg = np.zeros(n)
        chunk = x[start:start + n]
        seg[:len(chunk)] = chunk
        t = (start + n / 2) / SR
        fc, q = fc_fn(t), q_fn(t)
        g = np.exp(-0.5 * (np.log2(np.maximum(f, 1) / fc) * q * 2) ** 2)
        y = np.fft.irfft(np.fft.rfft(seg * win) * g, n)
        out[start:start + n] += y * win
        norm[start:start + n] += win ** 2
    return (out / np.maximum(norm, 1e-6))[:len(x)]


def osc(freq_fn, sec, shape="sine", phase=0.0):
    """Oscillator with a time-varying frequency (freq_fn(t) array)."""
    t = T(sec)
    f = freq_fn(t) if callable(freq_fn) else np.full_like(t, freq_fn)
    ph = 2 * np.pi * np.cumsum(f) / SR + phase
    if shape == "sine":
        return np.sin(ph)
    if shape == "saw":
        return 2 * ((ph / (2 * np.pi)) % 1) - 1
    if shape == "square":
        return np.sign(np.sin(ph))
    if shape == "tri":
        return 2 * np.abs(2 * ((ph / (2 * np.pi)) % 1) - 1) - 1
    raise ValueError(shape)


def env(sec, points):
    """Piecewise-linear envelope from (time, value) points."""
    t = T(sec)
    ts, vs = zip(*points)
    return np.interp(t, ts, vs)


def expdecay(sec, tau, start=0.0):
    t = T(sec)
    return np.where(t >= start, np.exp(-(t - start) / tau), 0.0)


def place(dst, src, at, gain=1.0):
    i = int(at * SR)
    if i >= len(dst):
        return dst
    n = min(len(src), len(dst) - i)
    dst[i:i + n] += src[:n] * gain
    return dst


def crackle(sec, rate, decay=0.004, fc=3000, q=0.7, env_fn=None):
    """Random little pops (fire crackle, ice ticks, debris)."""
    x = np.zeros(int(sec * SR))
    n = rng.poisson(rate * sec)
    for _ in range(n):
        at = rng.uniform(0, sec)
        if env_fn is not None and rng.random() > env_fn(at):
            continue
        L = int(decay * 6 * SR)
        click = rng.standard_normal(L) * np.exp(-np.arange(L) / (decay * SR)) * rng.uniform(0.3, 1.0)
        place(x, click, at)
    return bandpass(x, fc, q)


def reverb(x, size=1.2, mix=0.25, damp=4000):
    """Convolution with a decaying, darkening noise tail."""
    L = int(size * SR)
    ir = rng.standard_normal(L) * np.exp(-np.arange(L) / (size * SR / 6))
    ir = lowpass(ir, damp, 1)
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    n = len(x) + L
    wet = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)[:len(x)]
    return x * (1 - mix) + wet * mix * 3


def thump(sec=0.6, f0=110, f1=38, decay=0.18, click=0.4):
    """A low impact: a falling sine plus a short click."""
    t = T(sec)
    body = osc(lambda tt: f1 + (f0 - f1) * np.exp(-tt / 0.06), sec) * np.exp(-t / decay)
    hit = lowpass(white(sec), 2500) * np.exp(-t / 0.012) * click
    return body + hit


def whoosh(sec, f_from, f_to, q=1.2, peak=0.5, kind="white"):
    noise = white(sec) if kind == "white" else pink(sec) * 20
    swept = moving_band(noise, lambda t: f_from * (f_to / f_from) ** min(1, t / sec), lambda t: q)
    e = env(sec, [(0, 0), (sec * peak, 1), (sec, 0)])
    return swept * e


def bell(freq, sec, partials=((1, 1), (2.76, 0.5), (5.4, 0.25), (8.9, 0.12)), decay=1.2):
    t = T(sec)
    x = np.zeros_like(t)
    for ratio, amp in partials:
        x += amp * np.sin(2 * np.pi * freq * ratio * t) * np.exp(-t / (decay / ratio ** 0.5))
    return x * np.minimum(1, t / 0.003)


def loopify(x, xfade=0.25):
    """Makes a sound loop seamlessly by crossfading its tail into its head."""
    n = int(xfade * SR)
    head, tail = x[:n], x[-n:]
    w = np.linspace(0, 1, n)
    body = x[n:-n] if len(x) > 2 * n else x
    blended = tail * (1 - w) + head * w
    return np.concatenate([blended, body])


def norm(x, peak=0.89, fade_in=0.002, fade_out=0.03):
    x = x - np.mean(x)
    n_in, n_out = int(fade_in * SR), int(fade_out * SR)
    if n_in:
        x[:n_in] *= np.linspace(0, 1, n_in)
    if n_out:
        x[-n_out:] *= np.linspace(1, 0, n_out)
    return x * min(1.0, peak / (np.max(np.abs(x)) + 1e-9))


def level(x, loop=False):
    """Even out loudness between sounds: the loudest 0.4 s (or a whole loop) sits at the same RMS,
    and anything that would poke above that is rounded off by a soft limiter."""
    x = highpass(x, 32)  # sub rumble below phone/laptop range only eats headroom
    win = int(0.4 * SR)
    if loop or len(x) <= win:
        rms = np.sqrt(np.mean(x ** 2))
    else:
        rms = np.sqrt(np.max(np.convolve(x ** 2, np.ones(win) / win, mode="valid")))
    x = x / (rms + 1e-9) * (0.13 if loop else 0.2)
    return np.tanh(x / 0.85) * 0.85


def mix(sec, *layers):
    out = np.zeros(int(sec * SR))
    for layer in layers:
        out[:min(len(out), len(layer))] += layer[:len(out)]
    return out


def save(x, name, loop=False):
    OUT.mkdir(parents=True, exist_ok=True)
    x = norm(level(x, loop), fade_out=0 if loop else 0.03, fade_in=0 if loop else 0.002)
    pcm = (x * 32767).astype(np.int16)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        with wave.open(tmp.name, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(pcm.tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", tmp.name, "-c:a", "libvorbis", "-q:a", "5", str(OUT / f"{name}.ogg")], check=True)
        Path(tmp.name).unlink()
    print(f"  {name:<22} {len(x) / SR:5.2f}s")


# ---------------------------------------------------------------- FIRE


def flame_roar(sec, intensity_fn=lambda t: 1.0):
    t = T(sec)
    body = lowpass(brown(sec), 900) * 6
    flutter = 1 + 0.35 * lowpass(white(sec), 12)
    mid = bandpass(pink(sec), 700, 0.8) * 25
    k = intensity_fn(t)
    pops = crackle(sec, 90, 0.003, 2600, 0.6)
    return (body * flutter + mid * 0.6) * k + pops * 1.4 * np.sqrt(np.clip(k, 0, None))


def fire():
    save(mix(1.0, thump(1.0, 140, 45, 0.25, 0.6) * 0.8, whoosh(1.0, 300, 2500, 1.0, 0.25) * 0.8, flame_roar(1.0, lambda t: np.clip(t / 0.15, 0, 1) * np.exp(-t / 0.6))), "Fire_Beam_Start")
    save(loopify(flame_roar(2.5)), "Fire_Beam_Loop", loop=True)
    save(mix(0.8, whoosh(0.8, 400, 1800, 1.0, 0.35), flame_roar(0.8, lambda t: np.exp(-t / 0.35)) * 0.7, crackle(0.8, 60, 0.003, 3000) * 0.6), "Fire_Blast_Cast")
    boom = thump(2.0, 120, 35, 0.45, 1.0) * 1.3
    blast = lowpass(white(2.0), 1800) * expdecay(2.0, 0.25)
    save(reverb(mix(2.0, boom, blast, flame_roar(2.0, lambda t: np.exp(-t / 0.7)) * 0.6, crackle(2.0, 120, 0.004, 2500, 0.6, lambda a: math.exp(-a / 0.8)) * 1.2), 1.4, 0.3), "Fire_Blast_Hit")
    sec = 6.0

    def intensity(t):
        return np.clip(t / 0.7, 0, 1) * 0.45 + np.where((t > 0.7) & (t < 3.4), 0.6, 0) + np.where(t >= 3.4, np.exp(-(t - 3.4) / 0.4) * 0.6, 0) - np.where(t >= 3.9, 0.25 * np.clip((t - 3.9) / 1.6, 0, 1), 0)
    ult = flame_roar(sec, lambda t: np.clip(intensity(t), 0, None))
    ult = place(ult, whoosh(0.6, 250, 2000, 1.0, 0.3), 0.0, 0.8)
    ult = place(ult, thump(1.2, 120, 40, 0.35, 0.8) * 1.4, 0.7)
    ult = place(ult, whoosh(1.2, 2500, 400, 0.8, 0.15), 0.7, 1.0)
    save(reverb(ult, 1.6, 0.25), "Fire_Ultimate")


# ---------------------------------------------------------------- ELECTRIC


def buzz(sec, f=118, wobble=0.0):
    t = T(sec)
    fm = lambda tt: f * (1 + wobble * np.sin(2 * np.pi * 7 * tt))
    x = osc(fm, sec, "saw") * 0.5 + osc(lambda tt: fm(tt) * 2.01, sec, "square") * 0.2
    return highpass(x, 200) * (1 + 0.6 * (rng.random(len(t)) < 0.002).astype(float) * 0)


def zaps(sec, rate, env_fn=None):
    """Bursts of electric crackle: short gated noise with a high resonance."""
    x = np.zeros(int(sec * SR))
    for _ in range(rng.poisson(rate * sec)):
        at = rng.uniform(0, sec)
        if env_fn is not None and rng.random() > env_fn(at):
            continue
        L = int(rng.uniform(0.01, 0.05) * SR)
        burst = rng.standard_normal(L) * (rng.random(L) < 0.35)
        place(x, burst * rng.uniform(0.4, 1.0), at)
    return highpass(x, 1800) + bandpass(x, 5200, 1.2) * 0.8


def thunder_crack(sec=1.6):
    t = T(sec)
    crack = highpass(white(sec), 900) * np.exp(-t / 0.05) * 1.6
    zz = zaps(sec, 60, lambda a: math.exp(-a / 0.15)) * 0.8
    rumble = lowpass(brown(sec), 220) * 12 * env(sec, [(0, 0), (0.06, 1), (sec, 0)]) * (1 + 0.5 * lowpass(white(sec), 6))
    return reverb(crack + zz + rumble, 1.5, 0.3)


def electric():
    save(mix(0.8, zaps(0.8, 40, lambda a: math.exp(-a / 0.2)) * 1.2, buzz(0.8, 118) * expdecay(0.8, 0.3) * 0.6, thump(0.8, 200, 60, 0.12, 0.6) * 0.5), "Electric_Beam_Start")
    save(loopify(mix(2.5, buzz(2.5, 118, 0.02) * 0.45, zaps(2.5, 26) * 0.9, bandpass(white(2.5), 3500, 0.7) * 0.15)), "Electric_Beam_Loop", loop=True)
    save(mix(0.7, zaps(0.7, 50, lambda a: math.exp(-a / 0.25)), whoosh(0.7, 800, 4000, 1.4, 0.3) * 0.6, buzz(0.7, 236) * expdecay(0.7, 0.2) * 0.4), "Electric_Blast_Cast")
    save(mix(1.8, thunder_crack(1.8), zaps(1.8, 80, lambda a: math.exp(-a / 0.3)) * 0.7), "Electric_Blast_Hit")
    save(thunder_crack(2.4), "Electric_Strike")
    sec = 6.8
    t = T(sec)
    storm = lowpass(brown(sec), 160) * 14 * env(sec, [(0, 0), (1.2, 1), (5.2, 1), (sec, 0)]) * (1 + 0.6 * lowpass(white(sec), 3))
    wind = moving_band(pink(sec) * 15, lambda tt: 400 + 200 * math.sin(tt * 1.3), lambda tt: 1.2) * env(sec, [(0, 0), (1.0, 0.6), (5.2, 0.6), (sec, 0)])
    hiss = highpass(white(sec), 4000) * 0.05 * env(sec, [(0, 0), (1.5, 1), (5.2, 1), (sec, 0)])  # rain-like hiss
    save(reverb(mix(sec, storm, wind, hiss, zaps(sec, 6, lambda a: 1.0 if 0.8 < a < 5.2 else 0.0) * 0.3), 2.0, 0.3), "Electric_Ultimate")


# ---------------------------------------------------------------- RIFT


def shimmer(sec, base=660, chord=(1, 1.5, 2.0, 2.997), beat=3.0):
    t = T(sec)
    x = np.zeros_like(t)
    for i, r in enumerate(chord):
        x += np.sin(2 * np.pi * base * r * t + i) * (1 + 0.5 * np.sin(2 * np.pi * (beat + i * 0.7) * t)) / (i + 1)
    return x


def glass_tinkle(sec, rate, env_fn=None, lo=2500, hi=7000):
    x = np.zeros(int(sec * SR))
    for _ in range(rng.poisson(rate * sec)):
        at = rng.uniform(0, sec)
        if env_fn is not None and rng.random() > env_fn(at):
            continue
        place(x, bell(rng.uniform(lo, hi), 0.4, decay=0.15) * rng.uniform(0.2, 0.8), at)
    return x


def rip(sec, f_from=300, f_to=4000):
    """Space tearing: a rising sweep of gritty, gated noise."""
    t = T(sec)
    grit = white(sec) * (rng.random(len(t)) < 0.5)
    return moving_band(grit, lambda tt: f_from * (f_to / f_from) ** min(1, tt / sec), lambda tt: 1.5) * env(sec, [(0, 0), (sec * 0.7, 1), (sec, 0.2)])


def rift():
    save(reverb(mix(0.9, rip(0.5) * 1.2, shimmer(0.9, 880) * expdecay(0.9, 0.35) * 0.25, glass_tinkle(0.9, 25, lambda a: math.exp(-a / 0.3)) * 0.6), 1.2, 0.3), "Rift_Beam_Start")
    save(loopify(reverb(mix(2.5, shimmer(2.5, 440, beat=2.2) * 0.22, highpass(pink(2.5), 2500) * 0.6, glass_tinkle(2.5, 10) * 0.4), 1.0, 0.25)), "Rift_Beam_Loop", loop=True)
    save(reverb(mix(0.7, whoosh(0.7, 1500, 6000, 1.5, 0.3) * 0.8, glass_tinkle(0.7, 20) * 0.5, shimmer(0.7, 1320) * expdecay(0.7, 0.2) * 0.2), 1.0, 0.25), "Rift_Blast_Cast")
    shatter = highpass(white(1.6), 2000) * expdecay(1.6, 0.06) * 1.2
    save(reverb(mix(1.6, shatter, glass_tinkle(1.6, 90, lambda a: math.exp(-a / 0.4)), thump(1.6, 160, 60, 0.15, 0.3) * 0.5), 1.3, 0.35), "Rift_Blast_Hit")
    sec = 6.0
    ult = np.zeros(int(sec * SR))
    ult = place(ult, glass_tinkle(1.0, 30, lambda a: (a / 1.0) ** 2, 1500, 5000), 0.0, 0.9)
    ult = place(ult, rip(0.6, 200, 5000) * 1.4, 1.0)
    ult = place(ult, thump(1.0, 90, 40, 0.3, 0.3), 1.55, 0.8)
    hum = (shimmer(3.4, 330, beat=1.6) * 0.35 + highpass(pink(3.4), 1800) * 0.5) * env(3.4, [(0, 0), (0.3, 1), (3.0, 1), (3.4, 0)])
    ult = place(ult, hum, 1.5)
    ult = place(ult, glass_tinkle(3.2, 8), 1.6, 0.5)
    snap = highpass(white(0.8), 1500) * expdecay(0.8, 0.04) * 1.5 + whoosh(0.8, 5000, 300, 1.2, 0.1)
    ult = place(ult, snap, 4.8)
    save(reverb(ult, 1.8, 0.35), "Rift_Ultimate")


# ---------------------------------------------------------------- VOID


def drone(sec, f=42):
    t = T(sec)
    x = osc(f, sec, "saw") * 0.6 + osc(f * 1.5, sec, "sine") * 0.3 + osc(f * 0.5, sec, "sine") * 0.6
    phase_ = moving_band(pink(sec) * 20, lambda tt: 300 + 220 * math.sin(tt * 0.9), lambda tt: 1.4)
    return lowpass(x, 400) + phase_ * 0.25


def suction(sec):
    """A reversed swell: noise and a falling tone pulled inward, ending abruptly."""
    t = T(sec)
    x = lowpass(white(sec), 2000) * (t / sec) ** 3
    tone = osc(lambda tt: 300 - 240 * tt / sec, sec) * (t / sec) ** 2
    return x + tone * 0.4


def void():
    save(mix(1.0, suction(0.5), place(np.zeros(int(SR)), thump(0.6, 70, 28, 0.25, 0.4), 0.48), drone(1.0, 45) * env(1.0, [(0, 0), (0.5, 0.3), (1.0, 0.2)])), "Void_Beam_Start")
    save(loopify(mix(2.5, drone(2.5, 44) * 0.8, whoosh(2.5, 200, 600, 1.0, 0.5) * 0.25 + lowpass(brown(2.5), 120) * 4)), "Void_Beam_Loop", loop=True)
    save(mix(0.8, suction(0.4) * 0.8, place(np.zeros(int(0.8 * SR)), thump(0.5, 90, 35, 0.15, 0.3), 0.38), whoosh(0.8, 600, 200, 1.0, 0.2) * 0.5), "Void_Blast_Cast")
    save(reverb(mix(2.0, suction(0.6), place(np.zeros(int(2 * SR)), thump(1.4, 80, 25, 0.5, 0.8) * 1.4, 0.58), place(np.zeros(int(2 * SR)), lowpass(brown(1.4), 300) * 10 * expdecay(1.4, 0.4), 0.58)), 2.0, 0.35), "Void_Blast_Hit")
    sec = 8.0
    t = T(sec)
    ult = drone(sec, 38) * env(sec, [(0, 0), (0.8, 0.6), (6.6, 1.0), (6.8, 0.5), (sec, 0)])
    swirl = moving_band(pink(sec) * 25, lambda tt: 250 + 150 * math.sin(tt * 3.2) + 40 * tt, lambda tt: 1.3) * env(sec, [(0, 0), (1.0, 0.5), (6.8, 1.0), (7.0, 0), (sec, 0)])
    ult = ult + swirl * 0.6
    ult = place(ult, suction(0.8) * 1.1, 0.0)
    ult = place(ult, thump(1.0, 60, 25, 0.4, 0.5), 0.78)
    ult = place(ult, suction(0.5), 6.4)
    ult = place(ult, thump(1.4, 90, 22, 0.6, 1.0) * 1.6, 6.9)
    save(reverb(ult, 2.4, 0.35), "Void_Ultimate")


# ---------------------------------------------------------------- NATURE


def rustle(sec, density=1.0):
    t = T(sec)
    leaves = crackle(sec, 400 * density, 0.002, 3500, 0.5)
    air = bandpass(pink(sec) * 20, 1200, 0.6) * (0.6 + 0.4 * lowpass(white(sec), 2))
    return leaves * 0.8 + air * 0.3


def chimes(sec, notes, start=0.0, step=0.12, base=523.25):
    x = np.zeros(int(sec * SR))
    for i, n in enumerate(notes):
        place(x, bell(base * 2 ** (n / 12), 1.4, decay=0.8) * 0.5, start + i * step)
    return x


def creak(sec, f0=90):
    t = T(sec)
    f = lambda tt: f0 + 25 * np.sin(2 * np.pi * 0.7 * tt)
    pulses = osc(f, sec, "saw") * (0.5 + 0.5 * np.sin(2 * np.pi * 3 * t))
    return bandpass(pulses, 600, 0.8)


def nature():
    save(reverb(mix(0.9, rustle(0.9) * env(0.9, [(0, 0), (0.1, 1), (0.9, 0)]), chimes(0.9, [0, 7, 12], 0.05, 0.08)), 1.2, 0.3), "Nature_Beam_Start")
    loop = mix(2.5, rustle(2.5, 0.8), whoosh(2.5, 500, 900, 0.8, 0.5) * 0.3, chimes(2.5, [0, 4, 7, 12, 7, 4], 0.1, 0.4) * 0.35)
    save(loopify(reverb(loop, 1.0, 0.25)), "Nature_Beam_Loop", loop=True)
    save(reverb(mix(0.7, whoosh(0.7, 700, 2200, 0.9, 0.3), rustle(0.7) * expdecay(0.7, 0.3), chimes(0.7, [12, 16], 0.02, 0.06) * 0.6), 1.0, 0.25), "Nature_Blast_Cast")
    knock = bandpass(thump(1.5, 220, 120, 0.08, 0.6), 400, 0.8) * 1.5
    save(reverb(mix(1.5, knock, rustle(1.5, 1.6) * expdecay(1.5, 0.4) * 1.2, chimes(1.5, [12, 7, 4, 0], 0.02, 0.07) * 0.8), 1.4, 0.3), "Nature_Blast_Hit")
    sec = 6.0
    ult = np.zeros(int(sec * SR))
    ult = place(ult, rustle(0.6) * env(0.6, [(0, 0), (0.2, 1), (0.6, 0.4)]), 0.0)
    ult = place(ult, chimes(1.0, [0, 12], 0, 0.1) * 0.7, 0.0)
    ult = place(ult, creak(1.9, 85) * env(1.9, [(0, 0), (0.3, 1), (1.9, 0.3)]) * 0.9, 0.6)
    ult = place(ult, lowpass(brown(1.9), 300) * 6 * env(1.9, [(0, 0), (0.4, 1), (1.9, 0)]), 0.6)
    ult = place(ult, chimes(2.0, [0, 4, 7, 11, 14, 19], 0, 0.3), 0.6)
    pad = sum(osc(523.25 * 2 ** (n / 12) / 2, 2.6) for n in (0, 4, 7, 11)) * env(2.6, [(0, 0), (0.5, 0.25), (2.1, 0.25), (2.6, 0)])
    ult = place(ult, pad, 2.4)
    ult = place(ult, rustle(2.6, 0.7) * 0.6, 2.4)
    ult = place(ult, whoosh(1.0, 1500, 400, 0.9, 0.3) * 0.6, 4.8)
    ult = place(ult, chimes(1.2, [19, 14, 11, 7, 4, 0], 0, 0.12) * 0.6, 4.8)
    save(reverb(ult, 2.0, 0.35), "Nature_Ultimate")


# ---------------------------------------------------------------- ICE


def frost_hiss(sec):
    return highpass(white(sec), 5000) * 0.6 + bandpass(white(sec), 8000, 1.0) * 0.4


def ice_crack(sec=0.6, f=2500):
    t = T(sec)
    snap = highpass(white(sec), 1500) * np.exp(-t / 0.015) * 1.5
    ring_ = bell(f, sec, decay=0.25) * 0.4
    return snap + ring_ + crackle(sec, 200, 0.002, 4000, 0.6) * np.exp(-t / 0.1)


def ice():
    save(reverb(mix(0.9, ice_crack(0.9, 3100), frost_hiss(0.9) * env(0.9, [(0, 0), (0.05, 1), (0.9, 0)]) * 0.6), 1.2, 0.3), "Ice_Beam_Start")
    save(loopify(reverb(mix(2.5, frost_hiss(2.5) * 0.5, crackle(2.5, 120, 0.002, 4500, 0.6) * 0.9, glass_tinkle(2.5, 12, None, 3000, 8000) * 0.4, moving_band(pink(2.5) * 12, lambda tt: 900 + 300 * math.sin(tt * 2), lambda tt: 1.3) * 0.3), 1.0, 0.25)), "Ice_Beam_Loop", loop=True)
    save(reverb(mix(0.7, whoosh(0.7, 2000, 7000, 1.4, 0.3) * 0.7, frost_hiss(0.7) * expdecay(0.7, 0.3) * 0.5, glass_tinkle(0.7, 25, None, 4000, 9000) * 0.5), 1.0, 0.25), "Ice_Blast_Cast")
    smash = highpass(white(1.8), 1200) * expdecay(1.8, 0.08) * 1.4
    save(reverb(mix(1.8, smash, thump(1.8, 150, 60, 0.15, 0.4) * 0.6, glass_tinkle(1.8, 110, lambda a: math.exp(-a / 0.5), 2500, 9000)), 1.5, 0.35), "Ice_Blast_Hit")
    sec = 7.0
    ult = np.zeros(int(sec * SR))
    ult = place(ult, thump(1.0, 110, 35, 0.3, 0.8) * 1.4, 0.0)
    ult = place(ult, frost_hiss(0.8) * env(0.8, [(0, 0), (0.1, 1), (0.8, 0)]) * 0.7, 0.0)
    ult = place(ult, crackle(0.8, 300, 0.002, 4000, 0.5), 0.05)
    for k in range(5):
        ult = place(ult, ice_crack(0.6, 2200 + 300 * k) * 0.8, 0.4 + k * 0.16)
    for k in range(7):  # the wall rises section by section
        at = 1.2 + k * 0.2
        ult = place(ult, thump(0.6, 160, 70, 0.12, 0.3) * 0.8, at)
        ult = place(ult, ice_crack(0.6, 1600 + 150 * k) * 0.6, at + 0.02)
    grind = bandpass(white(1.6), 900, 1.0) * env(1.6, [(0, 0), (0.2, 1), (1.4, 1), (1.6, 0)]) * 0.5
    ult = place(ult, grind, 1.2)
    cold = moving_band(pink(2.8) * 15, lambda tt: 700 + 200 * math.sin(tt), lambda tt: 1.2) * env(2.8, [(0, 0), (0.4, 0.4), (2.4, 0.4), (2.8, 0)])
    ult = place(ult, cold, 2.6)
    shatter = highpass(white(1.6), 1200) * expdecay(1.6, 0.12) * 1.5
    ult = place(ult, shatter + glass_tinkle(1.6, 140, lambda a: math.exp(-a / 0.6), 2000, 9000), 5.4)
    save(reverb(ult, 1.8, 0.35), "Ice_Ultimate")


# ---------------------------------------------------------------- WIND


def gust(sec, f_lo=300, f_hi=1500, speed=0.8):
    return moving_band(pink(sec) * 25, lambda tt: f_lo + (f_hi - f_lo) * (0.5 + 0.5 * math.sin(tt * speed * 2 * math.pi)), lambda tt: 1.0)


def wind():
    save(mix(0.8, whoosh(0.8, 300, 3000, 1.0, 0.2) * 1.2, thump(0.8, 120, 50, 0.1, 0.5) * 0.4), "Wind_Beam_Start")
    save(loopify(mix(2.5, gust(2.5, 350, 1600, 0.6), gust(2.5, 900, 2600, 1.3) * 0.5, lowpass(brown(2.5), 150) * 3)), "Wind_Beam_Loop", loop=True)
    save(mix(0.6, whoosh(0.6, 400, 4000, 1.3, 0.35) * 1.3, whoosh(0.6, 2500, 600, 1.0, 0.6) * 0.5), "Wind_Blast_Cast")
    save(reverb(mix(1.4, thump(1.4, 100, 40, 0.18, 0.6), whoosh(1.4, 3000, 300, 0.9, 0.08) * 1.0, crackle(1.4, 80, 0.003, 2500, 0.6, lambda a: math.exp(-a / 0.4)) * 0.4), 1.2, 0.25), "Wind_Blast_Hit")
    sec = 2.4
    t = T(sec)
    clap = highpass(white(0.25), 800) * np.exp(-T(0.25) / 0.008) * 2.0
    ult = np.zeros(int(sec * SR))
    ult = place(ult, clap, 0.15)
    ult = place(ult, thump(1.6, 90, 30, 0.35, 0.3) * 1.4, 0.16)
    ult = place(ult, whoosh(2.0, 2500, 200, 0.9, 0.05) * 1.3, 0.16)
    ult = place(ult, gust(2.0, 300, 1200, 0.5) * env(2.0, [(0, 0), (0.1, 0.7), (2.0, 0)]), 0.2)
    ult = place(ult, crackle(1.5, 100, 0.003, 2200, 0.6, lambda a: math.exp(-a / 0.5)) * 0.5, 0.3)
    save(reverb(ult, 1.6, 0.35), "Wind_Ultimate")


# ---------------------------------------------------------------- EARTH


def rumble(sec, fc=120):
    return lowpass(brown(sec), fc) * 14 * (1 + 0.5 * lowpass(white(sec), 5))


def rock_smash(sec=1.8):
    t = T(sec)
    body = thump(sec, 100, 30, 0.5, 1.0) * 1.4
    crunch = bandpass(white(sec), 1200, 0.6) * np.exp(-t / 0.08)
    debris = crackle(sec, 120, 0.006, 1500, 0.6, lambda a: math.exp(-a / 0.6)) * 1.8
    return body + crunch + debris


def earth():
    save(reverb(mix(1.0, rock_smash(1.0) * 0.6, rumble(1.0) * expdecay(1.0, 0.5)), 1.0, 0.25), "Earth_Beam_Start")
    save(loopify(mix(2.5, rumble(2.5, 160), crackle(2.5, 40, 0.008, 1200, 0.6) * 1.6, bandpass(white(2.5), 700, 1.0) * 0.2)), "Earth_Beam_Loop", loop=True)
    save(mix(0.8, whoosh(0.8, 150, 900, 1.0, 0.4) * 1.2, rumble(0.8) * expdecay(0.8, 0.3) * 0.6, crackle(0.8, 30, 0.008, 1000) * 0.8), "Earth_Blast_Cast")
    save(reverb(rock_smash(2.0), 1.5, 0.3), "Earth_Blast_Hit")
    sec = 6.8
    ult = np.zeros(int(sec * SR))
    ult = place(ult, thump(1.2, 100, 30, 0.4, 0.9) * 1.4, 0.0)
    fissure = (rumble(0.9, 300) + crackle(0.9, 200, 0.004, 1500, 0.6) * 1.5) * env(0.9, [(0, 0), (0.2, 1), (0.9, 0.5)])
    ult = place(ult, fissure, 0.2)
    ult = place(ult, (rumble(1.0, 200) + bandpass(white(1.0), 500, 1.0) * 0.4) * env(1.0, [(0, 0), (0.3, 1), (1.0, 0)]), 0.6)
    for k in range(5):
        ult = place(ult, rock_smash(0.8) * 0.5, 1.2 + k * 0.17)
    ult = place(ult, rumble(2.2, 90) * env(2.2, [(0, 0.4), (2.2, 0.6)]) + crackle(2.2, 30, 0.008, 1200) * 0.6, 1.6)
    ult = place(ult, rock_smash(2.2) * 1.5, 3.8)
    ult = place(ult, rumble(2.0, 80) * env(2.0, [(0, 0.8), (2.0, 0)]), 4.4)
    save(reverb(ult, 1.8, 0.3), "Earth_Ultimate")


# ---------------------------------------------------------------- WATER


def rush(sec):
    t = T(sec)
    return bandpass(white(sec), 900, 0.5) * (0.7 + 0.3 * lowpass(white(sec), 4)) + highpass(white(sec), 3000) * 0.2


def bubbles(sec, rate):
    x = np.zeros(int(sec * SR))
    for _ in range(rng.poisson(rate * sec)):
        f = rng.uniform(400, 1400)
        L = 0.06
        tt = T(L)
        b = np.sin(2 * np.pi * (f + f * 2.5 * tt / L) * tt) * np.exp(-tt / 0.015)
        place(x, b * rng.uniform(0.2, 0.6), rng.uniform(0, sec))
    return x


def splash(sec=1.5):
    t = T(sec)
    hit = bandpass(white(sec), 1500, 0.4) * np.exp(-t / 0.12) * 1.4
    droplets = crackle(sec, 150, 0.004, 3000, 0.7, lambda a: math.exp(-a / 0.4))
    return hit + droplets + bubbles(sec, 40) * 0.6 + lowpass(white(sec), 300) * np.exp(-t / 0.2) * 0.8


def water():
    save(mix(0.9, splash(0.9) * 0.8, rush(0.9) * env(0.9, [(0, 0), (0.15, 1), (0.9, 0.3)])), "Water_Beam_Start")
    save(loopify(mix(2.5, rush(2.5), bubbles(2.5, 30) * 0.5, crackle(2.5, 80, 0.003, 3500, 0.7) * 0.4)), "Water_Beam_Loop", loop=True)
    save(mix(0.7, whoosh(0.7, 500, 2500, 1.0, 0.35) * 0.9, bubbles(0.7, 30) * 0.5, crackle(0.7, 50, 0.003, 3500) * 0.5), "Water_Blast_Cast")
    save(reverb(splash(1.6), 1.2, 0.3), "Water_Blast_Hit")
    sec = 6.5
    ult = np.zeros(int(sec * SR))
    swell = rush(4.0) * env(4.0, [(0, 0), (1.5, 0.7), (3.8, 1.0), (4.0, 0.8)]) + lowpass(brown(4.0), 200) * 10 * env(4.0, [(0, 0), (1.5, 0.5), (4.0, 1.0)])
    ult = place(ult, swell, 0.0)
    ult = place(ult, splash(2.2) * 1.6, 4.0)
    ult = place(ult, thump(1.4, 80, 30, 0.4, 0.6) * 1.2, 4.0)
    foam = (highpass(white(2.0), 2500) * 0.5 + bubbles(2.0, 80) * 0.5) * env(2.0, [(0, 0.8), (2.0, 0)])
    ult = place(ult, foam, 4.5)
    save(reverb(ult, 1.6, 0.3), "Water_Ultimate")


# ---------------------------------------------------------------- ENERGY


def ki_hum(sec, f=96, rise=0.0):
    t = T(sec)
    fr = lambda tt: f * (1 + rise * tt / sec)
    x = osc(fr, sec, "saw") + osc(lambda tt: fr(tt) * 1.005, sec, "saw") + osc(lambda tt: fr(tt) * 2.002, sec, "saw") * 0.5
    return lowpass(x, 1800) * 0.4 + bandpass(pink(sec) * 15, 1100, 0.6) * 0.35


def sparkle(sec, rate):
    return glass_tinkle(sec, rate, None, 3000, 7000) * 0.5


def energy():
    burst = thump(1.0, 180, 60, 0.15, 0.6) * 0.7 + whoosh(1.0, 400, 3500, 1.0, 0.15)
    save(reverb(mix(1.0, burst, ki_hum(1.0, 110) * env(1.0, [(0, 0), (0.1, 1), (1.0, 0.4)])), 1.0, 0.25), "Energy_Beam_Start")
    save(loopify(mix(2.5, ki_hum(2.5, 110), sparkle(2.5, 10))), "Energy_Beam_Loop", loop=True)
    save(mix(0.7, whoosh(0.7, 600, 3500, 1.2, 0.3), osc(lambda tt: 400 + 900 * tt / 0.7, 0.7) * expdecay(0.7, 0.25) * 0.4), "Energy_Blast_Cast")
    boom = thump(2.0, 160, 40, 0.5, 1.0) * 1.3 + lowpass(white(2.0), 3000) * expdecay(2.0, 0.2)
    save(reverb(mix(2.0, boom, sparkle(2.0, 40) * expdecay(2.0, 0.5)), 1.6, 0.35), "Energy_Blast_Hit")
    sec = 9.2
    ult = np.zeros(int(sec * SR))
    charge = ki_hum(6.5, 70, 1.4) * env(6.5, [(0, 0), (1.0, 0.5), (6.3, 1.0), (6.5, 0.6)])
    ult = place(ult, charge, 0.0)
    ult = place(ult, sparkle(6.5, 25) * env(6.5, [(0, 0), (6.5, 1)]), 0.0)
    ult = place(ult, whoosh(0.6, 300, 1500, 1.0, 0.4) * 1.2, 6.5)
    ult = place(ult, rumble(0.5, 150) * 0.6, 6.5)
    ult = place(ult, thump(2.2, 120, 25, 0.7, 1.0) * 1.8, 7.0)
    ult = place(ult, lowpass(white(2.2), 2500) * expdecay(2.2, 0.35) * 1.2, 7.0)
    ult = place(ult, rumble(2.2, 100) * env(2.2, [(0, 1), (2.2, 0)]), 7.0)
    save(reverb(ult, 2.2, 0.35), "Energy_Ultimate")


def main():
    for fn in (fire, electric, rift, void, nature, ice, wind, earth, water, energy):
        print(fn.__name__.title())
        fn()


if __name__ == "__main__":
    main()
