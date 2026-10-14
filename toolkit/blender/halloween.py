# Build A Bee Empire - the Halloween Egg corner (a limited-time event), made in Blender (chunky toy style).
#
# Run:  blender --background --factory-startup --python halloween.py -- <ABSOLUTE output folder> [preview] [icon] [export]
#
#   preview  halloween-preview.png: the whole corner as it will stand next to the Flower Garden
#   icon     icon-HalloweenEgg.png: the egg alone, for menus (icon-tools\finish-blender-icons.ps1 finishes it)
#   export   BeeEmpire-halloween.fbx (the file Roblox Studio imports) and halloween-layout.lua
#            (where every piece stands, for the script that builds the corner in the game)
#
# Game space: x = right, y = up, z = back. Pieces stand on y = 0 and face -z (the camera's side).
# Seen from the front, +x is on the LEFT.
#
# Pieces. WHITE ones are turned into glowing (Neon) parts by the game:
#   HwEgg, HwEggGlow(white)            the big pumpkin egg and its carved face
#   HwPedestal, HwPedestalGems(white)  the stone steps it stands on
#   Pumpkin, PumpkinFace(white)        a pumpkin, and the carved face some of them get
#   Gravestone, SpookyTree             scenery
#   BatProp, Ghostie                   little things that float in the air (made round their own middle)
#   Cauldron, CauldronGoo(white)       a pot of bubbling green goo
#   HwSign                             the board the chances are written on (the game adds the writing)
#   BatGear, GhostGear, PumpkinKingGear, PumpkinGlow(white)   what the three bees wear (halloween_gear.py)

import math
import os
import sys
import types

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Matrix, Vector  # noqa: E402

import halloween_gear  # noqa: E402
from toykit import (Piece, add_camera, add_sun, ball, box, export_for_roblox, for_blender, new_collection,  # noqa: E402
                    paint_material, put, rgb, say, setup_render, start, tube, turned)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
MODES = set(ARGS[1:]) or {"preview"}
os.makedirs(OUT, exist_ok=True)

KIT = types.SimpleNamespace(Piece=Piece, box=box, ball=ball, tube=tube, turned=turned, rgb=rgb)

INK = rgb(35, 30, 30)
WHITE = rgb(255, 255, 255)
STONE = rgb(112, 104, 140)
STONE_DARK = rgb(74, 68, 98)
STONE_LIGHT = rgb(150, 142, 178)
PURPLE = rgb(104, 52, 170)
PURPLE_LIGHT = rgb(150, 96, 220)
PUMPKIN = rgb(255, 128, 24)
PUMPKIN_DARK = rgb(222, 88, 10)
PUMPKIN_LIGHT = rgb(255, 170, 66)
STEM = rgb(92, 160, 60)
BARK = rgb(98, 68, 112)
BARK_DARK = rgb(66, 46, 80)
IRON = rgb(58, 54, 74)
IRON_LIGHT = rgb(98, 92, 120)
PLUM = rgb(132, 78, 190)
PLUM_DARK = rgb(74, 42, 112)
SHEET = rgb(250, 250, 255)
MOSS = rgb(110, 170, 80)
YELLOW = rgb(255, 214, 60)

# the colours the game will make the white pieces glow in (used here only for the pictures)
GLOWS = {
    "HwEggGlow": rgb(255, 196, 60),
    "HwPedestalGems": rgb(255, 140, 30),
    "PumpkinFace": rgb(255, 196, 60),
    "CauldronGoo": rgb(120, 255, 80),
    "PumpkinGlow": rgb(*halloween_gear.GLOW_COLOR),
}


# ---- shapes this file needs on top of toykit's ------------------------------------------------

