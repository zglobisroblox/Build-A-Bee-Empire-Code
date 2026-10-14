# Build A Bee Empire - the new Flower Garden, made in Blender (chunky toy style).
#
# Run:  blender --background --factory-startup --python garden.py -- <output folder> [lineup] [preview] [export]
#
#   lineup   draws every new flower next to a player-sized figure (garden-flowers.png)
#   preview  draws the whole garden as it will be laid out in the game (garden-preview.png)
#   export   writes BeeEmpire-garden.fbx for Studio's Import 3D, and garden-layout.lua (where everything goes)
#
# Every piece stands on the ground at (0, 0, 0). White shapes are tinted by the game (petals come in
# many colours), so a flower is two pieces: its green "Body" and its white "Petals".
# The front of a piece is the side towards -z.

import math
import os
import random
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Matrix, Vector  # noqa: E402
from toykit import (Piece, WHITE, add_camera, add_floor, add_sun, ball, box, export_for_roblox, for_blender,  # noqa: E402
                    new_collection, paint_material, put, rgb, say, setup_render, start, tint_material, tube, turned)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
MODES = set(ARGS[1:]) or {"lineup"}
os.makedirs(OUT, exist_ok=True)

# the map's own colours
GRASS = rgb(70, 200, 60)
MEADOW = rgb(205, 235, 140)
SOIL = rgb(125, 80, 55)
SOIL_DARK = rgb(95, 60, 45)
CREAM = rgb(235, 215, 175)
STONE = rgb(150, 150, 185)
STEM = rgb(60, 160, 65)
STEM_DARK = rgb(46, 132, 58)
LEAF = rgb(45, 120, 55)
LEAF_LIGHT = rgb(80, 155, 70)
LEAF_BRIGHT = rgb(96, 186, 76)
GOLD = rgb(255, 200, 40)
GOLD_DARK = rgb(232, 160, 24)
ORANGE_GOLD = rgb(255, 165, 30)
SEED = rgb(120, 75, 35)
SEED_DARK = rgb(90, 55, 28)
SEED_LIGHT = rgb(160, 104, 48)
PETAL_SHADE = rgb(222, 222, 222)  # tinted petals that should come out a little darker
POPPY_HEART = rgb(70, 50, 72)
WATER = rgb(80, 170, 255)
WATER_DEEP = rgb(60, 140, 235)
PAD = rgb(70, 170, 90)
PAD_LIGHT = rgb(104, 198, 108)
REED_HEAD = rgb(120, 75, 45)
FROG = rgb(98, 200, 92)
FROG_BELLY = rgb(196, 236, 156)
INK = rgb(35, 30, 30)
FENCE_POST = rgb(90, 60, 45)
FENCE_RAIL = rgb(135, 95, 65)

R = 0.45  # how round the edges are (the same dial as the other map pieces)


def at(x=0.0, y=0.0, z=0.0):
    return Matrix.Translation((x, y, z))


def stick(piece, shape, matrix, color):
    """Adds a shape using one full matrix (move and turn together)."""
    piece.add(shape, (0, 0, 0), color, matrix)


def limb(piece, start_point, end_point, thick, color, round_by=0.2):
    """A straight bar from one point to another (branches and leaf stalks)."""
    a, b = Vector(start_point), Vector(end_point)
    length = (b - a).length
    spin = Vector((0, 1, 0)).rotation_difference((b - a).normalized()).to_matrix().to_4x4()
    stick(piece, box((thick, length + thick * 0.4, thick), round_axis="y", round_axis_by=R * round_by * thick),
          Matrix.Translation((a + b) / 2) @ spin, color)


def slab_petal(long, wide, thick, taper=0.45, soft=0.25, segments=1):
    """A petal that points along its own +y and gets narrower towards the tip."""
    return box((thick, long, wide), round_all=R * soft, segments=segments, taper=taper)


# ---- the small and medium flowers ---------------------------------------------------------------

def make_daisy_body():
    p = Piece("DaisyBody")
    p.add(box((0.6, 6.0, 0.6), round_axis="y", round_axis_by=R * 0.2), (0, 3.0, 0), STEM)
    for side, height in ((1, 2.1), (-1, 2.8)):
        p.add(box((2.6, 0.32, 1.3), round_axis="y", round_axis_by=R * 0.55), (side * 1.45, height, 0), LEAF_LIGHT, turned(0, 0, 20 * side))
        p.add(box((2.1, 0.1, 0.18)), (side * 1.4, height + 0.2, 0), STEM_DARK, turned(0, 0, 20 * side))
    p.add(box((1.9, 0.5, 1.9), round_all=R * 0.3, segments=1), (0, 5.95, 0), STEM)
    p.add(box((2.3, 1.1, 2.3), round_all=R * 0.95, segments=2), (0, 6.55, 0), GOLD)
    for x in (-0.6, 0, 0.6):
        for z in (-0.6, 0, 0.6):
            p.add(ball(0.2, (1, 0.7, 1), detail=1), (x, 7.12, z), GOLD_DARK)
    return p


def make_daisy_petals():
    p = Piece("DaisyPetals")
    for index in range(12):
        m = at(0, 6.25, 0) @ turned(0, index * 30, 0) @ at(2.05, 0, 0) @ turned(0, 0, 12)
        stick(p, box((2.3, 0.34, 0.95), round_all=R * 0.3, segments=1), m, WHITE if index % 2 else PETAL_SHADE)
    return p


def make_tulip_body():
    p = Piece("TulipBody")
    p.add(box((0.5, 5.4, 0.5), round_axis="y", round_axis_by=R * 0.2), (0, 2.7, 0), STEM)
    for x, z, lean_z, lean_x, tall in ((0.6, 0, -15, 0, 4.4), (-0.6, 0.1, 15, 0, 3.8), (0, 0.55, 0, 16, 3.2)):
        stick(p, box((1.0, tall, 0.32), round_all=R * 0.2, segments=1, taper=0.3),
              at(x, tall / 2 - 0.1, z) @ turned(lean_x, 90 if lean_x else 0, lean_z), LEAF_LIGHT)
    p.add(box((0.9, 0.4, 0.9), round_all=R * 0.2, segments=1), (0, 5.45, 0), STEM)
    return p


