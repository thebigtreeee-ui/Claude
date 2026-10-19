"""The Void vs Rift fight: choreography, effects timing and camera shots.

    build()  -> constructs the whole animated scene and returns the post-processing cues

Layout: Void (V) starts on the left (x < 0) facing +X, Rift (R) on the right facing -X. Midway through the
melee they swap sides. Times are in seconds.
"""
import json
import math
import random

import bpy
from mathutils import Vector

import build_element_beams as beams
import build_element_blasts as blasts
import build_element_ultimates as ults
import fx
import scene
from avatar import Fighter
from common import F, FPS, collection, empty, ease, glow, key, key_value, lerp, rgb, visible

VOID_LOOK = dict(skin=rgb(235, 200, 170), shirt=rgb(18, 16, 22), pants=rgb(40, 36, 48), shoes=rgb(14, 12, 16),
                 hair=rgb(20, 18, 26), glow=rgb(150, 70, 255), eye=rgb(190, 120, 255), hair_style="spiky")
RIFT_LOOK = dict(skin=rgb(200, 150, 115), shirt=rgb(225, 232, 238), pants=rgb(30, 42, 64), shoes=rgb(235, 240, 245),
                 hair=rgb(235, 245, 250), glow=rgb(40, 220, 230), eye=rgb(150, 250, 255), hair_style="swept")
PURPLE = rgb(160, 80, 255)
DEEP = rgb(110, 40, 220)
CYAN = rgb(60, 230, 240)
WHITE = rgb(255, 255, 255)

END = 28.0
LEFT, RIGHT = -90, 90  # yaw: facing +X, facing -X

GUARD = dict(crouch=18, wide=12, lean=6, nod=4, armL=(72, 12, 108), armR=(48, 18, 118))
POWER = dict(crouch=6, wide=14, lean=0, nod=-5, armL=(8, 16, 28), armR=(8, 16, 28))  # standing tall, fists low
POST = {"shake": [], "impact": [], "white": [], "speed": [], "fade": [], "logo": None}

V = R = None
SHOTS = []


def W(obj, t):
    bpy.context.scene.frame_set(F(t))
    return obj.matrix_world.translation.copy()


def shake(t, amp, dur=0.35):
    POST["shake"].append([t, amp, dur])


def impact_frame(t, frames=2):
    POST["impact"].append([t, frames])


def land(attacker, a_marker, defender, d_marker, t, radius, times, axes=(1, 1, 0)):
    """Moves the defender (at the given placement times) so that the attacker's contact marker touches
    the defender's target part at time t (target = part centre pushed `radius` towards the attacker)."""
    a = W(attacker.joints[a_marker], t)
    c = W(defender.joints[d_marker], t)
    towards = a - c
    towards.z = 0 if axes[2] == 0 else towards.z
    target = c + (towards.normalized() * radius if towards.length > 1e-4 else Vector())
    d = a - target
    defender.shift(times, (d.x * axes[0], d.y * axes[1], d.z * axes[2]))
    return a


class Shots:
    """One camera per shot, switched with timeline markers; each camera tracks an animated target."""

    def __init__(self):
        self.col = collection("Cameras")
        self.n = 0

    def add(self, t0, keys, interp="BEZIER"):
        """keys: [(t, cam_pos, target_pos, lens)] — the first key's time is the cut."""
        self.n += 1
        cam_data = bpy.data.cameras.new(f"Shot{self.n}")
        cam_data.sensor_width = 36 * 1.1  # 10% overscan: post-processing crops (and shakes) inside it
        cam_data.clip_start = 0.1
        cam_data.clip_end = 1200
        cam = bpy.data.objects.new(f"Shot{self.n}", cam_data)
        self.col.objects.link(cam)
        tgt = empty(f"Shot{self.n}Target", self.col)
        con = cam.constraints.new("TRACK_TO")
        con.target = tgt
        con.track_axis = "TRACK_NEGATIVE_Z"
        con.up_axis = "UP_Y"
        for t, pos, target, lens in keys:
            cam.location = pos
            cam.keyframe_insert("location", frame=F(t))
            tgt.location = target
            tgt.keyframe_insert("location", frame=F(t))
            cam_data.lens = lens
            cam_data.keyframe_insert("lens", frame=F(t))
        m = bpy.context.scene.timeline_markers.new(f"S{self.n}", frame=F(t0))
        m.camera = cam
        if self.n == 1:
            bpy.context.scene.camera = cam
        return cam


def idle(f, t0, t1, base=GUARD, step=0.7, phase=0):
    """Breathing in the guard stance."""
    t = t0
    i = phase
    while t <= t1 + 1e-6:
        p = dict(base)
        p["crouch"] = base["crouch"] + (2.5 if i % 2 else 0)
        p["lean"] = base["lean"] + (1.5 if i % 2 else 0)
        f.pose(t, **p)
        t += step
        i += 1


# ====================================================================== acts


def act_standoff(shots):
    """0 - 4.4 s: the stand-off, then each fighter's eyes ignite."""
    V.place(0, (-9, 0, 0), LEFT)
    R.place(0, (9, 0, 0), RIGHT)
    idle(V, 0, 4.1, base=POWER)
    idle(R, 0, 4.1, base=POWER, phase=1)
    V.pose(4.3, **GUARD)
    R.pose(4.3, **GUARD)
    V.place(4.4, (-9, 0, 0), LEFT)
    R.place(4.4, (9, 0, 0), RIGHT)
    for f in (V, R):
        f.eyes(0, 0.6)
    V.eyes(2.45, 0.6)
    V.eyes(2.6, 30)
    V.eyes(2.9, 16)
    R.eyes(3.55, 0.6)
    R.eyes(3.7, 30)
    R.eyes(4.0, 16)
    fx.aura(V, "VAuraA", PURPLE, 2.55, 4.7, strength=5, seed=0)
    fx.aura(R, "RAuraA", CYAN, 3.65, 4.7, strength=5, seed=1)
    fx.dust(2.55, Vector((-9, 0, 0)), count=8, radius=3.5, rise=0.6, dur=1.5, size=(0.6, 1.2), seed=11)
    fx.dust(3.65, Vector((9, 0, 0)), count=8, radius=3.5, rise=0.6, dur=1.5, size=(0.6, 1.2), seed=12)

    shots.add(0.0, [(0.0, (0, -23, 2.2), (0, 0, 3.0), 30), (2.2, (0, -18.5, 2.6), (0, 0, 3.2), 30)])
    # anime close-ups: low, slightly off-axis, pushing in on the face as the eyes ignite
    shots.add(2.2, [(2.2, (-4.6, -3.4, 4.2), (-9.1, 0, 4.7), 42), (3.3, (-5.2, -2.9, 4.4), (-9.1, 0, 4.8), 50)])
    shots.add(3.3, [(3.3, (4.6, 3.4, 4.2), (9.1, 0, 4.7), 42), (4.4, (5.2, 2.9, 4.4), (9.1, 0, 4.8), 50)])


