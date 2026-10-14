# Build A Bee Empire - the thumbnails and the game icon (pictures only: nothing here goes into the game).
#
# Run:  blender --background --factory-startup --python thumbnails.py -- <ABSOLUTE output folder> <pictures> [draft]
#   pictures: queen (a giant Queen over the hive), ride (riding a giant bee), line (a line of bees), icon
#   draft:    half size and few light samples, for trying a layout quickly
#
# The bees, hives, trees and flowers are the game's own models: this file borrows the makers from
# bees.py, hives.py, props.py and garden.py. Only the kid, the honey jar and the clouds are made here.
#
# Places are written in "stage space": x = to the right of the picture, y = up, z = away from the
# camera. (The other files use game space, where +x is on the LEFT of a picture taken from the front.)

import math
import os
import random
import sys
import types

import bpy
from mathutils import Matrix, Vector

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import toykit  # noqa: E402
from toykit import Piece, TO_BLENDER, WHITE, ball, box, for_blender, new_collection, rgb, say, tube, turned  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else os.path.join(HERE, "out")
MODES = set(ARGS[1:]) or {"queen"}
DRAFT = "draft" in MODES
os.makedirs(OUT, exist_ok=True)


def borrow(file_name, stop_at):
    """Runs only the first part of another of our files: its colours, shapes and makers, not its drawing."""
    with open(os.path.join(HERE, file_name), encoding="utf-8") as handle:
        source = handle.read()
    space = {"__file__": os.path.join(HERE, file_name), "__name__": "borrowed_" + file_name}
    exec(compile(source[:source.index(stop_at)], file_name, "exec"), space)
    return types.SimpleNamespace(**space)


bees = borrow("bees.py", "# ---- what to do")
hives = borrow("hives.py", "\nscene = start()")
props = borrow("props.py", "\nscene = start()")
garden = borrow("garden.py", "# ---- make everything")

INK = rgb(35, 30, 30)
SKIN = rgb(255, 208, 160)
SKIN_SHADE = rgb(240, 180, 132)
CHEEK = rgb(255, 150, 175)
HAIR = rgb(126, 74, 40)
STRAW = rgb(246, 208, 116)
STRAW_DARK = rgb(214, 166, 80)
SHIRT = rgb(255, 204, 44)
JEANS = rgb(58, 124, 224)
JEANS_DARK = rgb(42, 96, 190)
BOOT = rgb(96, 60, 38)
TONGUE = rgb(255, 120, 130)
HONEY = rgb(255, 176, 28)
HONEY_LIGHT = rgb(255, 214, 96)
LID = rgb(232, 62, 54)
LID_DARK = rgb(190, 40, 40)
LABEL = rgb(255, 246, 220)
GRASS = rgb(84, 212, 62)
CLOUD = rgb(255, 255, 255)
CLOUD_SHADE = rgb(214, 232, 255)


# ---- stage space ------------------------------------------------------------------------------------

def move(x, y, z, turn=0.0, size=1.0, tip=0.0, roll=0.0):
    """Where a thing stands. turn: degrees towards the RIGHT of the picture (0 = it looks at the camera).
    tip: nose up. roll: leaning over to its own right."""
    return Matrix.Translation((-x, y, z)) @ turned(0, turn, 0) @ turned(tip, 0, 0) @ turned(0, 0, roll) @ Matrix.Scale(size, 4)