def make_tulip_petals():
    p = Piece("TulipPetals")
    p.add(box((1.7, 2.3, 1.7), round_all=R * 0.7, segments=2), (0, 6.75, 0), PETAL_SHADE)
    for index in range(4):
        m = at(0, 6.95, 0) @ turned(0, index * 90, 0) @ at(0.9, 0, 0) @ turned(0, 0, -7)
        stick(p, box((0.55, 3.0, 1.75), round_all=R * 0.45, segments=1, taper=0.5), m, WHITE)
    for index in range(4):
        m = at(0, 6.6, 0) @ turned(0, index * 90 + 45, 0) @ at(0.95, 0, 0) @ turned(0, 0, -10)
        stick(p, box((0.45, 2.3, 1.2), round_all=R * 0.35, segments=1, taper=0.5), m, PETAL_SHADE)
    return p


POPPY_HEAD = (0.5, 5.5, 0.0)


def make_poppy_body():
    p = Piece("PoppyBody")
    p.add(box((0.5, 3.1, 0.5), round_axis="y", round_axis_by=R * 0.2), (0, 1.55, 0), STEM)
    limb(p, (0, 2.9, 0), (POPPY_HEAD[0], POPPY_HEAD[1] - 0.2, 0), 0.46, STEM)
    for side, height in ((1, 1.6), (-1, 2.3)):
        p.add(box((2.0, 0.28, 1.0), round_axis="y", round_axis_by=R * 0.4), (side * 1.15, height, 0), LEAF_LIGHT, turned(0, 0, 22 * side))
        p.add(box((1.0, 0.26, 0.6), round_axis="y", round_axis_by=R * 0.25), (side * 2.3, height + 0.46 * 1, 0.3), LEAF_LIGHT, turned(0, 25 * side, 22 * side))
        p.add(box((0.9, 0.26, 0.55), round_axis="y", round_axis_by=R * 0.25), (side * 2.1, height + 0.4, -0.45), LEAF_LIGHT, turned(0, -30 * side, 22 * side))
    hx, hy, hz = POPPY_HEAD
    p.add(box((1.3, 0.85, 1.3), round_all=R * 0.5, segments=2), (hx, hy + 0.25, hz), POPPY_HEART)
    for index in range(8):
        m = at(hx, hy + 0.5, hz) @ turned(0, index * 45, 0) @ at(0.9, 0, 0)
        stick(p, box((0.3, 0.3, 0.3), round_all=R * 0.12, segments=1), m, GOLD)
    return p


def make_poppy_petals():
    p = Piece("PoppyPetals")
    hx, hy, hz = POPPY_HEAD
    for index in range(4):
        m = at(hx, hy, hz) @ turned(0, index * 90, 0) @ at(1.55, 0.3, 0) @ turned(0, 0, 24)
        stick(p, box((2.5, 0.42, 2.7), round_all=R * 0.95, segments=2), m, WHITE)
    for index in range(4):
        m = at(hx, hy - 0.15, hz) @ turned(0, index * 90 + 45, 0) @ at(1.35, 0.1, 0) @ turned(0, 0, 13)
        stick(p, box((2.0, 0.38, 2.1), round_all=R * 0.8, segments=2), m, PETAL_SHADE)
    return p


BELL_HOOKS = ((0, 5.35, -1.0, 1.0), (0, 6.25, -2.15, 0.9), (0, 6.55, -3.25, 0.78))  # x, y, z of each hanger's top, bell size


def make_bell_body():
    p = Piece("BellBody")
    p.add(box((0.5, 4.6, 0.5), round_axis="y", round_axis_by=R * 0.2), (0, 2.3, 0), STEM)
    limb(p, (0, 4.4, 0), (0, 6.3, -1.0), 0.44, STEM)
    limb(p, (0, 6.3, -1.0), (0, 7.1, -2.4), 0.4, STEM)
    limb(p, (0, 7.1, -2.4), (0, 6.9, -3.5), 0.34, STEM)
    for x, z, lean_z, lean_x, tall in ((0.55, 0.1, -17, 0, 3.6), (-0.55, 0.1, 17, 0, 3.1), (0, 0.6, 0, 18, 2.8), (0.1, -0.5, 0, -14, 2.2)):
        stick(p, box((0.9, tall, 0.3), round_all=R * 0.2, segments=1, taper=0.3),
              at(x, tall / 2 - 0.1, z) @ turned(lean_x, 90 if lean_x else 0, lean_z), LEAF_LIGHT)
    for x, y, z, size in BELL_HOOKS:
        p.add(box((0.14, 0.9, 0.14)), (x, y - 0.2, z), STEM_DARK)
        p.add(box((0.34 * size, 0.5 * size, 0.34 * size), round_all=R * 0.12, segments=1), (x, y - 2.3 * size, z), GOLD)  # the clapper
    return p


def make_bell_bells():
    p = Piece("BellBells")
    for x, y, z, size in BELL_HOOKS:
        top = y - 0.6
        p.add(box((0.75 * size, 0.4 * size, 0.75 * size), round_all=R * 0.2, segments=1), (x, top, z), PETAL_SHADE)
        # (taper narrows the TOP, which is just what a bell needs)
        p.add(box((1.5 * size, 1.4 * size, 1.5 * size), round_all=R * 0.5, segments=2, taper=0.58), (x, top - 0.85 * size, z), WHITE)
        p.add(box((1.75 * size, 0.3 * size, 1.75 * size), round_all=R * 0.22, segments=1), (x, top - 1.6 * size, z), PETAL_SHADE)
    return p


def make_spike_body():
    p = Piece("SpikeBody")
    p.add(box((0.5, 9.0, 0.5), round_axis="y", round_axis_by=R * 0.2), (0, 4.5, 0), STEM)
    for turn, height, long in ((0, 1.5, 2.8), (90, 2.3, 2.5), (45, 3.2, 2.0)):
        for side in (1, -1):
            m = turned(0, turn, 0) @ at(side * (long / 2 + 0.15), height, 0) @ turned(0, 0, 26 * side)
            stick(p, box((long, 0.26, 0.72), round_axis="y", round_axis_by=R * 0.3), m, LEAF_LIGHT)
    return p


def make_spike_blossoms():
    p = Piece("SpikeBlossoms")
    for tier in range(8):
        radius = 1.0 - tier * 0.085
        size = 1.0 - tier * 0.07
        for index in range(4):
            m = at(0, 4.5 + tier * 0.66, 0) @ turned(0, index * 90 + tier * 45, 0) @ at(radius * 0.72, 0, 0)
            stick(p, box((size, size * 0.72, size), round_all=R * 0.4, segments=1), m, WHITE if (tier + index) % 2 else PETAL_SHADE)
    p.add(box((0.55, 0.8, 0.55), round_all=R * 0.25, segments=1), (0, 9.95, 0), WHITE)
    return p


