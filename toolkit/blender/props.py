# Build A Bee Empire - nature pieces for the map, made in Blender (chunky toy style).
#
# Run:  blender --background --factory-startup --python props.py -- <output folder> [preview] [export]
#
# Each piece stands on the ground at (0, 0, 0) unless its note says otherwise.
# White shapes are tinted by the game (flower petals come in many colours).

import math
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Matrix  # noqa: E402
from toykit import (Piece, WHITE, add_camera, add_floor, add_sun, ball, box, export_for_roblox, for_blender,  # noqa: E402
                    new_collection, paint_material, put, rgb, say, setup_render, start, tint_material, tube, turned)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
MODES = set(ARGS[1:]) or {"preview"}
os.makedirs(OUT, exist_ok=True)

# the map's own colours (from the game's PlotBuilder)
GRASS = rgb(70, 200, 60)
STEM = rgb(60, 160, 65)
TUFT = rgb(40, 130, 60)
TUFT_LIGHT = rgb(70, 170, 70)
TRUNK = rgb(120, 70, 55)
TRUNK_DARK = rgb(96, 56, 44)
TRUNK_LIGHT = rgb(150, 96, 72)
LEAF = rgb(45, 120, 55)
LEAF_LIGHT = rgb(80, 155, 70)
FENCE_POST = rgb(90, 60, 45)
FENCE_RAIL = rgb(135, 95, 65)
GOLD = rgb(255, 200, 40)
BLOSSOM_PINK = rgb(255, 160, 196)
BLOSSOM_WHITE = rgb(255, 250, 238)
PETAL_SHADE = rgb(222, 222, 222)  # tinted petals that should come out a little darker
SEED = rgb(205, 205, 205)
ROCK = rgb(152, 156, 166)
ROCK_DARK = rgb(118, 122, 134)
MOSS = rgb(92, 172, 82)
CREAM = rgb(255, 240, 212)
MUSHROOM_RED = rgb(232, 62, 62)

GARDEN_HEAD = 5.0  # the garden-flower pieces are modelled for a head this many studs wide
R = 0.45  # how round the edges are: 1 = soft and pillowy, 0 = sharp bricks (the owner asked for "a little sharper")


def blossom(piece, at, color, size=0.9):
    """A small flower stuck on a tree or bush: a soft cube with a yellow dot showing on every side."""
    piece.add(box((size, size, size), round_all=R * size * 0.33), at, color)
    long, thin = size * 1.1, size * 0.36
    for bar in ((long, thin, thin), (thin, long, thin), (thin, thin, long)):
        piece.add(box(bar), at, GOLD)


def make_tree():
    p = Piece("Tree")
    p.add(box((3, 10, 3), round_all=R * 0.5, taper=0.8), (0, 5, 0), TRUNK)
    for x, z in ((1.25, 1.25), (-1.25, 1.25), (1.25, -1.25), (-1.25, -1.25)):  # roots
        p.add(box((1.5, 1.3, 1.5), round_all=R * 0.4), (x, 0.6, z), TRUNK_DARK)
    p.add(box((1.0, 1.0, 0.25), round_all=R * 0.1, segments=1), (0.2, 4.4, -1.38), TRUNK_LIGHT)  # knots
    p.add(box((0.25, 0.8, 0.8), round_all=R * 0.1, segments=1), (1.36, 6.6, 0.1), TRUNK_LIGHT)
    # the leaves: big soft blocks
    p.add(box((11, 7, 11), round_all=R * 2.2, segments=2), (0, 13, 0), LEAF)
    p.add(box((7, 5, 7), round_all=R * 1.6, segments=2), (3, 18.5, 2), LEAF_LIGHT)
    p.add(box((6, 4.4, 6), round_all=R * 1.4, segments=2), (-5, 14.2, -4), LEAF_LIGHT)
    p.add(box((5, 3.6, 5), round_all=R * 1.2, segments=2), (-2.8, 17.3, 2.6), LEAF)
    p.add(box((4.6, 3.4, 4.6), round_all=R * 1.1, segments=2), (4.6, 11.9, -4.3), LEAF_LIGHT)
    # blossom for the bees
    spots = [((-2.5, 14.6, -5.55), BLOSSOM_PINK), ((1.2, 11.2, -5.55), BLOSSOM_WHITE), ((5.55, 14.2, 1.6), BLOSSOM_PINK),
             ((5.55, 11.6, 2.6), BLOSSOM_WHITE), ((-5.55, 11.6, 2.6), BLOSSOM_PINK), ((2.2, 13.0, 5.55), BLOSSOM_WHITE),
             ((-3.0, 14.9, 5.55), BLOSSOM_PINK), ((3.2, 21.05, 1.2), BLOSSOM_WHITE), ((6.55, 18.9, 2.8), BLOSSOM_PINK),
             ((1.6, 17.9, -1.55), BLOSSOM_PINK), ((-8.05, 14.6, -4.4), BLOSSOM_WHITE), ((-5.2, 16.45, -3.4), BLOSSOM_PINK),
             ((-2.4, 19.15, 3.0), BLOSSOM_WHITE)]
    for at, color in spots:
        blossom(p, at, color)
    return p