def disc(radius, height, sides=32, soften=0.0):
    """A round plate lying flat, with its rims softened."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=radius, radius2=radius, depth=height)
    if soften > 0:
        rims = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6]
        bmesh.ops.bevel(bm, geom=rims, offset=min(soften, height * 0.45), offset_type="OFFSET", segments=2,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "X"))
    return bm


def ring_spot(angle_degrees, radius, y):
    angle = math.radians(angle_degrees)
    return (math.sin(angle) * radius, y, math.cos(angle) * radius)


def limb(p, start_at, end_at, thick, color):
    """A branch: a rounded bar from one point to another."""
    a, b = Vector(start_at), Vector(end_at)
    way = b - a
    turn = Vector((0, 1, 0)).rotation_difference(way.normalized()).to_matrix().to_4x4()
    p.add(box((thick, way.length + thick * 0.6, thick), round_all=thick * 0.3), tuple((a + b) / 2), color, turn)


# ---- the pieces ---------------------------------------------------------------------------------

EGG_LAYERS = [(2.4, 0.7), (3.6, 0.8), (4.4, 1.0), (4.8, 1.1), (4.4, 1.0), (3.4, 0.8), (2.2, 0.6)]  # bottom up: wide, tall


def make_egg():
    """The Halloween Egg: the mystery egg's shape, twice as big, as a pumpkin. 6 studs tall."""
    p = Piece("HwEgg")
    y = 0.0
    for index, (wide, tall) in enumerate(EGG_LAYERS):
        p.add(box((wide, tall + 0.1, wide), round_all=min(0.4, tall * 0.42), segments=3), (0, y + tall / 2, 0),
              PUMPKIN if index % 2 == 1 else PUMPKIN_DARK)
        y += tall
    # the stalk and a leaf
    p.add(tube(0.36, 0.9, "y", 8), (0.08, 6.3, 0), STEM, turned(0, 0, -12))
    p.add(box((0.9, 0.14, 0.5), round_all=0.06), (-0.55, 6.3, 0.1), STEM, turned(0, 15, -20))
    # a belt of purple diamonds round the lower part
    for dx in (-1.0, 0.0, 1.0):
        for z in (-1.84, 1.84):
            p.add(box((0.56, 0.56, 0.14)), (dx, 1.1, z), PURPLE, turned(0, 0, 45))
        for x in (-1.84, 1.84):
            p.add(box((0.14, 0.56, 0.56)), (x, 1.1, dx), PURPLE, turned(45, 0, 0))
    # little bat wings on its sides
    for side in (1, -1):
        lift = turned(0, 0, 20 * side)
        p.add(box((1.7, 1.3, 0.16), round_axis="z", round_axis_by=0.32), (side * 3.0, 3.7, 0.3), PLUM, lift)
        for dy in (-0.42, 0.0, 0.42):
            p.add(box((1.75, 0.16, 0.22), round_all=0.05, segments=1), (side * 3.0, 3.7 + dy, 0.3), PLUM_DARK, lift)
    return p


def make_egg_glow():
    p = Piece("HwEggGlow")
    deep = 0.16
    for side in (1, -1):
        halloween_gear.triangle(KIT, p, (side * 0.95, 4.08, -2.24), 1.0, 0.84, deep, WHITE)
    halloween_gear.triangle(KIT, p, (0, 3.3, -2.44), 0.44, 0.4, deep, WHITE)
    halloween_gear.grin(KIT, p, (0, 2.78, -2.44), 2.5, deep, WHITE)
    return p


def make_pedestal():
    p = Piece("HwPedestal")
    p.add(disc(6.2, 0.5, 32, soften=0.1), (0, 0.25, 0), STONE_DARK)
    p.add(disc(5.2, 0.5, 32, soften=0.1), (0, 0.75, 0), STONE)
    p.add(disc(3.9, 0.4, 28, soften=0.15), (0, 1.2, 0), PURPLE)
    p.add(disc(3.0, 0.06, 28), (0, 1.43, 0), PURPLE_LIGHT)
    for index in range(8):
        angle = 22.5 + index * 45
        p.add(box((0.9, 0.8, 0.9), round_all=0.2), ring_spot(angle, 5.35, 0.9), PUMPKIN, turned(0, angle, 0))
    return p


def make_pedestal_gems():
    p = Piece("HwPedestalGems")
    for index in range(8):
        angle = index * 45
        p.add(box((0.6, 0.6, 0.6), round_all=0.15), ring_spot(angle, 5.35, 0.84), WHITE, turned(0, angle + 45, 0))
    return p