def sunflower_head(p, frame, wide, detail=1):
    """A sunflower's head. frame puts its middle in place; the face looks along the frame's +y."""
    w = wide
    # the green back: a round cushion with two rings of pointed sepals (a sunflower is often seen from behind)
    stick(p, tube(0.33 * w, 0.1 * w, "y", 18), frame @ at(0, -0.1 * w, 0), STEM)
    stick(p, tube(0.2 * w, 0.08 * w, "y", 14), frame @ at(0, -0.18 * w, 0), STEM_DARK)
    for index in range(12):
        m = frame @ turned(0, index * 30, 0) @ at(0.27 * w, -0.1 * w, 0) @ turned(0, 0, -100) @ at(0, 0.11 * w, 0)
        stick(p, slab_petal(0.24 * w, 0.14 * w, 0.045 * w, taper=0.3, soft=0.03 * w), m, STEM_DARK)
    for index in range(12):
        m = frame @ turned(0, index * 30 + 15, 0) @ at(0.17 * w, -0.16 * w, 0) @ turned(0, 0, -108) @ at(0, 0.08 * w, 0)
        stick(p, slab_petal(0.17 * w, 0.11 * w, 0.04 * w, taper=0.3, soft=0.025 * w), m, LEAF_BRIGHT)
    # the brown disc
    stick(p, tube(0.315 * w, 0.1 * w, "y", 20), frame @ at(0, -0.02 * w, 0), SEED_DARK)
    stick(p, tube(0.29 * w, 0.14 * w, "y", 20), frame, SEED)
    # seeds in rings, a chunky block each
    seed = 0.047 * w
    stick(p, box((seed * 1.5, seed, seed * 1.5), round_all=R * 0.2 * seed), frame @ at(0, 0.075 * w, 0), SEED_LIGHT)
    for ring, (radius, count) in enumerate(((0.075, 6), (0.14, 11), (0.205, 16), (0.262, 22))):
        for index in range(count):
            color = (SEED_LIGHT, SEED_DARK, GOLD_DARK)[(index + ring) % 2 if ring < 3 else 2 * (index % 2)]
            m = frame @ turned(0, index * 360 / count + ring * 9, 0) @ at(radius * w, 0.07 * w, 0)
            stick(p, box((seed, seed * 0.9, seed), round_all=R * 0.2 * seed, segments=1), m, color)
    # two rings of petals
    for index in range(18):
        m = frame @ turned(0, index * 20, 0) @ at(0.31 * w, 0.0, 0) @ turned(0, 0, -98) @ at(0, 0.15 * w, 0)
        stick(p, slab_petal(0.3 * w, 0.118 * w, 0.034 * w, soft=0.02 * w, segments=detail), m, GOLD)
    for index in range(18):
        m = frame @ turned(0, index * 20 + 10, 0) @ at(0.3 * w, 0.03 * w, 0) @ turned(0, 0, -76) @ at(0, 0.115 * w, 0)
        stick(p, slab_petal(0.23 * w, 0.1 * w, 0.03 * w, soft=0.018 * w, segments=detail), m, ORANGE_GOLD)


def heart_leaf(p, frame, long, color, rib=STEM_DARK):
    """A big sunflower leaf lying along the frame's +x: wide near the stalk, pointed at the tip."""
    for along, length, wide in ((0.2, 0.46, 0.56), (0.52, 0.42, 0.44), (0.8, 0.28, 0.25)):
        stick(p, box((length * long, 0.05 * long, wide * long), round_all=R * 0.06 * long, segments=1), frame @ at(along * long, 0, 0), color)
    stick(p, box((0.98 * long, 0.022 * long, 0.045 * long)), frame @ at(0.48 * long, 0.03 * long, 0), rib)
    for along, reach in ((0.22, 0.24), (0.45, 0.2), (0.66, 0.13)):
        for side in (1, -1):
            m = frame @ at(along * long, 0.03 * long, side * reach * 0.55 * long) @ turned(0, -55 * side, 0)
            stick(p, box((reach * 1.1 * long, 0.018 * long, 0.035 * long)), m, rib)


SUN_HEAD = (0.0, 9.3, -0.7)  # the middle of the ordinary sunflower's face


def make_sunflower():
    """An ordinary sunflower, about 11 studs tall. Painted in its own colours (it is always yellow)."""
    p = Piece("Sunflower")
    p.add(box((0.8, 8.8, 0.8), round_axis="y", round_axis_by=R * 0.3), (0, 4.4, 0), STEM)
    for height, yaw, long in ((2.6, 10, 3.6), (4.3, 150, 3.2), (6.0, 265, 2.8)):
        frame = at(0, height, 0) @ turned(0, yaw, 0) @ turned(0, 0, -14)
        heart_leaf(p, frame @ at(0.3, 0, 0), long, LEAF_LIGHT)
    limb(p, (0, 8.5, 0), (SUN_HEAD[0], SUN_HEAD[1] - 0.4, SUN_HEAD[2] + 0.35), 0.7, STEM)
    sunflower_head(p, at(*SUN_HEAD) @ turned(-52, 0, 0), 6.4)
    return p


# ---- the giant sunflower in the middle ------------------------------------------------------------
# One huge plant, about 36 studs tall, with three heads that face three ways, so a face can be seen
# from every home area. Its pieces are modelled where they belong, so they all go on the same spot.

GIANT_TRUNK = [  # the middle of the trunk at each joint: x, y, z, and how thick
    (0.0, 0.0, 0.0, 3.0), (0.3, 5.0, 0.1, 2.8), (0.5, 10.0, -0.1, 2.6), (0.35, 15.0, 0.1, 2.45),
    (0.1, 20.0, 0.2, 2.3), (-0.15, 25.0, 0.0, 2.15), (-0.25, 29.5, -0.2, 2.0), (-0.2, 32.6, -0.6, 1.9),
]
GIANT_HEADS = {  # name: where the face's middle is, which way it looks (degrees round), how wide, where its branch leaves the trunk
    # (each head sits out on the side it looks towards, so no head hides behind another)
    "SunGiantHeadA": ((-0.2, 34.4, -2.8), 0, 15.0, None),
    "SunGiantHeadB": ((6.9, 27.6, 3.8), -118, 11.5, 21.5),
    "SunGiantHeadC": ((-6.7, 30.6, 4.1), 122, 12.0, 24.5),
}
GIANT_TURN = -90  # how the whole plant is turned in the garden: its faces then look between the gates, so
#                   every home area sees a face from 30 degrees to one side
GIANT_TILT = -64  # the faces look mostly sideways and a little up


def giant_head_frame(name):
    middle, yaw, _wide, _branch = GIANT_HEADS[name]
    return at(*middle) @ turned(0, yaw, 0) @ turned(GIANT_TILT, 0, 0)


