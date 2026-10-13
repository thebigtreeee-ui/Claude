"""Builds one 3D beam model per Eternium element in Blender and exports each as FBX.

Run with a Python that has the `bpy` module (pip install bpy), from the repo root:
    python tools/build_element_beams.py            # FBX files only
    python tools/build_element_beams.py --render   # also render preview PNGs

Every beam is modelled along +Y from Y=0 to Y=LENGTH and is split into named parts
(Core, Flames, Shards...). ElementBeams.lua colours each part by name in Roblox and uses
the two tiny "Start"/"End" markers to aim and stretch the beam, so import scale and axis
settings don't matter.
"""
import math
import random
import sys
from pathlib import Path

import bpy  # must come first: it makes bmesh/mathutils importable
import bmesh
from mathutils import Matrix, Vector, noise

OUT = Path(__file__).resolve().parent.parent / "ElementBeams"
LENGTH = 24.0
AXIS = Vector((0, 1, 0))


# ---------------------------------------------------------------- geometry helpers


def frames(points):
    """Parallel-transport frames (tangent, normal, binormal) along a polyline."""
    count = len(points)
    tangents = []
    for i in range(count):
        a = points[max(i - 1, 0)]
        b = points[min(i + 1, count - 1)]
        tangents.append((b - a).normalized())
    up = Vector((0, 0, 1)) if abs(tangents[0].z) < 0.9 else Vector((1, 0, 0))
    normal = tangents[0].cross(up).normalized()
    result = []
    for t in tangents:
        normal = (normal - t * normal.dot(t)).normalized()
        result.append((t, normal, t.cross(normal)))
    return result


def sweep(bm, points, profiles, closed=False):
    """Lofts 2D cross-sections along a path. A profile of None collapses to a point (a tip)."""
    rings = []
    for p, (_, n, b), prof in zip(points, frames(points), profiles):
        rings.append([p] if prof is None else [p + n * x + b * y for x, y in prof])
    loft(bm, rings, closed)


def loft(bm, rings, closed=False):
    """Skins a series of closed cross-sections given directly as world-space point lists."""
    rings = [[bm.verts.new(p) for p in ring] for ring in rings]
    pairs = list(zip(rings, rings[1:]))
    if closed:
        pairs.append((rings[-1], rings[0]))
    for r0, r1 in pairs:
        if len(r0) == 1 and len(r1) == 1:
            continue
        if len(r0) == 1:
            for j in range(len(r1)):
                bm.faces.new((r0[0], r1[j], r1[(j + 1) % len(r1)]))
        elif len(r1) == 1:
            for j in range(len(r0)):
                bm.faces.new((r0[j], r1[0], r0[(j + 1) % len(r0)]))
        else:
            for j in range(len(r0)):
                k = (j + 1) % len(r0)
                bm.faces.new((r0[j], r1[j], r1[k], r0[k]))
    if not closed:
        for ring, flip in ((rings[0], True), (rings[-1], False)):
            if len(ring) > 2:
                bm.faces.new(list(reversed(ring)) if flip else ring)


def circle(radius, sides, phase=0.0):
    return [
        (radius * math.cos(phase + 2 * math.pi * j / sides), radius * math.sin(phase + 2 * math.pi * j / sides))
        for j in range(sides)
    ]


def tube(bm, points, radii, sides=8, phase=0.0, closed=False):
    profiles = [None if r <= 1e-4 else circle(r, sides, phase) for r in radii]
    sweep(bm, points, profiles, closed)


def crystal(bm, base, tip, radius, sides=6, spin=0.0):
    """Elongated bipyramid: pointed at both ends, faceted in between."""
    d = tip - base
    pts = [base, base + d * 0.18, base + d * 0.78, tip]
    sweep(bm, pts, [None, circle(radius, sides, spin), circle(radius * 0.85, sides, spin), None])


