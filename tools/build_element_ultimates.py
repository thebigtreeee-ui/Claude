"""Builds the ultimate-move models for every Eternium element and exports each as FBX.

Run with a Python that has the `bpy` module, from the repo root:
    python tools/build_element_ultimates.py            # FBX files only
    python tools/build_element_ultimates.py --render   # also render preview JPGs

Blender axes here: X = the user's right, Y = forward (the way the user faces), Z = up, origin = the
ground under the user's feet. Each model carries three tiny markers ElementUltimates.lua uses to
find that frame after import: Start (origin), End (10 forward) and Top (10 up).

Every model is split into named parts (Frame, Swirl, Bolt_03...) that ElementUltimates.lua animates
separately. Parts that animate one by one (ice pillars, trees, bolts) carry a _NN suffix and share
the style of their base name.
"""
import math
import random
import sys

from build_element_beams import (
    OUT,
    bmesh,
    bpy,
    crystal,
    export,
    finish,
    jagged,
    leaf,
    loft,
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

UNIT = 10.0  # Start->End and Start->Top distance


# ---------------------------------------------------------------- helpers


def markers3(col):
    mat = material("Marker", (1, 0, 1))
    for name, pos in (("Start", (0, 0, 0)), ("End", (0, UNIT, 0)), ("Top", (0, 0, UNIT))):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=0.1, matrix=Matrix.Translation(pos))
        finish(bm, name, col, mat, smooth=False).hide_render = True


def ico(bm, center, radius, subdiv=2, squash=(1, 1, 1), bumps=0.15, seed=0.0):
    """Lumpy icosphere: clouds, canopies, black-hole cores."""
    geo = bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=1.0)
    for v in geo["verts"]:
        d = v.co.normalized()
        r = radius * (1 + bumps * n3(d * 2.0, seed))
        v.co = center + Vector((d.x * squash[0], d.y * squash[1], d.z * squash[2])) * r


def revolve(bm, center, u, v, w, section, n=48):
    """Spins a closed (radial, axial) cross-section round axis w, with u/v spanning the ring plane."""
    rings = []
    for j in range(n):
        a = 2 * math.pi * j / n
        d = u * math.cos(a) + v * math.sin(a)
        rings.append([center + d * rr + w * aa for rr, aa in section])
    loft(bm, rings, closed=True)


def flat_disc(bm, center, radius_fn, thickness=0.06, n=72):
    """A thin ground-hugging disc whose edge radius varies with angle."""
    top_c = bm.verts.new(center + Vector((0, 0, thickness)))
    bot_c = bm.verts.new(center)
    top, bot = [], []
    for j in range(n):
        a = 2 * math.pi * j / n
        r = radius_fn(a)
        p = center + Vector((math.cos(a) * r, math.sin(a) * r, 0))
        top.append(bm.verts.new(p + Vector((0, 0, thickness))))
        bot.append(bm.verts.new(p))
    for j in range(n):
        k = (j + 1) % n
        bm.faces.new((top_c, top[j], top[k]))
        bm.faces.new((bot_c, bot[k], bot[j]))
        bm.faces.new((top[j], bot[j], bot[k], top[k]))


def ribbon(bm, pts, widths, normal_fn, thick=0.03):
    """Flat strip along pts, lying across normal_fn(i) (the ribbon's face normal)."""
    rings = []
    count = len(pts)
    for i, p in enumerate(pts):
        t = (pts[min(i + 1, count - 1)] - pts[max(i - 1, 0)]).normalized()
        nrm = normal_fn(i)
        side = t.cross(nrm).normalized()
        w = widths[i]
        rings.append([p + side * w, p + nrm * thick, p - side * w, p - nrm * thick])
    loft(bm, rings)


def square(r):
    return [(r, r), (-r, r), (-r, -r), (r, -r)]


def angular_crack(bm, a, b, rng, segments=4, wander=0.25, r=0.07):
    """A crack made of a few long straight segments."""
    pts = [a]
    d = b - a
    for i in range(1, segments):
        off = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * d.length * wander / segments
        pts.append(a + d * (i / segments) + off)
    pts.append(b)
    for p, q in zip(pts, pts[1:]):
        sweep(bm, [p, q], [square(r), square(r)])