def make_pumpkin():
    """A pumpkin, 3 studs wide. It faces -z (that is where PumpkinFace goes)."""
    p = Piece("Pumpkin")
    p.add(box((3.0, 2.4, 3.0), round_all=0.75, segments=3), (0, 1.2, 0), PUMPKIN)
    for x in (-0.8, 0.0, 0.8):
        p.add(box((0.2, 2.46, 3.06), round_axis="x", round_axis_by=0.75), (x, 1.2, 0), PUMPKIN_DARK)
    for z in (-0.8, 0.0, 0.8):
        p.add(box((3.06, 2.46, 0.2), round_axis="z", round_axis_by=0.75), (0, 1.2, z), PUMPKIN_DARK)
    p.add(tube(0.3, 0.6, "y", 8), (0.05, 2.62, 0), STEM, turned(0, 0, -10))
    p.add(box((0.7, 0.12, 0.4), round_all=0.05), (-0.45, 2.6, 0.1), STEM, turned(0, 15, -18))
    return p


def make_pumpkin_face():
    p = Piece("PumpkinFace")
    deep = 0.14
    for side in (1, -1):
        halloween_gear.triangle(KIT, p, (side * 0.62, 1.6, -1.55), 0.72, 0.6, deep, WHITE)
    halloween_gear.triangle(KIT, p, (0, 1.12, -1.55), 0.3, 0.28, deep, WHITE)
    halloween_gear.grin(KIT, p, (0, 0.68, -1.55), 1.7, deep, WHITE)
    return p


def make_gravestone():
    p = Piece("Gravestone")
    p.add(box((2.9, 0.5, 1.2), round_all=0.15), (0, 0.25, 0), STONE_DARK)
    p.add(box((2.2, 2.4, 0.62), round_all=0.16), (0, 1.6, 0), STONE)
    p.add(tube(1.1, 0.62, "z", 20), (0, 2.75, 0), STONE)
    # a little six-sided honeycomb cell carved on the front, and a crack
    p.add(tube(0.46, 0.1, "z", 6), (0, 2.45, -0.3), STONE_DARK)
    p.add(tube(0.3, 0.14, "z", 6), (0, 2.45, -0.3), STONE_LIGHT)
    p.add(box((0.1, 0.7, 0.08)), (0.5, 1.2, -0.3), STONE_DARK, turned(0, 0, 20))
    p.add(box((0.1, 0.5, 0.08)), (0.36, 0.72, -0.3), STONE_DARK, turned(0, 0, -25))
    # moss at its foot
    p.add(box((0.9, 0.5, 0.3), round_all=0.12), (-0.8, 0.6, -0.36), MOSS)
    p.add(box((0.6, 0.36, 0.3), round_all=0.1), (0.9, 0.55, -0.36), MOSS)
    return p


def make_tree():
    """A bare, crooked tree with a few last orange leaves. About 14 studs tall."""
    p = Piece("SpookyTree")
    p.add(box((2.0, 5.0, 2.0), round_all=0.45, taper=0.8), (0, 2.5, 0), BARK)
    p.add(box((1.5, 4.0, 1.5), round_all=0.35, taper=0.8), (0.3, 6.6, 0), BARK, turned(0, 0, -8))
    for x, z in ((1.2, 0.3), (-1.1, 0.6), (0.2, -1.2), (-0.4, 1.2)):
        p.add(box((1.1, 0.7, 1.1), round_all=0.25), (x, 0.35, z), BARK_DARK)
    limbs = [
        ((0.6, 7.8, 0), (3.8, 11.2, 0.6), 0.8), ((3.8, 11.2, 0.6), (5.4, 11.7, -0.6), 0.5), ((3.0, 10.4, 0.5), (3.7, 13.2, 1.4), 0.45),
        ((0.2, 7.6, 0), (-3.2, 10.4, -0.5), 0.75), ((-3.2, 10.4, -0.5), (-4.8, 12.8, 0.3), 0.5), ((-2.4, 9.7, -0.4), (-4.6, 9.7, -1.6), 0.4),
        ((0.5, 8.4, 0), (0.2, 12.4, 1.2), 0.6), ((0.2, 12.4, 1.2), (1.2, 14.4, 0.6), 0.4),
    ]
    for start_at, end_at, thick in limbs:
        limb(p, start_at, end_at, thick, BARK if thick > 0.55 else BARK_DARK)
    for at, turn in (((5.5, 11.2, -0.7), 20), ((3.8, 13.4, 1.5), -30), ((-5.0, 13.0, 0.3), 40), ((-4.8, 9.3, -1.7), 10), ((1.4, 14.6, 0.5), -15)):
        p.add(box((0.7, 0.14, 0.5), round_all=0.06), at, PUMPKIN_LIGHT, turned(20, turn, 25))
    return p