def trunk_point(height):
    for (x0, y0, z0, _t0), (x1, y1, z1, _t1) in zip(GIANT_TRUNK, GIANT_TRUNK[1:]):
        if y0 <= height <= y1:
            f = (height - y0) / (y1 - y0)
            return (x0 + (x1 - x0) * f, height, z0 + (z1 - z0) * f)
    return GIANT_TRUNK[-1][:3]


def make_giant_stem():
    p = Piece("SunGiantStem")
    for (x0, y0, z0, thick0), (x1, y1, z1, thick1) in zip(GIANT_TRUNK, GIANT_TRUNK[1:]):
        limb(p, (x0, y0, z0), (x1, y1, z1), (thick0 + thick1) / 2, STEM, round_by=0.28)
        p.add(box((thick1 + 0.5, 0.6, thick1 + 0.5), round_all=R * 0.35, segments=1), (x1, y1, z1), STEM_DARK)  # a knot at each joint
    # roots gripping the mound
    for index in range(6):
        m = turned(0, index * 60 + 15, 0) @ at(2.0, 0.55, 0) @ turned(0, 0, -24)
        stick(p, box((3.0, 1.1, 1.3), round_all=R * 0.5, segments=1, taper=0.7), m, STEM_DARK)
    # the neck of the top head, and the two branches
    for name, (middle, yaw, wide, branch) in GIANT_HEADS.items():
        back = giant_head_frame(name) @ Vector((0, -0.16 * wide, 0))
        if branch is None:
            limb(p, GIANT_TRUNK[-1][:3], tuple(back), 1.6, STEM)
        else:
            start_point = Vector(trunk_point(branch))
            elbow = start_point.lerp(back, 0.55) + Vector((0, -1.6, 0))
            limb(p, tuple(start_point), tuple(elbow), 1.5, STEM)
            limb(p, tuple(elbow), tuple(back), 1.3, STEM)
            p.add(box((1.9, 1.0, 1.9), round_all=R * 0.4, segments=1), tuple(elbow), STEM_DARK)
    # the big leaves: the lowest ones are high enough to walk under
    leaves = ((9.0, 25, 11.0, -16), (12.0, 150, 10.5, -20), (15.0, 268, 10.0, -14), (18.0, 78, 9.0, -18),
              (20.5, 205, 8.6, -12), (23.5, 318, 7.6, -16), (27.0, 60, 6.4, -10))
    for number, (height, yaw, long, droop) in enumerate(leaves):
        root = Vector(trunk_point(height))
        frame = Matrix.Translation(root) @ turned(0, yaw, 0)
        stalk_end = frame @ Vector((2.6, 0.9, 0))
        limb(p, tuple(root), tuple(stalk_end), 0.7, STEM_DARK)
        heart_leaf(p, Matrix.Translation(stalk_end) @ turned(0, yaw, 0) @ turned(0, 0, droop), long, LEAF_BRIGHT if number % 2 else LEAF_LIGHT)
    return p


def make_giant_head(name):
    p = Piece(name)
    sunflower_head(p, giant_head_frame(name), GIANT_HEADS[name][2], detail=1)
    return p


# ---- the pond ---------------------------------------------------------------------------------------

def lily_pad(p):
    p.add(tube(1.7, 0.22, "y", 12), (0, 0.11, 0), PAD)
    p.add(tube(1.3, 0.26, "y", 12), (0, 0.13, 0), PAD_LIGHT)
    for index in range(5):
        m = at(0, 0.27, 0) @ turned(0, index * 72 + 20, 0) @ at(0.75, 0, 0)
        stick(p, box((1.3, 0.03, 0.1)), m, PAD)


def make_lily_pad():
    p = Piece("LilyPad")
    lily_pad(p)
    return p


def make_lily_bloom():
    """A lily pad with the yellow middle of a water lily on it (the petals are their own white piece)."""
    p = Piece("LilyBloom")
    lily_pad(p)
    p.add(box((0.6, 0.5, 0.6), round_all=R * 0.25, segments=1), (0, 0.6, 0), GOLD)
    for index in range(6):
        m = at(0, 0.82, 0) @ turned(0, index * 60, 0) @ at(0.2, 0, 0)
        stick(p, box((0.14, 0.2, 0.14)), m, GOLD_DARK)
    return p


def make_lily_petals():
    p = Piece("LilyPetals")
    for index in range(8):
        m = at(0, 0.3, 0) @ turned(0, index * 45, 0) @ at(0.42, 0.12, 0) @ turned(0, 0, -58) @ at(0, 0.6, 0)
        stick(p, slab_petal(1.25, 0.6, 0.2, taper=0.35, soft=0.12), m, WHITE)
    for index in range(6):
        m = at(0, 0.4, 0) @ turned(0, index * 60 + 30, 0) @ at(0.3, 0.2, 0) @ turned(0, 0, -30) @ at(0, 0.45, 0)
        stick(p, slab_petal(0.95, 0.46, 0.18, taper=0.35, soft=0.1), m, PETAL_SHADE)
    return p


def make_reeds():
    p = Piece("Reeds")
    for x, z, tall, lean in ((0, 0, 6.6, 2), (0.55, 0.3, 5.4, -5), (-0.5, 0.35, 4.8, 6), (0.2, -0.55, 5.9, 3), (-0.35, -0.4, 3.9, -4)):
        m = at(x, 0, z) @ turned(lean, 0, lean * 0.6)
        stick(p, box((0.22, tall, 0.22)), m @ at(0, tall / 2, 0), STEM)
        stick(p, box((0.58, 1.5, 0.58), round_all=R * 0.5, segments=1), m @ at(0, tall - 1.5, 0), REED_HEAD)
    for x, z, tall, lean_z, lean_x in ((0.75, -0.1, 3.8, -20, 0), (-0.8, 0.05, 3.4, 22, 0), (0.1, 0.75, 3.0, 0, 20), (-0.1, -0.85, 2.6, 0, -24)):
        stick(p, box((0.5, tall, 0.16), round_all=R * 0.1, segments=1, taper=0.2),
              at(x, tall / 2 - 0.1, z) @ turned(lean_x, 90 if lean_x else 0, lean_z), LEAF_LIGHT)
    return p


