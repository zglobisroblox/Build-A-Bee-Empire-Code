# Build A Bee Empire - pictures for the Shop (things bought with Robux), made in Blender (chunky toy style).
#
# Run:  blender --background --factory-startup --python shop.py -- <ABSOLUTE output folder> [shop starter ...]
#
# Pictures (768 x 768, see-through background; icon-tools\finish-blender-icons.ps1 trims them and
# adds the ink outline):
#   icon-Shop.png           a market stall with a striped roof: the Shop button and window     (mode: shop)
#   icon-PassStarter.png    a gift box with a bow: the Starter Pack                             (mode: starter)
#   icon-PassInventory.png  the backpack with an "infinity" sign: Infinite Inventory            (mode: inventory)
#   icon-PassRolls.png      two mystery eggs and "+2": +2 Rolls                                 (mode: rolls)
#   icon-PassAutoSell.png   a honey jar, a coin and "AUTO": Auto Sell                           (mode: autosell)
#   icon-PassVIP.png        a crown over "VIP"                                                  (mode: vip)
#   icon-PassLucky.png      a four-leaf clover wearing a crown, and "x2": Lucky Queen           (mode: lucky)
#
# Seen from the front (the camera's side, -z), +x is on the LEFT. Writing is placed with bar(),
# which takes (right, up) the way the camera sees it.

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Matrix  # noqa: E402
from toykit import (Piece, add_camera, add_sun, ball, box, new_collection, paint_material, put, rgb, say,  # noqa: E402
                    setup_render, start, tube, turned)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
ALL = ["shop", "starter", "inventory", "rolls", "autosell", "vip", "lucky"]
MODES = set(ARGS[1:]) or set(ALL)
os.makedirs(OUT, exist_ok=True)

INK = rgb(35, 30, 30)
WHITE = rgb(255, 255, 255)
CREAM = rgb(252, 246, 230)
RED = rgb(232, 62, 54)
RED_DARK = rgb(190, 40, 40)
WOOD = rgb(214, 150, 74)
WOOD_LIGHT = rgb(246, 196, 112)
WOOD_DARK = rgb(150, 84, 34)
HONEY = rgb(255, 200, 40)
AMBER = rgb(235, 150, 30)
JAR = rgb(255, 170, 30)
JAR_LIGHT = rgb(255, 206, 96)
GOLD = rgb(255, 206, 60)
GOLD_DARK = rgb(232, 160, 24)
GOLD_LIGHT = rgb(255, 232, 130)
CUSHION = rgb(204, 40, 62)
GEM_RED = rgb(255, 70, 110)
GEM_BLUE = rgb(70, 170, 255)
LIME = rgb(120, 255, 40)
GREEN = rgb(60, 180, 75)
GREEN_LIGHT = rgb(112, 206, 112)
GREEN_DARK = rgb(40, 140, 58)
SKY = rgb(110, 232, 255)
SUNNY = rgb(255, 236, 60)


# ---- shapes this file needs on top of toykit's ------------------------------------------------

def plate(radius, depth, sides=28, soften=0.0):
    """A round plate that faces the camera, with its rims softened."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=radius, radius2=radius, depth=depth)
    if soften > 0:
        rims = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6]
        bmesh.ops.bevel(bm, geom=rims, offset=min(soften, depth * 0.45), offset_type="OFFSET", segments=2,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    return bm


def ring(radius, thickness, around=28, across=10):
    """A doughnut that faces the camera."""
    bm = bmesh.new()
    rows = []
    for i in range(around):
        a = 2 * math.pi * i / around
        row = []
        for j in range(across):
            b = 2 * math.pi * j / across
            r = radius + thickness * math.cos(b)
            row.append(bm.verts.new((r * math.cos(a), r * math.sin(a), thickness * math.sin(b))))
        rows.append(row)
    for i in range(around):
        this, after = rows[i], rows[(i + 1) % around]
        for j in range(across):
            bm.faces.new((this[j], after[j], after[(j + 1) % across], this[(j + 1) % across]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    return bm


def bar(p, start_at, end_at, thick, color, z, depth=0.3, edge=0.1):
    """One rounded stroke of a letter, from start_at to end_at: (right, up) as the camera sees it.
    edge > 0 puts a dark rim behind it, so writing stays readable on top of a model."""
    dx, dy = end_at[0] - start_at[0], end_at[1] - start_at[1]
    length = math.hypot(dx, dy)
    turn = turned(0, 0, math.degrees(math.atan2(dy, -dx)))
    middle = (-(start_at[0] + end_at[0]) / 2, (start_at[1] + end_at[1]) / 2)
    if edge > 0:
        p.add(box((length + thick + edge * 2, thick + edge * 2, depth), round_all=(thick + edge * 2) * 0.3),
              (middle[0], middle[1], z + 0.06), INK, turn)
    p.add(box((length + thick, thick, depth), round_all=thick * 0.3), (middle[0], middle[1], z), color, turn)


def write(p, strokes, at, size, thick, color, z, edge=0.1):
    """strokes: lines in a 1 x 1 square. at = the square's lower left corner, size = its height."""
    for a, b in strokes:
        bar(p, (at[0] + a[0] * size, at[1] + a[1] * size), (at[0] + b[0] * size, at[1] + b[1] * size), thick, color, z,
            edge=edge)


