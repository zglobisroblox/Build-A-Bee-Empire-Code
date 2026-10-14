# Build A Bee Empire - the bee models, made in Blender.
#
# Run (no Blender window needed):
#   blender --background --factory-startup --python bees.py -- <output folder> [preview] [icons] [export]
#
# All sizes and places below are written in "bee space", the same numbers the game uses:
#   x = to the bee's right, y = up, z = towards its tail. The bee faces -z. 1 unit = 1 Roblox stud.
# The point (0, 0, 0.3) is the middle of the body (the game moves a bee by that point).
#
# Every bee is put together in the game from a few shared pieces:
#   Body      - the parts that take the bee's colour (white here, tinted in the game)
#   Details   - stripes, eyes, cheeks, fluffy collar, legs, antennae, stinger (own colours)
#   Wing      - one wing, used twice
#   ScoutGear / GuardGear / RoyalGear / EmperorGear / Crown - what each job wears

import bpy
import bmesh
import json
import math
import os
import sys
from mathutils import Matrix, Vector

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
MODES = set(ARGS[1:]) or {"preview"}
os.makedirs(OUT, exist_ok=True)


def say(*parts):
    print("BEE:", *parts, flush=True)


# bee space -> Blender space (Blender: x right, y away from the viewer, z up)
TO_BLENDER = Matrix(((1, 0, 0, 0), (0, 0, -1, 0), (0, 1, 0, 0), (0, 0, 0, 1)))


def rgb(r, g, b):
    return (r / 255, g / 255, b / 255, 1.0)


INK = rgb(35, 30, 30)
WHITE = rgb(255, 255, 255)
CHEEK = rgb(255, 150, 175)
CREAM = rgb(255, 238, 200)
WING = rgb(215, 240, 255)
LEATHER = rgb(126, 78, 44)
LEATHER_LIGHT = rgb(170, 112, 66)
BRASS = rgb(222, 168, 64)
GLASS = rgb(150, 224, 255)
BEDROLL = rgb(120, 176, 96)
STEEL = rgb(172, 184, 206)
DARK_STEEL = rgb(108, 120, 148)
CREST = rgb(224, 52, 52)
SHIELD_BLUE = rgb(58, 124, 224)
WOOD = rgb(150, 100, 58)
GOLD = rgb(255, 206, 60)
GEM_RED = rgb(255, 70, 110)
GEM_BLUE = rgb(70, 170, 255)
CAPE_RED = rgb(204, 40, 62)
FUR = rgb(250, 248, 240)

# colours of the second set of outfits (added 2026-10-10)
HAT_ORANGE = rgb(255, 138, 36)
HAT_ORANGE_DARK = rgb(226, 104, 20)
HAT_ORANGE_LIGHT = rgb(255, 180, 90)
KHAKI = rgb(228, 202, 148)
KHAKI_DARK = rgb(196, 162, 100)
PAPER = rgb(250, 240, 214)
RIBBON = rgb(226, 60, 70)
SILVER = rgb(220, 228, 242)
PLUME = rgb(232, 48, 64)
WIZ = rgb(66, 60, 200)
WIZ_DARK = rgb(44, 40, 150)
STAR = rgb(255, 222, 80)
SPACE = rgb(78, 48, 160)
SPACE_LIGHT = rgb(156, 104, 244)
STAR_CYAN = rgb(150, 236, 255)
STAR_PINK = rgb(255, 150, 226)
GLOW = rgb(110, 225, 255)  # what the game tints the white "glow" pieces with

BEES = [
    # game key, shown name, body colour, what it wears, size, glowing pieces
    ("Common", "Worker Bee", rgb(255, 200, 40), [], 1.0, []),
    ("Uncommon", "Scout Bee", rgb(90, 225, 110), ["ScoutGear"], 1.0, []),
    ("Rare", "Guard Bee", rgb(80, 170, 255), ["GuardGear"], 1.0, []),
    ("Epic", "Royal Bee", rgb(176, 96, 255), ["RoyalGear"], 1.0, []),
    ("Legendary", "Emperor Bee", rgb(255, 140, 30), ["EmperorGear", "Crown"], 1.0, []),
]

# the second bee of every rarity (2026-10-10): a little better than the first
NEW_BEES = [
    ("Builder", "Builder Bee", rgb(214, 232, 64), ["BuilderGear"], 1.0, []),
    ("Explorer", "Explorer Bee", rgb(40, 200, 186), ["ExplorerGear"], 1.0, []),
    ("Knight", "Knight Bee", rgb(92, 108, 242), ["KnightGear"], 1.0, []),
    ("Wizard", "Wizard Bee", rgb(232, 84, 204), ["WizardGear"], 1.0, []),
    ("Galaxy", "Galaxy Bee", rgb(52, 44, 120), ["GalaxyGear"], 1.0, ["GalaxyGlow"]),
]

WING_PLACES = [  # where the two wings sit on the body
    Matrix.Translation((0.95, 1.02, 0.25)) @ Matrix.Rotation(math.radians(25), 4, "Z"),
    Matrix.Translation((-0.95, 1.02, 0.25)) @ Matrix.Rotation(math.radians(-25), 4, "Z"),
]


# ---- small shape makers (each returns a fresh bmesh, centred on its own middle) ---------------

