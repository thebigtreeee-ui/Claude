"""Builds one 3D energy-blast (projectile) model per Eternium element and exports each as FBX.

Run with a Python that has the `bpy` module, from the repo root:
    python tools/build_element_blasts.py            # FBX files only
    python tools/build_element_blasts.py --render   # also render preview JPGs

Each blast flies along +Y: its core sits at the origin, the nose points to +Y and the trail streams
back towards -Y. Part names match the element's beam (Core, Flames, Shards...) so ElementBeams.lua
colours both with the same palette. The Start marker sits at the tail (Y=TAIL) and End at the nose
(Y=NOSE); ElementBeams.lua uses them to aim the blast and find its core.
"""
import math
import random
import sys

from build_element_beams import (
    AXIS,
    OUT,
    bmesh,
    bpy,
    crystal,
    export,
    finish,
    helix,
    jagged,
    leaf,
    loft,
    markers,
    material,
    n3,
    render,
    rgb,
    rock,
    setup_render_scene,
    sweep,
    tube,
)
from mathutils import Matrix, Vector

TAIL = -6.0
NOSE = 2.0  # so the core (origin) sits 75% of the way from Start to End


# ---------------------------------------------------------------- helpers


def blob(bm, center, radius, displace=None, segments=24, rings=16):
    """UV sphere, optionally pushed in/out per vertex by displace(direction) -> scale factor."""
    geo = bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=radius)
    for v in geo["verts"]:
        d = v.co.normalized()
        v.co = center + d * radius * (displace(d) if displace else 1.0)


def sphere_dir(polar, azimuth):
    """Direction from polar angle (0 = straight ahead, +Y) and azimuth around the Y axis."""
    s = math.sin(polar)
    return Vector((s * math.cos(azimuth), math.cos(polar), s * math.sin(azimuth)))


def radial(a):
    return Vector((math.cos(a), 0, math.sin(a)))


def spin_about_axis(p, angle):
    return Matrix.Rotation(angle, 3, "Y") @ p


# ---------------------------------------------------------------- the seven blasts


def blast_fire(col):
    """A fireball: a white-hot core swallowed by flame tongues that peel back into a roaring comet tail."""
    rng = random.Random(101)

    bm = bmesh.new()
    blob(bm, Vector(), 0.75, lambda d: 1 + 0.1 * n3(d * 2.5))
    finish(bm, "Core", col, material("FireCore", rgb(255, 240, 180), 6))

    def tongue(bm, polar, az, length, thick, start_r, twist):
        s = sphere_dir(polar, az) * start_r
        pts, rads = [], []
        for i in range(17):
            t = i / 16
            p = Vector((s.x * (1 - 0.55 * t), s.y - length * t, s.z * (1 - 0.55 * t)))
            pts.append(spin_about_axis(p, twist * t))
            lick = 0.75 + 0.25 * math.sin(t * math.pi * 5 + az)
            rads.append(thick * lick * (1 - t) ** 0.9 * min(1, t * 6 + 0.35))
        rads[-1] = 0
        tube(bm, pts, rads, sides=8)

    bm = bmesh.new()
    for i in range(18):
        polar = math.radians(rng.uniform(15, 110))
        tongue(bm, polar, rng.uniform(0, 2 * math.pi), rng.uniform(3.0, 5.8) * (0.6 + polar / 3), rng.uniform(0.3, 0.42), 0.8, rng.uniform(-1.2, 1.2))
    finish(bm, "Flames", col, material("FireFlames", rgb(255, 120, 20), 3))

    bm = bmesh.new()
    for _ in range(16):
        tongue(bm, math.radians(rng.uniform(40, 120)), rng.uniform(0, 2 * math.pi), rng.uniform(1.4, 3.0), rng.uniform(0.14, 0.22), 1.1, rng.uniform(-2, 2))
    finish(bm, "Wisps", col, material("FireWisps", rgb(255, 60, 15), 2.5))


