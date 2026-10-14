# Shared helpers for the Build A Bee Empire Blender scripts (the "chunky toy" look).
#
# Everything is written in "game space", the same numbers Roblox uses:
#   x = right, y = up, z = towards the back. 1 unit = 1 Roblox stud.
# A model is made from Pieces. Each Piece becomes one mesh in Roblox; the colours of its
# shapes are painted onto the mesh (a white shape takes whatever colour the game gives the part).

import bpy
import bmesh
import json
import math
import os
from mathutils import Matrix, Vector

# game space -> Blender space (Blender: x right, y away from the viewer, z up)
TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def say(*parts):
    print("BEE:", *parts, flush=True)


def rgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1.0)


WHITE = rgb(255, 255, 255)


def for_blender(color):
    """Our colours are written the way screens show them; Blender's paint wants the "linear" kind."""
    return tuple(((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92 for c in color[:3]) + (1.0,)


# ---- small shape makers (each returns a fresh bmesh, centred on its own middle) ---------------

def box(size, round_all=0.0, segments=2, round_axis=None, round_axis_by=0.0, axis_segments=3, taper=None):
    """A block. round_axis ('x', 'y' or 'z') rounds only the four edges that run along that axis
    (good for bands and plates); round_all rounds every edge like a toy brick.
    taper (for example 0.6) makes the top that much narrower than the bottom."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        narrow = taper if (taper is not None and v.co.y > 0) else 1.0
        v.co.x *= size[0] * narrow
        v.co.y *= size[1]
        v.co.z *= size[2] * narrow
    if round_axis and round_axis_by > 0:
        index = "xyz".index(round_axis)
        others = [i for i in range(3) if i != index]
        limit = min(size[others[0]], size[others[1]]) * 0.49
        edges = [e for e in bm.edges if abs(e.verts[0].co[index] - e.verts[1].co[index]) > 1e-6]
        bmesh.ops.bevel(bm, geom=edges, offset=min(round_axis_by, limit), offset_type="OFFSET",
                        segments=axis_segments, profile=0.5, affect="EDGES", clamp_overlap=True)
    if round_all > 0:
        smallest = min(size) * (taper if taper is not None and taper < 1 else 1.0)
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=min(round_all, smallest * 0.49), offset_type="OFFSET",
                        segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True)
    return bm


def ball(radius, squash=(1, 1, 1), detail=2):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=detail, radius=radius)
    for v in bm.verts:
        v.co.x *= squash[0]
        v.co.y *= squash[1]
        v.co.z *= squash[2]
    return bm


def tube(radius, length, axis="z", sides=16, tip_radius=None):
    """A cylinder (or a cone when tip_radius is given; the tip points towards +axis)."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=radius,
                          radius2=radius if tip_radius is None else tip_radius, depth=length)
    if axis == "x":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(90), 3, "Y"))
    elif axis == "y":
        bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "X"))
    return bm


def turned(x=0.0, y=0.0, z=0.0):
    """Same order as Roblox's CFrame.Angles(x, y, z), in degrees."""
    return (Matrix.Rotation(math.radians(x), 4, "X") @ Matrix.Rotation(math.radians(y), 4, "Y")
            @ Matrix.Rotation(math.radians(z), 4, "Z"))


def finish(obj):
    """Triangles first, then normals that keep flat faces flat and rounded edges soft."""
    obj.modifiers.new("Triangles", "TRIANGULATE")
    normals = obj.modifiers.new("Normals", "WEIGHTED_NORMAL")
    normals.keep_sharp = False
    normals.weight = 60


class Piece:
    """Collects shapes (with a colour each) and turns them into one Blender mesh."""

    def __init__(self, name):
        self.name = name
        self.verts = []
        self.faces = []
        self.colors = []

    def add(self, shape, at, color, turn=None):
        matrix = Matrix.Translation(at) @ (turn or Matrix.Identity(4))
        shape.verts.index_update()
        start = len(self.verts)
        for v in shape.verts:
            self.verts.append(tuple(matrix @ v.co))
        for f in shape.faces:
            self.faces.append([start + v.index for v in f.verts])
            self.colors.append(color)
        shape.free()

    def both_sides(self, make_shape, at, color, turn=None):
        """The same shape on the right and the left (x and every sideways turn flipped)."""
        for side in (1, -1):
            place = (at[0] * side, at[1], at[2])
            spin = turn(side) if callable(turn) else turn
            self.add(make_shape(), place, color, spin)

    def bounds(self):
        xs, ys, zs = zip(*self.verts)
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

    def triangles(self):
        return sum(len(face) - 2 for face in self.faces)

    def to_object(self, collection):
        mesh = bpy.data.meshes.new(self.name)
        mesh.from_pydata([tuple(TO_BLENDER @ Vector(v)) for v in self.verts], [], self.faces)
        mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
        paint = mesh.color_attributes.new("Col", "BYTE_COLOR", "CORNER")
        flat = []
        for polygon in mesh.polygons:
            flat.extend(self.colors[polygon.index] * polygon.loop_total)
        paint.data.foreach_set("color_srgb", flat)
        mesh.color_attributes.active_color = paint
        mesh.update()
        obj = bpy.data.objects.new(self.name, mesh)
        collection.objects.link(obj)
        finish(obj)
        return obj


# ---- scene helpers ------------------------------------------------------------------------------

def start():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    return bpy.context.scene


def new_collection(name):
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    return collection


