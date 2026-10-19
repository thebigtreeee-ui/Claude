"""Effects for the fight scene: everything is keyframed geometry so Cycles renders it with real light.

Every effect takes its start time in seconds. Positions are world-space Vectors (studs, Z up).
"""
import math
import random

import bpy
import bmesh
from mathutils import Matrix, Vector

import build_element_beams as beams
import build_element_blasts as blasts
import build_element_ultimates as ults
from common import F, _fcurves, collection, empty, glow, key, key_value, mesh_object, rgb, surface, visible

FX = None
_rng = random.Random(77)


def fx_col():
    global FX
    if FX is None:
        FX = collection("FX")
    return FX


def _ico(r=1.0, sub=2):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
    return bm


def _torus(r_major=1.0, r_minor=0.08, seg=48, ring=6):
    bm = bmesh.new()
    rings = []
    for i in range(seg):
        a = 2 * math.pi * i / seg
        c = Vector((math.cos(a), math.sin(a), 0)) * r_major
        n = Vector((math.cos(a), math.sin(a), 0))
        rings.append([bm.verts.new(c + n * math.cos(2 * math.pi * j / ring) * r_minor + Vector((0, 0, math.sin(2 * math.pi * j / ring) * r_minor))) for j in range(ring)])
    for i in range(seg):
        r0, r1 = rings[i], rings[(i + 1) % seg]
        for j in range(ring):
            k = (j + 1) % ring
            bm.faces.new((r0[j], r1[j], r1[k], r0[k]))
    return bm


def _disc_ring(inner=0.8, outer=1.0, seg=64):
    bm = bmesh.new()
    a_in = [bm.verts.new((math.cos(2 * math.pi * i / seg) * inner, math.sin(2 * math.pi * i / seg) * inner, 0)) for i in range(seg)]
    a_out = [bm.verts.new((math.cos(2 * math.pi * i / seg) * outer, math.sin(2 * math.pi * i / seg) * outer, 0)) for i in range(seg)]
    for i in range(seg):
        j = (i + 1) % seg
        bm.faces.new((a_in[i], a_out[i], a_out[j], a_in[j]))
    return bm


def _fade(mat, t0, t_peak, t_end, peak=1.0):
    _k(mat, "Fade", t0 - 1 / 30, 0.0)
    _k(mat, "Fade", t_peak, peak)
    _k(mat, "Fade", t_end, 0.0)


def _k(mat, node, t, v):
    key_value(mat, node, F(t), v)


def _light(name, pos, color, energy_keys, radius=0.5):
    li = bpy.data.lights.new(name, "POINT")
    li.color = color
    li.shadow_soft_size = radius
    o = bpy.data.objects.new(name, li)
    fx_col().objects.link(o)
    o.location = pos
    for t, e in energy_keys:
        li.energy = e
        li.keyframe_insert("energy", frame=F(t))
    return o


# ---------------------------------------------------------------- bursts


def flash(t, pos, color, size=2.0, dur=0.25, light=2000, soft=2.5):
    mat = glow("FlashMat", color, strength=30, soft=soft)
    o = mesh_object("Flash", _ico(1.0, 3), fx_col(), mat, smooth=True)
    key(o, F(t - 1 / 30), loc=pos, scale=0.01)
    key(o, F(t), scale=size * 0.7)
    key(o, F(t + dur), scale=size * 1.1)
    _fade(mat, t, t, t + dur)
    visible(o, F(t), F(t + dur) + 1)
    if light:
        _light("FlashLight", pos, color, [(t - 1 / 30, 0), (t, light), (t + dur * 1.5, 0)], radius=1.0)
    return o


def shockwave(t, pos, color, r0=0.5, r1=10.0, dur=0.5, normal=(0, 0, 1), thick=0.12, strength=12):
    mat = glow("ShockMat", color, strength=strength)
    o = mesh_object("Shock", _disc_ring(0.86, 1.0), fx_col(), mat)
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector(normal).to_track_quat("Z", "Y")
    o.location = pos
    o.scale = (r0, r0, 1)
    o.keyframe_insert("scale", frame=F(t))
    o.scale = (r1, r1, 1)
    o.keyframe_insert("scale", frame=F(t + dur))
    for fc in _fcurves(o.animation_data.action):
        for kp in fc.keyframe_points:
            kp.interpolation = "QUAD"
            kp.easing = "EASE_OUT"
    _fade(mat, t, t + dur * 0.15, t + dur)
    visible(o, F(t), F(t + dur) + 1)
    return o