def box(size, round_all=0.0, segments=2, round_axis=None, round_axis_by=0.0, axis_segments=3):
    """A block. round_axis ('x', 'y' or 'z') rounds only the four edges that run along that axis
    (good for bands and plates); round_all rounds every edge like a toy brick."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= size[0]
        v.co.y *= size[1]
        v.co.z *= size[2]
    if round_axis and round_axis_by > 0:
        index = "xyz".index(round_axis)
        others = [i for i in range(3) if i != index]
        limit = min(size[others[0]], size[others[1]]) * 0.49
        edges = [e for e in bm.edges if abs(e.verts[0].co[index] - e.verts[1].co[index]) > 1e-6]
        bmesh.ops.bevel(bm, geom=edges, offset=min(round_axis_by, limit), offset_type="OFFSET",
                        segments=axis_segments, profile=0.5, affect="EDGES", clamp_overlap=True)
    if round_all > 0:
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=min(round_all, min(size) * 0.49), offset_type="OFFSET",
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
        """The same shape on the bee's right and left (x and every sideways turn flipped)."""
        for side in (1, -1):
            place = (at[0] * side, at[1], at[2])
            spin = turn(side) if callable(turn) else turn
            self.add(make_shape(), place, color, spin)

    def bounds(self):
        xs, ys, zs = zip(*self.verts)
        return (min(xs), min(ys), min(zs)), (max(xs), max(ys), max(zs))

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


def finish(obj):
    """Triangles first, then normals that keep flat faces flat and rounded edges soft."""
    obj.modifiers.new("Triangles", "TRIANGULATE")
    normals = obj.modifiers.new("Normals", "WEIGHTED_NORMAL")
    normals.keep_sharp = False
    normals.weight = 60


# ---- the pieces ---------------------------------------------------------------------------------

def make_body():
    p = Piece("Body")
    p.add(box((1.9, 1.8, 2.6), round_all=0.30, segments=3), (0, 0, 0.3), WHITE)
    p.add(box((1.15, 1.05, 0.6), round_all=0.24, segments=2), (0, -0.05, 1.8), WHITE)
    p.add(box((1.65, 1.55, 1.4), round_all=0.32, segments=3), (0, 0.1, -1.5), WHITE)
    return p


def make_details():
    p = Piece("Details")
    for z in (0.05, 0.95):  # two dark stripes, a touch bigger than the body
        p.add(box((2.0, 1.9, 0.45), round_axis="z", round_axis_by=0.33), (0, 0, z), INK)
    p.add(tube(0.2, 0.55, "z", 12, tip_radius=0.0), (0, -0.05, 2.33), INK)  # stinger
    # face
    p.both_sides(lambda: box((0.44, 0.62, 0.16), round_all=0.07), (0.4, 0.2, -2.19), INK)
    p.both_sides(lambda: box((0.16, 0.19, 0.06), round_all=0.02, segments=1), (0.47, 0.38, -2.275), WHITE)
    p.both_sides(lambda: box((0.09, 0.09, 0.05)), (0.34, 0.06, -2.275), WHITE)
    p.both_sides(lambda: box((0.32, 0.2, 0.08), round_all=0.03, segments=1), (0.64, -0.18, -2.19), CHEEK)
    p.add(box((0.2, 0.07, 0.05)), (0, -0.31, -2.2), INK)  # a small smile: a flat bit with two raised corners
    p.both_sides(lambda: box((0.07, 0.1, 0.05)), (0.13, -0.265, -2.2), INK)
    # antennae
    p.both_sides(lambda: box((0.1, 0.6, 0.1), round_all=0.03, segments=1), (0.3, 1.0, -1.6), INK,
                 lambda side: turned(-20, 0, -15 * side))
    p.both_sides(lambda: ball(0.15), (0.38, 1.32, -1.72), INK)
    # fluffy collar: a soft band with a ring of little puffs
    p.add(box((1.98, 1.88, 0.4), round_axis="z", round_axis_by=0.36), (0, 0.03, -0.88), CREAM)
    for step in range(16):
        angle = math.radians(step * 22.5 + 11.25)
        c, s = math.cos(angle), math.sin(angle)
        x = 0.99 * math.copysign(abs(c) ** 0.45, c)
        y = 0.03 + 0.94 * math.copysign(abs(s) ** 0.45, s)
        p.add(ball(0.25, (1, 1, 0.95), detail=1), (x, y, -0.88), CREAM)
    # six stubby legs
    for z in (-0.4, 0.3, 1.0):
        p.both_sides(lambda: box((0.17, 0.44, 0.17), round_all=0.05, segments=1), (0.6, -1.03, z), INK,
                     lambda side: turned(0, 0, 12 * side))
    return p


def make_wing():
    p = Piece("Wing")
    p.add(box((1.55, 0.1, 1.15), round_axis="y", round_axis_by=0.42, axis_segments=4), (0, 0, 0), WING)
    p.add(box((1.0, 0.08, 0.75), round_axis="y", round_axis_by=0.3, axis_segments=4), (0, -0.02, 0.74), WING)
    return p


