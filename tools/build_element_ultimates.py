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


# ---------------------------------------------------------------- shared shapes for the reworked ultimates


def slab(bm, rng, base, width, depth, height, lean=0.2, facets=2):
    """A craggy, irregular chunk of ice or rock standing on `base`: no clean symmetry, flat-shaded facets."""
    geo = bmesh.ops.create_icosphere(bm, subdivisions=facets, radius=1.0)
    yaw = rng.uniform(0, 2 * math.pi)
    tilt = Matrix.Rotation(rng.uniform(-lean, lean), 3, "X") @ Matrix.Rotation(rng.uniform(-lean, lean), 3, "Y")
    spin = Matrix.Rotation(yaw, 3, "Z")
    seed = rng.random() * 50
    for v in geo["verts"]:
        d = v.co.normalized()
        crag = 1 + 0.32 * n3(d * 1.7, seed) + rng.uniform(-0.08, 0.08)
        top_bias = 1 - 0.45 * max(0.0, d.z) ** 2  # narrower towards the top, like a broken shard
        local = Vector((d.x * width * top_bias, d.y * depth * top_bias, (d.z + 1) * 0.5 * height)) * crag
        v.co = base + spin @ (tilt @ local)


def sliver(bm, rng, center, length, width=0.08):
    """A thin, sharp, three-sided glass splinter pointing in a random direction."""
    d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized()
    crystal(bm, center - d * length / 2, center + d * length / 2, width, 3, rng.uniform(0, 1))


# ---------------------------------------------------------------- Rift: a tear ripped open in space


def ult_rift(col):
    rng = random.Random(301)
    C = Vector((0, 10, 6.5))
    X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))
    n = 90
    jag = [1 + 0.16 * n3(Vector((j * 0.35, 0, 0)), 5) + (rng.uniform(-0.12, 0.05) if rng.random() < 0.3 else 0) for j in range(n)]

    def rim(j, grow=1.0):
        """A tall, lens-shaped, ragged opening: narrow pointed ends, wider in the middle."""
        th = 2 * math.pi * j / n
        x = 2.4 * math.sin(th) * (abs(math.sin(th)) ** 0.25)
        z = 5.8 * math.cos(th)
        return C + (X * x + Z * z) * jag[j] * grow

    perimeter = [rim(j) for j in range(n)]

    bm = bmesh.new()  # the blinding white interior: a lens that bows away from the viewer, so it reads as depth
    front_c = bm.verts.new(C + Y * 1.4)
    back_c = bm.verts.new(C + Y * 1.9)
    ring = [bm.verts.new(p) for p in perimeter]
    for j in range(n):
        k = (j + 1) % n
        bm.faces.new((front_c, ring[k], ring[j]))
        bm.faces.new((back_c, ring[j], ring[k]))
    finish(bm, "Abyss", col, material("RiftAbyss", rgb(245, 252, 255), 5), smooth=False)

    bm = bmesh.new()  # a thin, white-hot ragged edge with small splits running off it
    sweep(bm, perimeter, [square(0.07)] * n, closed=True)
    for _ in range(18):
        j = rng.randrange(n)
        out = (perimeter[j] - C).normalized()
        angular_crack(bm, perimeter[j], perimeter[j] + (out + Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.3, 0.3), rng.uniform(-0.6, 0.6)))).normalized() * rng.uniform(0.5, 1.4), rng, segments=2, r=0.035)
    finish(bm, "Edge", col, material("RiftEdge", rgb(215, 250, 255), 6), smooth=False)

    bm = bmesh.new()  # a soft halo hugging the edge
    sweep(bm, [rim(j, 1.06) for j in range(n)], [circle_profile(0.32, 6)] * n, closed=True)
    finish(bm, "Glow", col, material("RiftGlow", rgb(70, 190, 210), 1.0, alpha=0.35))

    bm = bmesh.new()  # faint filaments spiralling away into the depth behind the tear
    for k in range(10):
        j0 = int(n * k / 10)
        pts = []
        for i in range(31):
            t = i / 30
            p = perimeter[j0] - C
            a = t * 1.8
            rot = Matrix.Rotation(a, 3, "Y")
            pts.append(C + Y * (1.5 + 7 * t) + rot @ (p * (1 - t) ** 1.3))
        tube(bm, pts, [0.035 * (1 - i / 30) + 0.008 for i in range(31)], sides=4)
    finish(bm, "Depth", col, material("RiftDepth", rgb(80, 200, 220), 1.5, alpha=0.5))

    bm = bmesh.new()  # space cracking outwards from the tear, and along the ground
    for _ in range(16):
        j = rng.randrange(n)
        out = (perimeter[j] - C).normalized()
        start = perimeter[j] + out * 0.3
        end = start + (out + Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.5, 0.5), rng.uniform(-0.4, 0.4)))).normalized() * rng.uniform(2, 5)
        end.z = max(end.z, 0.05)
        angular_crack(bm, start, end, rng, segments=rng.choice((3, 4, 5)), wander=0.35, r=0.03)
    for _ in range(4):
        angular_crack(bm, Vector((rng.uniform(-0.6, 0.6), 9.6, 0.03)), Vector((rng.uniform(-3, 3), rng.uniform(3, 5.5), 0.03)), rng, segments=5, wander=0.35, r=0.04)
    finish(bm, "Cracks", col, material("RiftCracks", rgb(120, 225, 240), 3), smooth=False)

    bm = bmesh.new()  # splinters of broken space drifting round the tear
    for _ in range(70):
        j = rng.randrange(n)
        p = C + (perimeter[j] - C) * rng.uniform(1.15, 1.9) + Y * rng.uniform(-1.5, 1.5)
        sliver(bm, rng, p, rng.uniform(0.3, 1.1), rng.uniform(0.04, 0.1))
    finish(bm, "Shards", col, material("RiftShards", rgb(185, 225, 235), 0.4, glass=True), smooth=False)