# ---------------------------------------------------------------- Rift: a portal tearing open


def ult_rift(col):
    rng = random.Random(201)
    C = Vector((0, 10, 6.2))
    X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
    R = 5.2

    bm = bmesh.new()  # a jagged crystal ring with shards bursting outwards
    section = [(R - 0.35, 0), (R, 0.45), (R + 0.45, 0), (R, -0.45)]
    revolve(bm, C, X, Z, Y, section, n=60)
    for k in range(26):
        a = 2 * math.pi * k / 26 + rng.uniform(-0.08, 0.08)
        out = X * math.cos(a) + Z * math.sin(a)
        base = C + out * (R - 0.2) + Y * rng.uniform(-0.3, 0.3)
        tip = base + (out + Y * rng.uniform(-0.4, 0.4) + (X * -math.sin(a) + Z * math.cos(a)) * rng.uniform(-0.4, 0.4)).normalized() * rng.uniform(1.4, 3.2)
        crystal(bm, base - out * 0.6, tip, rng.uniform(0.25, 0.45), rng.choice((4, 5, 6)), rng.uniform(0, 1))
    finish(bm, "Frame", col, material("RiftCrystal", rgb(150, 240, 250), 0.6, glass=True), smooth=False)

    bm = bmesh.new()  # spiral arms, pulled back into a funnel so the portal has depth
    for k in range(6):
        phase = 2 * math.pi * k / 6
        pts, widths = [], []
        for i in range(41):
            t = i / 40
            r = 0.3 + (R - 0.6) * t
            a = phase + t * 2 * math.pi * 1.1
            pts.append(C + X * (r * math.cos(a)) + Z * (r * math.sin(a)) + Y * (2.2 * (1 - t) ** 2))
            widths.append(0.08 + 0.55 * math.sin(math.pi * t) ** 0.8)
        ribbon(bm, pts, widths, lambda i: Y)
    finish(bm, "Swirl", col, material("RiftSwirl", rgb(40, 220, 230), 2.5, alpha=0.75))

    bm = bmesh.new()  # receding hex rings: the tunnel on the other side
    for k in range(5):
        depth = 0.8 + k * 0.9
        r = R * (0.85 - k * 0.14)
        spin = k * 0.35
        corners = [C + Y * depth + (X * math.cos(spin + j * math.pi / 3) + Z * math.sin(spin + j * math.pi / 3)) * r for j in range(6)]
        for j in range(6):
            sweep(bm, [corners[j], corners[(j + 1) % 6]], [square(0.09), square(0.09)])
    finish(bm, "Tunnel", col, material("RiftTunnel", rgb(30, 200, 200), 2))

    bm = bmesh.new()
    ico(bm, C + Y * 0.6, 0.9, subdiv=2, squash=(1, 0.35, 1), bumps=0.05)
    finish(bm, "Core", col, material("RiftCore", rgb(220, 255, 255), 8))

    bm = bmesh.new()  # reality cracking around the portal, and along the ground towards the user
    for k in range(14):
        a = 2 * math.pi * k / 14 + rng.uniform(-0.15, 0.15)
        out = X * math.cos(a) + Z * math.sin(a)
        start = C + out * (R + 0.2)
        end = C + out * rng.uniform(R + 2.5, R + 5.5) + Y * rng.uniform(-1.5, 1.5)
        if end.z < 0.1:
            end.z = 0.1
        angular_crack(bm, start, end, rng, segments=rng.choice((3, 4)), r=0.06)
    for k in range(4):
        start = Vector((rng.uniform(-1.5, 1.5), 9.5, 0.05))
        end = Vector((rng.uniform(-4, 4), rng.uniform(2.5, 5), 0.05))
        angular_crack(bm, start, end, rng, segments=4, wander=0.3, r=0.08)
    finish(bm, "Cracks", col, material("RiftCyan", rgb(40, 220, 230), 3.5), smooth=False)

    bm = bmesh.new()
    for _ in range(34):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(R + 0.8, R + 3.2)
        base = C + X * (r * math.cos(a)) + Z * (r * math.sin(a)) + Y * rng.uniform(-1.2, 1.2)
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized()
        size = rng.uniform(0.4, 1.0)
        crystal(bm, base - d * size / 2, base + d * size / 2, size * 0.3, rng.choice((3, 4)), rng.uniform(0, 1))
    finish(bm, "Fragments", col, material("RiftGlass", rgb(190, 245, 245), 0.5, glass=True), smooth=False)