def rock(bm, rng, center, size, squash=(1, 1, 1), jitter=0.35):
    """Faceted irregular chunk (a jittered icosphere)."""
    rot = Matrix.Rotation(rng.uniform(0, 6.3), 4, Vector((rng.random(), rng.random(), rng.random())).normalized())
    geo = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=size)
    for v in geo["verts"]:
        c = v.co * (1 + rng.uniform(-jitter, jitter))
        c = Vector((c.x * squash[0], c.y * squash[1], c.z * squash[2]))
        v.co = center + rot.to_3x3() @ c


def leaf(bm, root, direction, normal, length, width, curl=0.25, thick=0.03):
    """Two-sided curved leaf with a raised midrib."""
    direction = direction.normalized()
    side = direction.cross(normal).normalized()
    normal = side.cross(direction).normalized()
    steps = 7
    left, right, top, bottom = [], [], [], []
    for i in range(steps + 1):
        u = i / steps
        w = width * math.sin(math.pi * u) ** 0.7
        c = root + direction * (length * u) + normal * (curl * length * u * u)
        left.append(bm.verts.new(c - side * w - normal * w * 0.25))
        right.append(bm.verts.new(c + side * w - normal * w * 0.25))
        top.append(bm.verts.new(c + normal * thick))
        bottom.append(bm.verts.new(c - normal * thick))
    for i in range(steps):
        bm.faces.new((left[i], top[i], top[i + 1], left[i + 1]))
        bm.faces.new((top[i], right[i], right[i + 1], top[i + 1]))
        bm.faces.new((left[i + 1], bottom[i + 1], bottom[i], left[i]))
        bm.faces.new((bottom[i + 1], right[i + 1], right[i], bottom[i]))


def jagged(a, b, depth, amount, rng):
    """Midpoint-displacement polyline between a and b (for lightning)."""
    pts = [a, b]
    for _ in range(depth):
        new = [pts[0]]
        for p, q in zip(pts, pts[1:]):
            d = q - p
            off = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1)))
            off -= d.normalized() * off.dot(d.normalized())
            new += [(p + q) / 2 + off * amount * d.length, q]
        pts = new
    return pts


def axis_point(y, offset=(0.0, 0.0)):
    return Vector((offset[0], y, offset[1]))


def helix(y0, y1, steps, radius_fn, turns, phase):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        a = phase + 2 * math.pi * turns * t
        r = radius_fn(t)
        pts.append(Vector((r * math.cos(a), y0 + (y1 - y0) * t, r * math.sin(a))))
    return pts


def n3(p, seed=0.0):
    return noise.noise(Vector((p.x + seed * 17.1, p.y + seed * 3.7, p.z - seed * 9.3)))


# ---------------------------------------------------------------- scene helpers

MATERIALS = {}


def material(name, color, strength=0.0, glass=False, alpha=1.0, rough=0.4):
    if name in MATERIALS:
        return MATERIALS[name]
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (*color, 1)
    bsdf.inputs["Roughness"].default_value = rough
    if strength:
        bsdf.inputs["Emission Color"].default_value = (*color, 1)
        bsdf.inputs["Emission Strength"].default_value = strength
    if glass:
        bsdf.inputs["Transmission Weight"].default_value = 0.9
        bsdf.inputs["IOR"].default_value = 1.31
        bsdf.inputs["Roughness"].default_value = 0.08
    if alpha < 1:
        bsdf.inputs["Alpha"].default_value = alpha
    MATERIALS[name] = mat
    return mat


def rgb(r, g, b):
    # sRGB 0-255 -> linear, so the Blender preview matches the Roblox colours in ElementBeams.lua
    return tuple(((c / 255) ** 2.2) for c in (r, g, b))


def finish(bm, name, collection, mat, smooth=True):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(mat)
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    tris = sum(len(p.vertices) - 2 for p in mesh.polygons)
    assert tris < 20000, f"{collection.name}/{name} has {tris} triangles (Roblox limit is 20k)"
    print(f"  {name:<12} {tris:>6} tris")
    return obj