def game_space(matrix):
    """A game-space move/turn/size change, written for Blender."""
    return TO_BLENDER @ matrix @ TO_BLENDER.inverted()


def paint_material():
    """Shows each piece's own colours."""
    material = bpy.data.materials.new("Paint")
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes["Principled BSDF"]
    colors = nodes.new("ShaderNodeVertexColor")
    colors.layer_name = "Col"
    links.new(colors.outputs["Color"], shader.inputs["Base Color"])
    shader.inputs["Roughness"].default_value = 0.45
    return material


def tint_material(color, alpha=1.0):
    """The piece's painted colours multiplied by one colour, the way Roblox tints a part."""
    material = bpy.data.materials.new("Tint")
    material.use_nodes = True
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes["Principled BSDF"]
    colors = nodes.new("ShaderNodeVertexColor")
    colors.layer_name = "Col"
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.blend_type = "MULTIPLY"
    mix.inputs[0].default_value = 1.0  # how strongly to mix
    mix.inputs[7].default_value = for_blender(color)  # colour B
    links.new(colors.outputs["Color"], mix.inputs[6])  # colour A
    links.new(mix.outputs[2], shader.inputs["Base Color"])
    shader.inputs["Roughness"].default_value = 0.45
    if alpha < 1:
        shader.inputs["Alpha"].default_value = alpha
        for setting, value in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(material, setting, value)
            except Exception:
                pass
    return material


def put(source, collection, matrix, material, name=None):
    """A copy of a piece somewhere in the picture (matrix is in game space)."""
    obj = bpy.data.objects.new(name or source.name, source.data.copy())
    obj.data.materials.append(material)
    collection.objects.link(obj)
    obj.matrix_world = game_space(matrix)
    finish(obj)
    return obj


def setup_render(scene, width, height, samples=48, sky=(1, 1, 1, 1), sky_strength=0.5, see_through=True):
    engine = scene.render.engine
    for candidate in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            scene.render.engine = candidate
            engine = candidate
            break
        except Exception:
            continue
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = see_through
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    try:
        scene.view_settings.look = "None"
    except Exception:
        pass
    if engine == "CYCLES":
        scene.cycles.samples = samples
        scene.cycles.use_denoising = True
    else:
        try:
            scene.eevee.taa_render_samples = samples
        except Exception:
            pass
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = sky
    background.inputs["Strength"].default_value = sky_strength
    scene.world = world
    return engine


def add_sun(collection, toward, strength, angle_degrees=12):
    """toward = the direction from the scene to the sun, in game space."""
    data = bpy.data.lights.new("Sun", "SUN")
    data.energy = strength
    data.angle = math.radians(angle_degrees)
    sun = bpy.data.objects.new("Sun", data)
    collection.objects.link(sun)
    direction = (TO_BLENDER.to_3x3() @ Vector(toward)).normalized()
    sun.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    return sun


def add_camera(collection, scene, eye, look_at, width_in_studs):
    data = bpy.data.cameras.new("Camera")
    data.type = "ORTHO"
    data.ortho_scale = width_in_studs
    data.clip_end = 1000
    camera = bpy.data.objects.new("Camera", data)
    collection.objects.link(camera)
    eye_b = TO_BLENDER.to_3x3() @ Vector(eye)
    target = TO_BLENDER.to_3x3() @ Vector(look_at)
    camera.location = eye_b
    camera.rotation_euler = (target - eye_b).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    return camera


def add_floor(collection, y, color, half=200):
    mesh = bpy.data.meshes.new("Floor")
    mesh.from_pydata([(-half, -half, y), (half, -half, y), (half, half, y), (-half, half, y)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("Floor", mesh)
    material = bpy.data.materials.new("Floor")
    material.use_nodes = True
    material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = for_blender(color)
    material.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    floor.data.materials.append(material)
    collection.objects.link(floor)
    return floor


def export_for_roblox(scene, pieces, piece_objects, target):
    """Writes the file Roblox Studio imports: every piece once, all standing on the same spot,
    plus four tiny marker cubes so a script can work out size and direction afterwards."""
    marks = new_collection("Marks")
    mark_objects = []
    for name, at in (("MarkOrigin", (0, -8, 0)), ("MarkRight", (10, -8, 0)), ("MarkUp", (0, 2, 0)), ("MarkBack", (0, -8, 10))):
        mark = Piece(name)
        mark.add(box((0.5, 0.5, 0.5)), at, WHITE)
        mark_objects.append(mark.to_object(marks))
    for obj in scene.objects:
        obj.select_set(False)
    chosen = list(piece_objects.values()) + mark_objects
    for obj in chosen:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = chosen[0]
    bpy.ops.export_scene.fbx(filepath=target, use_selection=True, object_types={"MESH"}, use_mesh_modifiers=True,
                             mesh_smooth_type="OFF", use_triangles=False, colors_type="SRGB", axis_forward="-Z",
                             axis_up="Y", apply_scale_options="FBX_SCALE_ALL", bake_anim=False,
                             add_leaf_bones=False)
    notes = {}
    for name, piece in pieces.items():
        low, high = piece.bounds()
        notes[name] = {"low": [round(v, 4) for v in low], "high": [round(v, 4) for v in high], "triangles": piece.triangles()}
    with open(os.path.splitext(target)[0] + ".json", "w") as handle:
        json.dump(notes, handle, indent=1)
    say("exported", target, os.path.getsize(target), "bytes,", len(chosen), "objects")