def make_scout_gear():
    p = Piece("ScoutGear")
    # goggles pushed up on the forehead
    p.add(box((1.72, 0.2, 1.47), round_axis="y", round_axis_by=0.34), (0, 0.66, -1.5), LEATHER)
    p.both_sides(lambda: tube(0.27, 0.16, "z", 16), (0.38, 0.68, -2.24), BRASS)
    p.both_sides(lambda: tube(0.19, 0.19, "z", 16), (0.38, 0.68, -2.25), GLASS)
    p.add(box((0.22, 0.08, 0.08)), (0, 0.68, -2.26), BRASS)
    # a little backpack with a bedroll
    p.add(box((1.0, 0.6, 0.8), round_all=0.12), (0, 1.14, 1.0), LEATHER)
    p.add(box((1.04, 0.16, 0.5), round_all=0.06, segments=1), (0, 1.46, 0.82), LEATHER_LIGHT)
    p.add(box((0.18, 0.18, 0.06)), (0, 1.22, 0.58), BRASS)
    p.add(tube(0.2, 1.12, "x", 12), (0, 1.66, 1.12), BEDROLL)
    p.both_sides(lambda: box((0.1, 0.44, 0.1)), (0.34, 1.6, 1.12), LEATHER_LIGHT)
    return p


def make_guard_gear():
    p = Piece("GuardGear")
    p.add(box((1.78, 0.62, 1.52), round_all=0.2, segments=2), (0, 0.84, -1.5), STEEL)
    p.add(box((0.15, 0.52, 0.08), round_all=0.03, segments=1), (0, 0.3, -2.25), STEEL)  # nose guard
    p.add(box((1.86, 0.12, 1.6), round_axis="y", round_axis_by=0.36), (0, 0.55, -1.5), DARK_STEEL)
    p.both_sides(lambda: box((0.1, 0.5, 0.7), round_all=0.04, segments=1), (0.9, 0.26, -1.35), STEEL)
    p.add(box((0.22, 0.42, 1.35), round_all=0.1), (0, 1.36, -1.45), CREST)
    # round shield on the right, spear on the left
    p.add(tube(0.66, 0.12, "x", 20), (1.08, -0.1, 0.35), STEEL)
    p.add(tube(0.5, 0.15, "x", 20), (1.09, -0.1, 0.35), SHIELD_BLUE)
    p.add(ball(0.17, (0.7, 1, 1)), (1.18, -0.1, 0.35), GOLD)
    p.add(tube(0.055, 3.3, "z", 8), (-1.12, -0.25, -0.1), WOOD)
    p.add(tube(0.15, 0.48, "z", 8, tip_radius=0.0), (-1.12, -0.25, -1.98), STEEL, turned(0, 180, 0))
    return p


def cape(p, cloth, trim, top_y=0.99):
    flare = 9  # degrees the cloth swings out at the bottom
    p.add(box((2.04, 0.12, 2.3), round_axis="y", round_axis_by=0.3), (0, top_y, 0.66), cloth)
    p.both_sides(lambda: box((0.12, 1.1, 2.3), round_axis="x", round_axis_by=0.25), (1.1, top_y - 0.52, 0.66), cloth,
                 lambda side: turned(0, 0, flare * side))
    p.add(box((2.04, 1.05, 0.12), round_axis="z", round_axis_by=0.25), (0, top_y - 0.5, 1.88), cloth, turned(-flare, 0, 0))
    # the trim along the bottom edge
    p.both_sides(lambda: box((0.17, 0.17, 2.34), round_all=0.05, segments=1), (1.19, top_y - 1.08, 0.66), trim)
    p.add(box((2.3, 0.17, 0.17), round_all=0.05, segments=1), (0, top_y - 1.03, 1.97), trim)


def make_royal_gear():
    p = Piece("RoyalGear")
    cape(p, CAPE_RED, FUR)
    # a white fur collar with little dark spots
    p.add(box((2.16, 1.98, 0.38), round_axis="z", round_axis_by=0.38), (0, 0.05, -0.7), FUR)
    for x in (-0.55, 0, 0.55):
        p.add(box((0.11, 0.05, 0.13)), (x, 1.03, -0.7), INK)
    for y in (-0.4, 0.3):
        p.both_sides(lambda: box((0.05, 0.11, 0.13)), (1.085, y, -0.7), INK)
    # a slim gold band on the head with one gem
    p.add(box((1.3, 0.14, 1.12), round_axis="y", round_axis_by=0.28), (0, 0.93, -1.5), GOLD)
    p.add(box((0.2, 0.3, 0.12), round_all=0.04, segments=1), (0, 1.07, -2.03), GOLD)
    p.add(box((0.14, 0.14, 0.08)), (0, 1.07, -2.08), GEM_RED)
    return p


def make_crown():
    p = Piece("Crown")
    z = -1.5
    p.add(box((1.16, 0.3, 1.16), round_axis="y", round_axis_by=0.2), (0, 1.02, z), GOLD)
    p.add(box((0.9, 0.3, 0.9), round_all=0.12), (0, 1.2, z), CAPE_RED)  # the cushion inside
    for dx in (-0.42, 0.42):
        for dz in (-0.42, 0.42):
            p.add(box((0.26, 0.42, 0.26), round_all=0.06, segments=1), (dx, 1.36, z + dz), GOLD)
            p.add(ball(0.09, detail=1), (dx, 1.62, z + dz), GOLD)
    for dx, dz in ((0, -0.45), (0, 0.45), (-0.45, 0), (0.45, 0)):
        p.add(box((0.24, 0.58, 0.24), round_all=0.06, segments=1), (dx, 1.44, z + dz), GOLD)
        p.add(ball(0.1, detail=1), (dx, 1.78, z + dz), GOLD)
    p.add(box((0.24, 0.22, 0.1), round_all=0.03, segments=1), (0, 1.02, z - 0.6), GEM_RED)
    p.both_sides(lambda: box((0.1, 0.2, 0.22), round_all=0.03, segments=1), (0.6, 1.02, z), GEM_BLUE)
    return p


