"""Roblox R15-style blocky fighters with a joint hierarchy that can be keyframed like an FK rig.

Each fighter faces +Y in its own space, feet on Z=0. Joint rotations (degrees):
  limbs (shoulders, elbows, hips, knees): +X swings the limb forward
  waist / neck: `lean` / `nod` are given forward-positive and converted
"""
import math

import bmesh
from mathutils import Matrix, Vector

from common import F, empty, glow, key, key_value, mesh_object, rgb, surface

THIGH, SHIN = 1.1, 1.0
PELVIS_Z = 2.6


def box(size, center=(0, 0, 0), bevel=0.06):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2])) + Vector(center)
    if bevel:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect="EDGES", profile=0.6)
    return bm


def append(dst, src):
    """Appends the geometry of bmesh src into bmesh dst (both freed/kept appropriately)."""
    me = __import__("bpy").data.meshes.new("_tmp")
    src.to_mesh(me)
    src.free()
    dst.from_mesh(me)
    __import__("bpy").data.meshes.remove(me)


class Fighter:
    def __init__(self, name, col, look):
        self.name = name
        self.col = col
        self.look = look
        self.joints = {}
        self.parts = []
        self.places = {}
        self._build()

    # ------------------------------------------------------------ construction
    def _part(self, name, bm, mat, joint):
        obj = mesh_object(f"{self.name}_{name}", bm, self.col, mat, smooth=True, parent=self.joints[joint])
        self.parts.append(obj)
        return obj

    def _build(self):
        L = self.look
        n = self.name
        skin = surface(f"{n}_Skin", L["skin"], rough=0.55)
        shirt = surface(f"{n}_Shirt", L["shirt"], rough=0.7)
        pants = surface(f"{n}_Pants", L["pants"], rough=0.75)
        shoes = surface(f"{n}_Shoes", L["shoes"], rough=0.5)
        hair = surface(f"{n}_Hair", L["hair"], rough=0.45)
        dark = surface(f"{n}_Dark", rgb(12, 10, 14), rough=0.6)
        self.trim = glow(f"{n}_Trim", L["glow"], strength=L.get("trim_strength", 4.0))
        self.eye = glow(f"{n}_Eye", L["eye"], strength=1.0)

        J = self.joints
        J["Root"] = empty(f"{n}_Root", self.col)
        J["Pelvis"] = empty(f"{n}_Pelvis", self.col, J["Root"], (0, 0, PELVIS_Z))
        J["Waist"] = empty(f"{n}_Waist", self.col, J["Pelvis"], (0, 0, 0.2))
        J["Neck"] = empty(f"{n}_Neck", self.col, J["Waist"], (0, 0, 1.6))
        for s, x in (("L", -1.5), ("R", 1.5)):
            J[f"Shoulder{s}"] = empty(f"{n}_Shoulder{s}", self.col, J["Waist"], (x, 0, 1.5))
            J[f"Elbow{s}"] = empty(f"{n}_Elbow{s}", self.col, J[f"Shoulder{s}"], (0, 0, -1.05))
            J[f"Wrist{s}"] = empty(f"{n}_Wrist{s}", self.col, J[f"Elbow{s}"], (0, 0, -0.95))
            J[f"Hip{s}"] = empty(f"{n}_Hip{s}", self.col, J["Pelvis"], (x / 3, 0, -0.2))
            J[f"Knee{s}"] = empty(f"{n}_Knee{s}", self.col, J[f"Hip{s}"], (0, 0, -THIGH))
            J[f"Ankle{s}"] = empty(f"{n}_Ankle{s}", self.col, J[f"Knee{s}"], (0, 0, -SHIN))

        # contact markers used to land hits exactly
        for s in ("L", "R"):
            J[f"Fist{s}"] = empty(f"{n}_Fist{s}", self.col, J[f"Wrist{s}"], (0, 0, -0.42))
            J[f"Toe{s}"] = empty(f"{n}_Toe{s}", self.col, J[f"Ankle{s}"], (0, 0.62, -0.15))
            J[f"Shin{s}"] = empty(f"{n}_Shin{s}", self.col, J[f"Knee{s}"], (0, 0.5, -0.5))
            J[f"Forearm{s}"] = empty(f"{n}_Forearm{s}", self.col, J[f"Elbow{s}"], (0, 0.5, -0.5))
        J["Face"] = empty(f"{n}_Face", self.col, J["Neck"], (0, 0.6, 0.65))
        J["Chest"] = empty(f"{n}_Chest", self.col, J["Waist"], (0, 0.5, 0.9))
        self._part("LowerTorso", box((2.0, 1.0, 0.42)), pants, "Pelvis")
        self._part("Belt", box((2.04, 1.04, 0.12), (0, 0, 0.15), 0.02), dark, "Pelvis")
        self._part("UpperTorso", box((2.0, 1.0, 1.6), (0, 0, 0.8)), shirt, "Waist")
        # a glowing trim: hem and collar
        self._part("Hem", box((2.03, 1.03, 0.08), (0, 0, 0.06), 0.02), self.trim, "Waist")
        self._part("Collar", box((0.9, 1.03, 0.1), (0, 0, 1.52), 0.02), self.trim, "Waist")
        self._part("Head", box((1.2, 1.15, 1.2), (0, 0, 0.62), 0.22), skin, "Neck")
        self._face("Neck", dark)
        self._hair(hair, "Neck")
        for s in ("L", "R"):
            self._part(f"UpperArm{s}", box((1.0, 1.0, 1.15), (0, 0, -0.45)), shirt, f"Shoulder{s}")
            self._part(f"Cuff{s}", box((1.03, 1.03, 0.08), (0, 0, -0.98), 0.02), self.trim, f"Shoulder{s}")
            self._part(f"LowerArm{s}", box((0.96, 0.96, 1.0), (0, 0, -0.48)), skin, f"Elbow{s}")
            self._part(f"Hand{s}", box((0.98, 0.98, 0.42), (0, 0, -0.18), 0.1), skin, f"Wrist{s}")
            self._part(f"UpperLeg{s}", box((1.0, 1.0, 1.2), (0, 0, -0.55)), pants, f"Hip{s}")
            self._part(f"LowerLeg{s}", box((0.98, 0.98, 1.05), (0, 0, -0.5)), pants, f"Knee{s}")
            self._part(f"Foot{s}", box((1.0, 1.15, 0.32), (0, 0.06, -0.15), 0.08), shoes, f"Ankle{s}")

    def _face(self, joint, dark):
        # determined eyes: slanted bars that glow, with heavy brows
        eyes = bmesh.new()
        brows = bmesh.new()
        for s in (-1, 1):
            e = box((0.24, 0.04, 0.11), (0, 0, 0), 0.015)
            bmesh.ops.transform(e, matrix=Matrix.Translation((0.25 * s, 0.585, 0.7)) @ Matrix.Rotation(math.radians(-12 * s), 4, "Y"), verts=e.verts)
            append(eyes, e)
            b = box((0.32, 0.05, 0.07), (0, 0, 0), 0.01)
            bmesh.ops.transform(b, matrix=Matrix.Translation((0.25 * s, 0.59, 0.86)) @ Matrix.Rotation(math.radians(-20 * s), 4, "Y"), verts=b.verts)
            append(brows, b)
        mouth = box((0.3, 0.04, 0.05), (0, 0.585, 0.38), 0.01)
        append(brows, mouth)
        self._part("Eyes", eyes, self.eye, joint)
        self._part("Brows", brows, dark, joint)

    def _hair(self, mat, joint):
        bm = bmesh.new()
        append(bm, box((1.3, 1.25, 0.32), (0, -0.04, 1.2), 0.1))  # cap
        append(bm, box((1.3, 0.35, 0.9), (0, -0.48, 0.85), 0.1))  # back
        style = self.look["hair_style"]
        if style == "spiky":
            for i, (x, y, h, tx, ty) in enumerate(
                ((-0.45, 0.2, 0.75, -0.25, 0.35), (0, 0.25, 0.85, 0, 0.45), (0.45, 0.2, 0.75, 0.25, 0.35),
                 (-0.35, -0.3, 0.8, -0.3, -0.35), (0.35, -0.3, 0.8, 0.3, -0.35), (0, -0.45, 0.7, 0, -0.6))):
                base = Vector((x, y, 1.3))
                tip = base + Vector((tx, ty, h))
                geo = bmesh.ops.create_cone(bm, cap_ends=True, segments=4, radius1=0.28, radius2=0.0, depth=1.0)
                d = (tip - base)
                rot = d.to_track_quat("Z", "Y").to_matrix().to_4x4()
                bmesh.ops.transform(bm, matrix=Matrix.Translation((base + tip) / 2) @ rot @ Matrix.Diagonal((1, 1, d.length, 1)), verts=geo["verts"])
        else:  # swept: long wedges combed back and to one side
            for i in range(5):
                x = -0.5 + i * 0.25
                w = box((0.3, 1.3, 0.22), (0, 0, 0), 0.06)
                bmesh.ops.transform(w, matrix=Matrix.Translation((x, -0.2, 1.32 - abs(x) * 0.15)) @ Matrix.Rotation(math.radians(-14), 4, "X") @ Matrix.Rotation(math.radians(x * 25), 4, "Y"), verts=w.verts)
                append(bm, w)
            fringe = box((0.5, 0.25, 0.45), (0, 0, 0), 0.08)
            bmesh.ops.transform(fringe, matrix=Matrix.Translation((0.38, 0.55, 1.05)) @ Matrix.Rotation(math.radians(25), 4, "Y"), verts=fringe.verts)
            append(bm, fringe)
        self._part("Hair", bm, mat, joint)

    # ------------------------------------------------------------ animation
    def place(self, t, pos, yaw, tilt=(0, 0), interp="BEZIER"):
        """Feet position (world), facing yaw in degrees (0 = +Y, -90 = +X), optional body tilt (x, y)."""
        self.places[t] = (tuple(pos), yaw, tuple(tilt), interp)
        key(self.joints["Root"], F(t), loc=pos, rot=(tilt[0], tilt[1], yaw), interp=interp)

    def shift(self, times, delta):
        """Re-keys existing placements at the given times, moved by delta (to land a hit exactly)."""
        for t in times:
            pos, yaw, tilt, interp = self.places[t]
            self.place(t, tuple(p + d for p, d in zip(pos, delta)), yaw, tilt, interp)

    def where(self, t):
        """The latest placement at or before t."""
        best = max((k for k in self.places if k <= t + 1e-6), default=min(self.places))
        return self.places[best]

    def hide(self, t_off, t_on=None):
        """Hides the whole fighter from t_off (until t_on)."""
        from common import visible
        for part in self.parts:
            part.hide_render = False
            part.keyframe_insert("hide_render", frame=1)
            part.hide_render = True
            part.keyframe_insert("hide_render", frame=F(t_off))
            if t_on is not None:
                part.hide_render = False
                part.keyframe_insert("hide_render", frame=F(t_on))
            from common import _fcurves
            for fc in _fcurves(part.animation_data.action):
                if fc.data_path == "hide_render":
                    for kp in fc.keyframe_points:
                        kp.interpolation = "CONSTANT"

    def size(self, t, s, interp="BEZIER"):
        key(self.joints["Root"], F(t), scale=s, interp=interp)

    def pose(self, t, crouch=0.0, wide=0.0, lift=0.0, lean=0.0, twist=0.0, side=0.0, nod=0.0, look=0.0,
             armL=(0, 8, 10), armR=(0, 8, 10), legL=None, legR=None, interp="BEZIER"):
        """A full-body pose.

        crouch: degrees of knee bend at the hips (feet stay planted); wide: legs apart (degrees);
        lift: extra pelvis height; lean: torso forward; twist: torso yaw; side: torso side-bend;
        arms: (forward pitch, outward, elbow bend[, twist]); legs: optional (hip pitch, outward, knee bend)
        to override the planted-leg solution for kicks / jumps.
        """
        f = F(t)
        J = self.joints
        drop = (THIGH + SHIN) * (1 - math.cos(math.radians(crouch)))
        key(J["Pelvis"], f, loc=(0, 0, PELVIS_Z - drop + lift), rot=(0, 0, 0), interp=interp)
        key(J["Waist"], f, rot=(-lean, side, twist), interp=interp)
        key(J["Neck"], f, rot=(-nod, 0, look), interp=interp)
        for s, arm, sign in (("L", armL, 1), ("R", armR, -1)):
            pitch, out, elbow = arm[0], arm[1], arm[2]
            tw = arm[3] if len(arm) > 3 else 0
            key(J[f"Shoulder{s}"], f, rot=(pitch, sign * out, sign * tw), interp=interp)
            key(J[f"Elbow{s}"], f, rot=(elbow, 0, 0), interp=interp)
            key(J[f"Wrist{s}"], f, rot=(0, 0, 0), interp=interp)
        for s, leg, sign in (("L", legL, 1), ("R", legR, -1)):
            if leg is None:
                hip, knee, ankle = crouch, -2 * crouch, crouch
                out = wide
            else:
                hip, out, knee = leg
                ankle = -(hip + knee) * 0.6
            key(J[f"Hip{s}"], f, rot=(hip, sign * out, 0), interp=interp)
            key(J[f"Knee{s}"], f, rot=(knee, 0, 0), interp=interp)
            key(J[f"Ankle{s}"], f, rot=(ankle, -sign * out * (1 if leg is None else 0.5), 0), interp=interp)

    def eyes(self, t, strength):
        key_value(self.eye, "Strength", F(t), strength)

    def trim_glow(self, t, strength):
        key_value(self.trim, "Strength", F(t), strength)

    def hand(self, side="R"):
        return self.joints[f"Wrist{side}"]