# ---------------------------------------------------------------- Electric: a thundercloud


def ult_electric(col):
    rng = random.Random(202)
    CC = Vector((0, 14, 26))
    ground = Vector((0, 14, 0))

    bm = bmesh.new()
    for _ in range(46):
        u, v = rng.uniform(-1, 1), rng.uniform(-1, 1)
        if u * u + v * v > 1:
            continue
        p = CC + Vector((u * 14, v * 11, rng.uniform(-1.0, 2.5)))
        r = rng.uniform(2.8, 5.0) * (1 - 0.35 * (u * u + v * v))
        ico(bm, p, r, subdiv=3, squash=(1, 1, 0.6), bumps=0.2, seed=rng.random() * 10)
    finish(bm, "Cloud", col, material("StormCloud", rgb(35, 32, 45), rough=1.0))

    bm = bmesh.new()  # the underside, lit from within by the lightning
    for _ in range(18):
        u, v = rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8)
        ico(bm, CC + Vector((u * 13, v * 10, -2.2)), rng.uniform(1.5, 2.8), subdiv=1, squash=(1, 1, 0.5), bumps=0.2, seed=rng.random() * 10)
    finish(bm, "CloudGlow", col, material("StormGlow", rgb(140, 60, 235), 2, alpha=0.6))

    bm = bmesh.new()  # rain in repeating columns so it can scroll down seamlessly
    for _ in range(60):
        u, v = rng.uniform(-1, 1), rng.uniform(-1, 1)
        if u * u + v * v > 1:
            continue
        x, y = u * 13, 14 + v * 10
        z0 = rng.uniform(0, 4)
        for m in range(6):
            z = 1 + z0 + 4 * m
            top = Vector((x, y, z + 1.6))
            sweep(bm, [Vector((x + 0.15, y, z)), top], [square(0.035), square(0.035)])
    finish(bm, "Rain", col, material("StormRain", rgb(190, 170, 255), 1, alpha=0.5), smooth=False)

    for k in range(6):
        bm = bmesh.new()
        a = 2 * math.pi * k / 6 + rng.uniform(-0.3, 0.3)
        r = rng.uniform(3, 11)
        hit = ground + Vector((math.cos(a) * r, math.sin(a) * r, 0))
        top = CC + Vector((math.cos(a) * r * 0.6, math.sin(a) * r * 0.6, -2.5))
        pts = jagged(top, hit, 6, 0.045, rng)
        tube(bm, pts, [0.32] * len(pts), sides=6)
        for _ in range(4):
            src = rng.choice(pts[6:-10])
            d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), -rng.uniform(0.3, 1.0))).normalized()
            bpts = jagged(src, src + d * rng.uniform(3, 6), 3, 0.25, rng)
            tube(bm, bpts, [0.14 * (1 - i / (len(bpts) - 1)) + 0.02 for i in range(len(bpts))], sides=4)
        revolve(bm, hit + Vector((0, 0, 0.08)), Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)), [(1.0, 0), (1.8, 0.06), (2.4, 0), (1.8, -0.02)], n=32)
        finish(bm, f"Bolt_{k + 1:02d}", col, material("StormBolt", rgb(245, 230, 255), 8), smooth=False)


# ---------------------------------------------------------------- Fire: flames pouring from both hands