def blast_ice(col):
    """An ice comet: a spearhead cluster of crystals around a glowing heart, shedding frost shards behind."""
    rng = random.Random(102)

    bm = bmesh.new()
    blob(bm, Vector(), 0.45, segments=12, rings=8)
    finish(bm, "Core", col, material("IceCore", rgb(225, 250, 255), 5), smooth=False)

    bm = bmesh.new()
    crystal(bm, Vector((0, -1.8, 0)), Vector((0, NOSE, 0)), 0.55, 6, 0.3)
    for k in range(7):
        a = 2 * math.pi * k / 7 + rng.uniform(-0.2, 0.2)
        base = Vector((0, rng.uniform(-1.4, -0.8), 0)) + radial(a) * 0.2
        tip = Vector((0, rng.uniform(0.4, 1.3), 0)) + radial(a) * rng.uniform(0.75, 1.05)
        crystal(bm, base, tip, rng.uniform(0.25, 0.38), 6, rng.uniform(0, 1))
    finish(bm, "Crystal", col, material("IceCrystal", rgb(150, 215, 255), 0.6, glass=True), smooth=False)

    bm = bmesh.new()
    for i in range(22):
        t = i / 21
        y = -0.6 - t * 4.8
        a = rng.uniform(0, 2 * math.pi)
        base = Vector((0, y, 0)) + radial(a) * (0.5 * (1 - t) + 0.1)
        d = (radial(a) * rng.uniform(0.4, 0.9) - AXIS).normalized()
        crystal(bm, base, base + d * rng.uniform(0.5, 1.3) * (1 - 0.6 * t), rng.uniform(0.08, 0.2) * (1 - 0.5 * t), rng.choice((4, 5, 6)), rng.uniform(0, 1))
    finish(bm, "Shards", col, material("IceShards", rgb(190, 235, 255), 0.8, glass=True), smooth=False)


def blast_electric(col):
    """Ball lightning: a blinding core in a rippling plasma shell, arcs crawling over it, sparks trailing behind."""
    rng = random.Random(103)

    bm = bmesh.new()
    blob(bm, Vector(), 0.5)
    finish(bm, "Core", col, material("ElecBolt", rgb(230, 250, 255), 8))

    bm = bmesh.new()
    blob(bm, Vector(), 1.0, lambda d: 1 + 0.06 * math.sin(d.x * 9) * math.sin(d.y * 9) * math.sin(d.z * 9), segments=32, rings=20)
    finish(bm, "Sheath", col, material("ElecSheath", rgb(90, 150, 255), 0.6, alpha=0.15))

    bm = bmesh.new()
    for _ in range(9):  # arcs leaping between two points on the shell
        d0 = sphere_dir(rng.uniform(0, math.pi), rng.uniform(0, 2 * math.pi))
        d1 = (d0 + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * 1.2).normalized()
        steps = 10
        curve = []
        for i in range(steps + 1):
            t = i / steps
            d = d0.lerp(d1, t).normalized()
            curve.append(d * (1.0 + 0.4 * math.sin(math.pi * t)))
        pts = []
        for p, q in zip(curve, curve[1:]):
            pts += jagged(p, q, 1, 0.35, rng)[:-1]
        pts.append(curve[-1])
        tube(bm, pts, [0.055] * len(pts), sides=5)
    finish(bm, "Bolt", col, material("ElecBolt", rgb(230, 250, 255), 8), smooth=False)

    bm = bmesh.new()
    for _ in range(7):
        start = sphere_dir(math.radians(rng.uniform(110, 170)), rng.uniform(0, 2 * math.pi)) * 0.95
        end = start + Vector((rng.uniform(-0.9, 0.9), -rng.uniform(2.2, 4.8), rng.uniform(-0.9, 0.9)))
        pts = jagged(start, end, 3, 0.25, rng)
        tube(bm, pts, [0.06 * (1 - i / (len(pts) - 1)) + 0.01 for i in range(len(pts))], sides=4)
        fork = rng.choice(pts[2:-2])
        end2 = fork + Vector((rng.uniform(-0.8, 0.8), -rng.uniform(0.6, 1.5), rng.uniform(-0.8, 0.8)))
        pts2 = jagged(fork, end2, 2, 0.3, rng)
        tube(bm, pts2, [0.035 * (1 - i / (len(pts2) - 1)) + 0.008 for i in range(len(pts2))], sides=4)
    finish(bm, "Branches", col, material("ElecBranch", rgb(120, 190, 255), 5), smooth=False)