def sparks(t, pos, direction, color, count=18, speed=14.0, spread=0.9, dur=0.35, length=0.9, seed=0):
    rng = random.Random(seed)
    mat = glow("SparkMat", color, strength=30)
    d0 = Vector(direction).normalized() if Vector(direction).length > 0 else Vector((0, 0, 1))
    for i in range(count):
        d = (d0 + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * spread).normalized()
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=4, radius1=0.05, radius2=0.0, depth=length * rng.uniform(0.6, 1.3))
        o = mesh_object("Spark", bm, fx_col(), mat)
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = d.to_track_quat("Z", "Y")
        s = speed * rng.uniform(0.5, 1.2)
        life = dur * rng.uniform(0.6, 1.0)
        key(o, F(t), loc=Vector(pos), scale=1.0, interp="LINEAR")
        key(o, F(t + life * 0.5), loc=Vector(pos) + d * s * life * 0.7, interp="LINEAR")
        key(o, F(t + life), loc=Vector(pos) + d * s * life + Vector((0, 0, -2 * life)), scale=0.05, interp="LINEAR")
        visible(o, F(t), F(t + life) + 1)
    _fade(mat, t, t, t + dur)


def dust(t, pos, count=10, radius=3.0, rise=1.5, dur=1.4, size=(0.8, 1.8), color=rgb(80, 72, 70), seed=0, ring=True):
    """Lit smoke puffs that billow outward and fade."""
    rng = random.Random(seed)
    mat = bpy.data.materials.new("DustMat")
    mat.use_nodes = True
    nt = mat.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = 1.0
    # soft puffs: opacity falls off towards the silhouette, times an animated overall opacity
    val = nt.nodes.new("ShaderNodeValue")
    val.name = "Fade"
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    inv = nt.nodes.new("ShaderNodeMath")
    inv.operation = "SUBTRACT"
    inv.inputs[0].default_value = 1.0
    nt.links.new(lw.outputs["Facing"], inv.inputs[1])
    pw = nt.nodes.new("ShaderNodeMath")
    pw.operation = "POWER"
    pw.inputs[1].default_value = 1.8
    nt.links.new(inv.outputs[0], pw.inputs[0])
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    nt.links.new(val.outputs[0], mul.inputs[0])
    nt.links.new(pw.outputs[0], mul.inputs[1])
    nt.links.new(mul.outputs[0], b.inputs["Alpha"])
    for tt, v in ((t - 1 / 30, 0.0), (t, 0.85), (t + dur * 0.4, 0.65), (t + dur, 0.0)):
        _k(mat, "Fade", tt, v)
    for i in range(count):
        ang = 2 * math.pi * i / count + rng.uniform(-0.3, 0.3)
        out = Vector((math.cos(ang), math.sin(ang), 0)) if ring else Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(0, 1))).normalized()
        bm = _ico(1.0, 2)
        for v in bm.verts:
            v.co *= 1 + 0.25 * beams.n3(v.co * 1.7, i)
        o = mesh_object("Dust", bm, fx_col(), mat, smooth=True)
        s0, s1 = size[0] * rng.uniform(0.7, 1.2), size[1] * rng.uniform(0.8, 1.3)
        p0 = Vector(pos) + out * 0.5 + Vector((0, 0, s0 * 0.4))
        p1 = Vector(pos) + out * radius * rng.uniform(0.7, 1.2) + Vector((0, 0, rise * rng.uniform(0.6, 1.3) + s1 * 0.4))
        key(o, F(t), loc=p0, scale=s0, rot=(rng.uniform(0, 360), rng.uniform(0, 360), 0))
        key(o, F(t + dur), loc=p1, scale=s1, rot=(rng.uniform(0, 360), rng.uniform(0, 360), rng.uniform(0, 360)))
        visible(o, F(t), F(t + dur) + 1)