def ult_fire(col):
    rng = random.Random(203)
    hands = [Vector((-0.9, 1.5, 3.2)), Vector((0.9, 1.5, 3.2))]
    merge = Vector((0, 4.5, 3.2))
    y_end = 24.0

    def cone_r(y):
        return 1.0 + 4.0 * max(0.0, (y - merge.y) / (y_end - merge.y)) ** 0.8

    def axis_at(y):
        return Vector((0, y, 3.2 + 0.03 * max(0.0, y - merge.y) ** 1.4))  # heat lifts the flames

    bm = bmesh.new()
    for h in hands:
        pts = [h.lerp(merge, i / 8) for i in range(9)]
        tube(bm, pts, [0.3 + 0.25 * i / 8 for i in range(9)], sides=10)
        ico(bm, h, 0.45, subdiv=2, bumps=0.1)
    steps = 50
    ys = [merge.y + (y_end - 2 - merge.y) * i / steps for i in range(steps + 1)]
    pts = [axis_at(y) for y in ys]
    rads = [0.55 * cone_r(y) * (1 + 0.12 * n3(Vector((0, y * 0.4, 0)), 1)) for y in ys]
    rads[-1] = 0
    tube(bm, pts, rads, sides=14)
    finish(bm, "Core", col, material("FireCore", rgb(255, 240, 180), 6))

    bm = bmesh.new()
    for k in range(8):
        phase = 2 * math.pi * k / 8
        path, rads = [], []
        for i in range(61):
            t = i / 60
            y = merge.y - 1 + (y_end - merge.y + 1) * t
            a = phase + t * 2 * math.pi * 1.6
            r = cone_r(y) * 0.8
            path.append(axis_at(y) + Vector((math.cos(a) * r, 0, math.sin(a) * r)))
            lick = 0.6 + 0.4 * math.sin(t * math.pi * 9 + k)
            rads.append((0.35 + 0.9 * t) * lick * min(1, t * 10, (1 - t) * 5))
        rads[0] = rads[-1] = 0
        tube(bm, path, rads, sides=8)
    finish(bm, "Flames", col, material("FireFlames", rgb(255, 120, 20), 3))

    bm = bmesh.new()
    for _ in range(36):
        y = rng.uniform(merge.y + 1, y_end - 2)
        a = rng.uniform(0, 2 * math.pi)
        out = Vector((math.cos(a), 0, math.sin(a)))
        side = out.cross(Vector((0, 1, 0)))
        r0 = cone_r(y) * 0.9
        length = rng.uniform(2, 4.5)
        sway = rng.uniform(-0.5, 0.5)
        path = []
        for i in range(11):
            t = i / 10
            path.append(axis_at(y - length * t * 0.6) + out * (r0 + 1.6 * t ** 0.7) + side * sway * math.sin(t * math.pi * 2) + Vector((0, 0, 0.8 * t * t)))
        rads = [rng.uniform(0.35, 0.55) * (1 - i / 10) ** 1.2 for i in range(11)]
        rads[-1] = 0
        tube(bm, path, rads, sides=7)
    finish(bm, "Wisps", col, material("FireWisps", rgb(255, 60, 15), 2.5))

    bm = bmesh.new()
    for _ in range(70):
        y = rng.uniform(merge.y, y_end + 3)
        a = rng.uniform(0, 2 * math.pi)
        r = cone_r(min(y, y_end)) * rng.uniform(0.6, 1.6)
        rock(bm, rng, axis_at(min(y, y_end)) + Vector((math.cos(a) * r, y - min(y, y_end), math.sin(a) * r + rng.uniform(0, 2))), rng.uniform(0.06, 0.16))
    finish(bm, "Embers", col, material("FireEmbers", rgb(255, 180, 60), 4), smooth=False)


# ---------------------------------------------------------------- Ice: a stomp raises a wall of ice