def act_clash(shots):
    """4.4 - 5.6 s: both dash in and their fists collide."""
    TI = 5.22
    # anticipation: sink and cock the punching arm
    V.pose(4.45, crouch=30, wide=14, lean=18, twist=-20, armR=(-35, 22, 110), armL=(70, 10, 100))
    R.pose(4.45, crouch=30, wide=14, lean=18, twist=20, armL=(-35, 22, 110), armR=(70, 10, 100))
    V.place(4.6, (-9, 0, 0), LEFT)
    R.place(4.6, (9, 0, 0), RIGHT)
    # the dash: low, fast, body tipped forward, legs trailing
    dash = dict(crouch=8, lift=0.5, lean=36, nod=-20, legL=(-35, 6, -70), legR=(25, 6, -45))
    V.pose(4.75, twist=-25, armR=(-40, 25, 105), armL=(60, 10, 90), **dash)
    R.pose(4.75, twist=25, armL=(-40, 25, 105), armR=(60, 10, 90), **dash)
    V.pose(5.1, twist=-28, armR=(-45, 25, 110), armL=(65, 10, 95), **dash)
    R.pose(5.1, twist=28, armL=(-45, 25, 110), armR=(65, 10, 95), **dash)
    # the punch
    hit = dict(crouch=16, wide=14, lean=12, nod=-6)
    V.pose(TI, twist=30, armR=(90, 0, 0), armL=(60, 10, 115), **hit)
    R.pose(TI, twist=-30, armL=(90, 0, 0), armR=(60, 10, 115), **hit)
    V.pose(5.55, twist=28, armR=(88, 0, 4), armL=(62, 10, 112), **dict(hit, crouch=20))
    R.pose(5.55, twist=-28, armL=(88, 0, 4), armR=(62, 10, 112), **dict(hit, crouch=20))
    # solve the positions so the fists meet exactly at x = 0
    V.place(TI, (0, 0, 0), LEFT)
    R.place(TI, (0, 0, 0), RIGHT)
    fv = W(V.joints["FistR"], TI)
    fr = W(R.joints["FistL"], TI)
    V.shift([TI], (-fv.x, 0, 0))
    R.shift([TI], (-fr.x, fv.y - fr.y, 0))
    xv = V.places[TI][0][0]
    xr = R.places[TI][0][0]
    V.place(5.12, (xv - 1.6, 0, 0), LEFT, interp="LINEAR")
    R.place(5.12, (xr + 1.6, R.places[TI][0][1], 0), RIGHT, interp="LINEAR")
    V.place(5.55, (xv - 0.15, 0, 0), LEFT)
    R.place(5.55, (xr + 0.15, R.places[TI][0][1], 0), RIGHT)
    for t in (4.8, 4.95, 5.1):
        fx.afterimage(V, t, PURPLE)
        fx.afterimage(R, t, CYAN)
    POST["speed"].append([4.62, 5.2, "horizontal"])
    p = W(V.joints["FistR"], TI)
    fx.flash(TI, p, WHITE, size=1.4, dur=0.2, light=6000)
    fx.shockwave(TI, p, PURPLE, 0.3, 5.5, 0.32, normal=(0.33, -0.94, 0), strength=14)
    fx.shockwave(TI + 0.03, p, CYAN, 0.3, 4.5, 0.3, normal=(0.33, -0.94, 0), strength=14)
    fx.shockwave(TI, Vector((p.x, p.y, 0.06)), rgb(200, 190, 255), 1, 15, 0.6, strength=6)
    fx.sparks(TI, p, (0, -1, 0.4), PURPLE, count=16, speed=16, seed=1)
    fx.sparks(TI, p, (0, 1, 0.4), CYAN, count=16, speed=16, seed=2)
    fx.dust(TI, Vector((p.x, p.y, 0)), count=14, radius=7, rise=1.0, dur=1.3, seed=3)
    fx.cracks(TI, Vector((p.x, p.y, 0)), rgb(200, 160, 255), count=10, reach=(4, 8), dur=2.5, seed=4)
    fx.debris(TI, Vector((p.x, p.y, 0)), count=16, seed=5)
    shake(TI, 1.0, 0.5)
    impact_frame(TI, 2)
    shots.add(4.4, [(4.4, (0, -15.5, 2.4), (0, 0, 3.0), 24), (5.22, (0, -13.5, 2.6), (0, 0, 3.2), 24)])
    shots.add(TI, [(TI, (1.6, -4.6, 2.0), (0, p.y, 3.9), 20), (5.6, (1.9, -5.2, 2.0), (0, p.y, 3.9), 20)])
    return xv, xr