def debris(t, pos, count=14, speed=(6, 14), up=(0.6, 1.2), dur=1.4, size=(0.15, 0.45), seed=0, color=rgb(60, 54, 58), direction=None):
    """Rock chunks thrown out ballistically, bouncing to rest."""
    rng = random.Random(seed)
    mat = surface("DebrisMat", color, rough=0.9)
    g = 30.0
    for i in range(count):
        bm = bmesh.new()
        beams.rock(bm, rng, Vector(), rng.uniform(*size))
        o = mesh_object("Debris", bm, fx_col(), mat)
        ang = rng.uniform(0, 2 * math.pi)
        if direction is not None:
            d = (Vector(direction).normalized() + Vector((rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), 0))).normalized()
        else:
            d = Vector((math.cos(ang), math.sin(ang), 0))
        s = rng.uniform(*speed)
        vz = s * rng.uniform(*up)
        p = Vector(pos) + Vector((0, 0, 0.2))
        v = d * s + Vector((0, 0, vz))
        spin = Vector((rng.uniform(-900, 900), rng.uniform(-900, 900), rng.uniform(-900, 900)))
        steps = int(dur * 15)
        for k in range(steps + 1):
            tt = t + k / 15
            key(o, F(tt), loc=p.copy(), rot=tuple(spin * (k / 15)), interp="LINEAR")
            v.z -= g / 15
            p += v / 15
            if p.z < 0.15:
                p.z = 0.15
                v.z = -v.z * 0.3
                v.xy *= 0.5
                spin *= 0.5
        visible(o, F(t), F(t + dur + 0.6))


def cracks(t, pos, color, count=8, reach=(4, 8), dur=2.0, seed=0):
    """Glowing cracks spreading across the ground from an impact."""
    rng = random.Random(seed)
    mat = glow("CrackMat", color, strength=8)
    bm = bmesh.new()
    for k in range(count):
        a = 2 * math.pi * k / count + rng.uniform(-0.3, 0.3)
        p = Vector(pos) + Vector((0, 0, 0.03))
        r = rng.uniform(*reach)
        steps = 6
        for i in range(steps):
            a += rng.uniform(-0.5, 0.5)
            q = p + Vector((math.cos(a), math.sin(a), 0)) * r / steps
            w = 0.09 * (1 - i / steps) + 0.02
            d = (q - p).normalized()
            side = Vector((-d.y, d.x, 0)) * w
            vs = [bm.verts.new(p - side), bm.verts.new(p + side), bm.verts.new(q + side * 0.7), bm.verts.new(q - side * 0.7)]
            bm.faces.new(vs)
            p = q
    o = mesh_object("Cracks", bm, fx_col(), mat)
    o.data.transform(Matrix.Translation(-Vector(pos)))  # scale about the impact point
    key(o, F(t), loc=Vector(pos), scale=0.15)
    key(o, F(t + 0.2), scale=1.0)
    _k(mat, "Fade", t - 1 / 30, 0.0)
    _k(mat, "Fade", t, 1.0)
    _k(mat, "Fade", t + dur * 0.5, 0.8)
    _k(mat, "Fade", t + dur, 0.0)
    visible(o, F(t), F(t + dur) + 1)


# ---------------------------------------------------------------- characters


def afterimage(fighter, t, color, life=0.18, strength=1.6):
    """A glowing ghost copy of the fighter frozen at time t, fading out."""
    scn = bpy.context.scene
    scn.frame_set(F(t))
    mat = glow("GhostMat", color, strength=strength)
    for part in fighter.parts:
        g = bpy.data.objects.new("Ghost", part.data)
        g.matrix_world = part.matrix_world.copy()
        fx_col().objects.link(g)
        if len(g.material_slots):
            # object-level material only: the mesh (shared with the fighter) keeps its own material
            g.material_slots[0].link = "OBJECT"
            g.material_slots[0].material = mat
        visible(g, F(t), F(t + life) + 1)
    _k(mat, "Fade", t, 0.22)
    _k(mat, "Fade", t + life, 0.0)


