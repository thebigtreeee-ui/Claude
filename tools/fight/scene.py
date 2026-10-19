"""Arena, lighting, world and render settings for the Eternium fight scene."""
import math
import random

import bpy
import bmesh
from mathutils import Matrix, Vector

from common import collection, glow, mesh_object, rgb, surface


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def render_settings(width=1280, height=720, samples=32, frames=(1, 840)):
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = samples
    scn.cycles.use_adaptive_sampling = True
    scn.cycles.adaptive_threshold = 0.03
    scn.cycles.use_denoising = True
    scn.cycles.denoiser = "OPENIMAGEDENOISE"
    scn.cycles.max_bounces = 6
    scn.cycles.diffuse_bounces = 2
    scn.cycles.glossy_bounces = 2
    scn.cycles.transmission_bounces = 4
    scn.cycles.transparent_max_bounces = 16
    scn.cycles.volume_bounces = 0
    scn.cycles.sample_clamp_indirect = 3.0
    scn.cycles.caustics_reflective = False
    scn.cycles.caustics_refractive = False
    scn.render.resolution_x, scn.render.resolution_y = width, height
    scn.render.resolution_percentage = 100
    scn.render.fps = 30
    scn.frame_start, scn.frame_end = frames
    scn.render.use_motion_blur = True
    scn.render.motion_blur_shutter = 0.45
    scn.view_settings.view_transform = "AgX"
    scn.view_settings.look = "AgX - Punchy" if "AgX - Punchy" in [l for l in dir(scn.view_settings)] else "None"
    try:
        scn.view_settings.look = "AgX - Punchy"
    except TypeError:
        pass
    scn.render.image_settings.file_format = "PNG"
    scn.render.film_transparent = False
    try:
        scn.render.threads_mode = "AUTO"
    except AttributeError:
        pass


def world():
    w = bpy.data.worlds.new("Dusk")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    tc = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    # vertical gradient: deep violet-blue overhead, a dim teal-violet band at the horizon
    ramp.color_ramp.elements[0].position = 0.0
    ramp.color_ramp.elements[0].color = (*rgb(44, 30, 62), 1)
    ramp.color_ramp.elements[1].position = 0.35
    ramp.color_ramp.elements[1].color = (*rgb(10, 10, 26), 1)
    stars_n = nt.nodes.new("ShaderNodeTexVoronoi")
    stars_n.feature = "F1"
    stars_n.inputs["Scale"].default_value = 260
    starmap = nt.nodes.new("ShaderNodeMapRange")
    starmap.inputs["From Min"].default_value = 0.03
    starmap.inputs["From Max"].default_value = 0.0
    add = nt.nodes.new("ShaderNodeMath")
    add.operation = "ADD"
    stars_mul = nt.nodes.new("ShaderNodeMath")
    stars_mul.operation = "MULTIPLY"
    up = nt.nodes.new("ShaderNodeMath")
    up.operation = "GREATER_THAN"
    up.inputs[1].default_value = 0.12
    mixc = nt.nodes.new("ShaderNodeMix")
    mixc.data_type = "RGBA"
    nt.links.new(tc.outputs["Generated"], sep.inputs[0])
    nt.links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    nt.links.new(tc.outputs["Generated"], stars_n.inputs["Vector"])
    nt.links.new(stars_n.outputs["Distance"], starmap.inputs["Value"])
    nt.links.new(sep.outputs["Z"], up.inputs[0])
    nt.links.new(starmap.outputs["Result"], stars_mul.inputs[0])
    nt.links.new(up.outputs[0], stars_mul.inputs[1])
    mixc.inputs["Factor"].default_value = 0
    nt.links.new(ramp.outputs["Color"], bg.inputs["Color"])
    # stars added via a second background layered with Add Shader
    bg2 = nt.nodes.new("ShaderNodeBackground")
    bg2.inputs["Color"].default_value = (0.85, 0.9, 1.0, 1)
    nt.links.new(stars_mul.outputs[0], bg2.inputs["Strength"])
    addsh = nt.nodes.new("ShaderNodeAddShader")
    bg.inputs["Strength"].default_value = 1.0
    nt.links.new(bg.outputs[0], addsh.inputs[0])
    nt.links.new(bg2.outputs[0], addsh.inputs[1])
    nt.links.new(addsh.outputs[0], out.inputs["Surface"])
    return w