def make_frog():
    """A little frog for a lily pad. It looks towards -z."""
    p = Piece("Frog")
    p.add(box((1.5, 0.95, 1.7), round_all=R * 0.9, segments=2), (0, 0.55, 0.1), FROG)
    p.add(box((1.45, 0.8, 1.05), round_all=R * 0.8, segments=2), (0, 0.95, -0.7), FROG)
    p.add(box((1.2, 0.3, 1.2), round_all=R * 0.3, segments=1), (0, 0.22, -0.25), FROG_BELLY)
    for side in (1, -1):
        p.add(ball(0.3, detail=2), (side * 0.42, 1.48, -0.8), WHITE)
        p.add(box((0.2, 0.26, 0.12)), (side * 0.42, 1.5, -1.06), INK)
        p.add(box((0.6, 0.5, 1.05), round_all=R * 0.4, segments=1), (side * 0.85, 0.3, 0.45), FROG, turned(0, 20 * side, 0))
        p.add(box((0.7, 0.2, 0.5), round_all=R * 0.15, segments=1), (side * 1.05, 0.1, -0.1), FROG)
        p.add(box((0.36, 0.5, 0.4), round_all=R * 0.25, segments=1), (side * 0.62, 0.27, -0.95), FROG)
    p.add(box((0.8, 0.07, 0.1)), (0, 0.8, -1.24), INK)
    return p


FLOWER_MAKERS = [make_daisy_body, make_daisy_petals, make_tulip_body, make_tulip_petals, make_poppy_body, make_poppy_petals,
                 make_bell_body, make_bell_bells, make_spike_body, make_spike_blossoms, make_sunflower]
OTHER_MAKERS = [make_giant_stem, lambda: make_giant_head("SunGiantHeadA"), lambda: make_giant_head("SunGiantHeadB"),
                lambda: make_giant_head("SunGiantHeadC"), make_lily_pad, make_lily_bloom, make_lily_petals, make_reeds, make_frog]

# What the game needs to know about each kind of flower: its pieces, and where a bee hovers over it
# (x, y, z above the flower's foot, for a flower of size 1).
KINDS = {
    "Daisy": {"Body": "DaisyBody", "Petals": "DaisyPetals", "Top": (0, 8.2, 0), "Tall": 7.2},
    "Tulip": {"Body": "TulipBody", "Petals": "TulipPetals", "Top": (0, 9.4, 0), "Tall": 8.4},
    "Poppy": {"Body": "PoppyBody", "Petals": "PoppyPetals", "Top": (0.5, 7.2, 0), "Tall": 6.2},
    "Bell": {"Body": "BellBody", "Petals": "BellBells", "Top": (0, 8.4, -2.2), "Tall": 7.4},
    "Spike": {"Body": "SpikeBody", "Petals": "SpikeBlossoms", "Top": (0, 11.4, 0), "Tall": 10.4},
    "Sunflower": {"Body": "Sunflower", "Petals": None, "Top": (0, 11.0, -2.6), "Tall": 11.6},
}

# ---- where everything goes --------------------------------------------------------------------------
# The garden keeps its size: a round meadow 44 studs out from the middle, a fence at 49.5 with six
# gates (where the paths from the home areas arrive, at 30, 90, 150... degrees).

GARDEN_RADIUS = 44
GATES = [30 + 60 * index for index in range(6)]
POND_SECTOR = 180  # the pond sits between the gates at 150 and 210 degrees
PINK, RED, PURPLE, WHITE_PETAL, BLUE, ORANGE, YELLOW, LILAC, HOT_PINK = (
    (255, 120, 170), (255, 90, 90), (190, 120, 255), (255, 255, 255), (110, 180, 255), (255, 165, 60), (255, 214, 70),
    (214, 170, 255), (255, 92, 190))
THEMES = {  # each bed between two gates has its own flowers: (kind, colours) for the small, medium and giant rows
    0: (("Daisy", (WHITE_PETAL, PINK, YELLOW)), ("Daisy", (WHITE_PETAL, PINK)), ("Sunflower", (YELLOW,))),
    60: (("Tulip", (RED, PINK, ORANGE, YELLOW)), ("Tulip", (RED, HOT_PINK, ORANGE)), ("Tulip", (RED, PURPLE))),
    120: (("Poppy", (RED, ORANGE)), ("Poppy", (RED, ORANGE, PINK)), ("Spike", (PURPLE, LILAC))),
    240: (("Spike", (PURPLE, BLUE, LILAC)), ("Bell", (BLUE, LILAC, WHITE_PETAL)), ("Bell", (BLUE, PURPLE))),
    300: (("Daisy", (YELLOW, ORANGE, WHITE_PETAL)), ("Poppy", (HOT_PINK, PURPLE)), ("Daisy", (PINK, WHITE_PETAL))),
}
ROWS = (  # distance from the middle, how many flowers, how tall the flowers are (studs), how much the height varies
    (38.5, 9, 3.0, 0.5),
    (29.0, 6, 6.6, 0.9),
    (19.5, 3, 13.5, 2.5),
)


def polar(angle, radius):
    return math.cos(math.radians(angle)) * radius, math.sin(math.radians(angle)) * radius