def blast_nature(col):
    """A living seed: vines wrap a glowing core and braid into a tail, a flower opens at the front."""
    rng = random.Random(104)

    bm = bmesh.new()
    blob(bm, Vector(), 0.6, lambda d: 1 + 0.05 * n3(d * 3))
    finish(bm, "Core", col, material("NatureCore", rgb(140, 255, 120), 4))

    bm = bmesh.new()
    vines = []
    for k in range(3):
        phase = 2 * math.pi * k / 3
        path = []
        for i in range(41):  # spiral round the core from front to back...
            t = i / 40
            path.append(sphere_dir(math.radians(20 + 150 * t), phase + t * 2 * math.pi * 1.2) * 0.78)
        last = path[-1]
        for i in range(1, 41):  # ...then braid into a tail
            t = i / 40
            a = phase + 2 * math.pi * 1.2 + t * 2 * math.pi * 2
            r = 0.35 * (1 - t) + 0.05
            path.append(Vector((r * math.cos(a), last.y - t * 4.8, r * math.sin(a))))
        vines.append(path)
        rads = [0.13 * min(1, (len(path) - 1 - i) / 15) for i in range(len(path))]
        rads[-1] = 0
        tube(bm, path, rads, sides=8)
        for _ in range(6):
            i = rng.randrange(3, 50)
            p = path[i]
            out = p.normalized() if p.length > 0.3 else radial(rng.uniform(0, 6.3))
            tube(bm, [p, p + (out - AXIS * 0.4).normalized() * 0.28], [0.05, 0], sides=4)
    finish(bm, "Vines", col, material("NatureVine", rgb(70, 95, 40), rough=0.8))

    bm = bmesh.new()
    for _ in range(26):
        v = rng.choice(vines)
        p = v[rng.randrange(8, 70)]
        out = Vector((p.x, 0, p.z)).normalized()
        d = (out * rng.uniform(0.5, 1.0) - AXIS * rng.uniform(0.6, 1.2)).normalized()  # swept back by the speed
        leaf(bm, p, d, out, rng.uniform(0.5, 0.85), rng.uniform(0.16, 0.26))
    finish(bm, "Leaves", col, material("NatureLeaf", rgb(80, 175, 60), rough=0.6))

    bm = bmesh.new()
    for j in range(7):  # the flower at the front, opening in the direction of travel
        a = 2 * math.pi * j / 7
        d = (radial(a) * 0.8 + AXIS * 0.6).normalized()
        leaf(bm, Vector((0, 0.45, 0)) + radial(a) * 0.2, d, -radial(a) + AXIS * 0.3, 0.75, 0.3, curl=-0.35, thick=0.03)
    for _ in range(3):
        v = rng.choice(vines)
        p = v[rng.randrange(45, 65)]
        out = Vector((p.x, 0, p.z)).normalized()
        for j in range(5):
            a = 2 * math.pi * j / 5
            side = out.cross(AXIS).normalized()
            up = side.cross(out)
            d = (side * math.cos(a) + up * math.sin(a) + out * 0.6).normalized()
            leaf(bm, p + out * 0.08, d, out, 0.22, 0.1, curl=0.4, thick=0.02)
    finish(bm, "Blossoms", col, material("NatureBloom", rgb(255, 150, 205), 0.4, rough=0.5))


def blast_void(col):
    """A travelling singularity: a black core in a violet horizon, a tilted accretion disc and matter spiralling in."""
    rng = random.Random(105)

    def wobble(d):
        return 1 + 0.08 * n3(d * 2.2, 3)

    bm = bmesh.new()
    blob(bm, Vector(), 0.75, wobble)
    finish(bm, "Core", col, material("VoidCore", rgb(8, 4, 14), rough=1.0))

    bm = bmesh.new()
    blob(bm, Vector(), 1.0, wobble)
    finish(bm, "Horizon", col, material("VoidHorizon", rgb(140, 60, 255), 0.5, alpha=0.1))

    tilt = Matrix.Rotation(math.radians(70), 3, "X") @ Matrix.Rotation(math.radians(15), 3, "Z")
    bm = bmesh.new()
    for r, w in ((1.45, 0.12), (1.9, 0.07)):
        ring = [tilt @ (radial(2 * math.pi * j / 56) * r) for j in range(56)]
        sweep(bm, ring, [[(w, 0), (0, 0.025), (-w, 0), (0, -0.025)]] * 56, closed=True)
    finish(bm, "Rings", col, material("VoidRing", rgb(190, 120, 255), 3))

    bm = bmesh.new()
    normal = tilt @ Vector((0, 1, 0))
    for k in range(7):  # matter streaming along the disc and spiralling into the core
        az = 2 * math.pi * k / 7
        lift = rng.uniform(-0.3, 0.3)
        pts = []
        for i in range(41):
            t = i / 40
            r = 1.6 * (1 - t) ** 1.2 + 0.8
            pts.append(tilt @ (radial(az + t * 2 * math.pi * 0.8) * r) + normal * lift * (1 - t))
        tube(bm, pts, [0.03 + 0.1 * math.sin(math.pi * min(i / 40 * 1.4, 1)) * (1 - i / 40) for i in range(40)] + [0], sides=6)
    for k in range(4):  # and a wake of dark energy dragged out behind it
        az = 2 * math.pi * k / 4 + 0.4
        path = helix(-0.6, -5.0, 40, lambda t: 0.7 * (1 - t) + 0.1, turns=0.8, phase=az)
        tube(bm, path, [0.12 * (1 - i / 40) + 0.01 for i in range(40)] + [0], sides=6)
    finish(bm, "Tendrils", col, material("VoidTendril", rgb(95, 20, 190), 3))

    bm = bmesh.new()
    for _ in range(36):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(1.2, 2.3)
        p = tilt @ (radial(a) * r) + Vector((0, rng.uniform(-0.15, 0.15), 0))
        rock(bm, rng, p, rng.uniform(0.05, 0.14), squash=(1, 1.6, 1))
    finish(bm, "Debris", col, material("VoidDebris", rgb(25, 15, 40), rough=0.9), smooth=False)