# letters and digits as strokes in a square (x to the right, y up); each is about 0.7 wide
PLUS = [((0.0, 0.5), (0.7, 0.5)), ((0.35, 0.15), (0.35, 0.85))]
TWO = [((0.08, 0.95), (0.6, 0.95)), ((0.66, 0.9), (0.66, 0.62)), ((0.66, 0.62), (0.06, 0.08)), ((0.06, 0.05), (0.7, 0.05))]
TIMES = [((0.05, 0.1), (0.6, 0.75)), ((0.05, 0.75), (0.6, 0.1))]
LETTERS = {
    "A": [((0.0, 0.0), (0.35, 1.0)), ((0.35, 1.0), (0.7, 0.0)), ((0.16, 0.38), (0.54, 0.38))],
    "U": [((0.0, 1.0), (0.0, 0.12)), ((0.7, 1.0), (0.7, 0.12)), ((0.08, 0.0), (0.62, 0.0))],
    "T": [((0.0, 1.0), (0.7, 1.0)), ((0.35, 1.0), (0.35, 0.0))],
    "O": [((0.0, 0.88), (0.0, 0.12)), ((0.7, 0.88), (0.7, 0.12)), ((0.1, 1.0), (0.6, 1.0)), ((0.1, 0.0), (0.6, 0.0))],
    "V": [((0.0, 1.0), (0.35, 0.0)), ((0.7, 1.0), (0.35, 0.0))],
    "I": [((0.35, 1.0), (0.35, 0.0))],
    "P": [((0.0, 0.0), (0.0, 1.0)), ((0.0, 1.0), (0.56, 1.0)), ((0.66, 0.92), (0.66, 0.58)), ((0.0, 0.5), (0.56, 0.5))],
}


def word(p, text, at, size, thick, color, z, gap=0.28, edge=0.1):
    x = at[0]
    for letter in text:
        strokes = LETTERS[letter]
        write(p, strokes, (x, at[1]), size, thick, color, z, edge=edge)
        x += (0.7 if letter != "I" else 0.42) * size + gap * size
        if letter == "I":
            x -= 0.0


def add_crown(p, at, s=1.0, points=8):
    """A gold crown with a red cushion, standing on `at`. s = 1 is 3.5 wide and 2.5 tall."""
    ax, ay, az = at
    p.add(ball(1.38 * s, squash=(1, 0.62, 1)), (ax, ay + 1.12 * s, az), CUSHION)
    p.add(tube(1.6 * s, 0.84 * s, axis="y", sides=24), (ax, ay + 0.6 * s, az), GOLD)
    p.add(tube(1.74 * s, 0.28 * s, axis="y", sides=24), (ax, ay + 0.16 * s, az), GOLD_DARK)
    p.add(tube(1.7 * s, 0.2 * s, axis="y", sides=24), (ax, ay + 1.02 * s, az), GOLD_DARK)
    for k in range(points):
        a = math.radians(k * 360 / points)
        x, z = math.sin(a) * 1.4 * s, math.cos(a) * 1.4 * s
        p.add(tube(0.42 * s, 1.2 * s, axis="y", sides=10, tip_radius=0.07 * s), (ax + x, ay + 1.66 * s, az + z), GOLD)
        p.add(ball(0.2 * s), (ax + x, ay + 2.32 * s, az + z), GOLD_LIGHT)
    for degrees, color in ((180, GEM_RED), (135, GEM_BLUE), (225, GEM_BLUE)):
        a = math.radians(degrees)
        p.add(ball(0.26 * s), (ax + math.sin(a) * 1.6 * s, ay + 0.6 * s, az + math.cos(a) * 1.6 * s), color)