def make_bat():
    """A little bat, made round its own middle (the game hangs it in the air)."""
    p = Piece("BatProp")
    p.add(ball(0.62, (1, 1.1, 0.9)), (0, 0, 0), PLUM_DARK)
    p.both_sides(lambda: tube(0.22, 0.5, "y", 4, tip_radius=0.0), (0.3, 0.74, 0), PLUM_DARK, lambda side: turned(0, 45, -12 * side))
    for side in (1, -1):
        lift = turned(0, 0, 22 * side)
        p.add(box((1.8, 0.12, 1.1), round_axis="y", round_axis_by=0.34, axis_segments=4), (side * 1.45, 0.3, 0.1), PLUM, lift)
        for z in (-0.3, 0.15, 0.6):
            p.add(box((1.85, 0.18, 0.13), round_all=0.05, segments=1), (side * 1.45, 0.3, z), PLUM_DARK, lift)
    p.both_sides(lambda: box((0.17, 0.17, 0.1)), (0.22, 0.14, -0.54), YELLOW)
    p.both_sides(lambda: tube(0.05, 0.14, "y", 6, tip_radius=0.0), (0.1, -0.2, -0.52), WHITE, turned(180, 0, 0))
    return p


def make_ghostie():
    """A small friendly ghost, made round its own middle (the game lets it bob in the air)."""
    p = Piece("Ghostie")
    p.add(ball(0.95), (0, 0.4, 0), SHEET)
    p.add(box((1.9, 1.3, 1.9), round_all=0.4), (0, -0.4, 0), SHEET)
    for dx in (-0.6, 0.0, 0.6):
        for dz in (-0.6, 0.0, 0.6):
            p.add(ball(0.38), (dx, -1.1, dz), SHEET)
    p.both_sides(lambda: box((0.28, 0.4, 0.1), round_all=0.04), (0.36, 0.45, -0.9), INK)
    p.add(box((0.34, 0.24, 0.1), round_all=0.04), (0, -0.08, -0.95), INK)
    # two stubby arms
    p.both_sides(lambda: ball(0.34, (1.2, 0.8, 0.8)), (1.05, -0.1, -0.2), SHEET)
    return p


def make_cauldron():
    p = Piece("Cauldron")
    p.add(ball(1.8, (1, 0.74, 1)), (0, 1.35, 0), IRON)
    p.add(tube(1.5, 0.5, "y", 20), (0, 2.25, 0), IRON)
    p.add(tube(1.72, 0.3, "y", 20), (0, 2.5, 0), IRON_LIGHT)
    for index in range(3):
        p.add(box((0.5, 0.6, 0.5), round_all=0.12), ring_spot(index * 120, 1.2, 0.2), IRON_LIGHT)
    p.both_sides(lambda: box((0.3, 0.5, 0.7), round_all=0.1), (1.82, 1.9, 0), IRON_LIGHT)
    return p


def make_goo():
    p = Piece("CauldronGoo")
    p.add(tube(1.44, 0.16, "y", 20), (0, 2.6, 0), WHITE)
    for x, z, size in ((0.5, 0.3, 0.38), (-0.6, -0.2, 0.3), (0.1, -0.7, 0.24), (-0.3, 0.7, 0.2)):
        p.add(ball(size), (x, 2.7, z), WHITE)
    for x, y, z, size in ((0.7, 3.5, -0.2, 0.18), (-0.4, 4.0, 0.3, 0.14), (0.2, 4.6, 0.1, 0.1)):
        p.add(ball(size), (x, y, z), WHITE)
    return p


