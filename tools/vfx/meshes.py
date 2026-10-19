"""Toon VFX mesh library for Eternium element effects (v2), written straight to OBJ in Roblox axes.

Roblox axes: X right, Y up, Z back (a part's LookVector is -Z). Every mesh fills the box -0.5..0.5 on
each axis it spans, so a MeshPart's Size scales it directly (Size.Z = length for the beam-aligned ones).

    python tools/vfx/meshes.py   -> ElementVFX/meshes/<Name>.obj

Import the OBJs with Studio's 3D Importer into ReplicatedStorage.Eternium.VFXMeshes (one MeshPart each,
named as the file). The effects clone them; they are drawn as solid glowing shapes (Neon), so they need
no textures.
"""
import math
import random
from pathlib import Path

import numpy as np

OUT = Path(__file__).resolve().parents[2] / "ElementVFX" / "meshes"


class Mesh:
    def __init__(self):
        self.v = []
        self.f = []

    def vert(self, p):
        self.v.append(tuple(float(c) for c in p))
        return len(self.v) - 1

    def quad(self, a, b, c, d):
        self.f.append((a, b, c))
        self.f.append((a, c, d))

    def tri(self, a, b, c):
        self.f.append((a, b, c))

    def loft(self, rings, closed_rings=True, cap=True):
        """Skins a list of rings (each a list of points)."""
        idx = [[self.vert(p) for p in r] for r in rings]
        n = len(rings[0])
        for r0, r1 in zip(idx, idx[1:]):
            for j in range(n if closed_rings else n - 1):
                k = (j + 1) % n
                self.quad(r0[j], r1[j], r1[k], r0[k])
        if cap and closed_rings:
            for ring, flip in ((idx[0], True), (idx[-1], False)):
                c = self.vert(np.mean([self.v[i] for i in ring], axis=0))
                for j in range(n):
                    k = (j + 1) % n
                    self.tri(c, ring[k], ring[j]) if flip else self.tri(c, ring[j], ring[k])

    def normalise(self, axes=(True, True, True)):
        """Fits the mesh into the -0.5..0.5 box (per axis, only where it spans)."""
        a = np.array(self.v)
        lo, hi = a.min(0), a.max(0)
        c = (lo + hi) / 2
        span = hi - lo
        for i in range(3):
            if axes[i] and span[i] > 1e-6:
                a[:, i] = (a[:, i] - c[i]) / span[i]
            else:
                a[:, i] = a[:, i] - c[i]
        self.v = [tuple(p) for p in a]
        return self

    def write(self, name):
        OUT.mkdir(parents=True, exist_ok=True)
        a = np.array(self.v)
        # smooth vertex normals
        nrm = np.zeros_like(a)
        for f in self.f:
            p0, p1, p2 = a[list(f)]
            n = np.cross(p1 - p0, p2 - p0)
            for i in f:
                nrm[i] += n
        nrm /= np.linalg.norm(nrm, axis=1, keepdims=True) + 1e-9
        with open(OUT / f"{name}.obj", "w") as fh:
            fh.write(f"# Eternium VFX mesh {name} (Roblox axes: Y up, -Z forward)\no {name}\n")
            for p in a:
                fh.write(f"v {p[0]:.5f} {p[1]:.5f} {p[2]:.5f}\n")
            for n in nrm:
                fh.write(f"vn {n[0]:.4f} {n[1]:.4f} {n[2]:.4f}\n")
            for f in self.f:
                fh.write("f " + " ".join(f"{i + 1}//{i + 1}" for i in f) + "\n")
        print(f"  {name:<12} {len(self.f):>5} tris  span {np.ptp(a, 0).round(2)}")


def frame(t):
    t = t / np.linalg.norm(t)
    up = np.array([0, 1.0, 0]) if abs(t[1]) < 0.9 else np.array([1.0, 0, 0])
    n = np.cross(t, up)
    n /= np.linalg.norm(n)
    return n, np.cross(n, t)


def tube(m, pts, radii, sides=6):
    rings = []
    for i, p in enumerate(pts):
        t = pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]
        n, b = frame(t)
        r = radii[i]
        rings.append([p + (n * math.cos(2 * math.pi * j / sides) + b * math.sin(2 * math.pi * j / sides)) * max(r, 1e-4) for j in range(sides)])
    m.loft(rings)


# ---------------------------------------------------------------- meshes