def circle_profile(r, sides):
    return [(r * math.cos(2 * math.pi * k / sides), r * math.sin(2 * math.pi * k / sides)) for k in range(sides)]


# ---------------------------------------------------------------- Electric: a thundercloud (bolts are generated live in Roblox)


def ult_electric(col):
    rng = random.Random(302)
    CC = Vector((0, 14, 26))

    def cloud_layer(bm, count, rx, ry, z0, rmin, rmax, squash, subdiv):
        for _ in range(count):
            u, v = rng.uniform(-1, 1), rng.uniform(-1, 1)
            if u * u + v * v > 1:
                continue
            edge = u * u + v * v
            p = CC + Vector((u * rx, v * ry, z0 + rng.uniform(-0.6, 1.8) * (1 - edge)))
            ico(bm, p, rng.uniform(rmin, rmax) * (1 - 0.4 * edge), subdiv=subdiv, squash=squash, bumps=0.35, seed=rng.random() * 50)

    bm = bmesh.new()
    cloud_layer(bm, 150, 17, 13, 0.5, 1.6, 3.4, (1, 1, 0.7), 2)
    finish(bm, "Cloud", col, material("StormCloud", rgb(52, 52, 62), rough=1.0), smooth=False)

    bm = bmesh.new()  # a darker, flatter base where the rain falls from
    cloud_layer(bm, 70, 14, 10.5, -1.4, 1.8, 3.2, (1, 1, 0.38), 2)
    finish(bm, "CloudBase", col, material("StormBase", rgb(28, 28, 36), rough=1.0), smooth=False)

    bm = bmesh.new()  # light trapped inside the cloud, only seen when lightning flashes
    cloud_layer(bm, 26, 13, 10, -0.6, 1.5, 2.6, (1, 1, 0.5), 1)
    finish(bm, "CloudGlow", col, material("StormGlow", rgb(150, 110, 230), 1.5, alpha=0.5))

    bm = bmesh.new()  # thin rain in repeating columns so it can scroll down seamlessly
    for _ in range(140):
        u, v = rng.uniform(-1, 1), rng.uniform(-1, 1)
        if u * u + v * v > 1:
            continue
        x, y = u * 14, 14 + v * 10.5
        z0 = rng.uniform(0, 4)
        for m in range(6):
            z = z0 + 4 * m
            sweep(bm, [Vector((x + 0.25, y, z)), Vector((x, y, z + 2.2))], [square(0.02), square(0.02)])
    finish(bm, "Rain", col, material("StormRain", rgb(170, 175, 200), 0.6, alpha=0.4), smooth=False)