def act_exchange(shots, xv, xr):
    """5.6 - 9.6 s: the fast exchange. Ends with the fighters swapped and far apart."""
    yr = R.places[5.22][0][1]
    # E0: pushed apart
    V.place(5.75, (xv - 1.3, 0, 0), LEFT)
    R.place(5.75, (xr + 1.3, yr, 0), RIGHT)
    V.pose(5.75, **GUARD)
    R.pose(5.75, **GUARD)
    fx.dust(5.6, Vector((xv - 0.6, 0, 0)), count=6, radius=1.5, rise=0.3, dur=0.8, size=(0.4, 0.8), seed=21)
    fx.dust(5.6, Vector((xr + 0.6, yr, 0)), count=6, radius=1.5, rise=0.3, dur=0.8, size=(0.4, 0.8), seed=22)

    # E1: Void's straight right into Rift's forearm guard
    T1 = 6.0
    V.pose(5.88, crouch=20, wide=14, lean=14, twist=-15, armR=(-20, 20, 110), armL=(70, 10, 105))
    V.pose(T1, crouch=16, wide=16, lean=14, twist=30, nod=-4, armR=(90, 0, 0), armL=(62, 10, 112))
    R.pose(T1, crouch=22, wide=12, lean=2, nod=8, armR=(78, -18, 128), armL=(55, 12, 110))
    V.place(T1, (xv + 0.4, 0, 0), LEFT)
    R.place(T1, (xr + 1.3, yr, 0), RIGHT)
    land(V, "FistR", R, "ForearmCR", T1, 0.5, [T1])
    p1 = W(V.joints["FistR"], T1)
    xr1, yr1 = R.places[T1][0][0], R.places[T1][0][1]
    R.place(6.18, (xr1 + 0.5, yr1, 0), RIGHT)
    R.pose(6.18, crouch=20, wide=12, lean=-2, nod=10, armR=(74, -15, 125), armL=(55, 12, 110))
    V.place(6.18, V.places[T1][0], LEFT)
    V.pose(6.18, **dict(GUARD, lean=10))
    fx.flash(T1, p1, WHITE, size=1.2, dur=0.15, light=2500)
    fx.sparks(T1, p1, (0, 0, 1), PURPLE, count=12, speed=10, seed=31)
    fx.sparks(T1, p1, (1, 0, 0.3), CYAN, count=10, speed=10, seed=32)
    fx.shockwave(T1, p1, rgb(210, 180, 255), 0.2, 3.5, 0.3, normal=(1, 0, 0), strength=10)
    shake(T1, 0.4, 0.25)
    impact_frame(T1, 1)

    # E2: Rift's spinning hook kick; Void ducks under it
    T2 = 6.5
    xv1 = V.places[T1][0][0]
    R.place(6.28, (xr1 + 0.5, yr1, 0), RIGHT)
    R.pose(6.28, crouch=24, wide=10, lean=8, armL=(40, 30, 90), armR=(30, 40, 90))
    R.place(T2, (xr1 - 0.9, yr1, 0), RIGHT - 300, interp="LINEAR")
    R.pose(T2, crouch=4, lift=0.35, lean=-20, side=-18, armL=(20, 60, 40), armR=(10, 70, 40), legR=(90, 25, -8), legL=(-10, 6, -30))
    R.place(6.66, (xr1 - 0.1, yr1, 0), RIGHT - 360, interp="CONSTANT")
    R.pose(6.66, **GUARD)
    R.place(6.7, (xr1 - 0.1, yr1, 0), RIGHT)  # same facing as -360: switch over while holding
    V.pose(6.38, crouch=44, wide=16, lean=38, nod=-10, armL=(80, 10, 120), armR=(70, 15, 120))
    V.pose(6.6, crouch=44, wide=16, lean=36, nod=-8, armL=(80, 10, 120), armR=(70, 15, 120))
    V.pose(6.72, **GUARD)
    POST["speed"].append([6.32, 6.55, "arc"])
    fx.afterimage(R, 6.42, CYAN, life=0.18)
    fx.afterimage(R, 6.47, CYAN, life=0.18)

    # E3: Rift hops back into a rift and comes out behind Void
    xr2 = xr1 + 1.6
    R.place(6.84, (xr2, yr1, 0), RIGHT)
    R.pose(6.84, crouch=22, wide=10, lean=-6, armL=(40, 25, 80), armR=(40, 25, 80))
    portal_src = fx.element(ults.ult_rift, "Portal")
    portal_a = fx.instance(portal_src[1], "PortalA")
    portal_b = fx.instance(portal_src[1], "PortalB")
    for o in list(portal_src[1].objects):
        o.hide_render = True
    portal(portal_a, Vector((xr2 + 1.2, yr1, 3.6)), -90, 6.7, 6.82, 7.02, 7.18)
    R.pose(7.0, crouch=22, wide=10, lean=-6, armL=(40, 25, 80), armR=(40, 25, 80))
    R.place(7.0, (xr2 + 1.5, yr1, 0), RIGHT)
    R.hide(7.02, 7.17)
    pb = Vector((xv1 - 2.6, 0, 3.8))
    portal(portal_b, pb, 90, 7.05, 7.15, 7.42, 7.58)
    kick = dict(crouch=4, lift=0.9, lean=-15, armL=(40, 40, 60), armR=(-20, 50, 40), legR=(92, 6, -4), legL=(-25, 6, -70))
    R.place(7.17, (pb.x - 0.2, 0, 0.3), LEFT)
    R.pose(7.17, **kick)
    T4 = 7.34
    R.place(T4, (xv1 - 0.6, 0, 0.35), LEFT, interp="LINEAR")
    R.pose(T4, **kick)
    POST["speed"].append([7.17, 7.34, "horizontal"])
    fx.afterimage(R, 7.22, CYAN, life=0.15)
    fx.afterimage(R, 7.28, CYAN, life=0.15)
    # E4: Void bursts into void smoke an instant before the kick lands
    V.place(7.29, (xv1, 0, 0), LEFT)
    V.pose(7.29, **GUARD)
    V.hide(7.3, 7.74)
    fx.smoke_vanish(7.3, Vector((xv1, 0, 0)), PURPLE, seed=41)
    R.place(7.5, (xv1 + 0.9, 0, 0), LEFT)
    R.pose(7.5, crouch=26, wide=12, lean=8, armL=(60, 15, 100), armR=(50, 20, 110))
    xr3 = xv1 + 0.9

    # E5: Void reappears above and drops an axe kick onto Rift's crossed arms
    T5 = 8.1
    above = Vector((xr3 + 3.3, 0, 6.2))
    fx.smoke_vanish(7.72, above - Vector((0, 0, 2.0)), PURPLE, seed=42, dur=0.5)
    V.place(7.74, above, RIGHT)
    V.pose(7.74, crouch=0, lift=0, lean=-10, armL=(60, 40, 60), armR=(40, 50, 60), legR=(150, 4, -5), legL=(10, 6, -60))
    V.place(7.95, above + Vector((-1.2, 0, 0.4)), RIGHT)
    V.pose(7.95, crouch=0, lean=-14, armL=(40, 50, 60), armR=(30, 55, 60), legR=(165, 4, 0), legL=(15, 6, -70))
    V.pose(T5, crouch=0, lean=22, armL=(20, 50, 60), armR=(20, 55, 60), legR=(70, 4, 0), legL=(-20, 6, -60))
    block = dict(crouch=26, wide=14, lean=0, nod=-14, armL=(158, -22, 35), armR=(158, -22, 35))
    R.pose(7.9, **block)
    R.pose(T5, **block)
    R.place(T5, (xr3, 0, 0), LEFT)
    V.place(T5, above + Vector((-1.6, 0, -1.2)), RIGHT)
    # land the heel exactly on top of the crossed forearms
    ftop = (W(R.joints["ForearmCL"], T5) + W(R.joints["ForearmCR"], T5)) / 2 + Vector((0, 0, 0.55))
    toe = W(V.joints["ToeR"], T5)
    V.shift([T5], tuple(ftop - toe))
    p5 = W(V.joints["ToeR"], T5)
    R.pose(8.25, **dict(block, crouch=40, nod=-20))
    R.place(8.25, (xr3, 0, 0), LEFT)
    fx.flash(T5, p5, WHITE, size=1.5, dur=0.2, light=6000)
    fx.shockwave(T5, Vector((xr3, 0, 0.06)), PURPLE, 1.0, 14, 0.6, strength=10)
    fx.shockwave(T5 + 0.05, Vector((xr3, 0, 0.08)), CYAN, 1.0, 10, 0.6, strength=10)
    fx.cracks(T5, Vector((xr3, 0, 0)), rgb(190, 150, 255), count=11, reach=(4, 9), dur=2.4, seed=51)
    fx.dust(T5, Vector((xr3, 0, 0)), count=14, radius=6.5, rise=1.2, dur=1.4, seed=52)
    fx.debris(T5, Vector((xr3, 0, 0)), count=18, seed=53)
    fx.sparks(T5, p5, (1, 0, 0.6), PURPLE, count=14, speed=12, seed=54)
    fx.sparks(T5, p5, (-1, 0, 0.6), CYAN, count=14, speed=12, seed=55)
    shake(T5, 1.1, 0.5)
    impact_frame(T5, 2)
    # Void rebounds off the guard and flips back to land facing Rift
    vb = V.places[T5][0]
    V.place(8.3, (vb[0] + 1.6, 0, vb[2] + 1.2), RIGHT, tilt=(180, 0))
    V.pose(8.3, crouch=0, lean=30, armL=(60, 20, 90), armR=(60, 20, 90), legR=(80, 6, -110), legL=(80, 6, -110))
    V.place(8.45, (xr3 + 4.2, 0, 0), RIGHT, tilt=(360, 0), interp="CONSTANT")
    V.pose(8.45, **dict(GUARD, crouch=30))
    V.place(8.46, (xr3 + 4.2, 0, 0), RIGHT)

    # E6: Rift answers with a burst of broken space that throws them apart
    T6 = 8.6
    R.pose(8.5, crouch=34, wide=14, lean=10, armL=(40, 30, 110), armR=(40, 30, 110))
    R.pose(T6, crouch=14, wide=18, lean=-16, nod=12, armL=(20, 85, 20), armR=(20, 85, 20))
    pr = Vector((xr3, 0, 3.4))
    fx.flash(T6, pr, CYAN, size=2.2, dur=0.3, light=5000)
    fx.shockwave(T6, pr, CYAN, 0.5, 12, 0.5, normal=(0, 1, 0), strength=12)
    fx.shockwave(T6, Vector((xr3, 0, 0.06)), CYAN, 1, 16, 0.6, strength=8)
    fx.sparks(T6, pr, (1, 0, 0.2), CYAN, count=24, speed=18, spread=1.2, seed=61)
    shake(T6, 0.8, 0.45)
    xv_end, xr_end = 11.0, -11.0
    V.pose(T6 + 0.05, crouch=10, lean=-30, nod=20, armL=(60, 50, 60), armR=(60, 50, 60), legL=(40, 6, -60), legR=(20, 6, -40))
    V.place(T6 + 0.05, (xr3 + 4.6, 0, 0.6), RIGHT, tilt=(-25, 0))
    V.place(9.15, (xv_end - 1.8, 0, 0.9), RIGHT, tilt=(-20, 0))
    V.place(9.3, (xv_end - 0.8, 0, 0), RIGHT)
    V.pose(9.3, **dict(GUARD, crouch=34, lean=14))
    V.place(9.6, (xv_end, 0, 0), RIGHT)
    V.pose(9.6, **GUARD)
    fx.dust(9.3, Vector((xv_end - 0.8, 0, 0)), count=8, radius=2.2, rise=0.4, dur=0.9, size=(0.5, 1.0), seed=62)
    R.place(T6 + 0.05, (xr3, 0, 0), LEFT)
    R.place(9.0, (xr_end, 0, 0), LEFT)
    R.pose(9.0, **dict(GUARD, crouch=28))
    R.pose(9.6, **GUARD)
    R.place(9.6, (xr_end, 0, 0), LEFT)
    fx.dust(8.7, Vector((xr3 - 1, 0, 0)), count=7, radius=2.0, rise=0.3, dur=1.0, size=(0.5, 1.0), seed=63)

    # cameras for the exchange
    shots.add(5.6, [(5.6, (xv - 5.6, -4.8, 5.2), (xr + 0.3, 0, 4.0), 34), (6.22, (xv - 5.0, -5.2, 5.0), (xr + 0.3, 0, 3.9), 34)])
    shots.add(6.22, [(6.22, (xv1 + 1.6, -9.5, 2.0), (xv1 + 1.6, 0, 3.0), 28), (6.75, (xv1 + 1.3, -9.0, 2.1), (xv1 + 1.6, 0, 3.0), 28)])
    shots.add(6.75, [(6.75, (0.5, -15, 3.2), (0.5, 0, 3.2), 24), (7.62, (0.0, -13.5, 3.4), (0.0, 0, 3.4), 24)])
    shots.add(7.62, [(7.62, (xr3 + 1.8, -13.5, 1.4), (xr3 + 1.9, 0, 6.4), 18), (8.45, (xr3 + 1.9, -14.0, 1.4), (xr3 + 1.9, 0, 4.8), 18)])
    shots.add(8.45, [(8.45, (0, -22, 5.0), (0, 0, 2.0), 24), (9.6, (0, -24, 5.5), (0, 0, 2.2), 24)])
    return xv_end, xr_end