def spiral(turns=2.0, strands=2, width=0.18, thick=0.05, steps=96):
    """Twisting flat ribbons around the Z axis (beam wraps). Length along Z."""
    m = Mesh()
    for s in range(strands):
        ph = 2 * math.pi * s / strands
        rings = []
        for i in range(steps + 1):
            t = i / steps
            a = ph + 2 * math.pi * turns * t
            c = np.array([math.cos(a) * 0.5, math.sin(a) * 0.5, -t])
            radial = np.array([math.cos(a), math.sin(a), 0.0])
            along = np.array([-math.sin(a), math.cos(a), -0.35])
            along /= np.linalg.norm(along)
            side = np.cross(radial, along)
            w = width / 2
            rings.append([c + side * w + radial * thick, c - side * w + radial * thick, c - side * w - radial * thick, c + side * w - radial * thick])
        m.loft(rings)
    return m.normalise()


def flame_cone(points=7, rings_n=24, seed=1):
    """A roaring cone of flame pointing along -Z: star cross-section with wavy flame tongues that
    lengthen towards the open end. Tip at -Z."""
    rng = random.Random(seed)
    m = Mesh()
    phases = [rng.uniform(0, 6.28) for _ in range(points)]
    lens = [rng.uniform(0.8, 1.2) for _ in range(points)]
    rings = []
    for i in range(rings_n + 1):
        t = i / rings_n  # 0 tip -> 1 mouth
        ring = []
        for k in range(points * 2):
            a = 2 * math.pi * k / (points * 2) + t * 0.8
            outer = k % 2 == 0
            r = (0.5 if outer else 0.3) * t ** 0.8 * (lens[k // 2] if outer else 1.0)
            r *= 1 + 0.12 * math.sin(t * 9 + phases[k // 2])
            ring.append(np.array([math.cos(a) * r, math.sin(a) * r, -1 + t]))
        rings.append(ring)
    m.loft(rings, cap=False)
    return m.normalise()


def tongue(seed=3, steps=20, sides=8):
    """One curling flame tongue rising along +Y: a fat bulb tapering to a hooked tip."""
    rng = random.Random(seed)
    m = Mesh()
    pts, radii = [], []
    lean = rng.uniform(0.15, 0.3)
    for i in range(steps + 1):
        t = i / steps
        pts.append(np.array([lean * t ** 2.2 + 0.05 * math.sin(t * 6), t, 0.03 * math.sin(t * 4)]))
        bulb = math.sqrt(max(0.0, 1 - ((t - 0.2) / 0.2) ** 2)) if t < 0.2 else 1.0
        radii.append(0.22 * bulb * (1 - t) ** 1.2 + 0.004)
    rings = []
    for i, p in enumerate(pts):
        t = pts[min(i + 1, steps)] - pts[max(i - 1, 0)]
        n, b = frame(t)
        r = radii[i]
        # flattened cross-section: wide side to side, thin front to back (a licking tongue)
        rings.append([p + n * math.cos(2 * math.pi * j / sides) * r + b * math.sin(2 * math.pi * j / sides) * r * 0.45 for j in range(sides)])
    m.loft(rings)
    return m.normalise()


def bolt(seed, branches=4):
    """A 3D jagged lightning bolt along Y (top to bottom) with forks."""
    rng = random.Random(seed)
    m = Mesh()

    def path(a, b, depth, amt):
        pts = [a, b]
        for _ in range(depth):
            out = [pts[0]]
            for p, q in zip(pts, pts[1:]):
                d = q - p
                off = np.array([rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)])
                off -= d / np.linalg.norm(d) * np.dot(off, d / np.linalg.norm(d))
                out += [(p + q) / 2 + off * amt * np.linalg.norm(d), q]
            pts = out
        return pts

    main = path(np.array([0, 0.5, 0]), np.array([0, -0.5, 0]), 5, 0.22)
    tube(m, main, [0.022 * (1 - 0.4 * i / len(main)) + 0.008 for i in range(len(main))], sides=5)
    for _ in range(branches):
        i = rng.randrange(4, len(main) - 6)
        s = main[i]
        d = np.array([rng.uniform(-1, 1), -rng.uniform(0.4, 1.0), rng.uniform(-1, 1)])
        d /= np.linalg.norm(d)
        bp = path(s, s + d * rng.uniform(0.15, 0.35), 3, 0.3)
        tube(m, bp, [0.012 * (1 - k / len(bp)) + 0.004 for k in range(len(bp))], sides=4)
    return m.normalise((False, True, False))


def ring(jag=0.0, seed=5, n=64, width=0.08, thick=0.04):
    """A flat ring in the XZ plane (ground shockwave); optionally jagged."""
    rng = random.Random(seed)
    m = Mesh()
    rings = []
    for i in range(n):
        a = 2 * math.pi * i / n
        r = 0.5 * (1 + jag * rng.uniform(-0.06, 0.06))
        w = width * (1 + jag * rng.uniform(-0.4, 0.4))
        c, s = math.cos(a), math.sin(a)
        rings.append([np.array([c * (r - w), thick, s * (r - w)]), np.array([c * r, thick, s * r]),
                      np.array([c * r, -thick, s * r]), np.array([c * (r - w), -thick, s * (r - w)])])
    idx = [[m.vert(p) for p in r] for r in rings]
    for i in range(n):
        r0, r1 = idx[i], idx[(i + 1) % n]
        for j in range(4):
            k = (j + 1) % 4
            m.quad(r0[j], r1[j], r1[k], r0[k])
    return m.normalise((True, False, True))


def zap_ring(seed=7, n=48):
    """A jagged electric ring around the Z axis (wraps the beam)."""
    rng = random.Random(seed)
    m = Mesh()
    pts = []
    for i in range(n + 1):
        a = 2 * math.pi * i / n
        r = 0.5 * (1 + rng.uniform(-0.08, 0.08)) if i < n else None
        pts.append(np.array([math.cos(a) * (r or 0.5), math.sin(a) * (r or 0.5), rng.uniform(-0.08, 0.08) if i < n else 0]))
    pts[-1] = pts[0].copy()
    tube(m, pts, [0.025] * len(pts), sides=4)
    return m.normalise((True, True, False))


def spikes(count=14, seed=9):
    """An impact starburst: cones radiating in every direction."""
    rng = random.Random(seed)
    m = Mesh()
    golden = math.pi * (3 - math.sqrt(5))
    for i in range(count):
        y = 1 - 2 * (i + 0.5) / count
        r = math.sqrt(1 - y * y)
        a = golden * i
        d = np.array([math.cos(a) * r, y, math.sin(a) * r])
        L = rng.uniform(0.6, 1.0)
        n, b = frame(d)
        base = [d * 0.1 + (n * math.cos(2 * math.pi * j / 4) + b * math.sin(2 * math.pi * j / 4)) * 0.06 for j in range(4)]
        tip = m.vert(d * 0.5 * L)
        ids = [m.vert(p) for p in base]
        for j in range(4):
            m.tri(ids[j], ids[(j + 1) % 4], tip)
    return m.normalise()


def orb(sub=2):
    """A smooth sphere (icosphere)."""
    t = (1 + 5 ** 0.5) / 2
    verts = [(-1, t, 0), (1, t, 0), (-1, -t, 0), (1, -t, 0), (0, -1, t), (0, 1, t), (0, -1, -t), (0, 1, -t), (t, 0, -1), (t, 0, 1), (-t, 0, -1), (-t, 0, 1)]
    faces = [(0, 11, 5), (0, 5, 1), (0, 1, 7), (0, 7, 10), (0, 10, 11), (1, 5, 9), (5, 11, 4), (11, 10, 2), (10, 7, 6), (7, 1, 8),
             (3, 9, 4), (3, 4, 2), (3, 2, 6), (3, 6, 8), (3, 8, 9), (4, 9, 5), (2, 4, 11), (6, 2, 10), (8, 6, 7), (9, 8, 1)]
    v = [np.array(p, float) / np.linalg.norm(p) for p in verts]
    for _ in range(sub):
        cache = {}
        nf = []

        def mid(a, b):
            k = (min(a, b), max(a, b))
            if k not in cache:
                p = v[a] + v[b]
                v.append(p / np.linalg.norm(p))
                cache[k] = len(v) - 1
            return cache[k]

        for a, b, c in faces:
            ab, bc, ca = mid(a, b), mid(b, c), mid(c, a)
            nf += [(a, ab, ca), (b, bc, ab), (c, ca, bc), (ab, bc, ca)]
        faces = nf
    m = Mesh()
    m.v = [tuple(p * 0.5) for p in v]
    m.f = faces
    return m


def main():
    print("Meshes")
    spiral().write("Spiral")
    spiral(turns=3, strands=3, width=0.1, thick=0.03).write("SpiralThin")
    flame_cone().write("FlameCone")
    for k in range(3):
        tongue(seed=3 + k).write(f"Tongue{k + 1}")
    for k in range(3):
        bolt(seed=11 + k).write(f"Bolt{k + 1}")
    ring().write("Ring")
    ring(jag=1.0, seed=6).write("RingJag")
    zap_ring().write("ZapRing")
    spikes().write("Spikes")
    orb().write("Orb")


if __name__ == "__main__":
    main()