def build_layout():
    rng = random.Random(7)
    layout = {"Flowers": [], "Beds": [], "Stones": [], "Pads": [], "Reeds": [], "Extras": [], "Mound": 8.5}
    # the flower beds
    for sector, rows in THEMES.items():
        for (radius, count, tall, vary), (kind, colors) in zip(ROWS, rows):
            spread = 21 if radius > 25 else 17  # degrees either side of the bed's middle
            width = 2 * radius * math.sin(math.radians(spread)) + 4
            x, z = polar(sector, radius)
            layout["Beds"].append({"X": x, "Z": z, "Turn": sector, "Long": round(width, 1), "Wide": 7.5 if radius > 25 else 8.5})
            for index in range(count):
                share = (index + 0.5) / count
                angle = sector - spread + share * 2 * spread + rng.uniform(-1.2, 1.2)
                r = radius + rng.uniform(-1.6, 1.6) + (1.2 if index % 2 else -1.2)
                height = tall + rng.uniform(-vary, vary)
                fx, fz = polar(angle, r)
                layout["Flowers"].append({
                    "Kind": kind, "X": round(fx, 2), "Z": round(fz, 2), "Scale": round(height / KINDS[kind]["Tall"], 3),
                    # (sunflowers and bellflowers have a front: it looks outwards, towards whoever walks in)
                    "Turn": round(rng.uniform(0, 360) if kind not in ("Sunflower", "Bell") else (-angle - 90 + rng.uniform(-25, 25)) % 360, 1),
                    "Color": colors[(index + rng.randrange(len(colors))) % len(colors)],
                })
    # stepping stones from every gate to the ring round the mound, and the ring itself
    for gate in GATES:
        radius = GARDEN_RADIUS - 1.5
        while radius > 13.5:
            x, z = polar(gate + rng.uniform(-1.3, 1.3), radius)
            layout["Stones"].append({"X": round(x, 2), "Z": round(z, 2), "Turn": round(rng.uniform(0, 90), 1), "Size": round(rng.uniform(2.6, 3.4), 2)})
            radius -= rng.uniform(3.7, 4.3)
    for index in range(14):
        x, z = polar(index * 360 / 14 + 8, 12.2 + rng.uniform(-0.4, 0.4))
        layout["Stones"].append({"X": round(x, 2), "Z": round(z, 2), "Turn": round(rng.uniform(0, 90), 1), "Size": round(rng.uniform(2.4, 3.0), 2)})
    # the pond
    px, pz = polar(POND_SECTOR, 28)
    layout["Pond"] = {"X": round(px, 2), "Z": round(pz, 2), "Radius": 10.5}
    pads = ((-4.5, 2.0, 1.25, True), (3.5, -3.0, 1.1, False), (0.5, 4.5, 0.9, False), (5.0, 3.2, 1.0, True), (-2.5, -4.8, 0.95, False),
            (-6.2, -1.8, 0.8, False), (1.2, -0.4, 1.3, False), (6.4, -0.6, 0.75, False))
    for dx, dz, size, bloom in pads:
        layout["Pads"].append({"X": round(px + dx, 2), "Z": round(pz + dz, 2), "Scale": size, "Turn": round(rng.uniform(0, 360), 1), "Bloom": bloom,
                               "Color": PINK if dx < 0 else WHITE_PETAL})
    layout["Frog"] = {"X": round(px + 1.2, 2), "Z": round(pz - 0.4, 2), "Turn": 215, "Scale": 1.5}
    for angle, radius, size in ((40, 10.6, 1.3), (75, 10.9, 1.0), (165, 10.4, 1.4), (200, 10.8, 1.1), (290, 10.7, 1.2)):
        x, z = polar(angle, radius)
        layout["Reeds"].append({"X": round(px + x, 2), "Z": round(pz + z, 2), "Scale": size, "Turn": round(rng.uniform(0, 360), 1)})
    for angle, radius, size in ((10, 11.8, 1.0), (120, 11.6, 0.8), (240, 11.9, 1.1), (320, 11.5, 0.7)):
        x, z = polar(angle, radius)
        layout["Extras"].append({"Kind": "Rock", "X": round(px + x, 2), "Z": round(pz + z, 2), "Scale": size, "Turn": round(rng.uniform(0, 360), 1)})
    # small things between the beds: bushes by the fence, mushrooms, grass and little lawn flowers
    for sector in list(THEMES) + [POND_SECTOR]:
        for offset, radius, kind, size in ((-24, 41.5, "Bush", 1.25), (24, 41.0, "Bush", 1.05), (-12, 34.0, "Mushroom", 1.5), (13, 24.0, "Mushroom", 1.2)):
            if sector == POND_SECTOR and kind == "Mushroom":
                continue
            x, z = polar(sector + offset + rng.uniform(-1.5, 1.5), radius + rng.uniform(-0.8, 0.8))
            layout["Extras"].append({"Kind": kind, "X": round(x, 2), "Z": round(z, 2), "Scale": size, "Turn": round(rng.uniform(0, 360), 1)})
    for _ in range(46):
        angle, radius = rng.uniform(0, 360), rng.uniform(11, 42.5)
        x, z = polar(angle, radius)
        if (x - px) ** 2 + (z - pz) ** 2 < 12.5 ** 2:
            continue
        kind = "GrassTuft" if rng.random() < 0.6 else "LawnFlower"
        layout["Extras"].append({"Kind": kind, "X": round(x, 2), "Z": round(z, 2), "Scale": round(rng.uniform(1.1, 1.7), 2), "Turn": round(rng.uniform(0, 360), 1),
                                 "Color": rng.choice((PINK, WHITE_PETAL, YELLOW, BLUE, ORANGE, LILAC))})
    return layout


def lua_value(value, indent=1):
    pad = "\t" * indent
    if isinstance(value, dict):
        inner = ", ".join(f"{key} = {lua_value(item, indent + 1)}" for key, item in value.items())
        return "{ " + inner + " }"
    if isinstance(value, (list, tuple)):
        if value and all(isinstance(item, (int, float)) for item in value):
            return "{ " + ", ".join(lua_value(item) for item in value) + " }"
        return "{\n" + "".join(f"{pad}{lua_value(item, indent + 1)},\n" for item in value) + "\t" * (indent - 1) + "}"
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "nil"
    if isinstance(value, str):
        return '"' + value + '"'
    return repr(round(value, 3)) if isinstance(value, float) else repr(value)


def write_layout(layout, target):
    lines = ["-- The new Flower Garden: where everything stands. Made by blender/garden.py (do not edit by hand:",
             "-- change garden.py and run it again). X and Z are studs from the middle of the garden.",
             "return {",
             f"\tRadius = {GARDEN_RADIUS},",
             f"\tMound = {layout['Mound']}, -- how wide the earth mound under the giant sunflower is (its radius)",
             f"\tGiantTurn = {GIANT_TURN}, -- the giant sunflower is turned this many degrees (its faces then look between the gates)",
             "\t-- every kind of flower: its pieces, and where a bee hovers over one of size 1",
             "\tKinds = {"]
    for name, kind in KINDS.items():
        lines.append(f"\t\t{name} = {lua_value(kind, 3)},")
    lines.append("\t},")
    lines.append("\t-- the giant sunflower's three faces: where a bee hovers in front of each")
    lines.append("\tGiantSpots = {")
    for name in GIANT_HEADS:
        frame = giant_head_frame(name)
        for sideways in (-0.18, 0.18):
            spot = frame @ Vector((sideways * GIANT_HEADS[name][2], 2.6, 0))
            lines.append(f"\t\t{{ {round(spot.x, 2)}, {round(spot.y, 2)}, {round(spot.z, 2)} }},")
    lines.append("\t},")
    def number(value):
        return repr(round(value, 2)).rstrip("0").rstrip(".") if isinstance(value, float) else repr(value)

    def short(entry, keys):
        """One thing on one short line: its values in a fixed order (a colour as three numbers)."""
        parts = []
        for key in keys:
            value = entry.get(key)
            if key == "Color":
                value = value or (255, 255, 255)
                parts.extend(str(v) for v in value)
            elif isinstance(value, str):
                parts.append('"' + value + '"')
            elif isinstance(value, bool):
                parts.append("true" if value else "false")
            else:
                parts.append(number(value))
        return "{" + ",".join(parts) + "}"

    rows = (("Flowers", ("Kind", "X", "Z", "Scale", "Turn", "Color")), ("Beds", ("X", "Z", "Turn", "Long", "Wide")),
            ("Stones", ("X", "Z", "Turn", "Size")), ("Pads", ("X", "Z", "Scale", "Turn", "Bloom", "Color")),
            ("Reeds", ("X", "Z", "Scale", "Turn")), ("Extras", ("Kind", "X", "Z", "Scale", "Turn", "Color")))
    for key, keys in rows:
        lines.append(f"\t-- {key}: " + ", ".join("R, G, B" if k == "Color" else k for k in keys))
        lines.append(f"\t{key} = {{")
        lines.extend("\t\t" + short(entry, keys) + "," for entry in layout[key])
        lines.append("\t},")
    lines.append(f"\tPond = {lua_value(layout['Pond'])},")
    lines.append(f"\tFrog = {lua_value(layout['Frog'])},")
    lines.append("}")
    with open(target, "w") as handle:
        handle.write("\n".join(lines) + "\n")
    say("layout written", target, len(layout["Flowers"]), "flowers")