# ---------------------------------------------------------------- Fire: flames pouring from both hands (mostly particles in Roblox)


def ult_fire(col):
    rng = random.Random(303)
    hands = [Vector((-0.9, 1.5, 3.2)), Vector((0.9, 1.5, 3.2))]
    merge = Vector((0, 4.5, 3.2))
    y_end = 22.0

    def cone_r(y):
        return 0.8 + 3.6 * max(0.0, (y - merge.y) / (y_end - merge.y)) ** 0.85

    def axis_at(y):
        return Vector((0, y, 3.2 + 0.035 * max(0.0, y - merge.y) ** 1.4))

    def turbulent_shell(bm, scale, seed, sides=20, steps=70, roughness=0.32):
        rings = []
        for i in range(steps + 1):
            t = i / steps
            y = merge.y - 0.5 + (y_end - merge.y + 0.5) * t
            c = axis_at(y)
            ring = []
            for k in range(sides):
                a = 2 * math.pi * k / sides
                d = Vector((math.cos(a), 0, math.sin(a)))
                r = cone_r(y) * scale * (1 + roughness * n3(Vector((d.x * 1.3, y * 0.28, d.z * 1.3)), seed))
                r *= min(1.0, (1 - t) * 6 + 0.15)
                ring.append(c + d * max(r, 0.05))
            rings.append(ring)
        loft(bm, rings)

    bm = bmesh.new()  # the white-hot jets leaving each hand and the thin core they merge into
    for h in hands:
        tube(bm, [h.lerp(merge, i / 8) for i in range(9)], [0.16 + 0.1 * i / 8 for i in range(9)], sides=8)
    ys = [merge.y + (14 - merge.y) * i / 30 for i in range(31)]
    tube(bm, [axis_at(y) for y in ys], [0.3 + 0.5 * (i / 30) for i in range(30)] + [0], sides=10)
    finish(bm, "Core", col, material("FireCore", rgb(255, 235, 190), 4))

    bm = bmesh.new()
    turbulent_shell(bm, 0.6, 1)
    finish(bm, "Shell", col, material("FireShell", rgb(255, 140, 50), 1.5, alpha=0.45))

    bm = bmesh.new()
    turbulent_shell(bm, 1.0, 2, roughness=0.42)
    finish(bm, "OuterShell", col, material("FireOuter", rgb(220, 70, 25), 1.0, alpha=0.25))


# ---------------------------------------------------------------- Ice: a stomp raises a wall of jagged ice