EGG = rgb(255, 240, 200)
EGG_DARK = rgb(250, 222, 160)
EGG_SPOT = rgb(255, 196, 40)
EGG_LAYERS = [(1.2, 0.35), (1.8, 0.4), (2.2, 0.5), (2.4, 0.55), (2.2, 0.5), (1.7, 0.4), (1.1, 0.3)]  # bottom up: wide, tall
QUESTION = ["01110", "10001", "00001", "00010", "00100", "00000", "00100"]


def add_egg(p, at):
    """The game's mystery egg (the same layers as the one by the Queen), with its "?" on the front."""
    ax, ay, az = at
    y = ay
    for index, (wide, tall) in enumerate(EGG_LAYERS):
        p.add(box((wide, tall + 0.06, wide), round_all=min(0.2, tall * 0.42), segments=3), (ax, y + tall / 2, az),
              EGG if index % 2 == 1 else EGG_DARK)
        y += tall
    for dx, dy, dz in ((-1.2, 1.8, 0.5), (1.2, 1.6, -0.5)):
        p.add(box((0.14, 0.42, 0.42), round_all=0.06), (ax + dx, ay + dy, az + dz), EGG_SPOT)
    brick = 0.25
    for row, line in enumerate(QUESTION):
        for column, filled in enumerate(line):
            if filled == "1":
                x = ax + (2 - column) * brick
                yy = ay + 1.5 + (3 - row) * brick
                p.add(box((brick + 0.13, brick + 0.13, 0.1)), (x, yy, az - 1.2), INK)
                p.add(box((brick, brick, 0.16), round_all=0.03), (x, yy, az - 1.26), rgb(255, 176, 30))


# ---- the seven models -------------------------------------------------------------------------

def make_shop():
    p = Piece("Shop")
    # the counter, with a honeycomb badge on the front
    p.add(box((3.7, 1.5, 1.5), round_all=0.2), (0, 0.75, 0), WOOD)
    p.add(box((4.1, 0.32, 1.9), round_all=0.13), (0, 1.62, 0), WOOD_LIGHT)
    p.add(tube(0.52, 0.16, axis="z", sides=6), (0, 0.78, -0.78), AMBER)
    p.add(tube(0.34, 0.2, axis="z", sides=6), (0, 0.78, -0.8), HONEY)
    # two posts hold the roof up
    for x in (1.72, -1.72):
        p.add(box((0.3, 2.5, 0.3), round_all=0.1), (x, 2.95, 0.5), WOOD_DARK)
    # the striped roof, sloping towards the front, with a wavy edge
    stripes, wide = 6, 0.72
    for index in range(stripes):
        x = (index - (stripes - 1) / 2) * wide
        color = RED if index % 2 == 0 else CREAM
        p.add(box((wide + 0.02, 0.36, 2.3), round_all=0.12), (x, 4.25, -0.15), color, turned(-22, 0, 0))
        p.add(tube(wide / 2, 0.32, axis="z", sides=16), (x, 3.78, -1.2), color)
    p.add(box((stripes * wide + 0.1, 0.3, 0.4), round_all=0.12), (0, 4.72, 0.86), RED_DARK)
    # on the counter: a jar of honey and a little pile of coins
    p.add(tube(0.44, 0.82, axis="y", sides=16), (0.95, 2.19, -0.2), JAR)
    p.add(tube(0.36, 0.14, axis="y", sides=16), (0.95, 2.66, -0.2), JAR_LIGHT)
    p.add(tube(0.42, 0.2, axis="y", sides=16), (0.95, 2.8, -0.2), WOOD_DARK)
    for index in range(3):
        p.add(tube(0.42, 0.17, axis="y", sides=20), (-0.95, 1.87 + index * 0.18, -0.2), GOLD if index % 2 == 0 else GOLD_DARK)
    return p