def markers(collection, start_y=0.0, end_y=LENGTH):
    mat = material("Marker", (1, 0, 1))
    for name, y in (("Start", start_y), ("End", end_y)):
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=0.1, matrix=Matrix.Translation((0, y, 0)))
        obj = finish(bm, name, collection, mat, smooth=False)
        obj.hide_render = True


# ---------------------------------------------------------------- the six beams


def build_fire(col):
    """No solid tube: a white-hot core wrapped in twisting flame tongues that flare and trail."""
    rng = random.Random(11)
    steps = 96

    bm = bmesh.new()
    pts = [axis_point(LENGTH * i / steps) for i in range(steps + 1)]
    radii = [0.3 + 0.15 * math.sin(math.pi * min(i / steps * 3, 1)) + 0.06 * n3(p * 1.3) for i, p in enumerate(pts)]
    radii[-1] = 0
    tube(bm, pts, radii, sides=12)
    finish(bm, "Core", col, material("FireCore", rgb(255, 240, 180), 6))

    bm = bmesh.new()
    for k in range(5):
        phase = 2 * math.pi * k / 5

        def spread(t):
            return 0.45 + 0.35 * t + 0.15 * n3(Vector((t * 6, k, 0)))

        path = helix(0.2, LENGTH - 0.6, steps, spread, turns=2.2, phase=phase)
        rads = []
        for i, p in enumerate(path):
            t = i / steps
            lick = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 6 + k * 1.7)  # bulges that read as flame licks
            rads.append((0.12 + 0.24 * lick) * min(t * 8, 1, (1 - t) * 6))
        rads[0] = rads[-1] = 0
        tube(bm, path, rads, sides=8)
    finish(bm, "Flames", col, material("FireFlames", rgb(255, 120, 20), 3))

    bm = bmesh.new()
    for _ in range(26):
        y = rng.uniform(1.5, LENGTH - 1)
        a = rng.uniform(0, 2 * math.pi)
        out = Vector((math.cos(a), 0, math.sin(a)))
        r0 = 0.5 + 0.35 * y / LENGTH
        length = rng.uniform(1.4, 2.6)
        side = out.cross(AXIS)
        sway = rng.uniform(-0.3, 0.3)
        path = []
        for i in range(13):
            t = i / 12
            # licks outward and streams backwards in an S-curve, like flame dragged by the beam's speed
            p = axis_point(y - length * t) + out * (r0 + 0.75 * t**0.7) + side * sway * math.sin(t * math.pi * 2)
            path.append(p)
        rads = [0.28 * (1 - i / 12) ** 1.3 for i in range(13)]
        rads[-1] = 0
        tube(bm, path, rads, sides=7)
    finish(bm, "Wisps", col, material("FireWisps", rgb(255, 60, 15), 2.5))


def build_ice(col):
    """A crystalline spear: overlapping hexagonal crystals with shards jutting forward-outward."""
    rng = random.Random(22)

    bm = bmesh.new()
    tube(bm, [axis_point(0), axis_point(LENGTH)], [0.16, 0.16], sides=6)
    finish(bm, "Core", col, material("IceCore", rgb(225, 250, 255), 5), smooth=False)

    bm = bmesh.new()
    y = -0.3
    while y < LENGTH - 2:
        length = rng.uniform(3.0, 4.4)
        lean = Vector((rng.uniform(-0.12, 0.12), 0, rng.uniform(-0.12, 0.12)))
        crystal(bm, axis_point(y), axis_point(min(y + length, LENGTH + 0.3)) + lean, rng.uniform(0.5, 0.75), 6, rng.uniform(0, 1))
        y += length * 0.6
    finish(bm, "Crystal", col, material("IceCrystal", rgb(150, 215, 255), 0.6, glass=True), smooth=False)

    bm = bmesh.new()
    for _ in range(34):
        y = rng.uniform(1, LENGTH - 2)
        a = rng.uniform(0, 2 * math.pi)
        out = Vector((math.cos(a), 0, math.sin(a)))
        base = axis_point(y) + out * 0.35
        tilt = math.radians(rng.uniform(25, 65))
        d = (AXIS * math.cos(tilt) + out * math.sin(tilt)).normalized()
        crystal(bm, base, base + d * rng.uniform(0.9, 2.4), rng.uniform(0.12, 0.28), rng.choice((4, 5, 6)), rng.uniform(0, 1))
    finish(bm, "Shards", col, material("IceShards", rgb(190, 235, 255), 0.8, glass=True), smooth=False)