def ult_ice(col):
    rng = random.Random(304)

    bm = bmesh.new()  # frost spreading across the ground
    spikes = [rng.uniform(0.7, 1.2) for _ in range(90)]
    flat_disc(bm, Vector((0, 7, 0.02)), lambda a: (8 + 3 * math.sin(a)) * spikes[int((a / (2 * math.pi)) * 90) % 90], thickness=0.03, n=90)
    finish(bm, "Frost", col, material("IceFrost", rgb(205, 230, 240), 0.2, glass=True), smooth=False)

    bm = bmesh.new()  # cracks running from the stomp to the wall
    for k in range(9):
        a = math.radians(-55 + 110 * k / 8 + rng.uniform(-5, 5))
        end = Vector((14 * math.sin(a), 14 * math.cos(a), 0.03))
        angular_crack(bm, Vector((0, 0.6, 0.03)), end, rng, segments=7, wander=0.18, r=0.05)
        for _ in range(2):
            src = Vector((0, 0.6, 0.03)).lerp(end, rng.uniform(0.3, 0.8))
            angular_crack(bm, src, src + Vector((rng.uniform(-2.5, 2.5), rng.uniform(-1, 2.5), 0)), rng, segments=3, wander=0.3, r=0.03)
    finish(bm, "Cracks", col, material("IceCracks", rgb(170, 225, 245), 2), smooth=False)

    for k in range(9):  # jagged spikes bursting up along the path, bigger towards the wall
        bm = bmesh.new()
        y = 2.0 + k * 1.3
        size = 0.5 + k * 0.28
        for _ in range(rng.randint(3, 5)):
            base = Vector((rng.uniform(-1.2, 1.2), y + rng.uniform(-0.5, 0.5), -0.4))
            d = Vector((rng.uniform(-0.6, 0.6), rng.uniform(0.0, 0.7), 1)).normalized()
            crystal(bm, base, base + d * size * rng.uniform(1.8, 3.4), size * rng.uniform(0.18, 0.35), rng.choice((3, 4, 5)), rng.uniform(0, 1))
        finish(bm, f"Spike_{k + 1:02d}", col, material("IceSpikes", rgb(190, 225, 240), 0.3, glass=True), smooth=False)

    n = 14
    for k in range(n):  # the wall: an arc of craggy slabs with splintered tops, each with a denser core
        shell, core = bmesh.new(), bmesh.new()
        th = math.radians(-60 + 120 * k / (n - 1) + rng.uniform(-2, 2))
        center = Vector((14.5 * math.sin(th), 14.5 * math.cos(th), -0.8))
        tangent = Vector((math.cos(th), -math.sin(th), 0))
        out = Vector((math.sin(th), math.cos(th), 0))
        falloff = 1 - 0.3 * abs(k - (n - 1) / 2) / ((n - 1) / 2)
        for s in range(rng.randint(4, 6)):
            base = center + tangent * rng.uniform(-1.4, 1.4) + out * rng.uniform(-0.8, 0.8)
            h = rng.uniform(8, 16) * falloff
            w = rng.uniform(1.0, 1.7)
            slab(shell, rng, base, w, w * rng.uniform(0.5, 0.8), h, lean=0.18)
            slab(core, rng, base + out * 0.1, w * 0.55, w * 0.35, h * 0.8, lean=0.1)
            for _ in range(rng.randint(1, 3)):  # splinters on the top
                top = base + Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.4, 0.4), h * rng.uniform(0.7, 0.92)))
                d = Vector((rng.uniform(-0.4, 0.4), rng.uniform(-0.3, 0.5), 1)).normalized()
                crystal(shell, top, top + d * rng.uniform(1.2, 3.2), rng.uniform(0.15, 0.32), rng.choice((3, 4)), rng.uniform(0, 1))
        finish(shell, f"Wall_{k + 1:02d}", col, material("IceWall", rgb(180, 215, 230), 0.25, glass=True), smooth=False)
        finish(core, f"WallCore_{k + 1:02d}", col, material("IceWallCore", rgb(95, 145, 180), rough=0.2), smooth=False)


# ---------------------------------------------------------------- Wind: the user claps, and a blast of wind bursts out