def make_flower_stem():
    """The lawn flower without its petals: stem, two leaves and the yellow middle."""
    p = Piece("FlowerStem")
    p.add(box((0.3, 2.0, 0.3), round_all=R * 0.1, segments=1), (0, 1.0, 0), STEM)
    p.add(box((0.9, 0.14, 0.46), round_axis="y", round_axis_by=R * 0.2), (0.5, 0.78, 0), STEM, turned(0, 0, 22))
    p.add(box((0.74, 0.12, 0.4), round_axis="y", round_axis_by=R * 0.18), (-0.43, 1.15, 0.04), STEM, turned(0, 0, -26))
    p.add(box((0.56, 0.4, 0.56), round_all=R * 0.16), (0, 2.32, 0), GOLD)
    return p


def make_flower_blossom():
    """Five petals. White, so the game can tint them any colour."""
    p = Piece("FlowerBlossom")
    p.add(tube(0.4, 0.16, "y", 12), (0, 2.02, 0), PETAL_SHADE)
    for step in range(5):
        angle = math.radians(step * 72 + 18)
        at = (math.cos(angle) * 0.56, 2.12, math.sin(angle) * 0.56)
        p.add(box((0.78, 0.26, 0.64), round_all=R * 0.12), at, WHITE, turned(0, -math.degrees(angle), 16))
    return p


def make_grass():
    p = Piece("GrassTuft")
    blades = [  # x, z, height, lean, turn, colour
        (0.0, 0.0, 2.2, 4, 0, TUFT), (0.42, 0.18, 1.6, 16, 20, TUFT_LIGHT), (-0.4, 0.22, 1.4, 18, 160, TUFT),
        (0.12, -0.42, 1.8, 14, 100, TUFT_LIGHT), (-0.2, 0.5, 1.1, 20, 250, TUFT), (0.55, -0.35, 1.0, 22, 60, TUFT),
    ]
    for x, z, height, lean, turn, color in blades:
        p.add(box((0.34, height, 0.34), round_all=R * 0.08, segments=1, taper=0.3), (x, height / 2 - 0.08, z), color,
              turned(0, turn, lean))
    return p


def make_garden_stem():
    """A plain post one stud tall and wide. The game stretches it to each flower's height."""
    p = Piece("GardenStem")
    p.add(box((1, 1, 1), round_axis="y", round_axis_by=R * 0.3), (0, 0.5, 0), STEM)
    return p


def make_garden_leaf():
    """The pair of leaves, modelled around the stem at leaf height (for a 5-stud flower head)."""
    p = Piece("GardenLeaf")
    head = GARDEN_HEAD
    p.both_sides(lambda: box((head * 0.5, 0.4, head * 0.3), round_axis="y", round_axis_by=R * 0.62), (head * 0.32, 0.1, 0), LEAF_LIGHT,
                 lambda side: turned(0, 0, 14 * side))
    p.both_sides(lambda: box((head * 0.36, 0.12, 0.16)), (head * 0.3, 0.3, 0), STEM, lambda side: turned(0, 0, 14 * side))
    return p


def make_garden_petals():
    """Eight puffy petals, modelled around the top of the stem (for a 5-stud head). White, tinted in the game."""
    p = Piece("GardenPetals")
    petal = GARDEN_HEAD * 0.36
    for x, z in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        p.add(box((petal, petal * 0.6, petal), round_all=R * 0.45, segments=2), (x * petal, 0, z * petal), PETAL_SHADE)
    for x, z in ((1, 1), (-1, 1), (1, -1), (-1, -1)):
        p.add(box((petal * 0.8, petal * 0.45, petal * 0.8), round_all=R * 0.36, segments=2), (x * petal * 0.9, -petal * 0.08, z * petal * 0.9), WHITE)
    return p


def make_garden_middle():
    """The middle of a garden flower (where the bees land). White, tinted in the game."""
    p = Piece("GardenMiddle")
    petal = GARDEN_HEAD * 0.36
    p.add(box((petal, petal * 0.8, petal), round_all=R * 0.5, segments=2), (0, petal * 0.15, 0), WHITE)
    for x in (-0.42, 0, 0.42):
        for z in (-0.42, 0, 0.42):
            p.add(ball(0.17, (1, 0.7, 1), detail=1), (x, petal * 0.55 + 0.02, z), SEED)
    return p