def build_electric(col):
    """A thick jagged main bolt with a thinner one twisting round it, forking branches, and a pulsing plasma sheath."""
    rng = random.Random(33)

    bm = bmesh.new()
    mains = []
    for seed, radius in ((0, 0.3), (1, 0.15)):
        pts = jagged(axis_point(0), axis_point(LENGTH), 6, 0.035, random.Random(33 + seed))
        mains.append(pts)
        tube(bm, pts, [radius] * len(pts), sides=6)
    finish(bm, "Bolt", col, material("ElecBolt", rgb(245, 230, 255), 8), smooth=False)

    bm = bmesh.new()
    for _ in range(14):
        src = rng.choice(mains[0][4:-4])
        a = rng.uniform(0, 2 * math.pi)
        d = (AXIS * rng.uniform(0.6, 1.0) + Vector((math.cos(a), 0, math.sin(a))) * rng.uniform(0.6, 1.2)).normalized()
        end = src + d * rng.uniform(2, 4.5)
        pts = jagged(src, end, 3, 0.3, rng)
        tube(bm, pts, [0.07 * (1 - i / (len(pts) - 1)) + 0.01 for i in range(len(pts))], sides=4)
        fork = rng.choice(pts[2:-1])
        end2 = fork + (d + Vector((rng.uniform(-1, 1), 0.3, rng.uniform(-1, 1)))).normalized() * rng.uniform(0.8, 1.8)
        pts2 = jagged(fork, end2, 2, 0.3, rng)
        tube(bm, pts2, [0.04 * (1 - i / (len(pts2) - 1)) + 0.008 for i in range(len(pts2))], sides=4)
    finish(bm, "Branches", col, material("ElecBranch", rgb(130, 80, 255), 1.2), smooth=False)

    bm = bmesh.new()
    steps = 120
    pts = [axis_point(LENGTH * i / steps) for i in range(steps + 1)]
    rads = [0.75 + 0.2 * math.sin(i / steps * 2 * math.pi * 10) ** 2 for i in range(steps + 1)]
    tube(bm, pts, rads, sides=16)
    finish(bm, "Sheath", col, material("ElecSheath", rgb(140, 60, 235), 0.6, alpha=0.15))