def make_emperor_gear():
    p = Piece("EmperorGear")
    cape(p, FUR, GOLD, top_y=1.0)
    # a wide gold collar with gems
    p.add(box((2.22, 2.04, 0.44), round_axis="z", round_axis_by=0.4), (0, 0.05, -0.7), GOLD)
    p.add(box((0.24, 0.08, 0.24), round_all=0.03, segments=1), (0, 1.09, -0.7), GEM_RED)
    for y in (-0.3, 0.4):
        p.both_sides(lambda: box((0.08, 0.22, 0.22), round_all=0.03, segments=1), (1.12, y, -0.7), GEM_BLUE)
    # gold shoulder plates where the cape is pinned
    p.both_sides(lambda: box((0.5, 0.2, 0.6), round_all=0.08), (0.78, 1.1, -0.2), GOLD)
    return p


def make_builder_gear():
    p = Piece("BuilderGear")
    z = -1.5
    # a hard hat: dome, a brim that sticks out at the front, a ridge along the top, a white badge
    p.add(box((1.62, 0.6, 1.42), round_all=0.26, segments=3), (0, 1.0, z), HAT_ORANGE)
    p.add(box((1.92, 0.13, 1.84), round_axis="y", round_axis_by=0.42), (0, 0.76, z - 0.14), HAT_ORANGE_DARK)
    p.add(box((0.34, 0.16, 1.2), round_all=0.07), (0, 1.33, z), HAT_ORANGE_LIGHT)
    p.add(box((0.38, 0.27, 0.08), round_all=0.03, segments=1), (0, 1.0, z - 0.72), WHITE)
    # a tool belt between the stripes, with a brass buckle on top
    p.add(box((2.06, 1.96, 0.32), round_axis="z", round_axis_by=0.35), (0, 0, 0.5), LEATHER)
    p.add(box((0.4, 0.1, 0.4), round_all=0.03, segments=1), (0, 0.99, 0.5), BRASS)
    # a hammer carried on the right
    p.add(box((0.15, 1.3, 0.15), round_all=0.04, segments=1), (1.14, -0.05, -0.42), WOOD)
    p.add(box((0.38, 0.38, 0.84), round_all=0.08), (1.14, 0.68, -0.42), DARK_STEEL)
    p.add(box((0.32, 0.32, 0.12), round_all=0.04, segments=1), (1.14, 0.68, -0.88), STEEL)
    return p


def make_explorer_gear():
    p = Piece("ExplorerGear")
    z = -1.5
    # a safari hat: a wide brim, a round top, a leather band
    p.add(box((2.12, 0.12, 2.02), round_axis="y", round_axis_by=0.6, axis_segments=4), (0, 0.76, z - 0.05), KHAKI_DARK)
    p.add(box((1.5, 0.62, 1.34), round_all=0.3, segments=3), (0, 1.04, z), KHAKI)
    p.add(box((1.56, 0.17, 1.4), round_axis="y", round_axis_by=0.3), (0, 0.9, z), LEATHER)
    p.add(ball(0.13, detail=1), (0, 1.38, z), KHAKI_DARK)
    # a brass spyglass on the right
    p.add(tube(0.15, 0.95, "z", 14), (1.15, 0.05, -0.15), BRASS)
    p.add(tube(0.21, 0.6, "z", 14), (1.15, 0.05, -0.85), LEATHER)
    p.add(tube(0.24, 0.1, "z", 14), (1.15, 0.05, -1.17), BRASS)
    p.add(tube(0.17, 0.05, "z", 14), (1.15, 0.05, -1.23), GLASS)
    # a rolled map on the back, tied with a red ribbon
    p.add(tube(0.2, 1.3, "x", 12), (0, 1.12, 1.05), PAPER)
    p.add(box((0.17, 0.46, 0.46), round_all=0.05, segments=1), (0, 1.12, 1.05), RIBBON)
    return p


def make_knight_gear():
    p = Piece("KnightGear")
    z = -1.5
    # a bright helmet with gold trim, cheek plates and a red plume that sweeps back
    p.add(box((1.8, 0.66, 1.54), round_all=0.2, segments=2), (0, 0.86, z), SILVER)
    p.add(box((1.88, 0.13, 1.62), round_axis="y", round_axis_by=0.36), (0, 0.56, z), GOLD)
    p.add(box((0.16, 0.5, 0.08), round_all=0.03, segments=1), (0, 0.3, -2.25), SILVER)
    p.both_sides(lambda: box((0.1, 0.52, 0.74), round_all=0.04, segments=1), (0.91, 0.25, -1.35), SILVER)
    for y, back, tall in ((1.36, -0.25, 0.44), (1.62, 0.15, 0.46), (1.74, 0.6, 0.4), (1.66, 1.0, 0.34)):
        p.add(box((0.26, tall, 0.52), round_all=0.1), (0, y, z + back), PLUME)
    # a chest plate round the front of the body, with a gold edge
    p.add(box((2.08, 1.98, 0.62), round_axis="z", round_axis_by=0.36), (0, 0, -0.2), SILVER)
    p.add(box((2.12, 2.02, 0.12), round_axis="z", round_axis_by=0.36), (0, 0, 0.12), GOLD)
    # a sword on the right (it points forward) and a shield on the left
    p.add(box((0.1, 0.24, 1.9), round_all=0.03, segments=1), (1.15, -0.1, -0.75), SILVER)
    p.add(box((0.16, 0.66, 0.16), round_all=0.05, segments=1), (1.15, -0.1, 0.28), GOLD)
    p.add(box((0.13, 0.17, 0.46), round_all=0.04, segments=1), (1.15, -0.1, 0.58), LEATHER)
    p.add(ball(0.14, detail=1), (1.15, -0.1, 0.86), GOLD)
    p.add(box((0.12, 1.2, 1.0), round_all=0.06), (-1.1, -0.08, 0.3), SILVER)
    p.add(box((0.14, 0.96, 0.76), round_all=0.05), (-1.12, -0.08, 0.3), PLUME)
    p.add(box((0.16, 0.72, 0.16)), (-1.13, -0.08, 0.3), GOLD)
    p.add(box((0.16, 0.16, 0.5)), (-1.13, 0.06, 0.3), GOLD)
    return p


