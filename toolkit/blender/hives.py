# Build A Bee Empire - the five beehives, made in Blender (chunky toy style).
#
# Run:  blender --background --factory-startup --python hives.py -- <output folder> [preview] [icons] [export]
#
# Pieces (each stands on the ground at (0, 0, 0); the DOOR faces -z, the side the camera looks at):
#   Hive1 .. Hive5   one beehive per level: Tiny, Cozy, Busy, Grand, Royal
#   HiveWindowFrame  the six-sided frame of a "bee window" (1 stud across; the game sizes it)
#   HiveWindowPane   the glass of a bee window (white: the game colours it like the bee that lives there)
#
# A hive is a stack of square rings with rounded corners, so the map's stud pattern sits flat on
# its sides. The bee windows are NOT part of the hive meshes: the game stands one on the front of
# the hive for every bee spot. The numbers it needs for that are written to hive-shapes.lua.

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Matrix  # noqa: E402
from toykit import (Piece, WHITE, add_camera, add_floor, add_sun, box, export_for_roblox, for_blender,  # noqa: E402
                    new_collection, paint_material, put, rgb, say, setup_render, start, tint_material, tube, turned)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
MODES = set(ARGS[1:]) or {"preview"}
os.makedirs(OUT, exist_ok=True)

GRASS = rgb(70, 200, 60)
MEADOW = rgb(205, 235, 140)
HONEY_LIGHT = rgb(255, 208, 76)
HONEY_DARK = rgb(242, 162, 44)
DOOR = rgb(70, 40, 15)
WOOD = rgb(150, 100, 60)
WOOD_DARK = rgb(112, 72, 44)
WOOD_LIGHT = rgb(205, 160, 105)
STONE = rgb(205, 205, 215)
STONE_DARK = rgb(165, 165, 182)
GOLD = rgb(255, 215, 60)
GOLD_DARK = rgb(232, 168, 28)
ROYAL = rgb(150, 95, 225)
ROYAL_LIGHT = rgb(196, 150, 255)
DRIP = rgb(255, 176, 28)
GEM = rgb(255, 70, 110)
CREAM = rgb(255, 246, 210)
STEM = rgb(70, 170, 70)
FRAME = rgb(176, 96, 20)
EMPTY_PANE = rgb(96, 58, 24)
FLOWER_COLORS = [rgb(255, 120, 170), rgb(255, 255, 255), rgb(190, 120, 255), rgb(110, 180, 255)]
BEE_COLORS = [rgb(255, 200, 40), rgb(90, 225, 110), rgb(80, 170, 255), rgb(176, 96, 255), rgb(255, 140, 30)]

R = 0.45  # how round the edges are: 1 = soft and pillowy, 0 = sharp bricks (the same as the other map pieces)
CORNER = 0.16  # how much of a ring's width its rounded corner takes
WINDOW_GAP = 0.24  # the gap between two bee windows, as a part of a window's width