def ult_ice(col):
    rng = random.Random(204)

    bm = bmesh.new()
    revolve(bm, Vector((0, 0, 0.25)), Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1)), [(2.6, 0), (3.4, 0.25), (4.2, 0), (3.4, -0.1)], n=48)
    finish(bm, "Shockwave", col, material("IceShock", rgb(200, 240, 255), 3, alpha=0.6))

    bm = bmesh.new()  # frost racing across the ground towards the wall
    spikes = [rng.uniform(0.75, 1.15) for _ in range(72)]
    flat_disc(bm, Vector((0, 6, 0.02)), lambda a: (8.5 + 3.5 * math.sin(a)) * spikes[int((a / (2 * math.pi)) * 72) % 72], thickness=0.05)
    finish(bm, "Frost", col, material("IceFrost", rgb(220, 245, 255), 0.6, glass=True), smooth=False)

    for k in range(7):  # spikes erupting along the path, growing towards the wall
        bm = bmesh.new()
        y = 2.2 + k * 1.55
        size = 0.6 + k * 0.32
        for _ in range(3):
            base = Vector((rng.uniform(-0.8, 0.8), y + rng.uniform(-0.4, 0.4), -0.3))
            d = Vector((rng.uniform(-0.5, 0.5), rng.uniform(0.1, 0.6), 1)).normalized()
            crystal(bm, base, base + d * size * rng.uniform(2.0, 3.2), size * rng.uniform(0.25, 0.4), 6, rng.uniform(0, 1))
        finish(bm, f"Spike_{k + 1:02d}", col, material("IceShards", rgb(190, 235, 255), 0.8, glass=True), smooth=False)

    n = 11
    for k in range(n):  # the wall: an arc of crystal pillars
        bm = bmesh.new()
        th = math.radians(-58 + 116 * k / (n - 1))
        center = Vector((14.5 * math.sin(th), 14.5 * math.cos(th), 0))
        out = Vector((math.sin(th), math.cos(th), 0))
        tangent = Vector((math.cos(th), -math.sin(th), 0))
        h = rng.uniform(13, 18) * (1 - 0.25 * abs(k - (n - 1) / 2) / ((n - 1) / 2))
        crystal(bm, center - Vector((0, 0, 1.5)), center + Vector((0, 0, h)) + out * 1.2, rng.uniform(1.5, 1.9), 6, rng.uniform(0, 1))
        for s in (-1, 1):
            base = center + tangent * s * 1.1 + out * rng.uniform(-0.4, 0.6) - Vector((0, 0, 1))
            tip = base + Vector((0, 0, h * rng.uniform(0.45, 0.7))) + tangent * s * rng.uniform(0.6, 1.8) + out * rng.uniform(0.3, 1.5)
            crystal(bm, base, tip, rng.uniform(0.8, 1.2), 6, rng.uniform(0, 1))
        finish(bm, f"Wall_{k + 1:02d}", col, material("IceCrystal", rgb(150, 215, 255), 0.6, glass=True), smooth=False)


# ---------------------------------------------------------------- Nature: a ring of glowing trees