def make_wizard_gear():
    p = Piece("WizardGear")
    z = -1.5
    # a tall hat that leans back: a round brim, five shrinking blocks, a gold band and bobble
    p.add(tube(1.3, 0.13, "y", 20), (0, 0.9, z), WIZ_DARK)
    y = 0.96
    stars = []
    for wide, tall, lean in ((1.2, 0.44, 0.0), (0.96, 0.42, 0.1), (0.72, 0.4, 0.26), (0.5, 0.36, 0.48), (0.3, 0.3, 0.74)):
        p.add(box((wide, tall + 0.06, wide), round_all=min(0.14, wide * 0.3)), (0, y + tall / 2, z + lean), WIZ)
        stars.append((wide, y + tall / 2, z + lean))
        y += tall
    p.add(box((1.26, 0.17, 1.26), round_axis="y", round_axis_by=0.14), (0, 1.06, z), GOLD)
    p.add(ball(0.17, detail=1), (0, y + 0.08, z + 0.8), STAR)
    # little gold stars on the hat: one on the front, one on each side
    wide, star_y, star_z = stars[1]
    p.add(box((0.24, 0.24, 0.06)), (0, star_y, star_z - wide / 2 - 0.02), STAR, turned(0, 0, 45))
    wide, star_y, star_z = stars[2]
    p.both_sides(lambda: box((0.06, 0.2, 0.2)), (wide / 2 + 0.02, star_y, star_z), STAR, turned(45, 0, 0))
    # a star-trimmed cape with a dark collar
    cape(p, WIZ, STAR)
    p.add(box((2.16, 1.98, 0.38), round_axis="z", round_axis_by=0.38), (0, 0.05, -0.7), WIZ_DARK)
    p.add(box((0.26, 0.08, 0.26)), (0, 1.05, -0.7), STAR, turned(0, 45, 0))
    for x, cape_z in ((-0.5, 0.2), (0.45, 0.75), (-0.2, 1.3)):
        p.add(box((0.2, 0.05, 0.2)), (x, 1.06, cape_z), STAR, turned(0, 45, 0))
    # a wand on the right, with a star on its tip
    p.add(tube(0.055, 1.5, "z", 8), (1.15, 0.0, -0.8), WOOD)
    p.add(box((0.1, 0.4, 0.4), round_all=0.03, segments=1), (1.15, 0.0, -1.7), STAR)
    p.add(box((0.1, 0.4, 0.4), round_all=0.03, segments=1), (1.15, 0.0, -1.7), STAR, turned(45, 0, 0))
    return p


def make_galaxy_gear():
    p = Piece("GalaxyGear")
    # a deep purple cape and collar, sprinkled with stars
    cape(p, SPACE, SPACE_LIGHT)
    p.add(box((2.22, 2.04, 0.44), round_axis="z", round_axis_by=0.4), (0, 0.05, -0.7), SPACE_LIGHT)
    for x, cape_z, color in ((-0.6, -0.1, STAR_CYAN), (0.5, 0.3, WHITE), (-0.15, 0.8, STAR_PINK), (0.62, 1.25, STAR_CYAN),
                             (-0.62, 1.4, WHITE)):
        p.add(box((0.2, 0.05, 0.2)), (x, 1.06, cape_z), color, turned(0, 45, 0))
    for side_z, y, color in ((0.0, -0.1, WHITE), (0.7, 0.2, STAR_PINK), (1.35, -0.2, STAR_CYAN)):
        p.both_sides(lambda: box((0.05, 0.18, 0.18)), (1.2, y, side_z), color, turned(45, 0, 0))
    # a band round the head
    p.add(box((1.72, 0.2, 1.47), round_axis="y", round_axis_by=0.34), (0, 0.7, -1.5), SPACE_LIGHT)
    return p


def make_galaxy_glow():
    """White: the game makes these glow. A ring round the whole bee, a big star over its head, little stars."""
    p = Piece("GalaxyGlow")
    count = 30
    tip = math.degrees(math.atan(0.16))  # the ring tips forward: low at the face, high at the tail
    for step in range(count):
        angle = 2 * math.pi * step / count
        x = 2.05 * math.sin(angle)
        z = 0.25 + 3.05 * math.cos(angle)
        y = -0.12 + 0.16 * (z - 0.25)
        along_x, along_z = 2.05 * math.cos(angle), -3.05 * math.sin(angle)  # the way the ring runs here
        yaw = math.degrees(math.atan2(-along_z, along_x))
        p.add(box((0.6, 0.07, 0.3), round_all=0.03, segments=1), (x, y, z), WHITE, turned(-tip, yaw, 0))
    # the big star: two squares, one turned
    p.add(box((0.62, 0.62, 0.14), round_all=0.04, segments=1), (0, 1.62, -1.5), WHITE)
    p.add(box((0.62, 0.62, 0.14), round_all=0.04, segments=1), (0, 1.62, -1.5), WHITE, turned(0, 0, 45))
    for at in ((1.55, 1.75, -0.7), (-1.7, 1.5, 1.1), (-1.35, 1.95, -1.1), (1.75, 1.3, 1.6)):
        p.add(box((0.22, 0.22, 0.22)), at, WHITE, turned(45, 45, 0))
    return p