def make_starter():
    p = Piece("PassStarter")
    gift, gift_light = rgb(255, 200, 40), rgb(255, 226, 96)
    p.add(box((3.0, 2.3, 3.0), round_all=0.28), (0, 1.15, 0), gift)
    p.add(box((3.36, 0.8, 3.36), round_all=0.24), (0, 2.6, 0), gift_light)
    # the ribbon, round the box both ways and over the lid
    p.add(box((0.66, 2.34, 3.08), round_all=0.1), (0, 1.15, 0), RED)
    p.add(box((3.08, 2.34, 0.66), round_all=0.1), (0, 1.15, 0), RED)
    p.add(box((0.7, 0.84, 3.44), round_all=0.1), (0, 2.6, 0), RED)
    p.add(box((3.44, 0.84, 0.7), round_all=0.1), (0, 2.6, 0), RED)
    # the bow
    for side in (1, -1):
        p.add(ball(0.74, squash=(1.25, 0.8, 0.62)), (side * 0.86, 3.5, 0), RED, turned(0, 0, side * 24))
        p.add(ball(0.36, squash=(1.25, 0.8, 0.7)), (side * 0.86, 3.5, -0.2), RED_DARK, turned(0, 0, side * 24))
    p.add(ball(0.42), (0, 3.3, 0), RED_DARK)
    return p


PACK = rgb(255, 178, 34)
PACK_DARK = rgb(238, 132, 26)
PACK_LIGHT = rgb(255, 214, 96)
STRAP = rgb(150, 84, 34)
BUCKLE = rgb(236, 238, 245)
EMBLEM = rgb(120, 66, 26)


def make_inventory():
    p = Piece("PassInventory")
    # the Inventory's backpack (the same one as rewards.py draws)
    p.add(box((3.1, 3.3, 1.9), round_all=0.55), (0, 1.85, 0.1), PACK)
    p.add(box((1.25, 0.34, 0.34), round_all=0.14), (0, 3.9, 0.35), STRAP)
    for x in (0.52, -0.52):
        p.add(box((0.3, 0.5, 0.3), round_all=0.1), (x, 3.68, 0.35), STRAP)
    p.add(box((3.24, 1.35, 2.0), round_all=0.45), (0, 2.98, 0.05), PACK_DARK)
    p.add(box((0.56, 1.5, 0.2), round_all=0.08), (0, 2.55, -0.98), STRAP)
    p.add(box((0.82, 0.5, 0.26), round_all=0.1), (0, 2.02, -1.0), BUCKLE)
    p.add(box((0.36, 0.2, 0.3), round_all=0.06), (0, 2.02, -1.03), STRAP)
    p.add(box((2.2, 1.3, 0.6), round_all=0.28), (0, 0.98, -1.0), PACK_LIGHT)
    p.add(box((2.3, 0.3, 0.66), round_all=0.12), (0, 1.56, -1.02), PACK_DARK)
    for x in (1.72, -1.72):
        p.add(box((0.36, 2.5, 0.6), round_all=0.16), (x, 1.9, 0.75), STRAP)
    # the "infinity" sign across the front: two rings side by side
    for side in (1, -1):
        p.add(ring(0.66, 0.31), (side * 0.64, 0.95, -1.62), INK)
        p.add(ring(0.66, 0.2), (side * 0.64, 0.95, -1.74), SKY)
    return p


def make_rolls():
    p = Piece("PassRolls")
    add_egg(p, (1.3, 0.5, 0.5))
    add_egg(p, (-1.3, 0.5, 0.5))
    # "+2" along the bottom
    z = -1.9
    write(p, PLUS, (-1.35, 0.0), 1.5, 0.4, LIME, z, edge=0.12)
    write(p, TWO, (0.2, 0.0), 1.5, 0.4, LIME, z, edge=0.12)
    return p