def make_fence_post():
    p = Piece("FencePost")
    p.add(box((1, 3.0, 1), round_all=R * 0.2), (0, 1.5, 0), FENCE_POST)
    p.add(box((1.24, 0.3, 1.24), round_all=R * 0.1, segments=1), (0, 3.05, 0), FENCE_RAIL)
    p.add(box((0.64, 0.34, 0.64), round_all=R * 0.14), (0, 3.34, 0), FENCE_POST)
    return p


def make_fence_rail():
    """One stud long (along z), centred. The game stretches it between two posts."""
    p = Piece("FenceRail")
    p.add(box((0.4, 0.45, 1), round_axis="z", round_axis_by=R * 0.14), (0, 0, 0), FENCE_RAIL)
    return p


def make_bush():
    p = Piece("Bush")
    p.add(box((3.4, 2.4, 3.0), round_all=R * 1.0, segments=2), (0, 1.2, 0), LEAF)
    p.add(box((2.4, 1.9, 2.4), round_all=R * 0.8, segments=2), (1.7, 0.95, 0.6), LEAF_LIGHT)
    p.add(box((2.2, 1.7, 2.2), round_all=R * 0.7, segments=2), (-1.6, 0.85, -0.5), LEAF_LIGHT)
    p.add(box((1.9, 1.3, 1.9), round_all=R * 0.6, segments=2), (-0.3, 2.3, 0.2), LEAF_LIGHT)
    for at, color in (((0.6, 1.7, -1.52), BLOSSOM_PINK), ((-1.9, 1.2, -1.62), BLOSSOM_WHITE), ((2.3, 1.3, -0.62), BLOSSOM_PINK),
                      ((-0.6, 2.97, 0.1), BLOSSOM_WHITE), ((1.72, 1.6, 1.3), BLOSSOM_PINK), ((-2.72, 1.0, -0.2), BLOSSOM_PINK)):
        blossom(p, at, color, size=0.56)
    return p


def make_rock():
    p = Piece("Rock")
    p.add(box((3.2, 2.0, 2.6), round_all=R * 0.55), (0, 0.95, 0), ROCK, turned(0, 18, 4))
    p.add(box((1.8, 1.2, 1.6), round_all=R * 0.4), (2.0, 0.55, 0.9), ROCK_DARK, turned(0, -25, -6))
    p.add(box((0.9, 0.6, 0.8), round_all=R * 0.25), (-1.9, 0.28, 1.0), ROCK, turned(0, 40, 0))
    p.add(box((1.7, 0.26, 1.4), round_all=R * 0.12), (-0.2, 1.98, -0.1), MOSS, turned(0, 18, 4))
    return p


def make_mushroom():
    p = Piece("Mushroom")

    def one(x, z, size):
        p.add(box((0.6 * size, 1.0 * size, 0.6 * size), round_all=R * 0.16 * size), (x, 0.5 * size, z), CREAM)
        p.add(box((1.5 * size, 0.14 * size, 1.5 * size), round_all=R * 0.06 * size, segments=1), (x, 0.98 * size, z), CREAM)
        p.add(box((1.9 * size, 0.62 * size, 1.9 * size), round_all=R * 0.3 * size), (x, 1.34 * size, z), MUSHROOM_RED)
        p.add(box((1.25 * size, 0.34 * size, 1.25 * size), round_all=R * 0.2 * size), (x, 1.78 * size, z), MUSHROOM_RED)
        for dx, dy, dz in ((0.2, 1.96, 0.1), (-0.35, 1.96, -0.3), (0.62, 1.66, -0.5), (-0.66, 1.66, 0.45), (0.3, 1.66, 0.66), (-0.5, 1.66, -0.7)):
            p.add(box((0.3 * size, 0.08 * size, 0.3 * size)), (x + dx * size, dy * size, z + dz * size), WHITE)
        for dx, dz in ((0.955, 0.3), (-0.955, -0.2), (0.25, -0.955), (-0.3, 0.955)):
            wide = (0.08 * size, 0.26 * size, 0.3 * size) if abs(dx) > abs(dz) else (0.3 * size, 0.26 * size, 0.08 * size)
            p.add(box(wide), (x + dx * size, 1.36 * size, z + dz * size), WHITE)

    one(0, 0, 1.0)
    one(1.15, 0.5, 0.6)
    return p


MAKERS = [make_tree, make_flower_stem, make_flower_blossom, make_grass, make_garden_stem, make_garden_leaf,
          make_garden_petals, make_garden_middle, make_fence_post, make_fence_rail, make_bush, make_rock, make_mushroom]

scene = start()
pieces = {}
for maker in MAKERS:
    piece = maker()
    pieces[piece.name] = piece