def ult_wind(col):
    rng = random.Random(307)
    K = Vector((0, 1.6, 4.3))  # where the user's hands meet, in front of the chest
    X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))

    bm = bmesh.new()  # the instant of the clap: a sharp starburst of compressed air
    for _ in range(36):
        d = Vector((rng.uniform(-1, 1), rng.uniform(-0.3, 1.0), rng.uniform(-1, 1))).normalized()
        crystal(bm, K + d * 0.2, K + d * rng.uniform(0.8, 2.4), rng.uniform(0.03, 0.07), 3, rng.uniform(0, 1))
    ico(bm, K, 0.3, subdiv=2, bumps=0.1)
    finish(bm, "Flash", col, material("WindFlash", rgb(240, 250, 250), 3, alpha=0.7), smooth=False)

    bm = bmesh.new()  # thin shockwave shells bulging forwards from the hands
    for r0, r1, depth, th in ((0.6, 2.2, 1.6, 0.05), (1.1, 3.6, 2.6, 0.04), (1.8, 5.2, 3.4, 0.03)):
        section = [(r0, 0.0), (r1 * 0.75, depth * 0.55), (r1, depth), (r1 * 0.75 - th, depth * 0.55 - th)]
        revolve(bm, K, X, Z, Y, section, n=64)
    finish(bm, "Rings", col, material("WindRings", rgb(215, 235, 235), 0.6, alpha=0.25))

    bm = bmesh.new()  # a flat ring of air rushing out along the ground
    revolve(bm, Vector((0, 0.5, 0.15)), X, Y, Z, [(2.0, 0.0), (2.8, 0.25), (3.6, 0.05), (2.8, 0.08)], n=64)
    finish(bm, "GroundRing", col, material("WindGround", rgb(205, 215, 210), 0.4, alpha=0.3))

    bm = bmesh.new()  # streaks of air shooting out, mostly forwards
    for _ in range(46):
        d = Vector((rng.uniform(-1, 1), rng.uniform(-0.2, 1.4), rng.uniform(-0.6, 0.8))).normalized()
        length = rng.uniform(5, 14)
        bend = Vector((rng.uniform(-0.15, 0.15), 0, rng.uniform(0, 0.12)))
        pts = [K + d * (0.6 + length * t) + bend * (length * t) ** 1.5 for t in (i / 16 for i in range(17))]
        up = Z if abs(d.z) < 0.8 else X
        ribbon(bm, pts, [0.06 * math.sin(math.pi * (i / 16)) ** 0.6 + 0.004 for i in range(17)], lambda i, up=up, d=d: d.cross(up).normalized(), thick=0.012)
    finish(bm, "Streaks", col, material("WindStreaks", rgb(215, 232, 230), 0.5, alpha=0.45))

    bm = bmesh.new()  # grit and pebbles around the feet that the blast kicks away
    for _ in range(70):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(1.2, 3.2)
        rock(bm, rng, Vector((math.cos(a) * r, math.sin(a) * r, 0.08)), rng.uniform(0.04, 0.13))
    finish(bm, "Debris", col, material("WindDebris", rgb(120, 115, 105), rough=0.9), smooth=False)


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


# ---------------------------------------------------------------- Earth: the ground splits open in front of the user


def ult_earth(col):
    rng = random.Random(308)
    length = 30.0

    bm = bmesh.new()  # the molten fissure ripping forwards, with branching cracks
    path = [Vector((0, 1.2, 0.03))]
    for i in range(1, 25):
        y = 1.2 + (length - 1.2) * i / 24
        path.append(Vector((path[-1].x * 0.6 + rng.uniform(-0.7, 0.7), y, 0.03)))
    for p, q in zip(path, path[1:]):
        w = 0.25 + 0.5 * (p.y / length)
        sweep(bm, [p, q], [[(w, 0.0), (0, 0.06), (-w, 0.0), (0, -0.02)]] * 2)
    for _ in range(14):
        src = rng.choice(path[2:-1])
        angular_crack(bm, src, src + Vector((rng.choice((-1, 1)) * rng.uniform(1.5, 4), rng.uniform(-0.5, 2.5), 0)), rng, segments=3, wander=0.3, r=0.07)
    finish(bm, "Fissure", col, material("EarthFissure", rgb(255, 160, 60), 5), smooth=False)

    bm = bmesh.new()  # broken rubble lining the fissure
    for p in path[1:]:
        for s in (-1, 1):
            for _ in range(3):
                rock(bm, rng, p + Vector((s * rng.uniform(0.8, 2.6), rng.uniform(-0.6, 0.6), 0.1)), rng.uniform(0.12, 0.35), squash=(1, 1, 0.6), jitter=0.45)
    finish(bm, "Rubble", col, material("EarthRubble", rgb(110, 95, 80), rough=0.95), smooth=False)

    k = 0
    for i in range(12):  # slabs of ground heaving up and tilting away from the fissure
        bm = bmesh.new()
        y = 3 + i * 2.2
        s = 1 if i % 2 == 0 else -1
        p = path[min(int((y - 1.2) / (length - 1.2) * 24), 24)]
        w = rng.uniform(1.6, 2.4)
        slab(bm, rng, Vector((0, 0, -0.4)), w, rng.uniform(0.35, 0.55), rng.uniform(3.5, 6.0) * (0.7 + 0.5 * i / 11), lean=0.06, facets=2)
        tilt = Matrix.Rotation(-s * math.radians(rng.uniform(25, 45)), 4, "Y")
        bmesh.ops.transform(bm, matrix=Matrix.Translation(Vector((p.x + s * rng.uniform(1.4, 2.0), y, 0))) @ tilt @ Matrix.Rotation(math.pi / 2, 4, "Z"), verts=bm.verts)
        k += 1
        finish(bm, f"Slab_{k:02d}", col, material("EarthSlab", rgb(100, 86, 72), rough=0.95), smooth=False)

    for i in range(8):  # jagged spires of rock erupting from the fissure itself
        bm = bmesh.new()
        y = 6 + i * 3.1
        p = path[min(int((y - 1.2) / (length - 1.2) * 24), 24)]
        h = rng.uniform(5, 9) * (0.75 + 0.4 * i / 7)
        slab(bm, rng, Vector((p.x, y, -0.6)), rng.uniform(0.8, 1.1), rng.uniform(0.7, 0.9), h, lean=0.25, facets=2)
        for _ in range(2):
            base = Vector((p.x + rng.uniform(-0.8, 0.8), y + rng.uniform(-0.8, 0.8), -0.4))
            slab(bm, rng, base, rng.uniform(0.4, 0.6), rng.uniform(0.35, 0.5), h * rng.uniform(0.4, 0.65), lean=0.35, facets=1)
        finish(bm, f"Spire_{i + 1:02d}", col, material("EarthSpire", rgb(85, 74, 64), rough=0.95), smooth=False)

    for i in range(7):  # boulders torn loose and held floating around the user
        bm = bmesh.new()
        a = 2 * math.pi * i / 7 + rng.uniform(-0.3, 0.3)
        r = rng.uniform(3, 5)
        c = Vector((math.cos(a) * r, math.sin(a) * r * 0.8, rng.uniform(2.5, 6)))
        rock(bm, rng, c, rng.uniform(0.6, 1.2), squash=(1, 1, 0.8), jitter=0.4)
        rock(bm, rng, c + Vector((rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), -0.4)), rng.uniform(0.3, 0.5), jitter=0.4)
        finish(bm, f"Boulder_{i + 1:02d}", col, material("EarthBoulder", rgb(95, 82, 70), rough=0.95), smooth=False)