def portal(root, center, yaw, t_open, t_full, t_close, t_gone, scale=0.6):
    """Opens a vertical rift (the Rift ultimate's tear, scaled down) centred at `center`."""
    C = Vector((0, 10, 6.5))
    rot = __import__("mathutils").Matrix.Rotation(math.radians(yaw), 3, "Z")
    pivot = empty(root.name + "Pivot", fx.fx_col())
    root.parent = pivot
    root.location = -C
    pivot.location = center
    pivot.rotation_euler = (0, 0, math.radians(yaw))
    key(pivot, F(t_open), loc=center, scale=(0.02, 0.02, 0.02))
    key(pivot, F(t_full), scale=(scale, scale, scale))
    key(pivot, F(t_close), scale=(scale, scale, scale))
    key(pivot, F(t_gone), scale=(0.01, 0.01, scale * 0.6))
    for o in root.children:
        visible(o, F(t_open), F(t_gone) + 1)
    fx.flash(t_open + 0.04, center, CYAN, size=1.1, dur=0.2, light=2500)
    return pivot


def build():
    global V, R
    scene.reset()
    scene.world()
    scene.arena()
    scene.lights()
    V = Fighter("V", collection("Void"), VOID_LOOK)
    R = Fighter("R", collection("Rift"), RIFT_LOOK)
    for f in (V, R):
        for s in ("L", "R"):
            f.joints[f"ForearmC{s}"] = empty(f"{f.name}_ForearmC{s}", f.col, f.joints[f"Elbow{s}"], (0, 0, -0.48))
            f.joints[f"ShinC{s}"] = empty(f"{f.name}_ShinC{s}", f.col, f.joints[f"Knee{s}"], (0, 0, -0.5))
        f.joints["HeadC"] = empty(f"{f.name}_HeadC", f.col, f.joints["Neck"], (0, 0, 0.62))
        f.joints["ChestC"] = empty(f"{f.name}_ChestC", f.col, f.joints["Waist"], (0, 0, 0.8))
    shots = Shots()
    SHOTS[:] = [shots]
    act_standoff(shots)
    xv, xr = act_clash(shots)
    act_exchange(shots, xv, xr)
    report()
    return POST


def report():
    """Prints contact distances and the closest approach during the duck, to verify the choreography."""
    d = (W(V.joints["FistR"], 5.22) - W(R.joints["FistL"], 5.22)).length
    print(f"CHECK fist clash gap {d:.3f}")
    worst = 99
    for i in range(0, 13):
        t = 6.38 + i * 0.02
        for leg in ("ToeR", "ShinCR"):
            for part in ("HeadC", "ChestC"):
                worst = min(worst, (W(R.joints[leg], t) - W(V.joints[part], t)).length)
    print(f"CHECK hook kick closest approach to Void head/chest {worst:.3f}")
    print(f"CHECK axe kick toe-to-guard {(W(V.joints['ToeR'], 8.1) - (W(R.joints['ForearmCL'], 8.1) + W(R.joints['ForearmCR'], 8.1)) / 2).length:.3f}")
    # body overlap: distance between torso centres should stay above ~1.6 whenever both are visible on the ground
    tight = min(((W(V.joints["ChestC"], t / 30) - W(R.joints["ChestC"], t / 30)).length, t / 30) for t in range(130, 290))
    print(f"CHECK closest torso centres {tight[0]:.3f} at {tight[1]:.2f}s")


# ====================================================================== second half
# From here Void stands on the right (x = +11, facing -X) and Rift on the left (x = -11, facing +X).


def palm(f):
    """The point between both fists (for blasts / beams fired with both hands)."""
    return f.joints["FistL"], f.joints["FistR"]


def mid(f, t):
    a, b = palm(f)
    return (W(a, t) + W(b, t)) / 2