library = new_collection("Pieces")
objects = {name: piece.to_object(library) for name, piece in pieces.items()}
for name, piece in pieces.items():
    low, high = piece.bounds()
    say("piece", name, "triangles", piece.triangles(), "size", [round(high[i] - low[i], 2) for i in range(3)])


def move(x, y, z, turn=0.0, size=1.0):
    return Matrix.Translation((x, y, z)) @ turned(0, turn, 0) @ Matrix.Scale(size, 4)


if "preview" in MODES:
    library.hide_render = True
    stage = new_collection("Stage")
    paint = paint_material()
    tints = {}

    def tint(color):
        key = tuple(round(c, 3) for c in color)
        if key not in tints:
            tints[key] = tint_material(color)
        return tints[key]

    def lawn_flower(x, z, color, size=1.0, turn=0.0):
        put(objects["FlowerStem"], stage, move(x, 0, z, turn, size), paint)
        put(objects["FlowerBlossom"], stage, move(x, 0, z, turn, size), tint(color))

    def garden_flower(x, z, head, stem, petal_color, middle_color):
        width = max(0.7, head * 0.16)
        put(objects["GardenStem"], stage, Matrix.Translation((x, 0, z)) @ Matrix.Diagonal((width, stem, width, 1)), paint)
        put(objects["GardenLeaf"], stage, move(x, stem * 0.4, z, 0, head / GARDEN_HEAD), paint)
        put(objects["GardenPetals"], stage, move(x, stem, z, 0, head / GARDEN_HEAD), tint(petal_color))
        put(objects["GardenMiddle"], stage, move(x, stem, z, 0, head / GARDEN_HEAD), tint(middle_color))

    put(objects["Tree"], stage, move(-18, 0, 8, 25), paint)
    put(objects["Bush"], stage, move(-6.5, 0, 6, -15), paint)
    put(objects["Bush"], stage, move(15.5, 0, 9, 40, 1.2), paint)
    put(objects["Rock"], stage, move(-9.5, 0, -3.5, 10), paint)
    put(objects["Rock"], stage, move(19, 0, -2, 200, 0.8), paint)
    put(objects["Mushroom"], stage, move(-4.5, 0, -4.5, 0, 1.2), paint)
    put(objects["Mushroom"], stage, move(12.5, 0, -6, 120), paint)
    colors = [rgb(255, 255, 255), rgb(255, 165, 60), rgb(255, 120, 170), rgb(110, 180, 255), rgb(190, 120, 255), rgb(255, 90, 90)]
    for index, color in enumerate(colors):
        lawn_flower(-13 + index * 2.6, -8.5 + (index % 2) * 1.2, color, 1.0, index * 40)
    for x, z, size, turn in ((-15, -5, 1, 0), (-1.5, -8, 1.2, 80), (4.5, -9, 0.9, 200), (9, -3.5, 1.1, 30), (16, -7.5, 1, 140),
                             (-11, 2, 1.1, 60), (21, 3.5, 1, 300), (-20, -2.5, 0.9, 10)):
        put(objects["GrassTuft"], stage, move(x, 0, z, turn, size), paint)
    garden_flower(0.5, 2.5, 4.6, 5.6, rgb(255, 120, 170), rgb(255, 200, 40))
    garden_flower(6.5, 4.5, 4.2, 4.6, rgb(110, 180, 255), rgb(255, 200, 40))
    garden_flower(3.5, 9.5, 9.0, 13.0, rgb(255, 200, 40), rgb(120, 75, 35))
    garden_flower(11, 1, 3.8, 4.0, rgb(255, 255, 255), rgb(255, 200, 40))
    # a short run of fence
    posts = [(-3 + i * 4.2, -1.2) for i in range(4)]
    for x, z in posts:
        put(objects["FencePost"], stage, move(x, 0, z), paint)
    for (x1, z1), (x2, z2) in zip(posts, posts[1:]):
        for height in (1.3, 2.4):
            middle = Matrix.Translation(((x1 + x2) / 2, height, z1)) @ turned(0, 90, 0) @ Matrix.Diagonal((1, 1, x2 - x1, 1))
            put(objects["FenceRail"], stage, middle, paint)

    add_floor(stage, 0, GRASS)
    add_sun(stage, (-0.5, 0.8, -0.35), 1.9)
    engine = setup_render(scene, 1800, 1000, samples=64, sky=for_blender(rgb(150, 210, 255)), sky_strength=0.55, see_through=False)
    add_camera(stage, scene, (-1, 38, -80), (-1.5, 8.6, 2), 60)
    scene.render.filepath = os.path.join(OUT, "nature-preview.png")
    bpy.ops.render.render(write_still=True)
    say("preview drawn with", engine)

if "export" in MODES:
    export_for_roblox(scene, pieces, objects, os.path.join(OUT, "BeeEmpire-nature.fbx"))

say("done")