def slab(width, height, corner, soften=0.0, depth=None, segments=4):
    """A square plate (seen from above) with rounded corners and softened top and bottom rims."""
    depth = depth or width
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co.x *= width
        v.co.y *= height
        v.co.z *= depth
    upright = [e for e in bm.edges if abs(e.verts[0].co.y - e.verts[1].co.y) > 1e-6]
    bmesh.ops.bevel(bm, geom=upright, offset=min(corner, min(width, depth) * 0.49), offset_type="OFFSET",
                    segments=segments, profile=0.5, affect="EDGES", clamp_overlap=True)
    if soften > 0:
        rims = [e for e in bm.edges if abs(e.verts[0].co.y - e.verts[1].co.y) < 1e-6
                and abs(abs(e.verts[0].co.y) - height / 2) < 1e-6]
        bmesh.ops.bevel(bm, geom=rims, offset=min(soften, height * 0.42), offset_type="OFFSET", segments=2,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    return bm


def soft(size, amount):
    return box(size, round_all=R * amount)


LEVELS = [
    dict(name="Hive1", title="Tiny Hive", width=4.2, height=4.9, profile=[0.85, 1.0, 0.72], stand="stump",
         stand_width=5.4, stand_height=1.4, window=1.15, drips=1),
    dict(name="Hive2", title="Cozy Hive", width=6.2, height=8.0, profile=[0.85, 1.0, 0.88, 0.62], stand="deck",
         stand_width=8.0, stand_height=1.2, window=1.3, drips=2),
    dict(name="Hive3", title="Busy Hive", width=8.6, height=11.0, profile=[0.82, 1.0, 0.95, 0.8, 0.55], stand="wood",
         stand_width=11.5, stand_height=1.2, window=1.45, drips=3, flowers=True),
    dict(name="Hive4", title="Grand Hive", width=11.0, height=14.4, profile=[0.8, 0.97, 1.0, 0.9, 0.74, 0.5],
         stand="stone", stand_width=15.0, stand_height=1.4, window=1.5, drips=4, bands=CREAM, side_hives=True,
         flowers=True),
    dict(name="Hive5", title="Royal Hive", width=13.6, height=17.6, profile=[0.78, 0.95, 1.0, 0.95, 0.84, 0.68, 0.46],
         stand="royal", stand_width=19.0, stand_height=1.6, window=1.55, drips=5, bands=ROYAL, side_hives=True,
         crown=True),
]


def build_stand(p, level):
    kind, width, tall = level["stand"], level["stand_width"], level["stand_height"]
    if kind == "stump":
        p.add(slab(width, tall, width * 0.34, R * 0.3), (0, tall / 2, 0), WOOD)
        p.add(slab(width * 0.84, 0.1, width * 0.3), (0, tall + 0.03, 0), WOOD_LIGHT)
        p.add(slab(width * 0.5, 0.06, width * 0.18), (0, tall + 0.1, 0), WOOD)
        for x, z, turn in ((width * 0.5, 0.5, 20), (-width * 0.48, -0.7, -30), (0.6, width * 0.5, 80)):
            p.add(soft((1.5, 0.7, 0.9), 0.5), (x, 0.3, z), WOOD_DARK, turned(0, turn, 0))
    elif kind == "deck":
        for x in (-1, 1):
            for z in (-1, 1):
                p.add(soft((1.0, tall - 0.4, 1.0), 0.3), (x * (width / 2 - 0.9), (tall - 0.4) / 2, z * (width / 2 - 0.9)), WOOD_DARK)
        p.add(slab(width, 0.5, 0.5, R * 0.25), (0, tall - 0.25, 0), WOOD_LIGHT)
        for index in range(1, 5):  # the gaps between the planks
            p.add(box((0.08, 0.06, width - 0.5)), (-width / 2 + index * width / 5, tall + 0.01, 0), WOOD)
    elif kind == "wood":
        p.add(slab(width + 0.5, 0.45, 1.0, R * 0.2), (0, 0.225, 0), WOOD)
        p.add(slab(width, tall, 1.2, R * 0.3), (0, tall / 2, 0), WOOD_LIGHT)
        p.add(slab(width * 0.86, 0.1, 1.0), (0, tall + 0.03, 0), CREAM)
    elif kind == "stone":
        p.add(slab(width + 0.6, 0.55, 0.9, R * 0.2), (0, 0.275, 0), STONE_DARK)
        p.add(slab(width, tall, 1.0, R * 0.3), (0, tall / 2, 0), STONE)
        p.add(slab(width * 0.84, 0.12, 0.9), (0, tall + 0.04, 0), rgb(232, 232, 240))
        for x in (-1, 1):  # a few darker blocks, like laid stones
            for z in (-1, 1):
                p.add(soft((2.2, 0.7, 0.3), 0.3), (x * width * 0.24, tall * 0.55, z * (width / 2 + 0.02)), STONE_DARK)
                p.add(soft((0.3, 0.7, 2.2), 0.3), (x * (width / 2 + 0.02), tall * 0.55, z * width * 0.24), STONE_DARK)
    elif kind == "royal":
        p.add(slab(width + 0.7, 0.6, 1.2, R * 0.2), (0, 0.3, 0), GOLD_DARK)
        p.add(slab(width, tall, 1.4, R * 0.3), (0, tall / 2, 0), ROYAL)
        p.add(slab(width + 0.36, 0.34, 1.5, R * 0.14), (0, tall - 0.12, 0), GOLD)
        p.add(slab(width * 0.86, 0.3, 1.2, R * 0.12), (0, tall + 0.13, 0), ROYAL_LIGHT)
        for x in (-1, 1):
            for z in (-1, 1):
                at = (x * (width / 2 - 1.0), 0, z * (width / 2 - 1.0))
                p.add(soft((1.1, 1.3, 1.1), 0.35), (at[0], tall + 0.6, at[2]), GOLD)
                p.add(soft((0.8, 0.8, 0.8), 0.7), (at[0], tall + 1.55, at[2]), GOLD_DARK)


def build_body(p, width, height, profile, base, center=(0, 0), small=False):
    """The honey-coloured body: stacked rings, a cap and a doorway on the front. Returns
    (rings, top) where rings is a list of (middle height, width, tall)."""
    cx, cz = center
    tall = height / (len(profile) + 0.4)
    rings = []
    y = base
    for index, part in enumerate(profile):
        wide = width * part
        p.add(slab(wide, tall + 0.03, wide * CORNER, R * (0.26 if small else 0.36)), (cx, y + tall / 2, cz),
              HONEY_LIGHT if index % 2 == 0 else HONEY_DARK)
        rings.append((y + tall / 2, wide, tall))
        y += tall
    top_wide = width * profile[-1]
    p.add(slab(top_wide * 0.62, tall * 0.45, top_wide * 0.62 * CORNER, R * 0.2), (cx, y + tall * 0.22, cz),
          HONEY_LIGHT if len(profile) % 2 == 0 else HONEY_DARK)
    top = y + tall * 0.45

    # the doorway, in a little wooden frame
    door_wide = max(0.5, width * 0.27)
    door_tall = tall * 0.8
    front = cz - width * profile[0] / 2
    p.add(soft((door_wide, door_tall, 0.3), 0.3), (cx, base + door_tall / 2, front - 0.02), DOOR)
    if not small:
        post = door_wide * 0.16
        for side in (-1, 1):
            p.add(soft((post, door_tall + post * 0.6, 0.42), 0.2), (cx + side * (door_wide / 2 + post * 0.4), base + door_tall / 2 + post * 0.3, front - 0.06), WOOD)
        p.add(soft((door_wide + post * 2.4, post, 0.5), 0.2), (cx, base + door_tall + post * 0.5, front - 0.08), WOOD_LIGHT)
        p.add(soft((door_wide * 1.5, 0.16, door_wide * 0.8), 0.2), (cx, base + 0.08, front - door_wide * 0.4), WOOD_LIGHT)
    return rings, top


def build_hive(level):
    p = Piece(level["name"])
    width, height, profile = level["width"], level["height"], level["profile"]
    base = level["stand_height"]
    build_stand(p, level)
    rings, top = build_body(p, width, height, profile, base)
    tall = rings[0][2]

    # honey running down the sides and the back (never the front: that is where the bee windows go)
    count = level.get("drips", 0)
    places = [(1, 0.18, 2), (-1, -0.2, 3), (0, 0.22, 2), (1, -0.24, 4), (-1, 0.16, 5), (0, -0.18, 4)]
    for index in range(count):
        side, along, ring_number = places[index % len(places)]
        ring_number = min(len(rings), ring_number)
        y, wide, _ = rings[ring_number - 1]
        length = tall * (0.7 + 0.2 * (index % 2))
        thick = max(0.14, width * 0.03)
        size = width * 0.09
        top_y = y + tall / 2 - 0.02
        if side == 0:
            p.add(soft((size, length, thick), 0.6), (along * wide, top_y - length / 2, wide / 2 + thick * 0.3), DRIP)
        else:
            p.add(soft((thick, length, size), 0.6), (side * (wide / 2 + thick * 0.3), top_y - length / 2, along * wide), DRIP)

    # and a little honey on the front, only on the top rings (above the bee windows)
    first_free = min(len(rings), 5)
    for index, ring_number in enumerate(range(first_free, len(rings) + 1)):
        y, wide, _ = rings[ring_number - 1]
        length = tall * (0.5 + 0.18 * (index % 2))
        thick = max(0.14, width * 0.03)
        along = (0.22 if index % 2 == 0 else -0.26) * wide
        p.add(soft((width * 0.085, length, thick), 0.6), (along, y + tall / 2 - 0.02 - length / 2, -(wide / 2 + thick * 0.3)), DRIP)

    # coloured bands between the upper rings (above the windows)
    if level.get("bands"):
        for ring_number in (1, len(rings) - 3, len(rings) - 2):
            y, wide, _ = rings[ring_number - 1]
            wider = max(wide, rings[ring_number][1])
            p.add(slab(wider + 0.3, tall * 0.15, (wider + 0.3) * CORNER, R * 0.1), (0, y + tall / 2, 0), level["bands"])

    # two baby hives on the stand, either side of the door
    if level.get("side_hives"):
        reach = level["stand_width"] / 2 - width * 0.14
        for side in (-1, 1):
            build_body(p, width * 0.25, height * 0.25, [0.85, 1.0, 0.72], base, (side * reach, -(level["stand_width"] / 2 - width * 0.16)), small=True)
            p.add(soft((width * 0.07, width * 0.07, width * 0.07), 0.6), (side * reach, base + height * 0.25 * 1.02, -(level["stand_width"] / 2 - width * 0.16)), HONEY_DARK)

    # little flowers at the back corners of the stand
    if level.get("flowers"):
        reach = level["stand_width"] / 2 - 0.9
        for index, (x, z) in enumerate(((-1, 1), (1, 1), (-1, 0.1), (1, 0.1))):
            at = (x * reach, base, z * reach)
            p.add(soft((0.22, 1.1, 0.22), 0.4), (at[0], base + 0.55, at[2]), STEM)
            p.add(soft((0.95, 0.7, 0.95), 0.6), (at[0], base + 1.3, at[2]), FLOWER_COLORS[index])
            p.add(soft((0.42, 0.3, 0.42), 0.6), (at[0], base + 1.75, at[2]), GOLD)

    # the very top: a knob, or a crown for the Royal Hive
    top_wide = width * profile[-1]
    if level.get("crown"):
        crown = top_wide * 0.78
        p.add(slab(crown, tall * 0.42, crown * CORNER, R * 0.2), (0, top + tall * 0.21, 0), GOLD)
        for x in (-1, 0, 1):
            for z in (-1, 0, 1):
                if x == 0 and z == 0:
                    continue
                high = tall * (0.62 if (x != 0 and z != 0) else 0.44)
                p.add(soft((crown * 0.22, high, crown * 0.22), 0.4), (x * crown * 0.38, top + tall * 0.42 + high / 2 - 0.05, z * crown * 0.38), GOLD)
        for x, z in ((0, -1), (1, 0), (-1, 0), (0, 1)):
            p.add(soft((crown * 0.2, crown * 0.2, crown * 0.2), 0.8), (x * crown * 0.52, top + tall * 0.21, z * crown * 0.52), GEM)
        p.add(soft((crown * 0.3, crown * 0.3, crown * 0.3), 0.8), (0, top + tall * 0.42 + crown * 0.12, 0), GEM)
        top += tall * 1.04
    else:
        knob = top_wide * 0.28
        p.add(soft((knob, knob, knob), 0.9), (0, top + knob / 2 - 0.04, 0), HONEY_DARK)
        top += knob - 0.04

    level["rings"] = rings
    level["top"] = top
    return p


def window_rows(count, rings, size):
    """How many bee windows go on each ring: a honeycomb triangle on the rings above the door.
    (The same sum is done by the game's HiveModelFactory.)"""
    usable = rings[1:-1] or rings[1:] or rings
    pitch = size * (1 + WINDOW_GAP)

    def fits(ring):
        flat = ring[1] * (1 - 2 * CORNER) + ring[1] * CORNER * 0.6
        return max(1, int((flat - size) / pitch) + 1)

    for base_row in range(1, 20):
        rows = []
        left = count
        for index, ring in enumerate(usable):
            want = min(base_row - index, fits(ring), left)
            if want <= 0:
                break
            rows.append(want)
            left -= want
        if left <= 0:
            return rows, usable
    return rows, usable


def window_spots(level, count):
    rows, usable = window_rows(count, level["rings"], level["window"])
    pitch = level["window"] * (1 + WINDOW_GAP)
    spots = []
    for row, ring in zip(rows, usable):
        for index in range(row):
            spots.append(((index - (row - 1) / 2) * pitch, ring[0], -ring[1] / 2))
    return spots


def make_window_frame():
    p = Piece("HiveWindowFrame")
    p.add(tube(0.5 / 0.866, 0.22, axis="z", sides=6), (0, 0, -0.11), FRAME)
    return p


def make_window_pane():
    p = Piece("HiveWindowPane")
    p.add(tube(0.4 / 0.866, 0.1, axis="z", sides=6), (0, 0, -0.2), WHITE)
    return p


CAPACITY = [2, 4, 6, 9, 12]  # GameConfig.HiveLevels[...].Capacity

scene = start()
pieces = {}
for level in LEVELS:
    piece = build_hive(level)
    pieces[piece.name] = piece
for maker in (make_window_frame, make_window_pane):
    piece = maker()
    pieces[piece.name] = piece
library = new_collection("Pieces")
objects = {name: piece.to_object(library) for name, piece in pieces.items()}
for name, piece in pieces.items():
    low, high = piece.bounds()
    say("piece", name, "triangles", piece.triangles(), "size", [round(high[i] - low[i], 2) for i in range(3)])

# the numbers the game needs (pasted into HiveModelFactory)
lines = ["-- made by blender/hives.py: do not edit by hand", "local SHAPES = {"]
for index, level in enumerate(LEVELS):
    rings = ", ".join("{ %.3f, %.3f }" % (y, wide) for y, wide, _ in level["rings"])
    rows, _ = window_rows(CAPACITY[index], level["rings"], level["window"])
    lines.append(
        "\t{ Mesh = \"%s\", Height = %.2f, StandWidth = %.2f, BodyWidth = %.2f, BodyBase = %.2f, BodyHeight = %.2f, "
        "WindowSize = %.2f, Rings = { %s } }, -- %s: rows %s"
        % (level["name"], level["top"], level["stand_width"], level["width"], level["stand_height"], level["height"],
           level["window"], rings, level["title"], rows))
lines.append("}")
lines.append("local CORNER = %.2f -- how much of a ring's width its rounded corner takes" % CORNER)
lines.append("local WINDOW_GAP = %.2f -- the gap between two bee windows, as a part of a window's width" % WINDOW_GAP)
with open(os.path.join(OUT, "hive-shapes.lua"), "w") as handle:
    handle.write("\n".join(lines) + "\n")
for index, level in enumerate(LEVELS):
    say(level["name"], "top", round(level["top"], 2), "windows", window_rows(CAPACITY[index], level["rings"], level["window"])[0])


def move(x, y, z, turn=0.0, size=1.0):
    return Matrix.Translation((x, y, z)) @ turned(0, turn, 0) @ Matrix.Scale(size, 4)


def place_hive(collection, index, x, z, paint, pane_material, lit=()):
    """Stands one hive in a picture, with its bee windows. lit = the colours of the bees that live in it."""
    level = LEVELS[index]
    put(objects[level["name"]], collection, move(x, 0, z), paint)
    size = level["window"]
    for number, (wx, wy, wz) in enumerate(window_spots(level, CAPACITY[index])):
        where = Matrix.Translation((x + wx, wy, z + wz)) @ Matrix.Scale(size, 4)
        put(objects["HiveWindowFrame"], collection, where, paint)
        color = lit[number] if number < len(lit) else EMPTY_PANE
        put(objects["HiveWindowPane"], collection, where, pane_material(color))


materials = {}


def pane_material(color):
    key = tuple(round(c, 3) for c in color)
    if key not in materials:
        materials[key] = tint_material(color)
    return materials[key]


if "preview" in MODES:
    library.hide_render = True
    stage = new_collection("Stage")
    paint = paint_material()
    lawn = Piece("Lawn")
    lawn.add(box((96, 0.2, 34)), (2, 0.1, 0), MEADOW)
    put(lawn.to_object(library), stage, move(0, 0, 0), paint)
    spots = [-36, -25.5, -12, 6.5, 30]
    lit = [
        [BEE_COLORS[0]],
        [BEE_COLORS[0], BEE_COLORS[1], BEE_COLORS[0]],
        [BEE_COLORS[1], BEE_COLORS[0], BEE_COLORS[2], BEE_COLORS[0], BEE_COLORS[1]],
        [BEE_COLORS[2], BEE_COLORS[0], BEE_COLORS[1], BEE_COLORS[3], BEE_COLORS[1], BEE_COLORS[0], BEE_COLORS[2]],
        [BEE_COLORS[3], BEE_COLORS[1], BEE_COLORS[4], BEE_COLORS[2], BEE_COLORS[0], BEE_COLORS[2], BEE_COLORS[3],
         BEE_COLORS[1], BEE_COLORS[4], BEE_COLORS[0]],
    ]
    for index in range(5):
        place_hive(stage, index, spots[index], 0, paint, pane_material, lit[index])
    # a figure as tall as a player, for scale
    figure = Piece("Figure")
    figure.add(soft((2.0, 2.0, 1.0), 0.5), (0, 3.0, 0), rgb(80, 150, 240))
    figure.add(soft((1.2, 1.2, 1.2), 0.6), (0, 4.6, 0), rgb(255, 220, 180))
    figure.add(soft((0.9, 2.0, 0.9), 0.4), (-0.5, 1.0, 0), rgb(60, 60, 80))
    figure.add(soft((0.9, 2.0, 0.9), 0.4), (0.5, 1.0, 0), rgb(60, 60, 80))
    put(figure.to_object(library), stage, move(-31, 0.2, -6), paint)
    add_floor(stage, 0, GRASS)
    add_sun(stage, (-0.45, 0.75, -0.6), 2.3)
    # (white light, like the menu pictures: a blue sky turns the honey colours green)
    engine = setup_render(scene, 2000, 900, samples=64, sky=(1, 1, 1, 1), sky_strength=0.75, see_through=False)
    add_camera(stage, scene, (-2, 34, -110), (-1.5, 10.5, 0), 88)
    scene.render.filepath = os.path.join(OUT, "hives-preview.png")
    bpy.ops.render.render(write_still=True)
    say("preview drawn with", engine)

    for obj in list(stage.objects):
        if obj.type == "CAMERA":
            bpy.data.objects.remove(obj)
    add_camera(stage, scene, (52, 30, -62), (24, 9.5, 0), 40)
    scene.render.resolution_x, scene.render.resolution_y = 1400, 1100
    scene.render.filepath = os.path.join(OUT, "hives-royal.png")
    bpy.ops.render.render(write_still=True)
    say("close-up drawn")
    bpy.data.collections.remove(stage)

if "icons" in MODES:
    library.hide_render = True
    paint = paint_material()
    for index, level in enumerate(LEVELS):
        studio = new_collection("Studio" + str(index))
        place_hive(studio, index, 0, 0, paint, pane_material, [])
        add_sun(studio, (-0.45, 0.75, -0.6), 2.3)
        setup_render(scene, 768, 768, samples=64, sky=(1, 1, 1, 1), sky_strength=0.75, see_through=True)
        tall = level["top"]
        add_camera(studio, scene, (-tall * 1.2, tall * 1.5, -tall * 3.2), (0, tall * 0.47, 0), max(tall, level["stand_width"]) * 1.42)
        scene.render.filepath = os.path.join(OUT, "icon-Hive%d.png" % (index + 1))
        bpy.ops.render.render(write_still=True)
        bpy.data.collections.remove(studio)
    say("menu pictures drawn")

if "export" in MODES:
    export_for_roblox(scene, pieces, objects, os.path.join(OUT, "BeeEmpire-hives.fbx"))

say("done")