def act_blasts(shots):
    """9.6 - 12.0 s: a rift blast and a void blast collide and explode between them."""
    xv, xr = 11.0, -11.0
    # wind-up and throw (right palm), facing each other
    R.pose(9.85, crouch=24, wide=16, lean=4, twist=-35, armR=(-20, 30, 110), armL=(70, 10, 100))
    V.pose(9.9, crouch=24, wide=16, lean=4, twist=-35, armR=(-20, 30, 110), armL=(70, 10, 100))
    throw = dict(crouch=20, wide=18, lean=12, twist=32, armR=(90, -4, 0), armL=(40, 25, 95))
    R.pose(10.0, **throw)
    V.pose(10.05, **throw)
    R.pose(10.6, **dict(throw, lean=8))
    V.pose(10.6, **dict(throw, lean=8))
    for f, x, yaw in ((V, xv, RIGHT), (R, xr, LEFT)):
        f.place(9.85, (x, 0, 0), yaw)
        f.place(10.6, (x, 0, 0), yaw)
    sr = W(R.joints["FistR"], 10.0)
    sv = W(V.joints["FistR"], 10.05)
    speed = 26.0
    tm = (sv.x - sr.x + speed * 10.0 + speed * 10.05) / (2 * speed)
    m = Vector((sr.x + speed * (tm - 10.0), 0.0, 3.8))
    rift_root, _ = fx.element(blasts.blast_rift, "RiftBlast")
    void_root, _ = fx.element(blasts.blast_void, "VoidBlast")
    for root, s, t0 in ((rift_root, sr, 10.0), (void_root, sv, 10.05)):
        d = (m - s).normalized()
        root.rotation_mode = "QUATERNION"
        root.rotation_quaternion = d.to_track_quat("Y", "Z")
        root.keyframe_insert("rotation_quaternion", frame=F(t0))
        key(root, F(t0), loc=s, scale=0.15, interp="LINEAR")
        key(root, F(t0 + 0.08), scale=0.85, interp="LINEAR")
        key(root, F(tm), loc=m, scale=0.85, interp="LINEAR")
        fx.show(root, F(t0), F(tm) + 1)
        fx.flash(t0, s, CYAN if root is rift_root else PURPLE, size=0.9, dur=0.15, light=1500)
    POST["speed"].append([10.05, tm, "horizontal"])
    # the collision
    fx.flash(tm, m, WHITE, size=3.0, dur=0.35, light=12000)
    fx.shockwave(tm, m, PURPLE, 0.5, 13, 0.6, normal=(0, 1, 0), strength=14)
    fx.shockwave(tm + 0.05, m, CYAN, 0.5, 10, 0.6, normal=(0, 1, 0), strength=14)
    fx.shockwave(tm, Vector((m.x, 0, 0.06)), rgb(200, 190, 255), 1, 20, 0.8, strength=7)
    fx.dust(tm, Vector((m.x, 0, 0)), count=18, radius=10, rise=2.0, dur=1.8, size=(1.2, 2.8), seed=71)
    fx.debris(tm, Vector((m.x, 0, 0)), count=20, speed=(8, 16), seed=72)
    fx.sparks(tm, m, (0, 0, 1), PURPLE, count=20, speed=18, spread=1.4, seed=73)
    fx.sparks(tm, m, (0, 0, 1), CYAN, count=20, speed=18, spread=1.4, seed=74)
    fx.cracks(tm, Vector((m.x, 0, 0)), rgb(200, 170, 255), count=12, reach=(5, 10), dur=3.0, seed=75)
    shake(tm, 1.3, 0.6)
    impact_frame(tm, 2)
    # brace against the blast wind
    brace = dict(crouch=30, wide=18, lean=18, nod=-12, armL=(95, -30, 120), armR=(95, -30, 120))
    for f in (V, R):
        f.pose(tm + 0.15, **brace)
        f.pose(11.6, **dict(brace, crouch=26))
        f.pose(11.9, **GUARD)
    V.place(tm + 0.15, (xv, 0, 0), RIGHT)
    V.place(11.0, (xv + 0.6, 0, 0), RIGHT)
    R.place(tm + 0.15, (xr, 0, 0), LEFT)
    R.place(11.0, (xr - 0.6, 0, 0), LEFT)
    shots.add(9.6, [(9.6, (xr - 6.5, -4.8, 6.2), (xv, 0, 3.2), 30), (10.15, (xr - 6.0, -5.0, 6.0), (xv, 0, 3.2), 30)])
    shots.add(10.15, [(10.15, (xv - 1.5, 6.2, 3.9), (xv - 4.5, 0, 3.8), 30), (tm, (xv - 1.8, 6.4, 3.9), (xv - 5.5, 0, 3.8), 30)])
    shots.add(tm, [(tm, (m.x, -19, 3.0), (m.x, 0, 3.6), 24), (12.0, (m.x, -21, 3.4), (m.x, 0, 3.6), 24)])
    return xv + 0.6, xr - 0.6


def act_charge(shots, xv, xr):
    """12.0 - 13.5 s: both gather power for their beams."""
    charge = dict(crouch=30, wide=18, lean=8, nod=-6, armL=(62, -30, 72), armR=(62, -30, 72))
    for f, x, yaw in ((V, xv, RIGHT), (R, xr, LEFT)):
        f.pose(12.1, **charge)
        f.pose(13.3, **dict(charge, crouch=34, lean=12))
        f.place(12.1, (x, 0, 0), yaw)
        f.place(13.4, (x, 0, 0), yaw)
        f.joints["Palm"] = empty(f"{f.name}_Palm", f.col, f.joints["Waist"], (0, 1.85, 0.95))
    fx.charge_orb(12.1, 13.5, V.joints["Palm"], PURPLE, size=0.75, seed=81)
    fx.charge_orb(12.1, 13.5, R.joints["Palm"], CYAN, size=0.75, seed=82)
    fx.aura(V, "VAuraB", PURPLE, 11.95, 19.6, height=7.0, count=8, strength=6, seed=2)
    fx.aura(R, "RAuraB", CYAN, 11.95, 18.45, height=7.0, count=8, strength=6, seed=3)
    fx.float_rocks(12.0, 13.5, Vector((xv, 0, 0)), count=12, blow=13.55, seed=83)
    fx.float_rocks(12.0, 13.5, Vector((xr, 0, 0)), count=12, blow=13.55, seed=84)
    for f in (V, R):
        f.eyes(12.0, 16)
        f.eyes(12.3, 26)
    shots.add(12.0, [(12.0, (xv - 3.6, 6.4, 2.6), (xv - 0.6, 0, 3.7), 30), (12.75, (xv - 3.2, 5.8, 2.8), (xv - 0.6, 0, 3.8), 32)])
    shots.add(12.75, [(12.75, (xr + 3.6, -6.4, 2.6), (xr + 0.6, 0, 3.7), 30), (13.5, (xr + 3.2, -5.8, 2.8), (xr + 0.6, 0, 3.8), 32)])