def build_nature(col):
    """Three thorned vines braiding around a living green core, sprouting leaves and blossoms."""
    rng = random.Random(44)
    steps = 140

    bm = bmesh.new()
    pts = [axis_point(LENGTH * i / steps, (0.05 * n3(Vector((0, i / 9, 0))), 0.05 * n3(Vector((3, i / 9, 0))))) for i in range(steps + 1)]
    tube(bm, pts, [0.2] * steps + [0.0], sides=10)
    finish(bm, "Core", col, material("NatureCore", rgb(140, 255, 120), 4))

    bm = bmesh.new()
    vines = []
    for k in range(3):
        phase = 2 * math.pi * k / 3
        path = helix(0, LENGTH, steps, lambda t, k=k: 0.42 + 0.14 * math.sin(t * 2 * math.pi * 4 + k * 2.1), turns=3.5, phase=phase)
        vines.append(path)
        rads = [0.15 * min(1, (1 - i / steps) * 5) for i in range(steps + 1)]
        rads[-1] = 0
        tube(bm, path, rads, sides=8)
        for _ in range(12):  # thorns
            i = rng.randrange(5, steps - 5)
            p = path[i]
            out = Vector((p.x, 0, p.z)).normalized()
            d = (out + AXIS * 0.5).normalized()
            tube(bm, [p, p + d * 0.35], [0.06, 0], sides=4)
    for _ in range(6):  # curling tendrils
        v = rng.choice(vines)
        i = rng.randrange(10, steps - 20)
        p0 = v[i]
        out = Vector((p0.x, 0, p0.z)).normalized()
        side = out.cross(AXIS)
        curl = []
        for j in range(25):
            t = j / 24
            r = 0.6 * (1 - t) + 0.08
            a = t * 2 * math.pi * 1.6
            curl.append(p0 + out * (0.5 * t + r * math.sin(a) * 0.6) + side * r * (1 - math.cos(a)) * 0.6 + AXIS * t * 0.8)
        tube(bm, curl, [0.05 * (1 - j / 24) + 0.01 for j in range(25)], sides=5)
    finish(bm, "Vines", col, material("NatureVine", rgb(70, 95, 40), rough=0.8))

    bm = bmesh.new()
    for _ in range(42):
        v = rng.choice(vines)
        i = rng.randrange(4, steps - 4)
        p = v[i]
        out = Vector((p.x, 0, p.z)).normalized()
        d = (out * rng.uniform(0.6, 1.2) + AXIS * rng.uniform(0.3, 1.0)).normalized()
        leaf(bm, p, d, AXIS.cross(d).normalized() * rng.choice((-1, 1)) + out * 0.5, rng.uniform(0.6, 1.1), rng.uniform(0.18, 0.3))
    finish(bm, "Leaves", col, material("NatureLeaf", rgb(80, 175, 60), rough=0.6))

    bm = bmesh.new()
    for _ in range(8):
        v = rng.choice(vines)
        p = v[rng.randrange(10, steps - 10)]
        out = Vector((p.x, 0, p.z)).normalized()
        side = out.cross(AXIS).normalized()
        up = side.cross(out)
        for j in range(5):
            a = 2 * math.pi * j / 5
            d = (side * math.cos(a) + up * math.sin(a)).normalized()
            leaf(bm, p + out * 0.12, (d + out * 0.6).normalized(), out, 0.32, 0.14, curl=0.4, thick=0.02)
        rock(bm, rng, p + out * 0.15, 0.08, jitter=0.1)
    finish(bm, "Blossoms", col, material("NatureBloom", rgb(255, 150, 205), 0.4, rough=0.5))


def build_void(col):
    """A light-eating black core with a violet event horizon, tendrils spiralling in, debris caught in orbit."""
    rng = random.Random(55)
    steps = 120

    def wobble(i):
        p = axis_point(LENGTH * i / steps)
        return 0.5 + 0.12 * n3(p * 0.5, 2) + 0.06 * math.sin(i / steps * 2 * math.pi * 7)

    pts = [axis_point(LENGTH * i / steps) for i in range(steps + 1)]
    bm = bmesh.new()
    tube(bm, pts, [wobble(i) for i in range(steps)] + [0], sides=16)
    finish(bm, "Core", col, material("VoidCore", rgb(8, 4, 14), rough=1.0))

    bm = bmesh.new()
    tube(bm, pts, [wobble(i) * 1.32 for i in range(steps)] + [0], sides=16)
    finish(bm, "Horizon", col, material("VoidHorizon", rgb(140, 60, 255), 0.5, alpha=0.1))

    bm = bmesh.new()
    for k in range(9):
        y0 = 0.5 + k * (LENGTH - 6) / 8
        phase = rng.uniform(0, 2 * math.pi)
        # spirals inward and forward, like matter being swallowed
        path = helix(y0, y0 + 5, 40, lambda t: 2.3 * (1 - t) ** 1.4 + 0.45, turns=1.2, phase=phase)
        tube(bm, path, [0.03 + 0.14 * math.sin(math.pi * min(i / 40 * 1.5, 1)) * (1 - i / 40) for i in range(40)] + [0], sides=6)
    finish(bm, "Tendrils", col, material("VoidTendril", rgb(95, 20, 190), 3))

    bm = bmesh.new()
    for k in range(4):
        y = 3 + k * 6
        tilt = Matrix.Rotation(math.radians(rng.uniform(-18, 18)), 4, "X") @ Matrix.Rotation(math.radians(rng.uniform(-18, 18)), 4, "Z")
        ring = [axis_point(y) + (tilt.to_3x3() @ Vector((math.cos(a), 0, math.sin(a)))) * 1.5 for a in (2 * math.pi * j / 40 for j in range(40))]
        sweep(bm, ring, [[(0.07, 0), (0, 0.025), (-0.07, 0), (0, -0.025)]] * 40, closed=True)
    finish(bm, "Rings", col, material("VoidRing", rgb(190, 120, 255), 3))

    bm = bmesh.new()
    for _ in range(45):
        t = rng.random()
        a = t * 2 * math.pi * 5 + rng.uniform(-0.4, 0.4)
        r = rng.uniform(0.9, 2.2)
        rock(bm, rng, Vector((r * math.cos(a), t * LENGTH, r * math.sin(a))), rng.uniform(0.07, 0.2), squash=(1, 1.8, 1))
    finish(bm, "Debris", col, material("VoidDebris", rgb(25, 15, 40), rough=0.9), smooth=False)