def make_sign():
    """The board. Its face (9.2 wide, 5.6 tall, middle at y = 5.2) is left plain: the game puts the writing there."""
    p = Piece("HwSign")
    for x in (4.6, -4.6):
        p.add(box((0.6, 8.4, 0.6), round_all=0.15), (x, 4.2, 0.1), BARK)
    p.add(box((9.8, 6.2, 0.5), round_all=0.15), (0, 5.2, 0), PLUM_DARK)
    p.add(box((10.3, 0.45, 0.75), round_all=0.14), (0, 8.4, 0), PUMPKIN)
    p.add(box((10.3, 0.45, 0.75), round_all=0.14), (0, 2.0, 0), PUMPKIN)
    # a bat sitting on top
    p.add(ball(0.5, (1, 1.1, 0.9)), (0, 9.2, 0), PLUM_DARK)
    for side in (1, -1):
        p.add(box((1.5, 0.9, 0.14), round_axis="z", round_axis_by=0.25), (side * 1.2, 9.3, 0), PLUM, turned(0, 0, 14 * side))
    p.both_sides(lambda: tube(0.18, 0.4, "y", 4, tip_radius=0.0), (0.25, 9.82, 0), PLUM_DARK, lambda side: turned(0, 45, -12 * side))
    p.both_sides(lambda: box((0.14, 0.14, 0.08)), (0.18, 9.3, -0.44), YELLOW)
    return p


MAKERS = [make_egg, make_egg_glow, make_pedestal, make_pedestal_gems, make_pumpkin, make_pumpkin_face, make_gravestone,
          make_tree, make_bat, make_ghostie, make_cauldron, make_goo, make_sign]

# ---- where everything stands (the egg is the middle; -z is the front, towards the Flower Garden) ----
# name, x, y, z, turn (degrees round the up axis), size
PEDESTAL_TOP = 1.46
LAYOUT = [
    ("HwPedestal", 0, 0, 0, 0, 1.0), ("HwPedestalGems", 0, 0, 0, 0, 1.0),
    ("HwEgg", 0, PEDESTAL_TOP, 0, 0, 1.0), ("HwEggGlow", 0, PEDESTAL_TOP, 0, 0, 1.0),
    ("HwSign", -11.0, 0, 3.0, -31, 1.0),
    ("SpookyTree", 10.5, 0, 6.5, 20, 1.0), ("SpookyTree", -13.5, 0, 10.5, 200, 0.75),
    ("Gravestone", 6.5, 0, -6.0, 12, 1.0), ("Gravestone", 11.8, 0, -1.0, -24, 0.85), ("Gravestone", -5.0, 0, 9.5, 8, 0.9),
    ("Pumpkin", -4.6, 0, -6.2, -12, 1.0), ("PumpkinFace", -4.6, 0, -6.2, -12, 1.0),
    ("Pumpkin", 3.6, 0, -9.2, 14, 0.7), ("PumpkinFace", 3.6, 0, -9.2, 14, 0.7),
    ("Pumpkin", -13.0, 0, -4.5, -30, 1.3), ("PumpkinFace", -13.0, 0, -4.5, -30, 1.3),
    ("Pumpkin", 8.0, 0, 2.0, 0, 0.6),
    ("Pumpkin", 13.5, 0, 10.0, 40, 0.9), ("PumpkinFace", 13.5, 0, 10.0, 40, 0.9),
    ("Pumpkin", -8.5, 0, 12.5, 0, 0.7),
    ("Cauldron", 9.0, 0, -9.5, 0, 1.0), ("CauldronGoo", 9.0, 0, -9.5, 0, 1.0),
    ("BatProp", 9.0, 10.5, 3.0, 20, 1.2), ("BatProp", -3.5, 9.5, 7.0, -30, 1.0), ("BatProp", 4.0, 12.5, 9.0, 10, 1.4),
    ("BatProp", -11.5, 8.0, 3.5, 40, 1.0), ("BatProp", 0.5, 10.8, -3.0, 0, 0.9),
    ("Ghostie", -7.5, 4.4, -1.5, -20, 1.0), ("Ghostie", 6.0, 5.4, 6.0, 25, 1.2),
]
GROUND_RADIUS = 17.5

# ---- drawing ------------------------------------------------------------------------------------

scene = start()
pieces = {}
for maker in MAKERS:
    piece = maker()
    pieces[piece.name] = piece
for maker in halloween_gear.MAKERS:
    piece = maker(KIT)
    pieces[piece.name] = piece
library = new_collection("Pieces")
objects = {name: piece.to_object(library) for name, piece in pieces.items()}
for name, piece in pieces.items():
    low, high = piece.bounds()
    say("piece", name, "triangles", piece.triangles(), "size", [round(high[i] - low[i], 2) for i in range(3)])