def make_autosell():
    p = Piece("PassAutoSell")
    # the honey jar (on the left as the camera sees it)
    x = 0.85
    p.add(tube(1.0, 1.8, axis="y", sides=20), (x, 2.2, 0), JAR)
    p.add(tube(0.84, 0.24, axis="y", sides=20), (x, 3.2, 0), JAR_LIGHT)
    p.add(tube(0.96, 0.36, axis="y", sides=20), (x, 3.48, 0), WOOD_DARK)
    p.add(box((1.1, 0.8, 0.2), round_all=0.08), (x, 2.2, -0.95), CREAM)
    p.add(tube(0.26, 0.24, axis="z", sides=6), (x, 2.2, -1.0), AMBER)
    # the coin it turns into
    p.add(plate(1.05, 0.34, soften=0.1), (-1.0, 2.25, -0.75), GOLD)
    p.add(plate(0.76, 0.4, soften=0.06), (-1.0, 2.25, -0.75), GOLD_DARK)
    p.add(tube(0.4, 0.46, axis="z", sides=6), (-1.0, 2.25, -0.75), GOLD_LIGHT)
    # "AUTO" along the bottom
    word(p, "AUTO", (-1.95, 0.0), 0.95, 0.3, LIME, -1.3, gap=0.3, edge=0.11)
    return p


def make_vip():
    p = Piece("PassVIP")
    add_crown(p, (0, 1.45, 0), 1.0)
    word(p, "VIP", (-1.32, 0.0), 1.1, 0.36, WHITE, -1.2, gap=0.34, edge=0.13)
    return p


def make_lucky():
    p = Piece("PassLucky")
    # the four-leaf clover (like the Queen's Luck picture): four round leaves and a stalk
    middle = 2.35
    bar(p, (0.05, middle - 0.6), (-0.5, 0.25), 0.4, GREEN_DARK, 0.1, depth=0.4, edge=0)
    for dx in (0.95, -0.95):
        for dy in (0.95, -0.95):
            p.add(plate(1.02, 0.5, soften=0.12), (dx, middle + dy, 0), GREEN)
            p.add(plate(0.58, 0.56, soften=0.08), (dx, middle + dy, -0.04), GREEN_LIGHT)
    p.add(plate(0.34, 0.6), (0, middle, -0.02), GREEN_DARK)
    # the Queen's crown on top
    add_crown(p, (0, middle + 1.55, 0), 0.56)
    # "x2" at the lower right
    z = -0.9
    write(p, TIMES, (0.5, 0.05), 1.15, 0.32, SUNNY, z, edge=0.11)
    write(p, TWO, (1.3, 0.0), 1.3, 0.34, SUNNY, z, edge=0.11)
    return p


# ---- drawing ------------------------------------------------------------------------------------

scene = start()
library = new_collection("Pieces")
library.hide_render = True


def move(x, y, z, turn=0.0, size=1.0):
    return Matrix.Translation((x, y, z)) @ turned(0, turn, 0) @ Matrix.Scale(size, 4)


def shoot(name, piece, turn, eye, look_at, width):
    studio = new_collection("Studio")
    paint = paint_material()
    source = piece.to_object(library)
    put(source, studio, move(0, 0, 0, turn), paint)
    add_sun(studio, (-0.45, 0.75, -0.6), 2.3)
    setup_render(scene, 768, 768, samples=64, sky=(1, 1, 1, 1), sky_strength=0.75, see_through=True)
    add_camera(studio, scene, eye, look_at, width)
    scene.render.filepath = os.path.join(OUT, "icon-" + name + ".png")
    bpy.ops.render.render(write_still=True)
    say(name, "picture drawn")
    bpy.data.collections.remove(studio)


SHOTS = {
    "shop": ("Shop", make_shop, -24, (0, 9, -40), (0, 2.45, 0), 6.4),
    "starter": ("PassStarter", make_starter, -32, (0, 14, -40), (0, 2.0, 0), 6.2),
    "inventory": ("PassInventory", make_inventory, -16, (0, 9, -40), (0, 2.05, 0), 5.7),
    "rolls": ("PassRolls", make_rolls, -8, (0, 7, -40), (0, 1.9, 0), 6.6),
    "autosell": ("PassAutoSell", make_autosell, -8, (0, 7, -40), (0, 1.95, 0), 5.4),
    "vip": ("PassVIP", make_vip, -8, (0, 9, -40), (0, 2.0, 0), 5.4),
    "lucky": ("PassLucky", make_lucky, -8, (0, 7, -40), (0, 2.5, 0), 6.4),
}

for mode in ALL:
    if mode in MODES:
        name, maker, turn, eye, look_at, width = SHOTS[mode]
        shoot(name, maker(), turn, eye, look_at, width)

say("done")