def act_beams(shots, xv, xr):
    """13.5 - 18.42 s: the beam clash. Pushed towards Void, Void roars and drives it back to Rift."""
    fire = dict(crouch=26, wide=18, lean=12, nod=-4, armL=(88, -9, 0), armR=(88, -9, 0))
    strain = dict(crouch=34, wide=20, lean=20, nod=-10, armL=(86, -9, 4), armR=(86, -9, 4))
    roar = dict(crouch=24, wide=20, lean=-6, nod=18, armL=(90, -9, 0), armR=(90, -9, 0))
    for f, x, yaw in ((V, xv, RIGHT), (R, xr, LEFT)):
        f.pose(13.5, **fire)
        f.place(13.5, (x, 0, 0), yaw)
    # Void is driven back (13.8 - 15.6), roars (15.6 - 16.2), then pushes; Rift is driven back after
    k = 0
    for t in [13.8 + i * 0.15 for i in range(13)]:
        V.pose(t, **dict(strain, crouch=strain["crouch"] + (2 if k % 2 else -1), nod=-10 + (3 if k % 2 else 0)))
        k += 1
    V.place(15.6, (xv + 1.0, 0, 0), RIGHT)
    V.pose(15.75, **roar)
    V.pose(16.1, **dict(roar, nod=22))
    V.pose(16.5, **fire)
    V.place(18.3, (xv + 1.0, 0, 0), RIGHT)
    V.pose(18.3, **dict(fire, lean=16))
    R.pose(16.0, **fire)
    for i, t in enumerate([16.3 + j * 0.15 for j in range(14)]):
        R.pose(t, **dict(strain, crouch=strain["crouch"] + (2 if i % 2 else -1), nod=-10 + (3 if i % 2 else 0)))
    R.place(16.2, (xr, 0, 0), LEFT)
    R.place(18.25, (xr - 1.0, 0, 0), LEFT)
    # the roar: Void's aura erupts
    fx.aura(V, "VAuraRoar", rgb(185, 120, 255), 15.65, 19.6, height=10.0, count=10, strength=9, seed=4)
    V.eyes(15.6, 26)
    V.eyes(15.7, 45)
    V.eyes(16.4, 30)
    fx.flash(15.65, Vector((xv + 1.0, 0, 3.4)), PURPLE, size=1.3, dur=0.3, light=6000)
    fx.shockwave(15.65, Vector((xv + 1.0, 0, 0.06)), PURPLE, 1, 14, 0.7, strength=10)
    fx.cracks(15.65, Vector((xv + 1.0, 0, 0)), rgb(190, 140, 255), count=10, reach=(4, 8), dur=3.0, seed=91)
    fx.debris(15.65, Vector((xv + 1.0, 0, 0)), count=14, seed=92)
    shake(15.65, 0.9, 0.6)
    POST["speed"].append([15.65, 16.15, "radial"])

    void_root, _ = fx.element(beams.build_void, "VoidBeam")
    rift_root, _ = fx.element(beams.build_rift, "RiftBeam")

    def P(t):
        """The clash point."""
        if t < 13.75:
            return None
        if t < 15.6:
            x = lerp(0.3, 5.0, ease((t - 13.75) / 1.85))
        elif t < 16.2:
            x = 5.0 + 0.2 * math.sin((t - 15.6) * 30)
        elif t < 18.25:
            x = lerp(5.0, -6.2, ease((t - 16.2) / 2.05) ** 1.2)
        else:
            x = lerp(-6.2, xr - 1.0, min(1, (t - 18.25) / 0.17))
        wob = 0.25 * math.sin(t * 19) + 0.12 * math.sin(t * 41)
        return Vector((x + wob, 0, 3.7 + 0.1 * math.sin(t * 23)))

    # the clash ball
    core_m = glow("ClashCore", WHITE, strength=40, soft=1.2)
    core = fx.mesh_object("ClashCore", fx._ico(1.0, 3), fx.fx_col(), core_m, smooth=True)
    pm = glow("ClashPurple", PURPLE, strength=16, soft=1.6)
    cm = glow("ClashCyan", CYAN, strength=16, soft=1.6)
    shell_p = fx.mesh_object("ClashP", fx._ico(1.0, 3), fx.fx_col(), pm, smooth=True)
    shell_c = fx.mesh_object("ClashC", fx._ico(1.0, 3), fx.fx_col(), cm, smooth=True)
    ring_p = fx.mesh_object("ClashRingP", fx._torus(2.2, 0.07), fx.fx_col(), glow("ClashRingPM", PURPLE, strength=20))
    ring_c = fx.mesh_object("ClashRingC", fx._torus(2.6, 0.06), fx.fx_col(), glow("ClashRingCM", CYAN, strength=20))
    light = fx._light("ClashLight", Vector((0, 0, 3.7)), WHITE, [(13.7, 0), (13.76, 9000), (18.25, 9000), (18.3, 0)], radius=1.5)

    t_meet = 13.75
    rng = random.Random(95)
    f = F(13.5)
    while f <= F(18.75):
        t = (f - 1) / FPS
        n = (f - 1) * 30 // FPS  # effect spawns are paced in 30 fps steps, whatever the frame rate
        new_step = (f - 1) * 30 % FPS == 0
        ov = mid(V, t)
        orr = mid(R, t)
        p = P(t)
        # beams: travel out to the meeting point, then end at the clash point
        if t < t_meet:
            u = (t - 13.5) / (t_meet - 13.5)
            p0 = Vector((0.3, 0, 3.7))
            fx.aim(void_root, f, ov, ov.lerp(p0, max(u, 0.02)), width=0.62)
            fx.aim(rift_root, f, orr, orr.lerp(p0, max(u, 0.02)), width=0.58)
        elif t <= 18.25:
            fx.aim(void_root, f, ov, p, width=0.62 + 0.04 * math.sin(t * 37))
            fx.aim(rift_root, f, orr, p, width=0.58 + 0.04 * math.sin(t * 31) - (0.25 * (t - 17.6) / 0.65 if t > 17.6 else 0))
        else:
            # breakthrough: the void beam engulfs Rift, then dies away
            reach = Vector((xr - 1.0, 0, 3.6))
            w = 0.62 * (1 - max(0, (t - 18.45) / 0.3)) + 0.9 * max(0, 1 - abs(t - 18.42) / 0.1)
            fx.aim(void_root, f, ov, reach, width=max(w, 0.001))
        if p is not None and t <= 18.25:
            pulse = 1 + 0.12 * math.sin(t * 29) + 0.08 * math.sin(t * 53)
            key(core, f, loc=p, scale=1.1 * pulse, interp="LINEAR")
            key(shell_p, f, loc=p + Vector((0.45, 0, 0)), scale=1.9 * pulse, interp="LINEAR")
            key(shell_c, f, loc=p - Vector((0.45, 0, 0)), scale=1.9 * (2 - pulse), interp="LINEAR")
            key(ring_p, f, loc=p, rot=(90 + 20 * math.sin(t * 3), t * 400, 0), interp="LINEAR")
            key(ring_c, f, loc=p, rot=(90 - 25 * math.sin(t * 2.5), -t * 350, 0), interp="LINEAR")
            light.location = p
            light.keyframe_insert("location", frame=f)
            if new_step and n % 2 == 0:
                d = Vector((rng.uniform(-0.3, 0.3), rng.uniform(-1, 1), rng.uniform(-1, 1))).normalized()
                fx.jag_bolt(t, p + d * 1.2, p + d * rng.uniform(3, 5.5), PURPLE if n % 4 == 0 else CYAN, width=0.06, dur=0.07, seed=n)
            if new_step and n % 5 == 0:
                fx.sparks(t, p, (0, rng.choice((-1, 1)), 0.5), PURPLE if n % 10 == 0 else CYAN, count=6, speed=12, spread=1.0, dur=0.3, seed=n)
            if new_step and n % 18 == 0:
                fx.dust(t, Vector((p.x, 0, 0)), count=5, radius=3, rise=1.5, dur=1.0, size=(0.7, 1.4), seed=f)
        f += 1
    fx.show(void_root, F(13.5), F(18.78))
    fx.show(rift_root, F(13.5), F(18.25) + 1)
    for o in (core, shell_p, shell_c, ring_p, ring_c):
        visible(o, F(t_meet), F(18.25) + 1)
    pm0 = P(t_meet)
    fx.flash(t_meet, pm0, WHITE, size=2.6, dur=0.3, light=8000)
    fx.shockwave(t_meet, pm0, rgb(210, 190, 255), 0.5, 11, 0.5, normal=(0, 1, 0), strength=14)
    fx.cracks(t_meet, Vector((pm0.x, 0, 0)), rgb(200, 170, 255), count=10, reach=(4, 9), dur=4.0, seed=96)
    shake(t_meet, 0.9, 0.5)
    impact_frame(t_meet, 1)
    POST["shake"].append([13.8, 0.18, 4.4])  # a constant rumble through the struggle

    # cameras
    shots.add(13.5, [(13.5, (0, -21, 3.4), (0, 0, 3.6), 24), (14.3, (0, -19.5, 3.6), (0.6, 0, 3.6), 24)])
    shots.add(14.3, [(14.3, (xv + 6.8, 4.4, 6.2), (2.0, 0, 3.6), 30), (15.0, (xv + 6.4, 4.6, 6.0), (3.5, 0, 3.6), 30)])
    shots.add(15.0, [(15.0, (xv - 3.6, 2.2, 4.4), (xv + 0.9, 0, 4.7), 40), (15.6, (xv - 3.2, 1.9, 4.5), (xv + 0.95, 0, 4.75), 44)])
    shots.add(15.6, [(15.6, (xv - 5.5, 7.5, 1.0), (xv + 0.8, 0, 4.5), 22), (16.3, (xv - 6.0, 8.2, 1.0), (xv + 0.5, 0, 4.8), 22)])
    keys = []
    for i in range(6):
        t = 16.3 + i * 0.18
        keys.append((t, (P(t).x, -14.5, 3.6), (P(t).x, 0, 3.7), 30))
    shots.add(16.3, keys)
    shots.add(17.2, [(17.2, (xr + 3.6, -2.2, 4.4), (xr - 0.6, 0, 4.7), 40), (17.8, (xr + 3.2, -1.9, 4.5), (xr - 0.8, 0, 4.75), 44)])
    shots.add(17.8, [(17.8, (0, -22, 3.4), (-1.5, 0, 3.6), 24), (18.6, (-2, -21, 3.4), (-4, 0, 3.4), 24)])
    return xv + 1.0, xr - 1.0