def build_rift(col):
    """A fracture through space: a faceted star-shaped crystal core caged by angular crack lines,
    with solid glass shards and cracked hex gates around it."""
    rng = random.Random(66)
    steps = 72
    points = 6
    pts = [axis_point(LENGTH * i / steps) for i in range(steps + 1)]
    spikes = [[rng.uniform(0.75, 1.15) for _ in range(points)] for _ in pts]

    def star(i, scale):
        """Irregular six-point star cross-section, slowly turning down the beam so it reads as solid."""
        t = i / steps
        taper = min(1.0, t * 10, (1 - t) * 10) * 0.6 + 0.4 * min(1.0, t * 10, (1 - t) * 10) ** 2
        turn = t * math.pi * 1.5
        pulse = 1 + 0.2 * n3(pts[i] * 0.3, 7)
        prof = []
        for k in range(points):
            a = turn + 2 * math.pi * k / points
            outer = 0.62 * spikes[i][k] * pulse * scale * taper + 0.02
            inner = 0.24 * pulse * scale * taper + 0.02
            prof.append((outer * math.cos(a), outer * math.sin(a)))
            b = a + math.pi / points
            prof.append((inner * math.cos(b), inner * math.sin(b)))
        return prof

    bm = bmesh.new()
    sweep(bm, pts, [star(i, 1.0) for i in range(steps + 1)])
    finish(bm, "Tear", col, material("RiftCrystal", rgb(170, 245, 250), 0.8, glass=True), smooth=False)

    bm = bmesh.new()  # the glowing fault line running through the crystal
    line = jagged(axis_point(0), axis_point(LENGTH), 5, 0.01, random.Random(67))
    tube(bm, line, [0.14] * (len(line) - 1) + [0.0], sides=6)
    finish(bm, "Core", col, material("RiftCore", rgb(220, 255, 255), 8), smooth=False)

    def cracks(bm, direction, seed):
        crng = random.Random(seed)
        for k in range(3):
            phase = 2 * math.pi * k / 3 + crng.uniform(-0.3, 0.3)
            path = []
            for i in range(19):  # few, long, straight segments: geometric cracks, not lightning
                t = i / 18
                a = phase + direction * t * 2 * math.pi * 1.5
                r = 0.95 + crng.uniform(-0.18, 0.18)
                path.append(Vector((r * math.cos(a), t * LENGTH, r * math.sin(a))))
            sq = [(0.055, 0.055), (-0.055, 0.055), (-0.055, -0.055), (0.055, -0.055)]
            for p, q in zip(path, path[1:]):
                sweep(bm, [p, q], [sq, sq])

    bm = bmesh.new()
    cracks(bm, 1, 61)
    # Still named EdgeMagenta (cyan, like EdgeCyan) so the style table and older imports keep matching.
    finish(bm, "EdgeMagenta", col, material("RiftCyan", rgb(40, 220, 230), 3.5), smooth=False)

    bm = bmesh.new()
    cracks(bm, -1, 62)
    finish(bm, "EdgeCyan", col, material("RiftCyan", rgb(40, 220, 230), 3.5), smooth=False)

    bm = bmesh.new()
    for _ in range(46):
        y = rng.uniform(0.5, LENGTH - 0.5)
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(1.25, 2.3)
        base = Vector((r * math.cos(a), y, r * math.sin(a)))
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized()
        size = rng.uniform(0.35, 0.8)
        crystal(bm, base - d * size / 2, base + d * size / 2, size * rng.uniform(0.25, 0.4), rng.choice((3, 4)), rng.uniform(0, 1))
    finish(bm, "Fragments", col, material("RiftGlass", rgb(190, 245, 245), 0.5, glass=True), smooth=False)

    bm = bmesh.new()
    for k, y in enumerate((3.5, 9.5, 15.5, 21.5)):
        spin = k * 0.5
        tilt = Matrix.Rotation(math.radians(rng.uniform(-12, 12)), 3, "X") @ Matrix.Rotation(math.radians(rng.uniform(-12, 12)), 3, "Z")
        corners = [axis_point(y) + tilt @ (Vector((math.cos(spin + j * math.pi / 3), 0, math.sin(spin + j * math.pi / 3))) * 1.75) for j in range(6)]
        for j in range(6):
            if rng.random() < 0.25:
                continue  # broken segments: the gate is cracking apart
            a, b = corners[j], corners[(j + 1) % 6]
            gap = (b - a) * 0.08
            sq = [(0.1, 0.1), (-0.1, 0.1), (-0.1, -0.1), (0.1, -0.1)]
            sweep(bm, [a + gap, b - gap], [sq, sq])
    finish(bm, "Gates", col, material("RiftGate", rgb(30, 200, 200), 3), smooth=False)