# ---------------------------------------------------------------- Water: a tidal wave rises and crashes forwards


def ult_water(col):
    rng = random.Random(309)
    width = 30.0
    cols = 60

    def curl(t, h):
        """The wave's cross-section: rising from the ground behind, curling over at the top.
        Returns (forward, up) for t in 0..1 along the face."""
        if t < 0.7:
            u = t / 0.7
            return (-2.0 + 3.5 * u ** 1.6, h * math.sin(u * math.pi / 2) ** 0.9)
        u = (t - 0.7) / 0.3
        ang = u * math.pi * 1.05
        r = 1.6 * h / 10
        return (1.5 + r * math.sin(ang), h - r * (1 - math.cos(ang)))

    def surface(thick, h_fn, x_fn):
        rows = 34
        grid = []
        for i in range(cols + 1):
            s = i / cols
            x = (s - 0.5) * width
            h = h_fn(s)
            bulge = x_fn(s)
            ring = []
            for j in range(rows + 1):
                f, z = curl(j / rows, h)
                ring.append(Vector((x, 4 + f + bulge, z)))
            for j in range(rows, -1, -1):  # back side, offset for thickness
                f, z = curl(j / rows, h)
                ring.append(Vector((x, 4 + f + bulge - thick * (1 - j / rows), z - thick * 0.4)))
            grid.append(ring)
        return grid

    heights = lambda s: 12 * math.sin(math.pi * (0.06 + 0.88 * s)) ** 0.6 * (1 + 0.08 * n3(Vector((s * 6, 0, 0)), 3))
    bulges = lambda s: 3.0 * math.sin(math.pi * s)  # the middle leads, the ends trail

    bm = bmesh.new()
    loft(bm, surface(0.7, heights, bulges))
    finish(bm, "Wave", col, material("WaterWave", rgb(60, 150, 220), 0.5, glass=True))

    bm = bmesh.new()  # foam along the curling lip
    lip = []
    for i in range(cols + 1):
        s = i / cols
        f, z = curl(0.93, heights(s))
        lip.append(Vector(((s - 0.5) * width, 4 + f + bulges(s), z)))
    noisy = [0.45 + 0.25 * abs(n3(Vector((i * 0.3, 0, 0)), 7)) for i in range(cols + 1)]
    tube(bm, lip, noisy, sides=10)
    finish(bm, "Crest", col, material("WaterCrest", rgb(235, 245, 255), 1.0, alpha=0.85))

    bm = bmesh.new()  # currents streaming up the face of the wave
    for k in range(14):
        s = (k + 0.5) / 14
        pts = []
        for j in range(30):
            f, z = curl(0.05 + 0.85 * j / 29, heights(s))
            pts.append(Vector(((s - 0.5) * width + rng.uniform(-0.2, 0.2), 4 + f + bulges(s) + 0.4, z)))
        tube(bm, pts, [0.06] * 29 + [0.0], sides=4)
    finish(bm, "Swirl", col, material("WaterSwirl", rgb(150, 215, 255), 1.5, alpha=0.6))

    bm = bmesh.new()  # spray thrown off the crest
    for _ in range(160):
        s = rng.random()
        f, z = curl(rng.uniform(0.85, 1.0), heights(s))
        c = Vector(((s - 0.5) * width, 4 + f + bulges(s) + rng.uniform(-0.5, 1.5), z + rng.uniform(0, 2.5)))
        geo = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=rng.uniform(0.06, 0.2))
        for v in geo["verts"]:
            v.co = c + v.co
    finish(bm, "Spray", col, material("WaterSpray", rgb(225, 240, 255), 1.0, alpha=0.8), smooth=False)

    bm = bmesh.new()  # churning foam at the foot of the wave
    edge = [rng.uniform(0.8, 1.2) for _ in range(80)]
    flat_disc(bm, Vector((0, 4.5, 0.03)), lambda a: (abs(math.cos(a)) * 15 + abs(math.sin(a)) * 3.5) * edge[int(a / (2 * math.pi) * 80) % 80], thickness=0.08, n=80)
    finish(bm, "Foam", col, material("WaterFoam", rgb(230, 242, 250), 0.4, alpha=0.7), smooth=False)