OLD_MAKERS = [make_body, make_details, make_wing, make_scout_gear, make_guard_gear, make_royal_gear, make_crown,
              make_emperor_gear]
NEW_MAKERS = [make_builder_gear, make_explorer_gear, make_knight_gear, make_wizard_gear, make_galaxy_gear,
              make_galaxy_glow]
# the three Halloween bees (2026-10-12): their outfits live in halloween_gear.py, because the
# file Roblox Studio imports them from is written by halloween.py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import types  # noqa: E402

import halloween_gear  # noqa: E402

KIT = types.SimpleNamespace(Piece=Piece, box=box, ball=ball, tube=tube, turned=turned, rgb=rgb)
HALLOWEEN_MAKERS = [lambda maker=maker: maker(KIT) for maker in halloween_gear.MAKERS]
HALLOWEEN_BEES = [(key, name, rgb(*color), gear, size, glowing) for key, name, color, gear, size, glowing in halloween_gear.BEES]
GLOW_COLORS = {"PumpkinGlow": rgb(*halloween_gear.GLOW_COLOR)}  # (pieces not listed glow in GLOW)

MAKERS = OLD_MAKERS + NEW_MAKERS + HALLOWEEN_MAKERS
NEW_PIECE_NAMES = ["BuilderGear", "ExplorerGear", "KnightGear", "WizardGear", "GalaxyGear", "GalaxyGlow",
                   "BatGear", "GhostGear", "PumpkinKingGear", "PumpkinGlow"]


# ---- scene helpers ------------------------------------------------------------------------------

def new_collection(name):
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    return collection


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


def for_blender(color):
    """Our colours are written the way screens show them; Blender's paint wants the "linear" kind."""
    return tuple(((c + 0.055) / 1.055) ** 2.4 if c > 0.04045 else c / 12.92 for c in color[:3]) + (1.0,)


def plain_material(name, color, alpha=1.0):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    shader = material.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = for_blender(color)
    shader.inputs["Roughness"].default_value = 0.45
    if alpha < 1:
        shader.inputs["Alpha"].default_value = alpha
        for setting, value in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
            try:
                setattr(material, setting, value)
            except Exception:
                pass
    return material


def pick_engine(scene):
    for engine in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            scene.render.engine = engine
            return engine
        except Exception:
            continue
    return scene.render.engine


def build_pieces():
    pieces = {}
    for maker in MAKERS:
        piece = maker()
        pieces[piece.name] = piece
    return pieces


def bee_space(matrix):
    """A bee-space move/turn, written for Blender."""
    return TO_BLENDER @ matrix @ TO_BLENDER.inverted()


def glow_material(color, strength=0.9):
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


def place_bee(pieces_objects, collection, bee, where, materials):
    key, _, color, gear, size, glowing = bee
    root = where @ Matrix.Scale(size, 4)
    made = []

    def put(name, material, extra=None):
        source = pieces_objects[name]
        obj = bpy.data.objects.new(key + "_" + name, source.data.copy())
        obj.data.materials.append(material)
        collection.objects.link(obj)
        obj.matrix_world = bee_space(root @ (extra or Matrix.Identity(4)))
        finish(obj)
        made.append(obj)

    put("Body", plain_material("Body_" + key, color))
    put("Details", materials["paint"])
    for wing_place in WING_PLACES:
        put("Wing", materials["wing"], wing_place)
    for name in gear:
        put(name, materials["paint"])
    for name in glowing:
        put(name, glow_material(GLOW_COLORS.get(name, GLOW)))
    return made


def setup_render(scene, width, height, samples=48):
    engine = pick_engine(scene)
    scene.render.resolution_x = width
    scene.render.resolution_y = height
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
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
    background.inputs["Color"].default_value = (1, 1, 1, 1)
    background.inputs["Strength"].default_value = 0.42
    scene.world = world
    return engine


def add_sun(collection, toward_bee_space, strength, angle_degrees=12):
    data = bpy.data.lights.new("Sun", "SUN")
    data.energy = strength
    data.angle = math.radians(angle_degrees)
    sun = bpy.data.objects.new("Sun", data)
    collection.objects.link(sun)
    direction = (TO_BLENDER.to_3x3() @ Vector(toward_bee_space)).normalized()
    sun.rotation_euler = (-direction).to_track_quat("-Z", "Y").to_euler()
    return sun


def add_camera(collection, scene, eye_bee_space, look_at_bee_space, width_in_studs):
    data = bpy.data.cameras.new("Camera")
    data.type = "ORTHO"
    data.ortho_scale = width_in_studs
    data.clip_end = 500
    camera = bpy.data.objects.new("Camera", data)
    collection.objects.link(camera)
    eye = TO_BLENDER.to_3x3() @ Vector(eye_bee_space)
    target = TO_BLENDER.to_3x3() @ Vector(look_at_bee_space)
    camera.location = eye
    camera.rotation_euler = (target - eye).to_track_quat("-Z", "Y").to_euler()
    scene.camera = camera
    return camera