def build_wind(col):
    """Air made visible: airflow streaks spiralling round a twisted core, shockwave rings and crescent wind blades."""
    rng = random.Random(77)

    def radial(a):
        return Vector((math.cos(a), 0, math.sin(a)))

    bm = bmesh.new()
    for k in range(3):  # a tight three-strand twist, like a wrung-out rope of air
        path = helix(0, LENGTH, 160, lambda t: 0.12, turns=9, phase=2 * math.pi * k / 3)
        tube(bm, path, [0.1] * 160 + [0], sides=6)
    finish(bm, "Core", col, material("WindCore", rgb(235, 255, 248), 2.5))

    bm = bmesh.new()
    for k in range(9):
        inner = k < 3
        y0 = 0 if inner else rng.uniform(0, LENGTH - 9)
        y1 = LENGTH if inner else min(LENGTH, y0 + rng.uniform(7, 14))
        r_base = 0.38 if inner else rng.uniform(0.6, 1.5)
        turns = (y1 - y0) / (4 if inner else rng.uniform(6, 9))
        phase = rng.uniform(0, 2 * math.pi)
        steps = 70
        rings = []
        for i in range(steps + 1):
            t = i / steps
            a = phase + 2 * math.pi * turns * t
            r = r_base * (1 + 0.15 * math.sin(t * math.pi * 3))
            c = radial(a) * r + AXIS * (y0 + (y1 - y0) * t)
            around = Vector((-math.sin(a), 0, math.cos(a)))  # flat side of the streak hugs the cylinder
            w = (0.09 if inner else 0.2) * math.sin(math.pi * t) ** 0.8
            rings.append([c + around * w, c + radial(a) * 0.025, c - around * w, c - radial(a) * 0.025])
        loft(bm, rings)
    finish(bm, "Streams", col, material("WindStream", rgb(160, 240, 215), 1.0))

    bm = bmesh.new()
    for k, y in enumerate((3.5, 9.5, 15.5, 21.5)):
        r = 1.0 + 0.12 * k
        # cross-section: a thin cone shell, sharp at the front, flaring and thinning towards the back
        section = [(r, 0.0), (r + 0.12, -0.35), (r + 0.45, -1.0), (r + 0.06, -0.3)]
        tilt = Matrix.Rotation(math.radians(rng.uniform(-6, 6)), 3, "X")
        rings = []
        for j in range(48):
            a = 2 * math.pi * j / 48
            rings.append([axis_point(y) + tilt @ (radial(a) * rr + AXIS * ay) for rr, ay in section])
        loft(bm, rings, closed=True)
    finish(bm, "Rings", col, material("WindRing", rgb(150, 235, 215), 0.5, alpha=0.3))

    bm = bmesh.new()
    for _ in range(7):
        y = rng.uniform(2, LENGTH - 2)
        r = rng.uniform(1.1, 1.8)
        start = rng.uniform(0, 2 * math.pi)
        span = math.radians(rng.uniform(150, 230))
        lean = rng.uniform(1.0, 2.2)  # the blade sweeps forward as it curls round
        steps = 40
        rings = []
        for i in range(steps + 1):
            u = i / steps
            a = start + span * u
            c = radial(a) * r * (1 - 0.15 * u) + AXIS * (y + lean * u)
            w = 0.38 * math.sin(math.pi * u) ** 0.6
            th = 0.05 * math.sin(math.pi * u) ** 0.6 + 0.005
            rings.append([c + AXIS * w, c + radial(a) * th, c - AXIS * w * 0.35, c - radial(a) * th])
        loft(bm, rings)
    finish(bm, "Blades", col, material("WindBlade", rgb(215, 255, 240), 1.5))