# ---------------------------------------------------------------- Energy: a Kamehameha


def ult_energy(col):
    rng = random.Random(310)
    M = Vector((0, 1.4, 3.6))  # the muzzle: hands thrust forwards at chest height
    beam_len = 60.0
    X, Y, Z = Vector((1, 0, 0)), Vector((0, 1, 0)), Vector((0, 0, 1))

    def beam_points(steps=80):
        return [M + Y * (beam_len * i / steps) for i in range(steps + 1)]

    pts = beam_points()
    bm = bmesh.new()
    tube(bm, pts, [1.25] * 80 + [0.0], sides=24)
    finish(bm, "Beam", col, material("EnergyCore", rgb(255, 255, 255), 8))

    bm = bmesh.new()
    tube(bm, pts, [2.1 + 0.12 * math.sin(i * 1.1) for i in range(80)] + [0.0], sides=24)
    finish(bm, "BeamGlow", col, material("EnergyGlow", rgb(90, 200, 255), 3, alpha=0.5))

    bm = bmesh.new()
    rings = []
    for i, p in enumerate(pts):
        ring = []
        for k in range(28):
            a = 2 * math.pi * k / 28
            r = (3.1 + 0.3 * math.sin(i * 0.7 + a * 3) + 0.2 * n3(Vector((math.cos(a), i * 0.15, math.sin(a))), 2)) * min(1.0, (80 - i) / 3 + 0.02)
            ring.append(p + (X * math.cos(a) + Z * math.sin(a)) * r)
        rings.append(ring)
    loft(bm, rings)
    finish(bm, "BeamAura", col, material("EnergyAura", rgb(40, 140, 255), 1, alpha=0.2))

    bm = bmesh.new()
    for k in range(3):
        path = [M + Y * (beam_len * t) + (X * math.cos(k * 2.09 + t * 2 * math.pi * 9) + Z * math.sin(k * 2.09 + t * 2 * math.pi * 9)) * 2.6 for t in (i / 300 for i in range(301))]
        tube(bm, path, [0.0] + [0.11] * 299 + [0.0], sides=6)
    finish(bm, "BeamCoils", col, material("EnergyCoils", rgb(160, 230, 255), 3))

    bm = bmesh.new()  # the bulbous head blasting out in front of the beam
    ico(bm, M + Y * beam_len, 4.2, subdiv=4, squash=(1, 1.15, 1), bumps=0.08, seed=4)
    finish(bm, "Head", col, material("EnergyHead", rgb(110, 210, 255), 3, alpha=0.55))

    bm = bmesh.new()
    ico(bm, M, 0.95, subdiv=4, bumps=0.03)
    finish(bm, "Ball", col, material("EnergyCore", rgb(255, 255, 255), 8))

    bm = bmesh.new()
    ico(bm, M, 1.6, subdiv=4, bumps=0.12, seed=8)
    finish(bm, "BallGlow", col, material("EnergyGlow", rgb(90, 200, 255), 3, alpha=0.5))

    bm = bmesh.new()  # shockwave rings punched out at the moment of release
    for d, r in ((1.0, 2.6), (3.0, 3.6), (5.5, 4.4)):
        revolve(bm, M + Y * d, X, Z, Y, [(r - 0.15, 0), (r, 0.12), (r + 0.25, 0), (r, -0.06)], n=56)
    finish(bm, "Rings", col, material("EnergyRings", rgb(190, 235, 255), 2, alpha=0.6))

    bm = bmesh.new()  # the ki aura blazing round the user while charging
    rings = []
    for i in range(31):
        t = i / 30
        z = 7.5 * t
        ring = []
        for k in range(32):
            a = 2 * math.pi * k / 32
            spike = 0.35 * abs(math.sin(a * 4 + t * 3)) ** 3
            r = (1.6 + 0.4 * math.sin(math.pi * min(t * 1.6, 1))) * (1 - t ** 3) + spike * t
            ring.append(Vector((math.cos(a) * r, math.sin(a) * r * 0.8, z)))
        rings.append(ring)
    loft(bm, rings)
    finish(bm, "Aura", col, material("EnergyAuraBody", rgb(90, 200, 255), 1.5, alpha=0.3))

    bm = bmesh.new()  # the ground cracking under the pressure
    for k in range(11):
        a = 2 * math.pi * k / 11 + rng.uniform(-0.2, 0.2)
        angular_crack(bm, Vector((math.cos(a) * 0.8, math.sin(a) * 0.8, 0.03)), Vector((math.cos(a) * rng.uniform(4, 7), math.sin(a) * rng.uniform(4, 7), 0.03)), rng, segments=4, wander=0.3, r=0.06)
    finish(bm, "Cracks", col, material("EnergyCracks", rgb(150, 220, 255), 3), smooth=False)

    bm = bmesh.new()  # chunks of ground lifted by the gathering energy
    for _ in range(26):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(2, 6.5)
        rock(bm, rng, Vector((math.cos(a) * r, math.sin(a) * r, rng.uniform(0.5, 3.5))), rng.uniform(0.15, 0.45), jitter=0.45)
    finish(bm, "Rocks", col, material("EnergyRocks", rgb(105, 95, 85), rough=0.95), smooth=False)


ULTIMATES = {
    "Rift": (ult_rift, (-18, -8, 10), (0, 9, 6)),
    "Electric": (ult_electric, (-46, -32, 18), (0, 13, 15)),
    "Fire": (ult_fire, (-15, -5, 9), (0, 11, 3)),
    "Ice": (ult_ice, (-25, -17, 14), (0, 10, 5)),
    "Wind": (ult_wind, (11, 15, 7), (0, 4, 3.5)),
    "Void": (ult_void, (-22, -10, 14), (0, 16, 8)),
    "Earth": (ult_earth, (-25, -7, 17), (0, 14, 3)),
    "Water": (ult_water, (-30, -10, 11), (0, 6, 6)),
    "Energy": (ult_energy, (-24, -14, 14), (0, 18, 3)),
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