# ---- what to do ---------------------------------------------------------------------------------

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
pieces = build_pieces()

library = new_collection("Pieces")  # one object per piece, all standing on the same spot
piece_objects = {name: piece.to_object(library) for name, piece in pieces.items()}
for name, piece in pieces.items():
    low, high = piece.bounds()
    triangles = sum(len(face) - 2 for face in piece.faces)
    say("piece", name, "triangles", triangles, "size", [round(high[i] - low[i], 3) for i in range(3)])

if "preview" in MODES:
    stage = new_collection("Stage")
    materials = {"paint": paint_material(), "wing": plain_material("Wing", rgb(190, 228, 255), alpha=0.7)}
    library.hide_render = True
    spacing = 4.6
    for index, bee in enumerate(BEES):
        x = ((len(BEES) - 1) / 2 - index) * spacing  # the camera looks from the front, so +x is on the left
        place_bee(piece_objects, stage, bee, Matrix.Translation((x, 0, 0)) @ turned(0, 34, 0), materials)
    # a soft floor so the bees cast a shadow
    floor_mesh = bpy.data.meshes.new("Floor")
    floor_mesh.from_pydata([(-60, -60, -1.27), (60, -60, -1.27), (60, 60, -1.27), (-60, 60, -1.27)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("Floor", floor_mesh)
    floor.data.materials.append(plain_material("Floor", rgb(255, 226, 150)))
    stage.objects.link(floor)
    add_sun(stage, (-0.45, 0.8, -0.4), 1.9)
    engine = setup_render(scene, 1800, 760)
    scene.render.film_transparent = False
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = for_blender(rgb(255, 232, 170))
    add_camera(stage, scene, (0, 9, -30), (0, 0.15, 0), 25.5)
    scene.render.filepath = os.path.join(OUT, "bees-preview.png")
    bpy.ops.render.render(write_still=True)
    say("preview drawn with", engine, scene.render.filepath)

if "newpreview" in MODES:
    # the five new bees in front, the five first bees behind them
    stage = new_collection("NewStage")
    materials = {"paint": paint_material(), "wing": plain_material("Wing", rgb(190, 228, 255), alpha=0.7)}
    library.hide_render = True
    spacing = 4.9
    for row, bees in ((0, NEW_BEES), (1, BEES)):
        for index, bee in enumerate(bees):
            x = ((len(bees) - 1) / 2 - index) * spacing  # the camera looks from the front, so +x is on the left
            place_bee(piece_objects, stage, bee, Matrix.Translation((x, 0, row * 12.0)) @ turned(0, 34, 0), materials)
    floor_mesh = bpy.data.meshes.new("Floor")
    floor_mesh.from_pydata([(-80, -80, -1.27), (80, -80, -1.27), (80, 80, -1.27), (-80, 80, -1.27)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("Floor", floor_mesh)
    floor.data.materials.append(plain_material("Floor", rgb(255, 226, 150)))
    stage.objects.link(floor)
    add_sun(stage, (-0.45, 0.8, -0.4), 1.9)
    engine = setup_render(scene, 1800, 1150)
    scene.render.film_transparent = False
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = for_blender(rgb(255, 232, 170))
    add_camera(stage, scene, (0, 20, -30), (0, 0.6, 5.2), 27.5)
    scene.render.filepath = os.path.join(OUT, "newbees-preview.png")
    bpy.ops.render.render(write_still=True)
    say("new bees preview drawn with", engine, scene.render.filepath)
    stage.hide_render = True

if "hwpreview" in MODES:
    # the three Halloween bees in a row, on a dark floor
    stage = new_collection("HalloweenStage")
    materials = {"paint": paint_material(), "wing": plain_material("Wing", rgb(190, 228, 255), alpha=0.7)}
    library.hide_render = True
    spacing = 6.2
    for index, bee in enumerate(HALLOWEEN_BEES):
        x = ((len(HALLOWEEN_BEES) - 1) / 2 - index) * spacing  # the camera looks from the front, so +x is on the left
        place_bee(piece_objects, stage, bee, Matrix.Translation((x, 0.35 * (bee[4] - 1) * 4, 0)) @ turned(0, 34, 0), materials)
    floor_mesh = bpy.data.meshes.new("Floor")
    floor_mesh.from_pydata([(-80, -80, -1.27), (80, -80, -1.27), (80, 80, -1.27), (-80, 80, -1.27)], [], [(0, 1, 2, 3)])
    floor = bpy.data.objects.new("Floor", floor_mesh)
    floor.data.materials.append(plain_material("Floor", rgb(150, 110, 200)))
    stage.objects.link(floor)
    add_sun(stage, (-0.45, 0.8, -0.4), 1.9)
    engine = setup_render(scene, 1800, 820)
    scene.render.film_transparent = False
    scene.world.node_tree.nodes["Background"].inputs["Color"].default_value = for_blender(rgb(176, 140, 222))
    add_camera(stage, scene, (0, 9, -30), (0, 0.5, 0), 21.5)
    scene.render.filepath = os.path.join(OUT, "halloween-bees-preview.png")
    bpy.ops.render.render(write_still=True)
    say("halloween bees preview drawn with", engine, scene.render.filepath)
    stage.hide_render = True

if "hwicons" in MODES:
    # menu pictures of the three Halloween bees (the same view as the other bees' pictures).
    # Every bee is drawn at size 1 here, so the big one is not cut off.
    library.hide_render = True
    for collection in list(scene.collection.children):
        if collection.name in ("Stage", "NewStage", "HalloweenStage"):
            collection.hide_render = True
    materials = {"paint": paint_material(), "wing": plain_material("Wing", rgb(190, 228, 255), alpha=0.72)}
    studio = new_collection("HalloweenIconStudio")
    add_sun(studio, (0.5, 0.75, -0.45), 1.6)
    engine = setup_render(scene, 1024, 1024, samples=64)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.56
    add_camera(studio, scene, (0, 8.6, -30), (0, 0.55, 0.05), 8.2)
    for bee in HALLOWEEN_BEES:
        shelf = new_collection("Icon_" + bee[0])
        place_bee(piece_objects, shelf, bee[:4] + (1.0,) + bee[5:], turned(0, -40, 0), materials)
        scene.render.filepath = os.path.join(OUT, "icon-Bee" + bee[0] + ".png")
        bpy.ops.render.render(write_still=True)
        shelf.hide_render = True
        say("icon drawn", bee[0])
    studio.hide_render = True

if "icons" in MODES:
    # one picture per bee for the menus: see-through background, same view for every bee
    library.hide_render = True
    for collection in list(scene.collection.children):
        if collection.name in ("Stage", "NewStage"):
            collection.hide_render = True
    materials = {"paint": paint_material(), "wing": plain_material("Wing", rgb(190, 228, 255), alpha=0.72)}
    studio = new_collection("IconStudio")
    add_sun(studio, (0.5, 0.75, -0.45), 1.6)
    engine = setup_render(scene, 1024, 1024, samples=64)
    scene.world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.56
    add_camera(studio, scene, (0, 8.6, -30), (0, 0.32, 0.05), 6.6)
    for bee in (NEW_BEES if "newonly" in MODES else BEES + NEW_BEES):
        shelf = new_collection("Icon_" + bee[0])
        place_bee(piece_objects, shelf, bee, turned(0, -40, 0), materials)
        scene.render.filepath = os.path.join(OUT, "icon-Bee" + bee[0] + ".png")
        bpy.ops.render.render(write_still=True)
        shelf.hide_render = True
        say("icon drawn", bee[0])

if "export" in MODES:
    # the file Roblox Studio imports: every piece once, all standing on the same spot,
    # plus four tiny marker cubes so the game can work out size and direction afterwards
    marks = new_collection("Marks")
    for name, at in (("MarkOrigin", (0, -8, 0)), ("MarkRight", (10, -8, 0)), ("MarkUp", (0, 2, 0)), ("MarkBack", (0, -8, 10))):
        mark = Piece(name)
        mark.add(box((0.5, 0.5, 0.5)), at, WHITE)
        mark.to_object(marks)
    for obj in scene.objects:
        obj.select_set(False)
    chosen = [obj for obj in library.objects if obj.name not in NEW_PIECE_NAMES] + list(marks.objects)
    for obj in chosen:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = chosen[0]
    target = os.path.join(OUT, "BeeEmpire-bees.fbx")
    bpy.ops.export_scene.fbx(filepath=target, use_selection=True, object_types={"MESH"}, use_mesh_modifiers=True,
                             mesh_smooth_type="OFF", use_triangles=False, colors_type="SRGB", axis_forward="-Z",
                             axis_up="Y", apply_scale_options="FBX_SCALE_ALL", bake_anim=False,
                             add_leaf_bones=False)
    notes = {}
    for name, piece in pieces.items():
        low, high = piece.bounds()
        notes[name] = {"low": [round(v, 4) for v in low], "high": [round(v, 4) for v in high]}
    with open(os.path.join(OUT, "BeeEmpire-bees.json"), "w") as handle:
        json.dump({"pivot": [0, 0, 0.3], "pieces": notes}, handle, indent=1)
    say("exported", target, os.path.getsize(target), "bytes,", len(chosen), "objects")

if "exportnew" in MODES:
    # only the outfits of the second set of bees (the game already has everything else),
    # with the same four marker cubes
    marks = new_collection("NewMarks")
    for name, at in (("MarkOrigin", (0, -8, 0)), ("MarkRight", (10, -8, 0)), ("MarkUp", (0, 2, 0)), ("MarkBack", (0, -8, 10))):
        mark = Piece(name)
        mark.add(box((0.5, 0.5, 0.5)), at, WHITE)
        mark.to_object(marks)
    for obj in scene.objects:
        obj.select_set(False)
    library.hide_render = False
    chosen = [obj for obj in library.objects if obj.name in NEW_PIECE_NAMES] + list(marks.objects)
    for obj in chosen:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = chosen[0]
    target = os.path.join(OUT, "BeeEmpire-newbees.fbx")
    bpy.ops.export_scene.fbx(filepath=target, use_selection=True, object_types={"MESH"}, use_mesh_modifiers=True,
                             mesh_smooth_type="OFF", use_triangles=False, colors_type="SRGB", axis_forward="-Z",
                             axis_up="Y", apply_scale_options="FBX_SCALE_ALL", bake_anim=False,
                             add_leaf_bones=False)
    say("exported", target, os.path.getsize(target), "bytes,", len(chosen), "objects:", [obj.name for obj in chosen])

say("done")