def blast_rift(col):
    """A flying fracture in space: two crossed jagged tears inside a cracked hex gate, glass fragments orbiting."""
    rng = random.Random(106)
    steps = 30
    ys = [-2.8 + (NOSE - 0.3 + 2.8) * i / steps for i in range(steps + 1)]
    pts = [Vector((0, y, 0)) for y in ys]
    # diamond silhouette: widest just behind the core, sharp at nose and tail, with jagged notches
    widths = []
    for i, y in enumerate(ys):
        t = i / steps
        base = math.sin(math.pi * t ** 0.8) * 1.0
        widths.append(base * (0.75 + 0.25 * abs(n3(Vector((0, y * 1.7, 0)), 4))) + (0.15 if rng.random() < 0.15 else 0) * base)

    def tear(scale, thick, angle):
        c, s = math.cos(angle), math.sin(angle)
        profiles = []
        for w in widths:
            raw = [(w * scale + 0.01, 0), (0, thick), (-w * scale - 0.01, 0), (0, -thick)]
            profiles.append([(x * c - y * s, x * s + y * c) for x, y in raw])
        return profiles

    bm = bmesh.new()
    for cross in (0, math.pi / 2):
        sweep(bm, pts, tear(0.6, 0.05, cross))
    finish(bm, "Tear", col, material("RiftTear", rgb(220, 255, 255), 7), smooth=False)

    bm = bmesh.new()
    for cross in (0, math.pi / 2):
        sweep(bm, pts, tear(0.85, 0.03, cross + 0.1))
    # Named EdgeMagenta (cyan, like the beam) so one style table covers both models.
    finish(bm, "EdgeMagenta", col, material("RiftCyan", rgb(40, 220, 230), 3.5), smooth=False)

    bm = bmesh.new()
    for cross in (0, math.pi / 2):
        sweep(bm, pts, tear(0.85, 0.03, cross - 0.1))
    finish(bm, "EdgeCyan", col, material("RiftCyan", rgb(40, 220, 230), 3.5), smooth=False)

    bm = bmesh.new()
    for y, r, spin in ((0.0, 1.55, 0.2), (-2.0, 1.05, 0.7)):
        corners = [Vector((0, y, 0)) + radial(spin + j * math.pi / 3) * r for j in range(6)]
        for j in range(6):
            if rng.random() < 0.25:
                continue
            a, b = corners[j], corners[(j + 1) % 6]
            gap = (b - a) * 0.08
            sq = [(0.06, 0.06), (-0.06, 0.06), (-0.06, -0.06), (0.06, -0.06)]
            sweep(bm, [a + gap, b - gap], [sq, sq])
    finish(bm, "Gates", col, material("RiftGate", rgb(30, 200, 200), 3), smooth=False)

    bm = bmesh.new()
    for _ in range(24):
        y = rng.uniform(-5.0, 1.0)
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(0.9, 1.9) * (1 - max(0, -y - 1) / 6)
        rock(bm, rng, Vector((r * math.cos(a), y, r * math.sin(a))), rng.uniform(0.12, 0.3), squash=(1.4, 1.0, 0.12), jitter=0.5)
    finish(bm, "Fragments", col, material("RiftGlass", rgb(190, 245, 245), 0.5, glass=True), smooth=False)