def move(x, y, z, turn=0.0, size=1.0):
    return Matrix.Translation((x, y, z)) @ turned(0, turn, 0) @ Matrix.Scale(size, 4)


def glow_material(color, strength=1.6):
    """A piece that shines by itself, the way a Neon part does in the game."""
    material = bpy.data.materials.new("Glow")
    material.use_nodes = True
    shader = material.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = for_blender(color)
    for name in ("Emission Color", "Emission"):
        if name in shader.inputs:
            shader.inputs[name].default_value = for_blender(color)
            break
    if "Emission Strength" in shader.inputs:
        shader.inputs["Emission Strength"].default_value = strength
    return material


def material_for(name, paint):
    return glow_material(GLOWS[name]) if name in GLOWS else paint


def flat_disc(collection, radius, y, color):
    mesh = bpy.data.meshes.new("Ground")
    ring = [(math.cos(2 * math.pi * i / 48) * radius, math.sin(2 * math.pi * i / 48) * radius, y) for i in range(48)]
    mesh.from_pydata(ring, [], [list(range(48))])
    ground = bpy.data.objects.new("Ground", mesh)
    material = bpy.data.materials.new("Ground")
    material.use_nodes = True
    material.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = for_blender(color)
    material.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
    ground.data.materials.append(material)
    collection.objects.link(ground)
    return ground


if "preview" in MODES:
    library.hide_render = True
    studio = new_collection("Studio")
    paint = paint_material()
    for name, x, y, z, turn, size in LAYOUT:
        put(objects[name], studio, move(x, y, z, turn, size), material_for(name, paint))
    # the lawn, and the dark patch the corner stands on
    flat_disc(studio, 400, 0.0, rgb(120, 200, 80))
    flat_disc(studio, GROUND_RADIUS, 0.03, rgb(86, 62, 120))
    add_sun(studio, (-0.45, 0.75, -0.6), 2.2)
    setup_render(scene, 1800, 1200, samples=64, sky=(1, 1, 1, 1), sky_strength=0.7, see_through=False)
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = for_blender(rgb(150, 190, 255))
    add_camera(studio, scene, (0, 34, -60), (0, 5.0, 1.5), 44)
    scene.render.filepath = os.path.join(OUT, "halloween-preview.png")
    bpy.ops.render.render(write_still=True)
    say("preview drawn", scene.render.filepath)
    bpy.data.collections.remove(studio)

if "icon" in MODES:
    library.hide_render = True
    studio = new_collection("IconStudio")
    paint = paint_material()
    for name in ("HwEgg", "HwEggGlow"):
        put(objects[name], studio, move(0, 0, 0, -16), material_for(name, paint))
    add_sun(studio, (-0.45, 0.75, -0.6), 2.3)
    setup_render(scene, 768, 768, samples=64, sky=(1, 1, 1, 1), sky_strength=0.75, see_through=True)
    add_camera(studio, scene, (0, 8, -40), (0, 3.4, 0), 8.6)
    scene.render.filepath = os.path.join(OUT, "icon-HalloweenEgg.png")
    bpy.ops.render.render(write_still=True)
    say("egg picture drawn")
    bpy.data.collections.remove(studio)

if "export" in MODES:
    library.hide_render = False
    export_for_roblox(scene, pieces, objects, os.path.join(OUT, "BeeEmpire-halloween.fbx"))
    lines = ["-- Where every piece of the Halloween Egg corner stands. Written by blender/halloween.py.",
             "-- The egg is the middle; -z is the front. { name, x, y, z, turn in degrees, size }",
             "return {",
             "\tGroundRadius = %g," % GROUND_RADIUS,
             "\tPedestalTop = %g," % PEDESTAL_TOP,
             "\tPieces = {"]
    for name, x, y, z, turn, size in LAYOUT:
        lines.append('\t\t{ "%s", %g, %g, %g, %g, %g },' % (name, x, y, z, turn, size))
    lines += ["\t},", "}", ""]
    with open(os.path.join(OUT, "halloween-layout.lua"), "w") as handle:
        handle.write("\n".join(lines))
    say("layout written")

say("done")