def act_breakthrough(shots, xv, xr):
    """18.42 - 20.0 s: the void beam engulfs Rift and throws it across the arena."""
    T = 18.42
    pr = Vector((xr, 0, 3.4))
    fx.flash(T, pr, PURPLE, size=2.2, dur=0.35, light=12000)
    fx.shockwave(T, pr, PURPLE, 0.5, 12, 0.6, normal=(0, 1, 0), strength=14)
    fx.shockwave(T, Vector((xr, 0, 0.06)), DEEP, 1, 16, 0.7, strength=9)
    fx.dust(T, Vector((xr, 0, 0)), count=14, radius=7, rise=1.6, dur=1.6, size=(1.0, 2.2), seed=101)
    fx.debris(T, Vector((xr, 0, 0)), count=18, seed=102, direction=(-1, 0, 0))
    shake(T, 1.2, 0.6)
    impact_frame(T, 2)
    land_x = xr - 13.5
    R.place(T, (xr, 0, 0), LEFT)
    R.pose(T, crouch=10, lean=-30, nod=30, armL=(120, 60, 30), armR=(120, 60, 30), legL=(30, 10, -40), legR=(10, 10, -20))
    R.place(18.75, (xr - 5.5, 0, 3.0), LEFT, tilt=(140, 0))
    R.pose(18.75, crouch=0, lean=-10, nod=20, armL=(160, 70, 10), armR=(150, 80, 20), legL=(60, 15, -90), legR=(-20, 15, -10))
    R.place(19.1, (land_x + 1.5, 0, 0.6), LEFT, tilt=(290, 0))
    R.pose(19.1, crouch=0, lean=10, armL=(60, 50, 60), armR=(70, 40, 60), legL=(80, 10, -100), legR=(70, 10, -90))
    R.place(19.4, (land_x, 0, 0), LEFT, tilt=(360, 0), interp="CONSTANT")
    kneel = dict(crouch=55, wide=14, lean=26, nod=16, armL=(30, 20, 40), armR=(55, 10, 30))
    R.pose(19.4, **kneel)
    R.place(19.44, (land_x, 0, 0), LEFT)
    R.pose(20.0, **dict(kneel, crouch=52))
    fx.dust(19.1, Vector((land_x + 1.5, 0, 0)), count=9, radius=2.5, rise=0.6, dur=1.2, size=(0.6, 1.3), seed=103)
    fx.debris(19.1, Vector((land_x + 1.5, 0, 0)), count=8, speed=(3, 7), seed=104, direction=(-1, 0, 0))
    R.eyes(18.4, 16)
    R.eyes(19.5, 6)
    V.pose(18.9, **dict(GUARD, crouch=20, armL=(70, 12, 100), armR=(60, 18, 100)))
    V.place(19.9, (xv, 0, 0), RIGHT)
    keys = [(18.6 + i * 0.2, (R.where(18.6 + i * 0.2)[0][0] + 5, -15, 3.0), (R.where(18.6 + i * 0.2)[0][0], 0, 2.6), 28) for i in range(8)]
    keys = [(18.6, (xr + 2, -15, 3.0), (xr - 2, 0, 2.8), 28), (19.1, (land_x + 5, -14, 2.6), (land_x + 1, 0, 2.2), 28), (20.0, (land_x + 5.5, -13, 2.4), (land_x, 0, 2.2), 28)]
    shots.add(18.6, keys)
    return land_x