def aura(fighter, name, color, t0, t1, height=6.0, count=7, strength=6.0, dark=False, seed=0):
    """Flame-like ribbons rising and spiralling round the fighter, following it."""
    rng = random.Random(seed)
    mat = glow(f"{name}Mat", color, strength=strength)
    root = empty(f"{name}Root", fx_col(), fighter.joints["Root"])
    objs = []
    for k in range(count):
        bm = bmesh.new()
        phase = 2 * math.pi * k / count + rng.uniform(-0.3, 0.3)
        tall = height * rng.uniform(0.7, 1.1)
        curl = rng.uniform(1.6, 2.6)
        pts, radii = [], []
        for i in range(33):
            u = i / 32
            r = 1.6 + 0.35 * math.sin(u * math.pi) - 0.7 * u
            a = phase + u * curl
            pts.append(Vector((math.cos(a) * r, math.sin(a) * r, 0.2 + u * tall)))
            radii.append(0.2 * math.sin(math.pi * min(1, u * 1.4)) * (1 - u) ** 1.2 + 0.01)
        beams.tube(bm, pts, radii[:-1] + [0], sides=5)
        o = mesh_object(f"{name}Wisp", bm, fx_col(), mat, smooth=True, parent=root)
        objs.append(o)
    # rotate the whole aura continuously and pulse it
    for i, tt in enumerate([t0 + j * 0.25 for j in range(int((t1 - t0) / 0.25) + 2)]):
        key(root, F(tt), rot=(0, 0, i * 40 * (1 if seed % 2 == 0 else -1)), scale=(1 + 0.08 * math.sin(i * 1.7), 1 + 0.08 * math.sin(i * 1.7), 1 + 0.15 * math.sin(i * 2.3)), interp="LINEAR")
    _k(mat, "Fade", t0 - 1 / 30, 0.0)
    _k(mat, "Fade", t0 + 0.3, 1.0)
    _k(mat, "Fade", t1 - 0.3, 1.0)
    _k(mat, "Fade", t1, 0.0)
    for o in objs:
        visible(o, F(t0), F(t1) + 1)
    return root, mat


def charge_orb(t0, t1, follow, color, size=0.9, seed=0):
    """Energy gathering into a point between the hands: a growing orb with streaks rushing inward."""
    rng = random.Random(seed)
    mat = glow("OrbMat", color, strength=18, soft=1.5)
    core = mesh_object("Orb", _ico(1.0, 3), fx_col(), mat, smooth=True, parent=follow)
    key(core, F(t0), loc=(0, 0, 0), scale=0.05)
    key(core, F(t1), scale=size)
    visible(core, F(t0), F(t1) + 1)
    smat = glow("OrbStreakMat", color, strength=20)
    n = int((t1 - t0) * 30)
    for i in range(n):
        tt = t0 + i / 30
        d = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized()
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, segments=4, radius1=0.04, radius2=0.0, depth=1.2)
        o = mesh_object("OrbStreak", bm, fx_col(), smat, parent=follow)
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = (-d).to_track_quat("Z", "Y")
        key(o, F(tt), loc=d * 3.5, interp="LINEAR")
        key(o, F(tt + 0.2), loc=d * 0.3, interp="LINEAR")
        visible(o, F(tt), F(tt + 0.2) + 1)
    _k(smat, "Fade", t0, 1.0)
    _k(smat, "Fade", t1, 1.0)
    return core, mat


def smoke_vanish(t, pos, color, seed=0, dur=0.6):
    """Void's dodge: the body bursts into dark smoke with violet edges."""
    dust(t, pos + Vector((0, 0, 2.0)), count=9, radius=1.8, rise=1.2, dur=dur, size=(0.9, 1.6), color=rgb(14, 10, 20), seed=seed, ring=False)
    sparks(t, pos + Vector((0, 0, 2.5)), (0, 0, 1), color, count=14, speed=6, spread=1.4, dur=dur * 0.8, seed=seed + 1)


# ---------------------------------------------------------------- element models (built by the original builders)


def element(builder, name):
    """Builds an element model with its original builder into its own collection, parented to an empty."""
    col = collection(name, fx_col())
    builder(col)
    root = empty(f"{name}Root", fx_col())
    for o in list(col.objects):
        if o.name.startswith(("Start", "End", "Top")) or o.hide_render:
            bpy.data.objects.remove(o)
            continue
        o.parent = root
    return root, col


def instance(src_col, name):
    """A linked duplicate of an element model (shares meshes)."""
    root = empty(f"{name}Root", fx_col())
    for o in src_col.objects:
        c = o.copy()
        fx_col().objects.link(c)
        c.parent = root
    return root