# ---- make everything -----------------------------------------------------------------------------------

scene = start()
pieces = {}
for maker in FLOWER_MAKERS + OTHER_MAKERS:
    piece = maker()
    pieces[piece.name] = piece
library = new_collection("Pieces")
objects = {name: piece.to_object(library) for name, piece in pieces.items()}
total = 0
for name, piece in pieces.items():
    low, high = piece.bounds()
    total += piece.triangles()
    say("piece", name, "triangles", piece.triangles(), "size", [round(high[i] - low[i], 2) for i in range(3)])
say("all pieces:", len(pieces), "triangles in all:", total)

paint = None
tints = {}


def tint(color):
    key = tuple(color)
    if key not in tints:
        tints[key] = tint_material(rgb(*color))
    return tints[key]


def move(x, y, z, turn=0.0, size=1.0):
    return Matrix.Translation((x, y, z)) @ turned(0, turn, 0) @ Matrix.Scale(size, 4)


def plant(stage, kind_name, x, z, size, turn, color, y=0.0):
    kind = KINDS[kind_name]
    put(objects[kind["Body"]], stage, move(x, y, z, turn, size), paint)
    if kind["Petals"]:
        put(objects[kind["Petals"]], stage, move(x, y, z, turn, size), tint(color))


def helper(name, shapes):
    piece = Piece(name)
    for shape, where, color in shapes:
        piece.add(shape, where, color)
    return piece.to_object(library)


def player_dummy():
    """A block figure as tall as a Roblox character (5 studs), to show how big things are."""
    skin, shirt, trousers = rgb(245, 205, 150), rgb(80, 170, 255), rgb(60, 80, 160)
    return helper("Player", [
        (box((0.9, 2.0, 0.9), round_all=0.1), (-0.5, 1.0, 0), trousers), (box((0.9, 2.0, 0.9), round_all=0.1), (0.5, 1.0, 0), trousers),
        (box((2.0, 2.0, 1.0), round_all=0.12), (0, 3.0, 0), shirt), (box((0.9, 2.0, 0.9), round_all=0.1), (-1.45, 3.0, 0), skin),
        (box((0.9, 2.0, 0.9), round_all=0.1), (1.45, 3.0, 0), skin), (box((1.25, 1.2, 1.25), round_all=0.3), (0, 4.6, 0), skin)])


if "lineup" in MODES:
    library.hide_render = True
    stage = new_collection("Lineup")
    paint = paint_material()
    dummy = player_dummy()
    spots = (("Daisy", -27, 1.0, (255, 255, 255)), ("Tulip", -20, 1.0, (255, 90, 90)), ("Poppy", -13, 1.0, (255, 165, 60)),
             ("Bell", -6, 1.0, (110, 180, 255)), ("Spike", 1, 1.0, (190, 120, 255)), ("Sunflower", 9, 1.0, (255, 214, 70)))
    for kind_name, x, size, color in spots:
        plant(stage, kind_name, x, 0, size, 0 if kind_name in ("Sunflower", "Bell") else 20, color)
    put(dummy, stage, move(-32.5, 0, 0), paint)
    # the same flowers small and giant, behind and in front
    plant(stage, "Daisy", -24, -6, 0.42, 40, (255, 120, 170))
    plant(stage, "Tulip", -17, -6, 0.38, 0, (255, 214, 70))
    plant(stage, "Poppy", -10, -6, 0.5, 10, (255, 90, 90))
    plant(stage, "Daisy", 20, 3, 1.9, 15, (255, 120, 170))
    plant(stage, "Tulip", 29, 3, 1.7, 0, (190, 120, 255))
    put(dummy, stage, move(24.5, 0, -2), paint)
    # pond things
    put(objects["LilyPad"], stage, move(-3, 0.05, -7), paint)
    put(objects["LilyBloom"], stage, move(2, 0.05, -7.5), paint)
    put(objects["LilyPetals"], stage, move(2, 0.05, -7.5), tint((255, 150, 190)))
    put(objects["Frog"], stage, move(-3, 0.3, -7, 200, 1.0), paint)
    put(objects["Reeds"], stage, move(7, 0, -6.5), paint)
    add_floor(stage, 0, MEADOW)
    add_sun(stage, (-0.5, 0.8, -0.4), 1.9)
    engine = setup_render(scene, 2000, 900, samples=64, sky=for_blender(rgb(150, 210, 255)), sky_strength=0.55, see_through=False)
    add_camera(stage, scene, (-2, 30, -80), (-1, 7.5, 0), 72)
    scene.render.filepath = os.path.join(OUT, "garden-flowers.png")
    bpy.ops.render.render(write_still=True)
    say("line-up drawn with", engine)
    bpy.data.collections.remove(stage)

