"""Shared helpers for the Eternium fight-scene build (Blender, Cycles).

Units are studs (1 Blender unit = 1 stud), Z is up. Time is given in seconds and converted to frames.
"""
import math

import bpy  # noqa: F401  (must be imported before bmesh/mathutils)
import bmesh
from mathutils import Euler, Matrix, Vector

import os

FPS = int(os.environ.get("ETERNIUM_FPS", "60"))


def F(seconds):
    """Seconds -> frame number (frame 1 is t = 0)."""
    return 1 + round(seconds * FPS)


def rgb(r, g, b):
    """sRGB 0-255 -> linear."""
    return tuple(((c / 255) ** 2.2) for c in (r, g, b))


def collection(name, parent=None):
    col = bpy.data.collections.new(name)
    (parent or bpy.context.scene.collection).children.link(col)
    return col


def mesh_object(name, bm, col, mat=None, smooth=False, parent=None):
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    if mat:
        me.materials.append(mat)
    for p in me.polygons:
        p.use_smooth = smooth
    obj = bpy.data.objects.new(name, me)
    col.objects.link(obj)
    if parent:
        obj.parent = parent
    return obj


def empty(name, col, parent=None, location=(0, 0, 0)):
    obj = bpy.data.objects.new(name, None)
    obj.empty_display_size = 0.3
    col.objects.link(obj)
    obj.parent = parent
    obj.location = location
    return obj


def surface(name, color, rough=0.6, metal=0.0, emission=None, strength=0.0):
    """An opaque Principled material."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    b = mat.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emission is not None:
        b.inputs["Emission Color"].default_value = (*emission, 1)
        b.inputs["Emission Strength"].default_value = strength
    return mat


def glow(name, color, strength=6.0, alpha=1.0, soft=0.0):
    """An emissive material that can fade: Emission mixed with Transparent by an animatable 'Fade' value.

    Returns the material; animate mat.node_tree.nodes['Fade'].outputs[0] (1 = fully visible) and
    mat.node_tree.nodes['Strength'].outputs[0].
    """
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1)
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    fade = nt.nodes.new("ShaderNodeValue")
    fade.name = "Fade"
    fade.outputs[0].default_value = alpha
    st = nt.nodes.new("ShaderNodeValue")
    st.name = "Strength"
    st.outputs[0].default_value = strength
    nt.links.new(st.outputs[0], em.inputs["Strength"])
    if soft:
        # soft edges: fade towards the silhouette (good for flashes, orbs and shells)
        lw = nt.nodes.new("ShaderNodeLayerWeight")
        lw.inputs["Blend"].default_value = 0.5
        inv = nt.nodes.new("ShaderNodeMath")
        inv.operation = "SUBTRACT"
        inv.inputs[0].default_value = 1.0
        nt.links.new(lw.outputs["Facing"], inv.inputs[1])
        pw = nt.nodes.new("ShaderNodeMath")
        pw.operation = "POWER"
        pw.inputs[1].default_value = soft
        nt.links.new(inv.outputs[0], pw.inputs[0])
        mul = nt.nodes.new("ShaderNodeMath")
        mul.operation = "MULTIPLY"
        nt.links.new(fade.outputs[0], mul.inputs[0])
        nt.links.new(pw.outputs[0], mul.inputs[1])
        nt.links.new(mul.outputs[0], mix.inputs["Fac"])
    else:
        nt.links.new(fade.outputs[0], mix.inputs["Fac"])
    nt.links.new(tr.outputs[0], mix.inputs[1])
    nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    mat.blend_method = "BLEND" if hasattr(mat, "blend_method") else None
    return mat


def key_value(mat, node, frame, value, interp="BEZIER"):
    sock = mat.node_tree.nodes[node].outputs[0]
    sock.default_value = value
    sock.keyframe_insert("default_value", frame=frame)
    _interp(mat.node_tree.animation_data, interp)


def key(obj, frame, loc=None, rot=None, scale=None, interp="BEZIER"):
    """Keyframes an object; rot in degrees (XYZ)."""
    if loc is not None:
        obj.location = loc
        obj.keyframe_insert("location", frame=frame)
    if rot is not None:
        obj.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
        obj.keyframe_insert("rotation_euler", frame=frame)
    if scale is not None:
        obj.scale = (scale, scale, scale) if isinstance(scale, (int, float)) else scale
        obj.keyframe_insert("scale", frame=frame)
    _interp(obj.animation_data, interp, frame)


def _interp(anim, interp, frame=None):
    if not anim or not anim.action:
        return
    for fc in _fcurves(anim.action):
        for kp in fc.keyframe_points:
            if frame is None or abs(kp.co.x - frame) < 0.01:
                kp.interpolation = interp


def _fcurves(action):
    """F-curves of an action, for both the legacy and the layered (4.4+) action APIs."""
    if hasattr(action, "fcurves") and len(getattr(action, "fcurves", [])):
        return list(action.fcurves)
    out = []
    for layer in getattr(action, "layers", []):
        for strip in layer.strips:
            for bag in getattr(strip, "channelbags", []):
                out += list(bag.fcurves)
    return out


def visible(obj, frame_on, frame_off=None):
    """Shows an object (render) from frame_on until frame_off."""
    obj.hide_render = True
    obj.keyframe_insert("hide_render", frame=max(1, frame_on - 1))
    obj.hide_render = False
    obj.keyframe_insert("hide_render", frame=frame_on)
    if frame_off is not None:
        obj.hide_render = True
        obj.keyframe_insert("hide_render", frame=frame_off)
    for fc in _fcurves(obj.animation_data.action):
        if fc.data_path == "hide_render":
            for kp in fc.keyframe_points:
                kp.interpolation = "CONSTANT"


def look_at(obj, target):
    d = Vector(target) - obj.location
    obj.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t