def ult_nature(col):
    rng = random.Random(205)
    trees = 6

    bm = bmesh.new()  # glowing roots spreading from the user out to every tree
    for k in range(trees * 2):
        a = 2 * math.pi * k / (trees * 2) + rng.uniform(-0.1, 0.1)
        reach = 11 if k % 2 == 0 else rng.uniform(5, 8)
        pts = []
        for i in range(25):
            t = i / 24
            wob = 0.6 * math.sin(t * math.pi * 3 + k)
            r = 0.8 + (reach - 0.8) * t
            pts.append(Vector((math.cos(a) * r - math.sin(a) * wob, math.sin(a) * r + math.cos(a) * wob, 0.08)))
        tube(bm, pts, [0.2 * (1 - t) + 0.05 for t in (i / 24 for i in range(25))], sides=6)
    finish(bm, "Roots", col, material("NatureRoots", rgb(90, 230, 130), 3))

    def branch_path(start, direction, length, steps=8):
        pts = []
        d = direction.normalized()
        p = start.copy()
        for i in range(steps + 1):
            pts.append(p.copy())
            d = (d + Vector((0, 0, 0.12))).normalized()
            p = p + d * (length / steps)
        return pts

    for k in range(trees):
        a = 2 * math.pi * k / trees + math.pi / trees
        base = Vector((math.cos(a) * 11, math.sin(a) * 11, 0))
        height = rng.uniform(9, 12)
        trunk_bm, canopy_bm, glow_bm = bmesh.new(), bmesh.new(), bmesh.new()

        trunk = []
        for i in range(17):
            t = i / 16
            sway = Vector((0.5 * math.sin(t * 3 + k), 0.5 * math.cos(t * 2.5 + k), 0))
            trunk.append(base + sway * t + Vector((0, 0, height * t - 0.5)))
        tube(trunk_bm, trunk, [0.75 * (1 - t) ** 0.8 + 0.18 + 0.5 * max(0, 0.15 - t) * 4 for t in (i / 16 for i in range(17))], sides=10)
        for r in range(5):  # flared roots
            ra = rng.uniform(0, 2 * math.pi)
            d = Vector((math.cos(ra), math.sin(ra), -0.3))
            tube(trunk_bm, branch_path(base + Vector((0, 0, 0.6)), d, rng.uniform(1.6, 2.4), 6)[::-1][::-1], [0.35 * (1 - i / 6) + 0.05 for i in range(7)], sides=6)

        tips = [trunk[-1]]
        for b in range(5):
            i = rng.randrange(8, 14)
            ba = rng.uniform(0, 2 * math.pi)
            d = Vector((math.cos(ba), math.sin(ba), rng.uniform(0.4, 0.9)))
            pts = branch_path(trunk[i], d, rng.uniform(2.5, 4.0))
            tube(trunk_bm, pts, [0.3 * (1 - j / 8) + 0.06 for j in range(9)], sides=6)
            tips.append(pts[-1])
        finish(trunk_bm, f"Trunk_{k + 1:02d}", col, material("NatureTrunk", rgb(70, 55, 40), rough=0.9))

        for tip in tips:
            for _ in range(rng.randint(4, 6)):
                ico(canopy_bm, tip + Vector((rng.uniform(-1.2, 1.2), rng.uniform(-1.2, 1.2), rng.uniform(-0.4, 1.0))), rng.uniform(0.9, 1.6), subdiv=2, bumps=0.25, seed=rng.random() * 10)
            for _ in range(2):
                ico(glow_bm, tip + Vector((rng.uniform(-1.4, 1.4), rng.uniform(-1.4, 1.4), rng.uniform(-1.6, -0.8))), 0.22, subdiv=1, bumps=0.05)
        finish(canopy_bm, f"Canopy_{k + 1:02d}", col, material("NatureCanopy", rgb(110, 255, 160), 0.9, alpha=0.8))
        finish(glow_bm, f"Glow_{k + 1:02d}", col, material("NatureGlow", rgb(220, 255, 180), 6))

    bm = bmesh.new()  # glowing leaves drifting through the grove
    for _ in range(70):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(3, 13)
        p = Vector((math.cos(a) * r, math.sin(a) * r, rng.uniform(1, 8)))
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.3, 0.3))).normalized()
        leaf(bm, p, d, Vector((0, 0, 1)), rng.uniform(0.3, 0.5), rng.uniform(0.1, 0.16))
    finish(bm, "Petals", col, material("NaturePetals", rgb(150, 255, 190), 3))


# ---------------------------------------------------------------- Wind: two giant hands of air clap


def hand(bm, side, rng):
    """A giant open hand, palm facing the centre line, fingers up. side = -1 left hand, +1 right hand."""
    palm_c = Vector((0, 0, 0))
    ico(bm, palm_c, 1.0, subdiv=3, squash=(0.45, 1.25, 1.5), bumps=0.04)
    # fingers along +Z, spread across Y; thumb towards the user (-Y)
    for j, (dy, length) in enumerate(((0.85, 2.3), (0.3, 2.7), (-0.25, 2.6), (-0.8, 2.1))):
        pts = []
        for i in range(9):
            t = i / 8
            pts.append(Vector((-side * 0.15 * t * t, dy * (1 + 0.1 * t), 1.2 + length * t)))
        tube(bm, pts, [0.36 - 0.06 * t for t in (i / 8 for i in range(8))] + [0.0], sides=10)
    pts = []
    for i in range(9):
        t = i / 8
        pts.append(Vector((-side * 0.25 * t, -1.0 - 1.3 * t, 0.2 + 1.2 * t)))
    tube(bm, pts, [0.4 - 0.08 * t for t in (i / 8 for i in range(8))] + [0.0], sides=10)