if "preview" in MODES:
    library.hide_render = True
    stage = new_collection("Garden")
    paint = paint_material()
    layout = build_layout()
    dummy = player_dummy()

    def slab(name, size, where, color, turn=0.0):
        piece = Piece(name)
        piece.add(box(size), (0, 0, 0), color)
        put(piece.to_object(library), stage, Matrix.Translation(where) @ turned(0, turn, 0), paint)

    def disc(name, radius, top, color, thick=0.4, x=0.0, z=0.0):
        piece = Piece(name)
        piece.add(tube(radius, thick, "y", 40), (0, 0, 0), color)
        put(piece.to_object(library), stage, at(x, top - thick / 2, z), paint)

    disc("SoilRim", GARDEN_RADIUS + 4, 0.3, SOIL)
    disc("Meadow", GARDEN_RADIUS, 0.5, MEADOW)
    for bed in layout["Beds"]:
        slab("Bed", (bed["Wide"], 0.3, bed["Long"]), (bed["X"], 0.45, bed["Z"]), SOIL, -bed["Turn"])
    disc("Mound", layout["Mound"], 1.1, SOIL, 0.9)
    disc("MoundTop", layout["Mound"] - 2.5, 1.7, SOIL_DARK, 0.9)
    pond = layout["Pond"]
    disc("PondRim", pond["Radius"] + 1.2, 0.95, STONE, 0.6, pond["X"], pond["Z"])
    disc("Water", pond["Radius"], 1.0, WATER, 0.3, pond["X"], pond["Z"])
    disc("WaterDeep", pond["Radius"] - 4, 1.02, WATER_DEEP, 0.3, pond["X"], pond["Z"])
    for stone in layout["Stones"]:
        slab("Stone", (stone["Size"], 0.3, stone["Size"]), (stone["X"], 0.6, stone["Z"]), CREAM, stone["Turn"])
    for flower in layout["Flowers"]:
        plant(stage, flower["Kind"], flower["X"], flower["Z"], flower["Scale"], flower["Turn"], flower["Color"], 0.5)
    for pad in layout["Pads"]:
        where = move(pad["X"], 1.0, pad["Z"], pad["Turn"], pad["Scale"])
        put(objects["LilyBloom" if pad["Bloom"] else "LilyPad"], stage, where, paint)
        if pad["Bloom"]:
            put(objects["LilyPetals"], stage, where, tint(pad["Color"]))
    frog = layout["Frog"]
    put(objects["Frog"], stage, move(frog["X"], 1.25, frog["Z"], frog["Turn"], frog["Scale"]), paint)
    for reed in layout["Reeds"]:
        put(objects["Reeds"], stage, move(reed["X"], 0.9, reed["Z"], reed["Turn"], reed["Scale"]), paint)
    # the giant sunflower
    for name in ["SunGiantStem"] + list(GIANT_HEADS):
        put(objects[name], stage, move(0, 1.6, 0, GIANT_TURN), paint)
    # stand-ins for the pieces the game already has (so the picture is complete)
    bush = helper("BushStandIn", [(box((3.4, 2.4, 3.0), round_all=0.45), (0, 1.2, 0), LEAF), (box((2.4, 1.9, 2.4), round_all=0.36), (1.7, 0.95, 0.6), LEAF_LIGHT)])
    rock = helper("RockStandIn", [(box((3.2, 2.0, 2.6), round_all=0.25), (0, 0.95, 0), rgb(152, 156, 166))])
    shroom = helper("MushroomStandIn", [(box((0.6, 1.0, 0.6)), (0, 0.5, 0), rgb(255, 240, 212)), (box((1.9, 0.62, 1.9), round_all=0.14), (0, 1.34, 0), rgb(232, 62, 62))])
    tuft = helper("TuftStandIn", [(box((0.34, 2.0, 0.34), taper=0.3), (0, 1.0, 0), rgb(40, 130, 60)), (box((0.34, 1.4, 0.34), taper=0.3), (0.4, 0.7, 0.2), rgb(70, 170, 70))])
    lawn = helper("LawnStandIn", [(box((0.24, 1.7, 0.24)), (0, 0.85, 0), STEM), (box((1.0, 0.26, 1.0), round_all=0.1), (0, 1.8, 0), WHITE),
                                  (box((0.4, 0.3, 0.4)), (0, 1.95, 0), GOLD)])
    for extra in layout["Extras"]:
        source = {"Bush": bush, "Rock": rock, "Mushroom": shroom, "GrassTuft": tuft, "LawnFlower": lawn}[extra["Kind"]]
        material = tint(extra["Color"]) if extra["Kind"] == "LawnFlower" else paint
        put(source, stage, move(extra["X"], 0.5, extra["Z"], extra["Turn"], extra["Scale"]), material)
    post = helper("PostStandIn", [(box((1, 3.0, 1), round_all=0.09), (0, 1.5, 0), FENCE_POST)])
    for degrees in range(0, 360, 12):
        x, z = polar(degrees, GARDEN_RADIUS + 5.5)
        put(post, stage, move(x, 0, z), paint)
        if (degrees + 6 - 30) % 60 != 0:
            x2, z2 = polar(degrees + 12, GARDEN_RADIUS + 5.5)
            for height in (1.3, 2.4):
                rail = Piece("Rail")
                rail.add(box((math.hypot(x2 - x, z2 - z), 0.45, 0.4)), (0, 0, 0), FENCE_RAIL)
                put(rail.to_object(library), stage, at((x + x2) / 2, height, (z + z2) / 2) @ turned(0, -math.degrees(math.atan2(z2 - z, x2 - x)), 0), paint)
    for degrees, radius in ((30, 40), (95, 15), (270, 36), (200, 14.5)):
        x, z = polar(degrees, radius)
        put(dummy, stage, move(x, 0.6, z, degrees), paint)

    add_floor(stage, 0, GRASS)
    add_sun(stage, (-0.45, 0.85, -0.35), 1.9)
    engine = setup_render(scene, 2000, 1250, samples=64, sky=for_blender(rgb(150, 210, 255)), sky_strength=0.55, see_through=False)
    add_camera(stage, scene, (-60, 95, -150), (0, 9, 0), 118)
    scene.render.filepath = os.path.join(OUT, "garden-preview.png")
    bpy.ops.render.render(write_still=True)
    say("garden drawn with", engine)
    # a second look from the ground, the way a player walking in sees it
    for obj in list(stage.objects):
        if obj.type == "CAMERA":
            bpy.data.objects.remove(obj)
    gx, gz = polar(30, 62)
    camera_data = bpy.data.cameras.new("Eye")
    camera_data.lens = 22
    camera_data.clip_end = 1000
    eye = bpy.data.objects.new("Eye", camera_data)
    stage.objects.link(eye)
    from toykit import TO_BLENDER  # noqa: E402
    eye_at = TO_BLENDER.to_3x3() @ Vector((gx, 8, gz))
    target = TO_BLENDER.to_3x3() @ Vector((0, 15, 0))
    eye.location = eye_at
    eye.rotation_euler = (target - eye_at).to_track_quat("-Z", "Y").to_euler()
    scene.camera = eye
    scene.render.resolution_x, scene.render.resolution_y = 1800, 1100
    scene.render.filepath = os.path.join(OUT, "garden-walk-in.png")
    bpy.ops.render.render(write_still=True)
    say("walk-in view drawn")
    bpy.data.collections.remove(stage)

if "export" in MODES:
    export_for_roblox(scene, pieces, objects, os.path.join(OUT, "BeeEmpire-garden.fbx"))
    write_layout(build_layout(), os.path.join(OUT, "garden-layout.lua"))

say("done")