def ground_material():
    mat = bpy.data.materials.new("ArenaGround")
    mat.use_nodes = True
    nt = mat.node_tree
    b = nt.nodes["Principled BSDF"]
    tc = nt.nodes.new("ShaderNodeTexCoord")
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 0.08
    noise.inputs["Detail"].default_value = 8
    vor = nt.nodes.new("ShaderNodeTexVoronoi")
    vor.feature = "DISTANCE_TO_EDGE"
    vor.inputs["Scale"].default_value = 0.35
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = (*rgb(34, 30, 36), 1)
    ramp.color_ramp.elements[1].color = (*rgb(92, 84, 88), 1)
    cracks = nt.nodes.new("ShaderNodeMapRange")
    cracks.inputs["From Min"].default_value = 0.0
    cracks.inputs["From Max"].default_value = 0.035
    cracks.inputs["To Min"].default_value = 0.45
    cracks.inputs["To Max"].default_value = 1.0
    mul = nt.nodes.new("ShaderNodeMix")
    mul.data_type = "RGBA"
    mul.blend_type = "MULTIPLY"
    mul.inputs["Factor"].default_value = 1.0
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    nt.links.new(tc.outputs["Object"], noise.inputs["Vector"])
    nt.links.new(tc.outputs["Object"], vor.inputs["Vector"])
    nt.links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(vor.outputs["Distance"], cracks.inputs["Value"])
    nt.links.new(ramp.outputs["Color"], mul.inputs["A"])
    nt.links.new(cracks.outputs["Result"], mul.inputs["B"])
    nt.links.new(mul.outputs["Result"], b.inputs["Base Color"])
    nt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    b.inputs["Roughness"].default_value = 0.92
    return mat


def arena():
    col = collection("Arena")
    rng = random.Random(4)
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=1, y_segments=1, size=400)
    mesh_object("Ground", bm, col, ground_material())

    rockmat = surface("ArenaRock", rgb(52, 46, 52), rough=0.9)
    # mesas and spires on the horizon, and scattered boulders near the fighting ground
    bm = bmesh.new()
    for i in range(26):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(90, 170)
        c = Vector((math.cos(a) * r, math.sin(a) * r, 0))
        h = rng.uniform(14, 48)
        w = rng.uniform(10, 30)
        geo = bmesh.ops.create_cone(bm, cap_ends=True, segments=7, radius1=w, radius2=w * rng.uniform(0.45, 0.8), depth=h)
        for v in geo["verts"]:
            v.co = v.co + c + Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), h / 2))
    for i in range(70):
        a = rng.uniform(0, 2 * math.pi)
        r = rng.uniform(26, 80)
        c = Vector((math.cos(a) * r, math.sin(a) * r, 0))
        s = rng.uniform(0.6, 3.2)
        geo = bmesh.ops.create_icosphere(bm, subdivisions=1, radius=s)
        for v in geo["verts"]:
            v.co = Vector((v.co.x * rng.uniform(0.8, 1.4), v.co.y * rng.uniform(0.8, 1.4), v.co.z * 0.7)) + c
    mesh_object("Rocks", bm, col, rockmat)
    return col


def lights():
    col = collection("Lights")
    moon = bpy.data.lights.new("Moon", "SUN")
    moon.energy = 2.8
    moon.color = rgb(175, 190, 255)
    moon.angle = math.radians(2)
    o = bpy.data.objects.new("Moon", moon)
    o.rotation_euler = (math.radians(52), 0, math.radians(-35))
    col.objects.link(o)
    rim = bpy.data.lights.new("Rim", "SUN")
    rim.energy = 1.8
    rim.color = rgb(150, 110, 255)
    o2 = bpy.data.objects.new("Rim", rim)
    o2.rotation_euler = (math.radians(70), 0, math.radians(150))
    col.objects.link(o2)
    return col


def camera(col=None):
    cam = bpy.data.cameras.new("Cam")
    cam.lens = 35
    cam.sensor_width = 36
    cam.clip_start = 0.1
    cam.clip_end = 1000
    o = bpy.data.objects.new("Cam", cam)
    (col or bpy.context.scene.collection).objects.link(o)
    bpy.context.scene.camera = o
    return o


def compositor(bloom=True):
    """Bloom (glare) on the render, for the anime glow."""
    scn = bpy.context.scene
    scn.use_nodes = True
    tree = scn.compositing_node_group if hasattr(scn, "compositing_node_group") else None
    if tree is None and hasattr(scn, "node_tree"):
        tree = scn.node_tree
    if tree is None:
        tree = bpy.data.node_groups.new("Comp", "CompositorNodeTree")
        scn.compositing_node_group = tree
    for n in list(tree.nodes):
        tree.nodes.remove(n)
    rl = tree.nodes.new("CompositorNodeRLayers")
    out = None
    try:
        out = tree.nodes.new("CompositorNodeComposite")
    except RuntimeError:
        out = tree.nodes.new("NodeGroupOutput")
        tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
    last = rl.outputs["Image"]
    if bloom:
        g = tree.nodes.new("CompositorNodeGlare")
        for attr, val in (("glare_type", "BLOOM"), ("quality", "HIGH"), ("threshold", 1.0), ("size", 8), ("mix", 0.0)):
            try:
                setattr(g, attr, val)
            except (AttributeError, TypeError):
                pass
        for name, val in (("Type", "Bloom"), ("Threshold", 1.0), ("Strength", 0.6), ("Size", 0.6)):
            if name in g.inputs:
                try:
                    g.inputs[name].default_value = val
                except (TypeError, AttributeError):
                    pass
        tree.links.new(last, g.inputs[0])
        last = g.outputs[0]
    tree.links.new(last, out.inputs[0])
    return tree