def ult_wind(col):
    rng = random.Random(207)
    W = Vector((0, 7, 7))
    scale = 1.6
    for idx, side in ((1, -1), (2, 1)):
        bm = bmesh.new()
        hand(bm, side, rng)
        m = Matrix.Translation(W + Vector((side * 0.55 * scale + side * 0.15, 0, -1.2 * scale))) @ Matrix.Scale(scale, 4)
        bmesh.ops.transform(bm, matrix=m, verts=bm.verts)
        finish(bm, f"Hand_{idx:02d}", col, material("WindHand", rgb(170, 255, 230), 1.2, alpha=0.45))

    Y, X, Z = Vector((0, 1, 0)), Vector((1, 0, 0)), Vector((0, 0, 1))
    bm = bmesh.new()  # the shockwave: a cone-shaped ring of compressed air opening forwards
    revolve(bm, W, X, Z, Y, [(2.4, 0.0), (2.7, 0.6), (4.2, 2.2), (2.6, 0.4)], n=56)
    revolve(bm, W + Y * 1.0, X, Z, Y, [(1.2, 0.0), (1.4, 0.3), (2.3, 1.3), (1.35, 0.2)], n=40)
    finish(bm, "Shockwave", col, material("WindShock", rgb(200, 255, 240), 1.5, alpha=0.5))

    bm = bmesh.new()  # streaks bursting forwards from the clap
    for k in range(18):
        a = 2 * math.pi * k / 18 + rng.uniform(-0.1, 0.1)
        out = X * math.cos(a) + Z * math.sin(a)
        length = rng.uniform(14, 22)
        spread = rng.uniform(3, 6)
        pts = [W + Y * (length * t) + out * (0.6 + spread * t) for t in (i / 20 for i in range(21))]
        ribbon(bm, pts, [0.25 * math.sin(math.pi * (i / 20)) ** 0.7 + 0.01 for i in range(21)], lambda i, out=out: out)
    finish(bm, "Streams", col, material("WindStream", rgb(160, 240, 215), 1.0))

    bm = bmesh.new()  # crescent blades that fly out with the shockwave
    for k in range(6):
        a0 = 2 * math.pi * k / 6
        r = rng.uniform(3.0, 4.2)
        rings = []
        for i in range(31):
            u = i / 30
            a = a0 + math.radians(80) * u
            out = X * math.cos(a) + Z * math.sin(a)
            c = W + Y * (2.0 - 0.8 * u) + out * r
            w = 0.5 * math.sin(math.pi * u) ** 0.6
            th = 0.06 * math.sin(math.pi * u) ** 0.6 + 0.005
            rings.append([c + Y * w, c + out * th, c - Y * w * 0.35, c - out * th])
        loft(bm, rings)
    finish(bm, "Blades", col, material("WindBlade", rgb(215, 255, 240), 1.5))


# ---------------------------------------------------------------- Void: a black hole