def act_blackhole(shots, xv, xr):
    """20.0 - 25.0 s: Void raises a hand and a black hole swallows Rift, then implodes."""
    H = Vector((xr, 0, 12.0))
    V.pose(20.0, **dict(GUARD, crouch=16))
    V.pose(20.35, crouch=10, wide=16, lean=-4, nod=-8, armR=(172, 6, 6), armL=(14, 18, 30))
    V.pose(23.4, crouch=10, wide=16, lean=-4, nod=-8, armR=(170, 6, 6), armL=(14, 18, 30))
    V.place(23.4, (xv, 0, 0), RIGHT)
    fx.flash(20.33, V.joints["FistR"].matrix_world.translation if False else W(V.joints["FistR"], 20.35), PURPLE, size=0.8, dur=0.3, light=2000)

    root, col = fx.element(ults.ult_void, "BlackHole")
    for o in list(col.objects):
        if o.name.startswith("Jets"):
            bpy.data.objects.remove(o)  # the polar jets would stab down through Rift in these shots
    from mathutils import Matrix
    pivot = empty("BHPivot", fx.fx_col())
    tilt = empty("BHTilt", fx.fx_col(), pivot)
    spin = empty("BHSpin", fx.fx_col(), tilt)
    untilt = empty("BHUntilt", fx.fx_col(), spin)
    root.parent = untilt
    root.location = Vector((0, -16, -9))
    tilt.rotation_euler = (math.radians(20), 0, 0)
    untilt.rotation_euler = (math.radians(-20), 0, 0)
    pivot.location = H
    pivot.rotation_euler = (math.radians(35), 0, 0)  # tip the disc towards the cameras so its spiral reads
    S = 0.85
    key(pivot, F(20.3), loc=H, scale=0.02)
    key(pivot, F(21.0), scale=S)
    key(pivot, F(23.62), scale=S)
    key(pivot, F(23.76), scale=S * 1.12)
    key(pivot, F(23.93), scale=0.02)
    for i in range(0, 37):
        t = 20.3 + i * 0.1
        key(spin, F(t), rot=(0, 0, -i * 22), interp="LINEAR")
    fx.show(root, F(20.3), F(23.95))
    fx.flash(20.32, H, PURPLE, size=1.6, dur=0.3, light=4000)
    fx.shockwave(20.35, H, PURPLE, 0.5, 9, 0.6, normal=(0, 1, 0), strength=10)
    fx._light("BHLight", H, PURPLE, [(20.3, 0), (21.0, 5000), (23.6, 5000), (23.93, 0)], radius=3)

    # Rift looks up, gets to its feet and tries to escape through a rift
    R.pose(20.55, **dict(crouch=50, wide=14, lean=8, nod=-35, armL=(30, 20, 40), armR=(55, 10, 30)))
    R.pose(20.95, crouch=22, wide=16, lean=-6, nod=-25, armL=(60, 20, 90), armR=(90, 30, 20))
    R.place(20.95, (xr, 0, 0), LEFT)
    pc = Vector((xr + 2.6, 0, 3.6))
    portal_src = fx.element(ults.ult_rift, "PortalC")
    for o in list(portal_src[1].objects):
        pass
    piv = portal(portal_src[0], pc, 0, 21.0, 21.15, 21.45, 21.95)
    key(piv, F(21.45), loc=pc)
    key(piv, F(21.95), loc=H)
    fx.suck(21.45, 0.5, pc, H, seed=110)
    # pulled off the ground and up into the hole
    R.pose(21.6, crouch=14, wide=10, lean=-20, nod=-30, armL=(100, 40, 30), armR=(120, 40, 20))
    R.place(21.75, (xr, 0, 0), LEFT)
    R.pose(21.9, crouch=0, lean=-10, nod=-20, armL=(150, 40, 20), armR=(160, 30, 20), legL=(10, 10, -30), legR=(-10, 10, -10))
    for i in range(1, 9):
        u = i / 8
        t = 21.75 + u * 1.5
        a = u * 3.5
        r = 2.0 * (1 - u)
        R.place(t, (xr + math.cos(a) * r, math.sin(a) * r, (H.z - 3.0) * u ** 1.4), LEFT + i * 50, tilt=(-20 * u, 30 * math.sin(i)), interp="LINEAR")
        R.pose(t, crouch=0, lean=-15 + 10 * math.sin(i), nod=-20, armL=(150 + 10 * math.sin(i * 2), 45, 20), armR=(155, 35 + 10 * math.cos(i), 20), legL=(15 * math.sin(i), 12, -40), legR=(-15 * math.sin(i), 12, -20))
    R.size(22.85, 1.0)
    R.size(23.25, 0.04)
    R.hide(23.26)
    R.eyes(21.0, 16)
    # the ground and the air are dragged in
    rng = random.Random(111)
    for i in range(30):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(5, 15)
        fx.suck(rng.uniform(20.6, 22.8), rng.uniform(0.9, 1.5), Vector((xr + math.cos(a) * r, math.sin(a) * r, 0.2)), H, seed=120 + i)
    fx.dust(21.1, Vector((xr, 0, 0)), count=10, radius=4, rise=6, dur=1.6, size=(1.0, 2.0), seed=112, ring=False)
    fx.dust(22.0, Vector((xr, 0, 0)), count=10, radius=3, rise=8, dur=1.4, size=(1.0, 2.0), seed=113, ring=False)
    POST["shake"].append([20.4, 0.15, 3.4])

    # the implosion
    T = 23.93
    fx.flash(T, H, WHITE, size=8, dur=0.6, light=40000, soft=4.0)
    fx.shockwave(T, Vector((xr, 0, 0.1)), rgb(220, 200, 255), 2, 60, 1.0, strength=10)
    fx.shockwave(T, H, PURPLE, 1, 35, 0.8, normal=(0, 1, 0), strength=12)
    fx.dust(T + 0.05, Vector((xr, 0, 0)), count=24, radius=26, rise=4, dur=2.2, size=(2.0, 4.0), seed=114)
    fx.debris(T, Vector((xr, 0, 0)), count=30, speed=(10, 22), seed=115)
    fx.cracks(T, Vector((xr, 0, 0)), rgb(200, 160, 255), count=14, reach=(8, 16), dur=3.5, seed=116)
    POST["white"].append([T, 0.08, 0.5])
    shake(T, 1.6, 0.9)
    impact_frame(T, 1)

    shots.add(20.0, [(20.0, (xv + 7.5, 4.8, 1.3), (xv - 8, 0, 7.0), 26), (20.9, (xv + 7.0, 4.5, 1.4), (xv - 10, 0, 8.0), 26)])
    shots.add(20.9, [(20.9, (xr + 13, -20, 1.2), (xr, 0, 7.0), 22), (22.25, (xr + 12, -19, 1.3), (xr, 0, 8.0), 22)])
    keys = []
    for i in range(7):
        t = 22.25 + i * (23.6 - 22.25) / 6
        p = Vector(R.where(t)[0]) + Vector((0, 0, 2.5))
        keys.append((t, tuple(p + Vector((8.5, -13, 1.0))), tuple(p), 28))
    shots.add(22.25, keys)
    shots.add(23.6, [(23.6, (xr + 12, -30, 6.0), (xr + 2, 0, 8.0), 28), (25.0, (xr + 12, -32, 6.4), (xr + 2, 0, 7.0), 28)])
    return H


def act_finale(shots, xv):
    """25.0 - 28.0 s: Void stands alone as the dust settles, then the logo."""
    V.pose(25.0, crouch=10, wide=16, lean=-4, nod=-8, armR=(165, 6, 8), armL=(14, 18, 30))
    V.pose(25.7, **dict(POWER, nod=-2))
    V.pose(26.4, **dict(POWER, nod=0, look=0))
    V.place(26.4, (xv, 0, 0), RIGHT)
    V.eyes(25.6, 30)
    V.eyes(26.4, 6)
    V.trim_glow(25.0, 4)
    V.trim_glow(26.6, 1.5)
    fx.dust(25.0, Vector((xv - 6, 0, 0)), count=10, radius=8, rise=1.0, dur=2.5, size=(1.5, 3.0), seed=131)
    shots.add(25.0, [(25.0, (xv + 13, -7.0, 2.6), (xv - 12, 0, 3.0), 28), (END, (xv + 11.5, -6.2, 2.7), (xv - 12, 0, 3.2), 30)])
    POST["fade"].append([26.5, 26.95])
    POST["logo"] = [26.95, END]


def build_all():
    global V, R
    post = build()
    xv, xr = act_blasts(SHOTS[0])
    act_charge(SHOTS[0], xv, xr)
    xv2, xr2 = act_beams(SHOTS[0], xv, xr)
    land_x = act_breakthrough(SHOTS[0], xv2, xr2)
    act_blackhole(SHOTS[0], xv2, land_x)
    act_finale(SHOTS[0], xv2)
    return POST