def blast_wind(col):
    """A pocket cyclone: a teardrop vortex of airflow streaks behind a sonic-boom cone, with blades orbiting."""
    rng = random.Random(107)

    bm = bmesh.new()
    for k in range(3):  # the same wrung three-strand twist as the beam, curled into a tight knot
        path = helix(-1.0, 0.9, 60, lambda t: 0.28 * math.sin(math.pi * t) + 0.04, turns=3, phase=2 * math.pi * k / 3)
        tube(bm, path, [0.0] + [0.11] * 59 + [0.0], sides=6)
    finish(bm, "Core", col, material("WindCore", rgb(235, 255, 248), 2.5))

    def teardrop(y):  # vortex radius along the body: round nose, fat middle, long thin tail
        if y >= 0:
            return 1.05 * math.sqrt(max(0.0, 1 - (y / 1.4) ** 2))
        return 0.2 + 0.85 * math.exp(y / 2.2)

    bm = bmesh.new()
    for k in range(9):
        phase = 2 * math.pi * k / 9 + rng.uniform(-0.2, 0.2)
        y0, y1 = rng.uniform(0.9, 1.3), rng.uniform(-5.6, -3.5)
        steps = 70
        rings = []
        for i in range(steps + 1):
            t = i / steps
            y = y0 + (y1 - y0) * t
            a = phase + t * 2 * math.pi * 2.2
            r = teardrop(y) * rng.uniform(0.97, 1.03)
            c = radial(a) * r + Vector((0, y, 0))
            around = Vector((-math.sin(a), 0, math.cos(a)))
            w = 0.16 * math.sin(math.pi * t) ** 0.7 + 0.005
            rings.append([c + around * w, c + radial(a) * 0.025, c - around * w, c - radial(a) * 0.025])
        loft(bm, rings)
    finish(bm, "Streams", col, material("WindStream", rgb(160, 240, 215), 1.0))

    bm = bmesh.new()
    for y, r0, r1, length in ((1.45, 0.45, 1.15, 0.8), (-1.7, 0.7, 1.0, 0.5)):
        section = [(r0, 0.0), (r0 + 0.1, -0.15), (r1, -length), (r0 + 0.04, -0.1)]
        rings = [[Vector((0, y, 0)) + radial(2 * math.pi * j / 48) * rr + AXIS * ay for rr, ay in section] for j in range(48)]
        loft(bm, rings, closed=True)
    finish(bm, "Rings", col, material("WindRing", rgb(150, 235, 215), 0.5, alpha=0.3))

    bm = bmesh.new()
    for k in range(4):
        y = rng.uniform(-1.6, 0.6)
        r = rng.uniform(1.35, 1.7)
        start = 2 * math.pi * k / 4 + rng.uniform(-0.3, 0.3)
        span = math.radians(rng.uniform(110, 160))
        rings = []
        for i in range(31):
            u = i / 30
            a = start + span * u
            c = radial(a) * r + Vector((0, y - 0.8 * u, 0))
            w = 0.3 * math.sin(math.pi * u) ** 0.6
            th = 0.045 * math.sin(math.pi * u) ** 0.6 + 0.005
            rings.append([c + AXIS * w, c + radial(a) * th, c - AXIS * w * 0.35, c - radial(a) * th])
        loft(bm, rings)
    finish(bm, "Blades", col, material("WindBlade", rgb(215, 255, 240), 1.5))


BLASTS = {
    "Fire": blast_fire,
    "Ice": blast_ice,
    "Electric": blast_electric,
    "Nature": blast_nature,
    "Void": blast_void,
    "Rift": blast_rift,
    "Wind": blast_wind,
}


def main():
    do_render = "--render" in sys.argv
    bpy.ops.wm.read_factory_settings(use_empty=True)
    out = OUT / "Blasts"
    out.mkdir(parents=True, exist_ok=True)
    if do_render:
        (out / "previews").mkdir(exist_ok=True)
        setup_render_scene()
    for element, build in BLASTS.items():
        print(element)
        col = bpy.data.collections.new(element)
        bpy.context.scene.collection.children.link(col)
        build(col)
        markers(col, TAIL, NOSE)
        export(col, out / f"{element}Blast.fbx")
    if do_render:
        for element in BLASTS:
            render(element, out / "previews" / f"{element}.jpg", camera=(7.5, 2.0, 2.6), target=(0, -1.6, 0))
    print(f"Wrote blasts to {out}")


if __name__ == "__main__":
    main()