def ult_void(col):
    rng = random.Random(206)
    V = Vector((0, 16, 9))
    tilt = Matrix.Rotation(math.radians(20), 3, "X")  # ElementUltimates.lua spins the disc about this tilted normal
    U, Vv, N = tilt @ Vector((1, 0, 0)), tilt @ Vector((0, 1, 0)), tilt @ Vector((0, 0, 1))

    bm = bmesh.new()
    ico(bm, V, 3.2, subdiv=4, bumps=0.05, seed=3)
    finish(bm, "Core", col, material("VoidCore", rgb(8, 4, 14), rough=1.0))

    bm = bmesh.new()
    ico(bm, V, 3.9, subdiv=4, bumps=0.05, seed=3)
    finish(bm, "Horizon", col, material("VoidHorizon", rgb(140, 60, 255), 0.5, alpha=0.1))

    bm = bmesh.new()  # photon ring hugging the horizon
    revolve(bm, V, U, Vv, N, [(4.1, 0), (4.35, 0.12), (4.6, 0), (4.35, -0.12)], n=72)
    finish(bm, "Ring", col, material("VoidRing", rgb(205, 185, 255), 4))

    def arms(bm, count, r0, r1, turns, width, seed):
        arng = random.Random(seed)
        for k in range(count):
            phase = 2 * math.pi * k / count + arng.uniform(-0.2, 0.2)
            pts, widths = [], []
            for i in range(49):
                t = i / 48
                r = r0 + (r1 - r0) * t
                a = phase - t * 2 * math.pi * turns
                pts.append(V + U * (r * math.cos(a)) + Vv * (r * math.sin(a)) + N * arng.uniform(-0.05, 0.05))
                widths.append(width * (0.4 + t) * math.sin(math.pi * min(1, t * 1.2)) ** 0.6 + 0.02)
            ribbon(bm, pts, widths, lambda i: N, thick=0.04)

    bm = bmesh.new()
    arms(bm, 8, 4.7, 11.5, 0.9, 0.9, 61)
    finish(bm, "Disk", col, material("VoidDisk", rgb(130, 60, 255), 1.2, alpha=0.85))

    bm = bmesh.new()
    arms(bm, 6, 8.5, 15, 0.6, 0.6, 62)
    finish(bm, "DiskOuter", col, material("VoidDiskOuter", rgb(90, 30, 200), 1.2, alpha=0.6))

    bm = bmesh.new()  # polar jets, straight up and down
    for s in (1, -1):
        pts = [V + Vector((0, 0, s * (3.5 + 13 * t))) for t in (i / 20 for i in range(21))]
        tube(bm, pts, [1.1 * (1 - t) ** 0.7 + 0.05 for t in (i / 20 for i in range(20))] + [0], sides=12)
        for k in range(3):
            path = [V + Vector((math.cos(k * 2.1 + t * 9) * (1.3 - t), math.sin(k * 2.1 + t * 9) * (1.3 - t), s * (3.5 + 12 * t))) for t in (i / 40 for i in range(41))]
            tube(bm, path, [0.12 * (1 - i / 40) + 0.02 for i in range(41)], sides=5)
    finish(bm, "Jets", col, material("VoidJets", rgb(165, 140, 255), 1.5, alpha=0.7))

    bm = bmesh.new()
    for _ in range(55):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(5, 14)
        rock(bm, rng, V + U * (r * math.cos(a)) + Vv * (r * math.sin(a)) + N * rng.uniform(-0.6, 0.6), rng.uniform(0.15, 0.45), squash=(1, 1.6, 1))
    finish(bm, "Debris", col, material("VoidDebris", rgb(25, 15, 40), rough=0.9), smooth=False)


ULTIMATES = {
    "Rift": (ult_rift, (-14, -6, 12), (0, 9, 5)),
    "Electric": (ult_electric, (-40, -28, 26), (0, 13, 13)),
    "Fire": (ult_fire, (-16, -4, 10), (0, 11, 3)),
    "Ice": (ult_ice, (-27, -19, 17), (0, 10, 5)),
    "Nature": (ult_nature, (-29, -29, 21), (0, 0, 4)),
    "Wind": (ult_wind, (21, 1, 10), (0, 10, 7)),
    "Void": (ult_void, (-22, -10, 14), (0, 16, 8)),
}


def main():
    do_render = "--render" in sys.argv
    bpy.ops.wm.read_factory_settings(use_empty=True)
    out = OUT / "Ultimates"
    out.mkdir(parents=True, exist_ok=True)
    if do_render:
        (out / "previews").mkdir(exist_ok=True)
        setup_render_scene()
    for element, (build, _, _) in ULTIMATES.items():
        print(element)
        col = bpy.data.collections.new(element)
        bpy.context.scene.collection.children.link(col)
        build(col)
        markers3(col)
        export(col, out / f"{element}Ultimate.fbx")
    if do_render:
        for element, (_, cam, target) in ULTIMATES.items():
            render(element, out / "previews" / f"{element}.jpg", camera=cam, target=target)
    print(f"Wrote ultimates to {out}")


if __name__ == "__main__":
    main()