BEAMS = {
    "Fire": build_fire,
    "Ice": build_ice,
    "Electric": build_electric,
    "Nature": build_nature,
    "Void": build_void,
    "Rift": build_rift,
    "Wind": build_wind,
}


# ---------------------------------------------------------------- export / preview


def export(col, path):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in col.objects:
        obj.select_set(True)
    bpy.ops.export_scene.fbx(
        filepath=str(path),
        use_selection=True,
        object_types={"MESH"},
        mesh_smooth_type="FACE",
        apply_scale_options="FBX_SCALE_ALL",
        bake_space_transform=True,
        path_mode="STRIP",
    )


def render(element, path, camera=(17.0, 7.0, 6.0), target=(0, 12.0, 0)):
    scene = bpy.context.scene
    for col in bpy.data.collections:
        hidden = col.name != element
        for obj in col.objects:
            obj.hide_render = hidden or obj.name.startswith(("Start", "End", "Top"))
    cam = scene.camera
    cam.location = camera
    direction = Vector(target) - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def setup_render_scene():
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 640
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.quality = 88
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("World")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.012, 0.014, 0.02, 1)
    scene.world = world
    cam_data = bpy.data.cameras.new("Camera")
    cam_data.lens = 30
    cam = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    key = bpy.data.lights.new("Key", "AREA")
    key.energy = 900
    key.size = 12
    light = bpy.data.objects.new("Key", key)
    light.location = (6, 12, 10)
    light.rotation_euler = (math.radians(-30), math.radians(25), 0)
    scene.collection.objects.link(light)


def main():
    do_render = "--render" in sys.argv
    bpy.ops.wm.read_factory_settings(use_empty=True)
    OUT.mkdir(exist_ok=True)
    if do_render:
        (OUT / "previews").mkdir(exist_ok=True)
        setup_render_scene()
    for element, build in BEAMS.items():
        print(element)
        col = bpy.data.collections.new(element)
        bpy.context.scene.collection.children.link(col)
        build(col)
        markers(col)
        export(col, OUT / f"{element}Beam.fbx")
    if do_render:
        for element in BEAMS:
            render(element, OUT / "previews" / f"{element}.jpg")
    print(f"Wrote beams to {OUT}")


if __name__ == "__main__":
    main()