def aim(root, frame, start, end, length_model=beams.LENGTH, width=1.0, interp="LINEAR"):
    """Points a +Y-modelled beam from start to end at a frame, stretching it to the distance."""
    d = Vector(end) - Vector(start)
    length = max(d.length, 0.01)
    root.rotation_mode = "QUATERNION"
    root.location = start
    root.rotation_quaternion = d.normalized().to_track_quat("Y", "Z")
    root.scale = (width, length / length_model, width)
    root.keyframe_insert("location", frame=frame)
    root.keyframe_insert("rotation_quaternion", frame=frame)
    root.keyframe_insert("scale", frame=frame)


def show(root, f_on, f_off=None):
    for o in [root] + list(root.children):
        if o.type == "MESH":
            visible(o, f_on, f_off)


def jag_bolt(t, a, b, color, width=0.08, dur=0.12, seed=0):
    """A single lightning-like arc (used for crackles in the clash)."""
    rng = random.Random(seed)
    pts = beams.jagged(Vector(a), Vector(b), 4, 0.18, rng)
    bm = bmesh.new()
    beams.tube(bm, pts, [width] * (len(pts) - 1) + [0.0], sides=4)
    mat = glow("ArcMat", color, strength=25)
    o = mesh_object("Arc", bm, fx_col(), mat)
    visible(o, F(t), F(t + dur) + 1)
    return o


def float_rocks(t0, t1, center, count=10, radius=(2.5, 5.0), height=(1.5, 4.0), blow=None, seed=0, color=rgb(60, 54, 58)):
    """Rocks tearing loose and floating up while power gathers; optionally blown outward at `blow` (time)."""
    rng = random.Random(seed)
    mat = surface("FloatRockMat", color, rough=0.9)
    for i in range(count):
        bm = bmesh.new()
        beams.rock(bm, rng, Vector(), rng.uniform(0.15, 0.4))
        o = mesh_object("FloatRock", bm, fx_col(), mat)
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(*radius)
        base = Vector(center) + Vector((math.cos(a) * r, math.sin(a) * r, 0.15))
        start = t0 + rng.uniform(0, (t1 - t0) * 0.5)
        top = base + Vector((0, 0, rng.uniform(*height)))
        spin = (rng.uniform(-200, 200), rng.uniform(-200, 200), rng.uniform(-200, 200))
        key(o, F(start), loc=base, rot=(0, 0, 0))
        end = blow if blow else t1
        key(o, F(end), loc=top, rot=spin)
        last = end
        if blow:
            out = (base - Vector(center)).normalized()
            key(o, F(blow + 0.5), loc=top + out * rng.uniform(8, 14) + Vector((0, 0, rng.uniform(1, 3))), rot=tuple(s * 3 for s in spin))
            last = blow + 0.5
        visible(o, F(start), F(last) + 1)


def suck(t0, dur, start, hole, seed=0, size=(0.2, 0.55), color=rgb(55, 48, 60)):
    """A rock spiralling up into the black hole and vanishing into it."""
    rng = random.Random(seed)
    mat = surface("SuckRockMat", color, rough=0.9)
    bm = bmesh.new()
    beams.rock(bm, rng, Vector(), rng.uniform(*size))
    o = mesh_object("SuckRock", bm, fx_col(), mat)
    rel = Vector(start) - Vector(hole)
    r0 = Vector((rel.x, rel.y, 0)).length
    a0 = math.atan2(rel.y, rel.x)
    turns = rng.uniform(0.8, 1.6)
    steps = max(4, int(dur * 15))
    for k in range(steps + 1):
        u = k / steps
        e = u ** 1.6
        a = a0 + turns * 2 * math.pi * e
        r = r0 * (1 - e)
        z = rel.z * (1 - e)
        p = Vector(hole) + Vector((math.cos(a) * r, math.sin(a) * r, z))
        key(o, F(t0 + dur * u), loc=p, rot=(k * 40, k * 25, k * 15), scale=1.0 if u < 0.8 else max(0.05, (1 - u) * 5), interp="LINEAR")
    visible(o, F(t0), F(t0 + dur) + 1)