def shift(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


# ---- materials --------------------------------------------------------------------------------------

def add_studs(material, strength=0.55):
    """Roblox studs, pressed into the surface: one round stud per stud of size, on every flat side."""
    nodes, links = material.node_tree.nodes, material.node_tree.links
    shader = nodes["Principled BSDF"]

    def sums(operation, a, b=None):
        node = nodes.new("ShaderNodeMath")
        node.operation = operation
        for index, value in enumerate((a, b)):
            if value is None:
                continue
            if isinstance(value, (int, float)):
                node.inputs[index].default_value = value
            else:
                links.new(value, node.inputs[index])
        return node.outputs[0]

    coords = nodes.new("ShaderNodeTexCoord")
    place = nodes.new("ShaderNodeSeparateXYZ")
    links.new(coords.outputs["Object"], place.inputs[0])
    geometry = nodes.new("ShaderNodeNewGeometry")
    local = nodes.new("ShaderNodeVectorTransform")
    local.vector_type, local.convert_from, local.convert_to = "NORMAL", "WORLD", "OBJECT"
    links.new(geometry.outputs["True Normal"], local.inputs[0])
    facing = nodes.new("ShaderNodeSeparateXYZ")
    links.new(local.outputs[0], facing.inputs[0])
    ax, ay, az = (sums("ABSOLUTE", facing.outputs[index]) for index in range(3))

    def stud(a, b):
        fa = sums("SUBTRACT", sums("FRACT", a), 0.5)
        fb = sums("SUBTRACT", sums("FRACT", b), 0.5)
        distance = sums("SQRT", sums("ADD", sums("MULTIPLY", fa, fa), sums("MULTIPLY", fb, fb)))
        ramp = nodes.new("ShaderNodeMapRange")
        ramp.interpolation_type = "SMOOTHSTEP"
        for name, value in (("From Min", 0.25), ("From Max", 0.31), ("To Min", 1.0), ("To Max", 0.0)):
            ramp.inputs[name].default_value = value
        links.new(distance, ramp.inputs["Value"])
        return ramp.outputs["Result"]

    x, y, z = place.outputs[0], place.outputs[1], place.outputs[2]
    top = sums("MULTIPLY", sums("GREATER_THAN", az, ax), sums("GREATER_THAN", az, ay))
    side_x = sums("MULTIPLY", sums("GREATER_THAN", ax, ay), sums("SUBTRACT", 1.0, top))
    side_y = sums("MAXIMUM", sums("SUBTRACT", sums("SUBTRACT", 1.0, top), side_x), 0.0)
    height = sums("ADD", sums("ADD", sums("MULTIPLY", top, stud(x, y)), sums("MULTIPLY", side_x, stud(y, z))),
                  sums("MULTIPLY", side_y, stud(x, z)))

    # far away the studs fade out, or they turn into sparkle
    camera = nodes.new("ShaderNodeCameraData")
    fade = nodes.new("ShaderNodeMapRange")
    for name, value in (("From Min", 30.0), ("From Max", 170.0), ("To Min", strength), ("To Max", 0.0)):
        fade.inputs[name].default_value = value
    links.new(camera.outputs["View Distance"], fade.inputs["Value"])
    bump = nodes.new("ShaderNodeBump")
    bump.inputs["Distance"].default_value = 0.12
    links.new(fade.outputs["Result"], bump.inputs["Strength"])
    links.new(height, bump.inputs["Height"])
    links.new(bump.outputs["Normal"], shader.inputs["Normal"])
    return material


def plain(name, color, alpha=1.0, rough=0.45, glow=0.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = for_blender(color)
    shader.inputs["Roughness"].default_value = rough
    if alpha < 1:
        shader.inputs["Alpha"].default_value = alpha
        for setting, value in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(material, setting, value)
            except Exception:
                pass
    if glow > 0:
        for name in ("Emission Color", "Emission"):
            if name in shader.inputs:
                shader.inputs[name].default_value = for_blender(color)
                break
        shader.inputs["Emission Strength"].default_value = glow
    return material


MATERIALS = {}


def paint():
    if "paint" not in MATERIALS:
        MATERIALS["paint"] = toykit.paint_material()
    return MATERIALS["paint"]


def stud_paint():
    if "stud_paint" not in MATERIALS:
        MATERIALS["stud_paint"] = add_studs(toykit.paint_material())
    return MATERIALS["stud_paint"]


def tint(color, studs=False):
    key = ("tint", tuple(round(c, 3) for c in color), studs)
    if key not in MATERIALS:
        material = toykit.tint_material(color)
        MATERIALS[key] = add_studs(material) if studs else material
    return MATERIALS[key]


def flat(color, alpha=1.0, glow=0.0):
    key = ("flat", tuple(round(c, 3) for c in color), alpha, glow)
    if key not in MATERIALS:
        MATERIALS[key] = plain("Flat", color, alpha=alpha, glow=glow)
    return MATERIALS[key]


# ---- the things made only for these pictures ------------------------------------------------------

def make_kid():
    """Our own blocky kid: a beekeeper with a straw hat and a bee-striped shirt. Returns the pieces;
    every piece is modelled around its own joint, so the kid can be posed."""
    parts = {}

    p = Piece("KidTorso")  # joint: the middle of the hips
    p.add(box((2.0, 2.0, 1.0), round_all=0.16), (0, 1.0, 0), SHIRT)
    for y in (0.62, 1.34):
        p.add(box((2.05, 0.36, 1.05), round_axis="y", round_axis_by=0.16), (0, y, 0), INK)
    p.add(box((2.04, 0.2, 1.04), round_axis="y", round_axis_by=0.16), (0, 0.1, 0), BOOT)  # belt
    p.add(box((0.34, 0.26, 0.1), round_all=0.03, segments=1), (0, 0.1, -0.52), STRAW)  # buckle
    p.add(box((0.9, 0.2, 0.7), round_all=0.06, segments=1), (0, 1.97, 0), WHITE)  # collar
    parts["torso"] = p

    for name, mouth in (("KidHeadHappy", "open"), ("KidHeadSmile", "smile"), ("KidHeadCool", "cool")):
        p = Piece(name)  # joint: the neck
        p.add(box((1.34, 1.26, 1.34), round_all=0.36, segments=3), (0, 0.66, 0), SKIN)
        face = -0.672
        p.both_sides(lambda: box((0.2, 0.36, 0.1), round_all=0.07), (0.28, 0.74, face), INK)
        p.both_sides(lambda: box((0.08, 0.11, 0.05), round_all=0.02, segments=1), (0.32, 0.85, face - 0.04), WHITE)
        p.both_sides(lambda: box((0.22, 0.13, 0.06), round_all=0.03, segments=1), (0.47, 0.5, face + 0.01), CHEEK)
        if mouth == "open":
            p.add(box((0.4, 0.26, 0.08), round_all=0.07), (0, 0.38, face), INK)
            p.add(box((0.24, 0.1, 0.05), round_all=0.03, segments=1), (0, 0.31, face - 0.03), TONGUE)
        elif mouth == "smile":
            p.add(box((0.32, 0.07, 0.07)), (0, 0.38, face), INK)
            p.both_sides(lambda: box((0.08, 0.12, 0.07)), (0.18, 0.42, face), INK)
        else:  # a cool half smile, one eyebrow up
            p.add(box((0.3, 0.07, 0.07)), (-0.02, 0.38, face), INK)
            p.add(box((0.08, 0.12, 0.07)), (-0.19, 0.42, face), INK)
            p.add(box((0.3, 0.07, 0.07)), (0.28, 1.0, face), INK, turned(0, 0, -12))
            p.add(box((0.3, 0.07, 0.07)), (-0.28, 1.06, face), INK, turned(0, 0, -6))
        # hair showing under the hat
        p.both_sides(lambda: box((0.22, 0.62, 0.9), round_all=0.08), (0.66, 0.9, 0.12), HAIR)
        p.add(box((1.36, 0.86, 0.26), round_all=0.1), (0, 0.82, 0.62), HAIR)
        for x, wide in ((-0.42, 0.34), (0.0, 0.4), (0.42, 0.34)):
            p.add(box((wide, 0.24, 0.2), round_all=0.07), (x, 1.14, -0.62), HAIR)
        # the straw hat
        p.add(tube(1.42, 0.07, "y", 28), (0, 1.25, 0), STRAW_DARK)
        p.add(tube(1.38, 0.12, "y", 28), (0, 1.31, 0), STRAW)
        p.add(tube(0.74, 0.5, "y", 24), (0, 1.6, 0), STRAW)
        p.add(tube(0.62, 0.14, "y", 24), (0, 1.9, 0), STRAW)
        p.add(tube(0.77, 0.2, "y", 24), (0, 1.47, 0), INK)
        p.add(box((0.3, 0.2, 0.08), round_all=0.03, segments=1), (0, 1.47, -0.77), SHIRT)  # a little bee badge
        p.add(box((0.07, 0.2, 0.09)), (0, 1.47, -0.775), INK)
        parts[mouth] = p

    for side, name in ((1, "R"), (-1, "L")):
        p = Piece("KidUpperArm" + name)  # joint: the shoulder
        p.add(box((0.96, 1.08, 0.96), round_all=0.16), (0, -0.32, 0), SHIRT)
        p.add(box((1.0, 0.2, 1.0), round_axis="y", round_axis_by=0.16), (0, -0.74, 0), INK)
        parts["upper_arm" + name] = p
        p = Piece("KidLowerArm" + name)  # joint: the elbow
        p.add(box((0.9, 1.12, 0.9), round_all=0.18), (0, -0.5, 0), SKIN)
        parts["lower_arm" + name] = p
        p = Piece("KidUpperLeg" + name)  # joint: the hip
        p.add(box((0.97, 1.12, 0.97), round_all=0.12), (0, -0.46, 0), JEANS)
        parts["upper_leg" + name] = p
        p = Piece("KidLowerLeg" + name)  # joint: the knee
        p.add(box((0.94, 1.0, 0.94), round_all=0.12), (0, -0.45, 0), JEANS_DARK)
        p.add(box((1.0, 0.42, 1.12), round_all=0.12), (0, -0.84, -0.06), BOOT)
        parts["lower_leg" + name] = p
    return parts


def make_jar():
    """A chunky honey jar, standing on (0, 0, 0)."""
    p = Piece("HoneyJar")
    p.add(box((1.3, 1.25, 1.3), round_axis="y", round_axis_by=0.36), (0, 0.63, 0), HONEY)
    p.add(box((1.32, 0.3, 1.32), round_axis="y", round_axis_by=0.36), (0, 1.1, 0), HONEY_LIGHT)
    p.add(box((1.05, 0.2, 1.05), round_axis="y", round_axis_by=0.3), (0, 1.32, 0), HONEY_LIGHT)
    p.add(box((1.26, 0.3, 1.26), round_axis="y", round_axis_by=0.36), (0, 1.52, 0), LID)
    p.add(box((0.9, 0.1, 0.9), round_axis="y", round_axis_by=0.26), (0, 1.7, 0), LID_DARK)
    p.add(box((0.86, 0.56, 0.08), round_all=0.03, segments=1), (0, 0.58, -0.64), LABEL)
    p.add(box((0.44, 0.3, 0.06), round_all=0.03, segments=1), (0, 0.58, -0.69), SHIRT)  # a tiny bee on the label
    for x in (-0.08, 0.1):
        p.add(box((0.08, 0.3, 0.07)), (x, 0.58, -0.695), INK)
    p.add(box((0.12, 0.7, 0.06), round_all=0.03, segments=1), (0.44, 0.7, -0.66), rgb(255, 236, 170))  # a shine
    return p


SIGN_MIDDLE = 13.4  # how high the middle of the honeycomb is above the foot of its stick
SIGN_RADIUS = 8.6


def make_sign():
    """The loading screen's sign: a big six-sided honeycomb on a stick, honey running over its top.
    The game's name is NOT on it: the game writes that over the picture, so it is always sharp."""
    p = Piece("HoneycombSign")
    wood, wood_dark = rgb(170, 112, 62), rgb(128, 80, 44)
    rim, rim_dark, face = rgb(240, 140, 20), rgb(206, 108, 12), rgb(255, 226, 158)
    cy, radius = SIGN_MIDDLE, SIGN_RADIUS
    p.add(box((1.5, cy - 3, 1.3), round_all=0.28), (0.4, (cy - 3) / 2, 0.7), wood)
    p.add(box((1.0, 5.0, 1.0), round_all=0.22), (2.9, 1.9, 0.5), wood_dark, turned(0, 0, -34))
    p.add(box((2.4, 0.9, 1.9), round_all=0.25), (0.4, 0.35, 0.7), wood_dark)
    flat_top = turned(0, 0, 30)  # a corner to the left and the right, a flat edge on top
    p.add(tube(radius, 1.9, "z", 6), (0, cy, 0), rim_dark, flat_top)
    p.add(tube(radius - 0.35, 1.2, "z", 6), (0, cy, -0.6), rim, flat_top)
    p.add(tube(radius - 1.25, 0.5, "z", 6), (0, cy, -1.05), face, flat_top)
    # honey over the top edge, and runs of it down the front
    top = cy + radius * 0.866
    p.add(box((radius + 2.2, 1.5, 2.8), round_all=0.5, segments=3), (0, top + 0.1, -0.1), HONEY)
    for x, long, wide in ((-4.4, 3.2, 1.9), (-1.6, 1.7, 1.5), (1.3, 2.3, 1.7), (4.2, 4.0, 2.0)):
        p.add(box((wide, long, 1.0), round_all=0.45, segments=3), (x, top - 0.3 - long / 2, -1.25), HONEY)
        p.add(box((wide * 0.35, long * 0.45, 0.2), round_all=0.08, segments=1), (x - wide * 0.2, top - 0.5 - long * 0.3, -1.76), HONEY_LIGHT)
    p.add(box((1.6, 2.6, 1.0), round_all=0.45, segments=3), (-6.6, cy + 3.5, -1.0), HONEY, turned(0, 0, 30))
    p.add(box((1.5, 2.0, 1.0), round_all=0.45, segments=3), (6.3, cy + 4.1, -1.0), HONEY, turned(0, 0, -30))
    return p


def make_cliff():
    """A length of the game's cliff: lilac rock with grass on top (40 wide, 1 tall, 14 deep: stretched to fit)."""
    p = Piece("CliffBlock")
    p.add(box((40, 1, 14)), (0, 0.5, 0), rgb(150, 140, 185))
    return p


def make_cliff_cap():
    p = Piece("CliffCap")
    p.add(box((41, 1.6, 15), round_all=0.2, segments=1), (0, 0, 0), rgb(55, 165, 90))
    return p


def make_cloud():
    p = Piece("Cloud")
    for (x, y, z), (wide, tall, deep), color in (
            ((0, 0, 0), (16, 5, 7), CLOUD_SHADE), ((-3, 2.6, 0), (8, 5, 6), CLOUD), ((3.5, 2.2, 0.5), (7, 4, 6), CLOUD),
            ((0.5, 4.2, 0.2), (6, 4, 5.5), CLOUD), ((-7.5, 0.6, 0.3), (5, 3.4, 5.5), CLOUD), ((8, 0.4, 0.2), (5, 3, 5), CLOUD)):
        p.add(box((wide, tall, deep), round_all=1.5, segments=3), (x, y, z), color)
    return p


def make_sun():
    p = Piece("SquareSun")
    p.add(box((10, 10, 1), round_all=0.4), (0, 0, 0), WHITE)
    return p


# ---- putting the game's things on the stage --------------------------------------------------------

scene = toykit.start()
library = new_collection("Pieces")
library.hide_render = True
SHAPES = {}


def keep(piece):
    SHAPES[piece.name] = piece.to_object(library)


for maker in bees.MAKERS:
    keep(maker())
for level in hives.LEVELS:
    keep(hives.build_hive(level))
keep(hives.make_window_frame())
keep(hives.make_window_pane())
for maker in props.MAKERS:
    keep(maker())
for maker in garden.FLOWER_MAKERS + garden.OTHER_MAKERS:
    keep(maker())
KID = make_kid()
for part in KID.values():
    keep(part)
for maker in (make_jar, make_cloud, make_sun, make_sign, make_cliff, make_cliff_cap):
    keep(maker())
say("pieces ready:", len(SHAPES))

STAGE = None


def add(name, where, material):
    return toykit.put(SHAPES[name], STAGE, where, material)


BEE_LOOKS = {key: (color, gear, size, glowing) for key, _name, color, gear, size, glowing
             in bees.BEES + bees.NEW_BEES + bees.HALLOWEEN_BEES}
BEE_LOOKS["Queen"] = (rgb(255, 200, 40), ["RoyalGear", "Crown"], 1.0, [])  # the same as the Queen in the game


def bee(key, where, wings=25.0, jar=False):
    """wings: how high the wings are lifted, in degrees (25 = the way they sit in the game)."""
    color, gear, own_size, glowing = BEE_LOOKS[key]
    root = where @ Matrix.Scale(own_size, 4)
    add("Body", root, flat(color))
    add("Details", root, paint())
    for side in (1, -1):
        hinge = (shift(0.248 * side, 0.693, 0.25) @ Matrix.Rotation(math.radians(wings * side), 4, "Z")
                 @ shift(0.775 * side, 0, 0))
        add("Wing", root @ hinge, flat(rgb(200, 232, 255), alpha=0.72))
    for name in gear:
        add(name, root, paint())
    for name in glowing:
        add(name, root, flat(bees.GLOW_COLORS.get(name, bees.GLOW), glow=1.2))
    if jar:  # a honey jar held under the bee
        add("HoneyJar", root @ shift(0, -2.72, -0.1) @ Matrix.Scale(0.86, 4), paint())


def hive(index, where, lit=()):
    level = hives.LEVELS[index]
    add(level["name"], where, stud_paint())
    for number, (wx, wy, wz) in enumerate(hives.window_spots(level, hives.CAPACITY[index])):
        spot = where @ shift(wx, wy, wz) @ Matrix.Scale(level["window"], 4)
        add("HiveWindowFrame", spot, paint())
        color = lit[number] if number < len(lit) else hives.EMPTY_PANE
        add("HiveWindowPane", spot, tint(color))


def flower(kind_name, where, color):
    kind = garden.KINDS[kind_name]
    add(kind["Body"], where, paint())
    if kind["Petals"]:
        add(kind["Petals"], where, tint(rgb(*color)))


def lawn_flower(where, color):
    add("FlowerStem", where, paint())
    add("FlowerBlossom", where, tint(rgb(*color)))


def giant_sunflower(where):
    for name in ("SunGiantStem", "SunGiantHeadA", "SunGiantHeadB", "SunGiantHeadC"):
        add(name, where, paint())


def kid(where, face="open", lean=(0, 0, 0), head=(0, 0, 0), arm_r=(0, 0, 8), elbow_r=0.0, arm_l=(0, 0, -8), elbow_l=0.0,
        leg_r=(0, 0, 0), knee_r=0.0, leg_l=(0, 0, 0), knee_l=0.0, holds=None, fold_r=0.0, fold_l=0.0):
    """A posed kid standing on `where`. Angles are (forward, turn, sideways) in degrees: an arm or leg
    swings FORWARD with a positive first number; the third number lifts the right one out to the side when
    positive, the left one when negative. elbow: bends the forearm forward. knee: bends the shin back.
    fold: turns the forearm across the chest (right arm: positive, left arm: negative)."""
    hips = where @ shift(0, 2.0, 0)
    torso = hips @ turned(*lean)
    add("KidTorso", torso, paint())
    add({"open": "KidHeadHappy", "smile": "KidHeadSmile", "cool": "KidHeadCool"}[face], torso @ shift(0, 2.0, 0) @ turned(*head), paint())
    hand = None
    for side, name, arm, elbow, fold in ((1, "R", arm_r, elbow_r, fold_r), (-1, "L", arm_l, elbow_l, fold_l)):
        shoulder = torso @ shift(1.48 * side, 1.72, 0) @ turned(*arm)
        add("KidUpperArm" + name, shoulder, paint())
        fore = shoulder @ shift(0, -0.8, 0) @ turned(0, fold, 0) @ turned(elbow, 0, 0)
        add("KidLowerArm" + name, fore, paint())
        if holds and holds[0] == name:
            hand = fore @ shift(0, -1.06, 0)
    for side, name, leg, knee in ((1, "R", leg_r, knee_r), (-1, "L", leg_l, knee_l)):
        hip = hips @ shift(0.5 * side, 0, 0) @ turned(*leg)
        add("KidUpperLeg" + name, hip, paint())
        add("KidLowerLeg" + name, hip @ shift(0, -1.0, 0) @ turned(-knee, 0, 0), paint())
    if hand is not None:
        add(holds[1], hand @ holds[2], paint())


# ---- sky, ground, light, camera ---------------------------------------------------------------------

def make_sky(top, bottom, light=rgb(225, 240, 255), strength=1.0):
    """The camera sees a sky that fades from `bottom` (low in the picture) to `top`; the models are lit
    by one soft colour."""
    world = bpy.data.worlds.new("Sky")
    world.use_nodes = True
    nodes, links = world.node_tree.nodes, world.node_tree.links
    nodes.clear()
    out = nodes.new("ShaderNodeOutputWorld")
    lamp = nodes.new("ShaderNodeBackground")
    lamp.inputs["Color"].default_value = for_blender(light)
    lamp.inputs["Strength"].default_value = strength
    seen = nodes.new("ShaderNodeBackground")
    coords = nodes.new("ShaderNodeTexCoord")
    split = nodes.new("ShaderNodeSeparateXYZ")
    ramp = nodes.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.3
    ramp.color_ramp.elements[0].color = for_blender(bottom)
    ramp.color_ramp.elements[1].position = 1.0
    ramp.color_ramp.elements[1].color = for_blender(top)
    links.new(coords.outputs["Window"], split.inputs[0])
    links.new(split.outputs[1], ramp.inputs["Fac"])
    links.new(ramp.outputs["Color"], seen.inputs["Color"])
    path = nodes.new("ShaderNodeLightPath")
    mix = nodes.new("ShaderNodeMixShader")
    links.new(path.outputs["Is Camera Ray"], mix.inputs[0])
    links.new(lamp.outputs[0], mix.inputs[1])
    links.new(seen.outputs[0], mix.inputs[2])
    links.new(mix.outputs[0], out.inputs["Surface"])
    scene.world = world


def add_ground(color=GRASS, bounce=rgb(196, 214, 170), half=3000):
    """bounce: the colour of the light the lawn throws back up at the models. (With the lawn's own bright
    green, every white thing above it turns mint green.)"""
    mesh = bpy.data.meshes.new("Ground")
    mesh.from_pydata([(-half, -half, 0), (half, -half, 0), (half, half, 0), (-half, half, 0)], [], [(0, 1, 2, 3)])
    ground = bpy.data.objects.new("Ground", mesh)
    material = add_studs(plain("Ground", color, rough=0.6), strength=0.7)
    nodes, links = material.node_tree.nodes, material.node_tree.links
    path = nodes.new("ShaderNodeLightPath")
    mix = nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    mix.inputs[6].default_value = for_blender(bounce)
    mix.inputs[7].default_value = for_blender(color)
    links.new(path.outputs["Is Camera Ray"], mix.inputs[0])
    links.new(mix.outputs[2], nodes["Principled BSDF"].inputs["Base Color"])
    ground.data.materials.append(material)
    STAGE.objects.link(ground)


def add_sun(toward, strength=3.4, soft=2.5):
    """toward: the way to the sun from the stage, in stage space."""
    toykit.add_sun(STAGE, (-toward[0], toward[1], toward[2]), strength, soft)


VIEW = {}


def add_view(eye, look_at, lens=26.0, shape=16 / 9, rise=0.0):
    """shape: the picture's width divided by its height. rise: slides the picture up without tipping the
    camera (0.1 = a tenth of the picture's width), so the ground sits lower and upright things stay upright."""
    data = bpy.data.cameras.new("View")
    data.type = "PERSP"
    data.lens = lens
    data.shift_y = rise
    data.clip_start = 0.2
    data.clip_end = 8000
    camera = bpy.data.objects.new("View", data)
    STAGE.objects.link(camera)
    eye_b = TO_BLENDER.to_3x3() @ Vector((-eye[0], eye[1], eye[2]))
    target = TO_BLENDER.to_3x3() @ Vector((-look_at[0], look_at[1], look_at[2]))
    camera.location = eye_b
    camera.rotation_euler = (target - eye_b).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    # what on_screen() needs (all in stage space)
    forward = (Vector(look_at) - Vector(eye)).normalized()
    right = Vector((forward.z, 0, -forward.x)).normalized()
    up = (Vector((0, 1, 0)) - forward * forward.y).normalized()
    wide = 18.0 / lens if shape >= 1 else 18.0 * shape / lens  # half the picture's width, one stud away
    VIEW.update(eye=Vector(eye), forward=forward, right=right, up=up, wide=wide, tall=wide / shape, rise=rise * 2 * wide)


def on_screen(across, down, distance):
    """The spot that shows at (across, down) of the picture (0 to 1 from the top left), that far away."""
    spot = VIEW["eye"] + distance * (VIEW["forward"] + VIEW["right"] * (2 * across - 1) * VIEW["wide"]
                                     + VIEW["up"] * ((1 - 2 * down) * VIEW["tall"] + VIEW["rise"]))
    return spot


def facing_camera(spot, size):
    """Stands a flat thing at `spot`, square to the camera."""
    def game(v):
        return Vector((-v.x, v.y, v.z))
    turn = Matrix.Identity(4)
    for column, axis in enumerate((game(-VIEW["right"]), game(VIEW["up"]), game(VIEW["forward"]))):
        for row in range(3):
            turn[row][column] = axis[row]
    return Matrix.Translation(game(spot)) @ turn @ Matrix.Scale(size, 4)


def glow_paint(strength):
    """A piece's own colours, shining a little by themselves (clouds: or the lawn's light turns them green)."""
    key = ("glow_paint", strength)
    if key not in MATERIALS:
        material = toykit.paint_material()
        nodes, links = material.node_tree.nodes, material.node_tree.links
        colors = next(node for node in nodes if node.bl_idname == "ShaderNodeVertexColor")
        shader = nodes["Principled BSDF"]
        for name in ("Emission Color", "Emission"):
            if name in shader.inputs:
                links.new(colors.outputs["Color"], shader.inputs[name])
                break
        shader.inputs["Emission Strength"].default_value = strength
        MATERIALS[key] = material
    return MATERIALS[key]


def where_on_screen(point):
    """Where a spot (stage space) shows in the picture: (across, down), each 0 to 1 from the top left."""
    reach = Vector(point) - VIEW["eye"]
    depth = reach.dot(VIEW["forward"])
    across = (reach.dot(VIEW["right"]) / depth / VIEW["wide"] + 1) / 2
    down = (1 - (reach.dot(VIEW["up"]) / depth - VIEW["rise"]) / VIEW["tall"]) / 2
    return round(across, 4), round(down, 4)


def cliff(x, z, wide, high, deep, turn=0.0, color=None):
    """A block of cliff standing on the lawn at (x, z)."""
    where = move(x, 0, z, turn)
    add("CliffBlock", where @ Matrix.Diagonal((wide / 40, high, deep / 14, 1)), tint(color or rgb(255, 255, 255), studs=True) if color else stud_paint())
    add("CliffCap", where @ shift(0, high + 0.8, -0.5) @ Matrix.Diagonal((wide / 40, 1, deep / 14, 1)), stud_paint())


def cloud(across, down, distance=420, size=4.0):
    add("Cloud", facing_camera(on_screen(across, down, distance), size), glow_paint(0.55))


def square_sun(across, down, size=11.0):
    material = plain("Sun", rgb(0, 0, 0), glow=0.0)
    shader = material.node_tree.nodes["Principled BSDF"]
    for name in ("Emission Color", "Emission"):
        if name in shader.inputs:
            shader.inputs[name].default_value = for_blender(rgb(255, 240, 150))
            break
    shader.inputs["Emission Strength"].default_value = 1.0
    add("SquareSun", facing_camera(on_screen(across, down, 900), size), material)


def scatter(seed, count, x_range, z_range, keep_clear=()):
    """Grass tufts and little flowers on the lawn. keep_clear: (x, z, radius) spots to leave empty."""
    dice = random.Random(seed)
    colors = [(255, 255, 255), (255, 165, 60), (255, 120, 170), (110, 180, 255), (190, 120, 255), (255, 90, 90), (255, 214, 70)]
    made = 0
    while made < count:
        x, z = dice.uniform(*x_range), dice.uniform(*z_range)
        if any((x - cx) ** 2 + (z - cz) ** 2 < radius ** 2 for cx, cz, radius in keep_clear):
            continue
        made += 1
        if dice.random() < 0.6:
            add("GrassTuft", move(x, 0, z, dice.uniform(0, 360), dice.uniform(0.8, 1.4)), paint())
        else:
            lawn_flower(move(x, 0, z, dice.uniform(0, 360), dice.uniform(0.9, 1.3)), dice.choice(colors))


def setup(width, height, samples):
    engine = scene.render.engine
    for candidate in ("CYCLES", "BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
        try:
            scene.render.engine = candidate
            engine = candidate
            break
        except Exception:
            continue
    part = 0.5 if DRAFT else 1.0
    scene.render.resolution_x = int(width * part)
    scene.render.resolution_y = int(height * part)
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.view_settings.view_transform = "Standard"
    for look in ("Medium High Contrast", "Standard - Medium High Contrast"):
        try:
            scene.view_settings.look = look
            break
        except Exception:
            continue
    if engine == "CYCLES":
        scene.cycles.device = "CPU"
        scene.cycles.samples = 20 if DRAFT else samples
        scene.cycles.use_denoising = True
        scene.cycles.max_bounces = 6
    else:
        try:
            scene.eevee.taa_render_samples = samples
        except Exception:
            pass
    return engine


def shoot(name, width=1920, height=1080, samples=160):
    engine = setup(width, height, samples)
    scene.render.filepath = os.path.join(OUT, name + ("-draft" if DRAFT else "") + ".png")
    bpy.ops.render.render(write_still=True)
    say("drawn", name, "with", engine, scene.render.filepath)


BEE_COLORS = [look[0] for look in (BEE_LOOKS[key] for key in ("Common", "Uncommon", "Rare", "Epic", "Legendary", "Builder",
                                                              "Explorer", "Knight", "Wizard", "Common", "Uncommon", "Rare"))]


def new_stage(name):
    global STAGE
    for collection in list(scene.collection.children):
        if collection is not library:
            bpy.data.collections.remove(collection)
    STAGE = new_collection(name)


# ---- picture 1: a giant Queen looks over the hive ---------------------------------------------------

if "queen" in MODES:
    new_stage("Queen")
    make_sky(top=rgb(36, 140, 250), bottom=rgb(150, 222, 255))
    add_view(eye=(-4.5, 2.0, -13), look_at=(3.5, 15.5, 30), lens=20)
    add_ground()
    add_sun((-0.55, 0.8, -0.5))
    hive(4, move(9, 0, 30, -16), BEE_COLORS)
    bee("Queen", move(8, 33, 42, -12, 7.5, tip=-25), wings=50)
    kid(move(-6.5, 0.25, 2.5, 30, 1.0), face="open", lean=(14, 0, 0), head=(-6, -18, 0),
        arm_r=(-50, 0, 20), elbow_r=70, arm_l=(150, 0, -25), elbow_l=20,
        leg_r=(55, 0, 0), knee_r=30, leg_l=(-35, 0, 0), knee_l=70)
    bee("Common", move(-12, 5.6, 5.5, 40, 1.0, tip=8), wings=55)
    bee("Uncommon", move(-3.4, 9.6, 8, 24, 1.0, tip=-6), wings=40)
    bee("Rare", move(-16, 9.8, 13, 35, 1.0, tip=4), wings=58)
    bee("Epic", move(21, 6.5, 16, -40, 1.0, tip=6), wings=50)
    bee("Legendary", move(26, 11, 24, -50, 1.0, tip=4), wings=44)
    add("Tree", move(-29, 0, 28, 30, 1.25), stud_paint())
    add("Bush", move(-17, 0, 20, 20, 1.3), stud_paint())
    add("Rock", move(26, 0, 20, 40, 1.2), stud_paint())
    add("Mushroom", move(-1, 0, 12, 0, 1.3), paint())
    flower("Tulip", move(31, 0, 30, 10, 1.0), (255, 90, 90))
    flower("Daisy", move(37, 0, 36, -20, 1.2), (255, 255, 255))
    flower("Tulip", move(27, 0, 38, 0, 0.8), (255, 165, 60))
    scatter(11, 40, (-30, 36), (5, 44), keep_clear=((9, 30, 13), (-6.5, 2.5, 6), (-5.5, -6, 6)))
    cloud(0.3, 0.5, size=3.6)
    cloud(0.8, 0.34, size=4.4)
    cloud(0.97, 0.56, size=3.0)
    square_sun(0.89, 0.12)
    shoot("thumb-queen")


# ---- picture 2: riding a giant bee ------------------------------------------------------------------

if "ride" in MODES:
    new_stage("Ride")
    make_sky(top=rgb(30, 134, 248), bottom=rgb(156, 226, 255))
    add_view(eye=(-8, 4.6, -24), look_at=(1.2, 8.4, 6), lens=28)
    add_ground()
    add_sun((-0.5, 0.85, -0.55))
    big = 3.8
    steed = move(2, 1.27 * big + 0.1, 6, -50, big, tip=4)
    bee("Common", steed, wings=58)
    kid(steed @ shift(0, 0.875, -1.15) @ Matrix.Scale(1 / big, 4) @ turned(-4, 22, 0), face="open", head=(-4, 8, 0),
        arm_r=(0, 0, 30), elbow_r=24, arm_l=(176, 0, -10), elbow_l=0, leg_r=(0, 0, 10), leg_l=(0, 0, -10),
        holds=("L", "HoneyJar", turned(180, 0, 0) @ shift(0, 0.05, 0)))
    giant_sunflower(move(40, 0, 62, -14, 1.0))
    hive(4, move(-30, 0, 62, 24), BEE_COLORS)
    bee("Uncommon", move(-14.5, 11.5, 14, 55, 1.0, tip=6), wings=52)
    bee("Wizard", move(-10, 16.5, 24, 40, 1.0, tip=-4), wings=44)
    bee("Rare", move(17, 4.6, 0, -40, 1.0, tip=8), wings=56)
    bee("Galaxy", move(-20, 5.2, 4, 60, 1.0, tip=2), wings=48)
    bee("Knight", move(22, 13, 26, -30, 1.0, tip=2), wings=50)
    add("Tree", move(56, 0, 80, 140, 1.2), stud_paint())
    add("Tree", move(-58, 0, 90, 20, 1.1), stud_paint())
    add("Bush", move(-20, 0, 30, 0, 1.4), stud_paint())
    add("Rock", move(21, 0, 22, 100, 1.3), stud_paint())
    flower("Daisy", move(30, 0, 34, 20, 1.3), (255, 120, 170))
    flower("Tulip", move(14, 0, 40, 0, 1.2), (255, 90, 90))
    flower("Spike", move(44, 0, 46, 0, 1.2), (190, 120, 255))
    flower("Poppy", move(-8, 0, 36, 30, 1.2), (255, 165, 60))
    scatter(23, 64, (-34, 40), (-3, 50), keep_clear=((2, 6, 11), (40, 62, 6), (-8, -24, 14), (-3, -8, 7)))
    cloud(0.12, 0.2, size=4.4)
    cloud(0.6, 0.1, size=3.4)
    cloud(0.3, 0.5, size=3.0)
    cloud(0.93, 0.42, size=3.6)
    shoot("thumb-ride")


# ---- picture 3: a line of bees brings honey out of the hive -------------------------------------------

if "line" in MODES:
    new_stage("Line")
    make_sky(top=rgb(40, 146, 250), bottom=rgb(160, 228, 255))
    add_view(eye=(7, 8.5, -26), look_at=(1.5, 7.0, 10), lens=26)
    add_ground()
    add_sun((-0.6, 0.85, -0.45))
    home = move(11, 0, 32, -18)
    hive(4, home, BEE_COLORS)
    door = home @ Vector((0, 3.9, -12.5))  # (game space: x is the other way round)
    start_at = Vector((-door.x, door.y, door.z))
    bend = Vector((-0.5, 3.9, 6))
    end_at = Vector((-4.2, 4.0, -7.5))
    order = ["Common", "Uncommon", "Rare", "Epic", "Legendary"]
    for index, key in enumerate(order):
        t = 1.0 - index / (len(order) - 1) * 0.92
        spot = (1 - t) ** 2 * start_at + 2 * (1 - t) * t * bend + t ** 2 * end_at
        to_camera = VIEW["eye"] - spot  # every bee shows the camera its face, a little from the side
        heading = math.degrees(math.atan2(to_camera.x, -to_camera.z)) - 30
        bee(key, move(spot.x, spot.y + 0.25 * math.sin(index * 2.1), spot.z, heading, 1.25, tip=3), wings=42 + 14 * (index % 2), jar=True)
    kid(move(11, 0.25, -4, -20, 1.0), face="cool", lean=(-5, 0, -3), head=(2, 8, 3),
        arm_r=(24, 0, -4), elbow_r=92, fold_r=78, arm_l=(30, 0, 4), elbow_l=84, fold_l=-78,
        leg_r=(4, 0, 5), leg_l=(-6, 0, -9))
    for row, count in enumerate((3, 2, 1)):  # a pile of honey jars beside the kid
        for index in range(count):
            add("HoneyJar", move(16.6 + (index - (count - 1) / 2) * 1.75, row * 1.6, -2.0, -12 + 9 * ((index + row) % 3 - 1), 0.92), paint())
    bee("Wizard", move(24, 15, 30, -40, 1.0, tip=4), wings=50)
    bee("Builder", move(-2, 17, 34, 30, 1.0, tip=-4), wings=46)
    add("Tree", move(-40, 0, 56, 30, 1.2), stud_paint())
    add("Tree", move(46, 0, 64, 200, 1.1), stud_paint())
    add("Bush", move(32, 0, 30, 0, 1.3), stud_paint())
    add("Rock", move(-26, 0, 30, 40, 1.2), stud_paint())
    add("Mushroom", move(24, 0, 12, 0, 1.3), paint())
    flower("Sunflower", move(-30, 0, 44, 10, 1.3), (255, 214, 70))
    flower("Daisy", move(-22, 0, 38, 0, 1.2), (255, 255, 255))
    flower("Tulip", move(36, 0, 40, 0, 1.2), (255, 90, 90))
    scatter(37, 50, (-40, 42), (2, 52), keep_clear=((11, 32, 15), (5, 18, 7), (-4, 10, 7), (-5, 0, 7), (10.5, -6, 5), (16, -4, 5), (7, -26, 16)))
    cloud(0.12, 0.16, size=4.0)
    cloud(0.42, 0.34, size=3.2)
    cloud(0.9, 0.14, size=4.2)
    shoot("thumb-line")


# ---- the game icon: the Queen, close up -----------------------------------------------------------------

if "icon" in MODES:
    new_stage("Icon")
    make_sky(top=rgb(30, 134, 248), bottom=rgb(170, 232, 255))
    add_view(eye=(-1.0, 2.6, -15), look_at=(0, 4.8, 0), lens=42, shape=1)
    add_ground()
    add_sun((-0.5, 0.85, -0.55))
    bee("Queen", move(0.2, 4.2, 0, -22, 2.3, tip=4), wings=46)
    hive(4, move(-17, 0, 46, 14), BEE_COLORS)
    flower("Sunflower", move(15, 0, 30, -10, 1.4), (255, 214, 70))
    flower("Daisy", move(10, 0, 22, 0, 0.9), (255, 120, 170))
    add("Tree", move(26, 0, 60, 30, 1.2), stud_paint())
    scatter(51, 26, (-22, 22), (8, 40), keep_clear=((0, 0, 8),))
    cloud(0.2, 0.12, size=3.6)
    cloud(0.84, 0.2, size=3.2)
    shoot("icon-game", 1024, 1024)

# ---- the loading screen: a honeycomb sign with the Queen beside it ------------------------------------
# The bottom third is plain lawn on purpose: the game writes "Loading" and a tip there.
# The picture is extra wide (2400 x 1080, the shape of a phone). A wide phone shows all of it; a
# desktop or a tablet shows the middle and loses the sides. So the sign and the Queen stay in
# the middle 60% of the width.

if "loading" in MODES:
    new_stage("Loading")
    make_sky(top=rgb(34, 136, 250), bottom=rgb(160, 228, 255))
    add_view(eye=(0, 8.4, -46), look_at=(0, 12.2, 0), lens=24, shape=2400 / 1080)
    add_ground()
    add_sun((-0.5, 0.85, -0.6))
    lean = -9  # degrees: the sign leans to the left of the picture
    sign = move(-2.0, 0, 0, 0, 1.0, roll=lean)
    add("HoneycombSign", sign, stud_paint())
    bee("Common", sign @ shift(-4.9, SIGN_MIDDLE + SIGN_RADIUS * 0.866 + 2.25, -0.2) @ turned(0, 28, 0) @ Matrix.Scale(0.95, 4), wings=40)
    bee("Queen", move(13.4, 11.2, -5, -16, 2.5, tip=4), wings=52)  # flying beside the sign, clear of the words below
    # behind: the game's cliffs with trees on top, a hive, flowers
    cliff(-34, 46, 60, 12, 20)
    cliff(-52, 60, 70, 24, 20)
    cliff(30, 50, 64, 9, 20)
    cliff(54, 64, 70, 20, 20)
    cliff(0, 78, 120, 15, 16)
    cliff(-96, 70, 80, 30, 20)
    cliff(100, 74, 80, 27, 20)
    add("Tree", move(-92, 31.6, 70, 200, 1.0), stud_paint())
    add("Tree", move(104, 28.6, 74, 40, 1.05), stud_paint())
    add("Tree", move(-52, 0, 30, 140, 1.1), stud_paint())
    add("Tree", move(66, 0, 44, 20, 1.0), stud_paint())
    add("Bush", move(-40, 0, 14, 60, 1.4), stud_paint())
    add("Bush", move(52, 0, 18, 10, 1.3), stud_paint())
    flower("Sunflower", move(29, 0, 30, -8, 1.2), (255, 214, 70))
    flower("Spike", move(-46, 0, 22, 0, 1.0), (190, 120, 255))
    flower("Poppy", move(42, 0, 12, 0, 0.9), (255, 165, 60))
    add("Tree", move(-44, 13.6, 46, 30, 0.9), stud_paint())
    add("Tree", move(-64, 25.6, 60, 120, 1.0), stud_paint())
    add("Tree", move(58, 21.6, 64, 200, 1.0), stud_paint())
    add("Bush", move(-22, 13.6, 44, 0, 1.6), stud_paint())
    add("Bush", move(38, 10.6, 48, 40, 1.7), stud_paint())
    flower("Sunflower", move(-30, 13.6, 46, 6, 1.1), (255, 214, 70))
    flower("Tulip", move(24, 10.6, 48, 0, 1.4), (255, 90, 90))
    flower("Daisy", move(46, 10.6, 50, -10, 1.3), (255, 255, 255))
    hive(4, move(47, 0, 34, -16), BEE_COLORS)
    add("Tree", move(-30, 0, 24, 60, 1.05), stud_paint())
    add("Bush", move(-17, 0, 16, 20, 1.3), stud_paint())
    add("Rock", move(19, 0, 12, 40, 1.1), stud_paint())
    flower("Tulip", move(-21, 0, 8, 0, 0.9), (255, 120, 170))
    flower("Daisy", move(-13, 0, 20, 0, 0.9), (255, 255, 255))
    scatter(61, 44, (-58, 60), (6, 40), keep_clear=((-2, 0, 12), (47, 34, 13)))
    bee("Uncommon", move(-15, 6.5, -4, 40, 1.0, tip=6), wings=52)
    bee("Rare", move(-21, 18, 10, 36, 1.0, tip=4), wings=46)
    cloud(0.16, 0.2, size=4.2)
    cloud(0.82, 0.14, size=4.0)
    cloud(0.64, 0.34, size=2.8)
    cloud(0.36, 0.1, size=3.0)
    # where the game must write the name: the middle of the honeycomb, and how wide it is, in the picture
    middle = sign @ Vector((0, SIGN_MIDDLE, -1.3))
    edge = sign @ Vector((-SIGN_RADIUS, SIGN_MIDDLE, -1.3))
    top = sign @ Vector((0, SIGN_MIDDLE + SIGN_RADIUS * 0.866, -1.3))
    say("SIGN middle", where_on_screen((-middle.x, middle.y, middle.z)), "right corner", where_on_screen((-edge.x, edge.y, edge.z)),
        "top", where_on_screen((-top.x, top.y, top.z)), "lean", lean)
    shoot("loading-screen", 2400, 1080)

say("done")
