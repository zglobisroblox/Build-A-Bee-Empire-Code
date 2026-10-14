# Build A Bee Empire - the Queen's roll area, made in Blender (chunky toy style).
#
# Run:  blender --background --factory-startup --python rollarea.py -- <output folder> [preview] [icons] [export]
#
# Pieces (each stands on the ground at (0, 0, 0); its FRONT is the side towards -z, the side
# the preview camera looks at; the game turns it round to face the right way):
#   Stall         the honeycomb stand a rolled bee hatches on (the dark screen is added by the game)
#   StallBulbs    the little lights round its screen (white: the game makes them glow yellow)
#   Pedestal      the Queen's round rug, two wooden steps, gold knobs and cushion
#   PedestalGems  the gems between the knobs (white: the game makes them glow purple)
#   Egg           the mystery egg that shows while a roll is hatching

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

# the map's own colours (from the game's PlotBuilder)
GRASS = rgb(70, 200, 60)
EARTH = rgb(215, 170, 110)
PLINTH = rgb(120, 70, 30)
HONEY = rgb(255, 200, 40)
CELL_RIM = rgb(225, 130, 25)
CELL_FILL = rgb(255, 180, 45)
CELL_LIGHT = rgb(255, 228, 100)
CELL_EDGE = rgb(190, 100, 15)
RUNNY = rgb(255, 222, 70)
AMBER = rgb(235, 150, 30)
RED = rgb(225, 40, 40)
RED_DARK = rgb(176, 28, 34)
BULB = rgb(255, 230, 40)
NAVY = rgb(30, 30, 62)
WOOD = rgb(195, 135, 80)
TAN = rgb(215, 170, 110)
TAN_LIGHT = rgb(235, 200, 145)
PURPLE = rgb(150, 95, 225)
PURPLE_LIGHT = rgb(196, 150, 255)
GOLD = rgb(255, 200, 40)
GOLD_DARK = rgb(232, 160, 24)
GEM = rgb(180, 80, 255)
EGG = rgb(255, 240, 200)
EGG_DARK = rgb(250, 222, 160)
EGG_SPOT = rgb(255, 196, 40)
INK = rgb(35, 30, 30)

R = 0.45  # how round the edges are: 1 = soft and pillowy, 0 = sharp bricks (the same as the nature pieces)


def disc(radius, height, sides=32, soften=0.0, segments=2):
    """An upright round plate (it stands on its flat side), with its rims softened."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=radius, radius2=radius, depth=height)
    if soften > 0:
        rims = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6]
        bmesh.ops.bevel(bm, geom=rims, offset=min(soften, height * 0.45), offset_type="OFFSET", segments=segments,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=Matrix.Rotation(math.radians(-90), 3, "X"))
    return bm


def cell_color(number):
    if number % 5 == 2:
        return CELL_LIGHT
    if number % 7 == 4:
        return CELL_RIM
    return CELL_FILL


def comb_wall(piece, columns, rows, wide, middle_y, pitch_y, place, axis):
    """Rows of six-sided honeycomb cells standing a little proud of a wall.
    place(along, y) gives the middle of a cell; axis is the way the wall faces."""
    pitch = wide / (columns + 0.1)
    number = 0
    for row in range(rows):
        shifted = row % 2 == 1  # every other row sits half a cell along, like real honeycomb
        for column in range(columns - (1 if shifted else 0)):
            number += 1
            along = (column - (columns - 1) / 2 + (0.5 if shifted else 0)) * pitch
            y = middle_y + (row - (rows - 1) / 2) * pitch_y
            piece.add(tube(pitch * 0.56, 0.12, axis=axis, sides=6), place(along, y, 0.0), CELL_EDGE)
            piece.add(tube(pitch * 0.45, 0.2, axis=axis, sides=6), place(along, y, 0.02), cell_color(number))


def make_stall():
    p = Piece("Stall")
    front = -1  # the screen is on the side towards -z
    p.add(box((6.45, 0.375, 4.65), round_all=R * 0.16), (0, 0.1875, 0), PLINTH)
    p.add(box((6.0, 3.0, 4.2), round_all=R * 0.24), (0, 1.875, 0), HONEY)
    # honeycomb on both sides and on the back
    for side in (1, -1):
        comb_wall(p, 4, 3, 4.2, 1.9, 0.86, lambda along, y, out, side=side: (side * (3.0 + out), y, along), "x")
    comb_wall(p, 6, 3, 6.0, 1.9, 0.86, lambda along, y, out: (along, y, 2.1 + out), "z")

    # the band, and the cap of runny honey with drips over the edge
    p.add(box((6.45, 0.75, 4.65), round_all=R * 0.22), (0, 3.75, 0), CELL_RIM)
    p.add(box((6.62, 0.26, 4.82), round_all=R * 0.22), (0, 4.24, 0), RUNNY)
    for x, z, length in ((-2.2, front * 2.42, 0.95), (-1.5, front * 2.42, 0.5), (2.35, front * 2.42, 0.75),
                         (0.9, 2.42, 0.65), (-2.5, 2.42, 1.0), (1.9, 2.42, 0.4)):
        p.add(box((0.5, length, 0.22), round_all=R * 0.22), (x, 4.2 - length / 2, z), RUNNY)
    for x, z, length in ((-3.32, -0.9, 0.9), (-3.32, 1.2, 0.5), (3.32, 0.3, 1.0), (3.32, -1.5, 0.45)):
        p.add(box((0.22, length, 0.5), round_all=R * 0.22), (x, 4.2 - length / 2, z), RUNNY)

    # the six-sided cell the bee stands on, with two little cells behind it
    p.add(tube(1.9, 0.3, axis="y", sides=6), (0, 4.5, front * 0.22), AMBER)
    p.add(tube(1.56, 0.1, axis="y", sides=6), (0, 4.7, front * 0.22), rgb(255, 232, 120))
    for side in (1, -1):
        p.add(tube(0.82, 0.22, axis="y", sides=6), (side * 2.33, 4.46, 1.43), AMBER)
        p.add(tube(0.6, 0.08, axis="y", sides=6), (side * 2.33, 4.61, 1.43), CELL_FILL)

    # the red frame round the screen (the screen itself is put in by the game)
    z = front * 2.26
    for y in (3.15, 0.6):
        p.add(box((5.55, 0.45, 0.5), round_all=R * 0.2), (0, y, z), RED)
    for x in (-2.55, 2.55):
        p.add(box((0.45, 2.1, 0.5), round_all=R * 0.2), (x, 1.875, z), RED)
        for y in (3.15, 0.6):
            p.add(box((0.7, 0.7, 0.62), round_all=R * 0.24), (x, y, z), RED_DARK)
    return p


def make_stall_bulbs():
    """White: the game turns them into glowing yellow lights."""
    p = Piece("StallBulbs")
    z = -2.56
    for index in range(6):
        for y in (3.15, 0.6):
            p.add(box((0.34, 0.34, 0.22), round_all=0.07), (-1.875 + index * 0.75, y, z), WHITE)
    for index in range(3):
        for x in (-2.55, 2.55):
            p.add(box((0.34, 0.34, 0.22), round_all=0.07), (x, 1.2 + index * 0.675, z), WHITE)
    for x in (-2.55, 2.55):
        for y in (3.15, 0.6):
            p.add(box((0.3, 0.3, 0.16), round_all=0.06), (x, y, z - 0.08), WHITE)
    return p


def ring_spot(angle_degrees, radius, y):
    angle = math.radians(angle_degrees)
    return (math.sin(angle) * radius, y, math.cos(angle) * radius)


def make_pedestal():
    p = Piece("Pedestal")
    p.add(disc(6.7, 0.08, 40), (0, 0.04, 0), PURPLE)  # the rug
    p.add(disc(6.0, 0.06, 40), (0, 0.11, 0), PURPLE_LIGHT)
    p.add(disc(4.8, 0.5, 40, soften=R * 0.24), (0, 0.25, 0), WOOD)
    p.add(disc(4.0, 0.5, 40, soften=R * 0.24), (0, 0.75, 0), TAN)
    p.add(disc(3.2, 0.06, 40), (0, 1.03, 0), TAN_LIGHT)
    p.add(disc(2.4, 0.45, 32, soften=R * 0.4, segments=3), (0, 1.26, 0), PURPLE)  # the cushion
    p.add(disc(1.7, 0.06, 32), (0, 1.5, 0), PURPLE_LIGHT)
    for index in range(4):
        p.add(box((0.5, 0.5, 0.5), round_all=R * 0.3), ring_spot(45 + index * 90, 2.45, 1.26), GOLD, turned(0, 45 + index * 90, 0))
    # gold knobs round the lower step (the gems between them are their own piece)
    for index in range(8):
        angle = 22.5 + index * 45
        p.add(box((0.86, 0.8, 0.86), round_all=R * 0.42), ring_spot(angle, 4.4, 0.9), GOLD, turned(0, angle, 0))
        p.add(box((0.56, 0.5, 0.56), round_all=R * 0.36), ring_spot(angle, 4.4, 1.5), GOLD_DARK, turned(0, angle, 0))
    return p


def make_pedestal_gems():
    """White: the game turns them into glowing purple gems."""
    p = Piece("PedestalGems")
    for index in range(8):
        angle = index * 45
        p.add(box((0.62, 0.62, 0.62), round_all=0.16), ring_spot(angle, 4.4, 0.82), WHITE, turned(0, angle + 45, 0))
    return p


EGG_LAYERS = [(1.2, 0.35), (1.8, 0.4), (2.2, 0.5), (2.4, 0.55), (2.2, 0.5), (1.7, 0.4), (1.1, 0.3)]  # bottom up: wide, tall


def make_egg():
    """The mystery egg, standing on (0, 0, 0). 3 studs tall."""
    p = Piece("Egg")
    y = 0.0
    for index, (wide, tall) in enumerate(EGG_LAYERS):
        p.add(box((wide, tall + 0.06, wide), round_all=min(0.2, tall * 0.42), segments=3), (0, y + tall / 2, 0),
              EGG if index % 2 == 1 else EGG_DARK)
        y += tall
    for at in ((-1.2, 1.8, 0.5), (-1.1, 1.05, -0.4), (1.2, 1.6, -0.5), (1.1, 2.15, 0.35)):
        p.add(box((0.14, 0.42, 0.42), round_all=0.06), at, EGG_SPOT)
    for at in ((0.45, 2.2, 1.1), (-0.5, 0.95, 1.2), (0.3, 1.5, 1.2)):
        p.add(box((0.42, 0.42, 0.14), round_all=0.06), at, EGG_SPOT)
    return p


# a "?" built from little bricks: 1 = a brick. It goes on the front of the egg in the menu picture.
QUESTION = ["01110",
            "10001",
            "00001",
            "00010",
            "00100",
            "00000",
            "00100"]


def make_question():
    p = Piece("EggMark")
    brick = 0.25
    for row, line in enumerate(QUESTION):
        for column, filled in enumerate(line):
            if filled == "1":
                x = (2 - column) * brick  # (seen from the front, +x is on the left)
                y = 1.5 + (3 - row) * brick
                p.add(box((brick + 0.13, brick + 0.13, 0.1)), (x, y, -1.2), INK)
                p.add(box((brick, brick, 0.16), round_all=0.03), (x, y, -1.26), rgb(255, 176, 30))
    return p


MAKERS = [make_stall, make_stall_bulbs, make_pedestal, make_pedestal_gems, make_egg]
EXTRA_MAKERS = [make_question]  # only for the pictures; not sent to the game

scene = start()
pieces = {}
for maker in MAKERS:
    piece = maker()
    pieces[piece.name] = piece
library = new_collection("Pieces")
objects = {name: piece.to_object(library) for name, piece in pieces.items()}
extras = {}
for maker in EXTRA_MAKERS:
    piece = maker()
    extras[piece.name] = piece.to_object(library)
for name, piece in pieces.items():
    low, high = piece.bounds()
    say("piece", name, "triangles", piece.triangles(), "size", [round(high[i] - low[i], 2) for i in range(3)])


def move(x, y, z, turn=0.0, size=1.0):
    return Matrix.Translation((x, y, z)) @ turned(0, turn, 0) @ Matrix.Scale(size, 4)


def screen_dummy():
    """Stands in for the game's dark screen, so the pictures look like the real thing."""
    p = Piece("ScreenDummy")
    p.add(box((4.65, 2.1, 0.2)), (0, 1.875, -2.12), NAVY)
    return p.to_object(library)


if "preview" in MODES:
    library.hide_render = True
    stage = new_collection("Stage")
    paint = paint_material()
    bulbs = tint_material(BULB)
    gems = tint_material(GEM)
    screen = screen_dummy()

    def stall(x, z, turn):
        where = move(x, 0.2, z, turn)
        put(objects["Stall"], stage, where, paint)
        put(objects["StallBulbs"], stage, where, bulbs)
        put(screen, stage, where, paint)

    # a patch of bare earth, like the pad in the game
    earth = Piece("Earth")
    earth.add(box((44, 0.2, 30)), (0, 0.1, 2), EARTH)
    put(earth.to_object(library), stage, move(0, 0, 0), paint)

    stall(0, 12, 0)
    stall(7.7, 11.4, 9)
    stall(-7.7, 11.4, -9)
    put(objects["Egg"], stage, move(0, 0.2 + 4.75 + 0.9, 12 - 0.22), paint)
    put(objects["Pedestal"], stage, move(0, 0.2, -1.5), paint)
    put(objects["PedestalGems"], stage, move(0, 0.2, -1.5), gems)

    add_floor(stage, 0, GRASS)
    add_sun(stage, (-0.5, 0.8, -0.4), 1.9)
    engine = setup_render(scene, 1800, 1000, samples=64, sky=for_blender(rgb(150, 210, 255)), sky_strength=0.55, see_through=False)
    add_camera(stage, scene, (10, 26, -60), (0, 3.2, 5), 34)
    scene.render.filepath = os.path.join(OUT, "rollarea-preview.png")
    bpy.ops.render.render(write_still=True)
    say("preview drawn with", engine)

    # a close look at one stand
    for obj in list(stage.objects):
        if obj.type == "CAMERA":
            bpy.data.objects.remove(obj)
    add_camera(stage, scene, (-16, 15, -30), (0, 3.4, 12), 13)
    scene.render.resolution_x, scene.render.resolution_y = 1200, 1000
    scene.render.filepath = os.path.join(OUT, "rollarea-stall.png")
    bpy.ops.render.render(write_still=True)
    say("close-up drawn")
    bpy.data.collections.remove(stage)

if "icons" in MODES:
    library.hide_render = True
    studio = new_collection("Studio")
    paint = paint_material()
    put(objects["Egg"], studio, move(0, 0, 0, -24), paint)
    put(extras["EggMark"], studio, move(0, 0, 0, -24), paint)
    add_sun(studio, (-0.45, 0.75, -0.6), 2.3)
    setup_render(scene, 768, 768, samples=64, sky=(1, 1, 1, 1), sky_strength=0.75, see_through=True)
    add_camera(studio, scene, (0, 9, -40), (0, 1.5, 0), 4.2)
    scene.render.filepath = os.path.join(OUT, "icon-Egg.png")
    bpy.ops.render.render(write_still=True)
    say("menu picture drawn")
    bpy.data.collections.remove(studio)

if "fasticon" in MODES:
    # The Roll Speed upgrade's menu picture: the mystery egg leaning forward, with speed lines behind it.
    library.hide_render = True
    studio = new_collection("Studio")
    paint = paint_material()
    lean = Matrix.Translation((-0.75, 0, 0)) @ turned(0, 0, 13) @ turned(0, -24, 0)
    put(objects["Egg"], studio, lean, paint)
    put(extras["EggMark"], studio, lean, paint)
    streaks = Piece("SpeedLines")
    # (seen from the front, +x is on the LEFT: the lines trail off to the left of the egg)
    for long, y, x in ((1.5, 2.5, 1.75), (1.15, 1.65, 2.2), (1.4, 0.8, 1.7)):
        streaks.add(box((long, 0.34, 0.3), round_all=0.13), (x, y, 0), rgb(150, 208, 255))
        streaks.add(box((long * 0.55, 0.13, 0.1), round_all=0.04), (x - long * 0.1, y + 0.05, -0.18), WHITE)
    put(streaks.to_object(library), studio, move(0, 0, 0), paint)
    add_sun(studio, (-0.45, 0.75, -0.6), 2.3)
    setup_render(scene, 768, 768, samples=64, sky=(1, 1, 1, 1), sky_strength=0.75, see_through=True)
    add_camera(studio, scene, (0, 9, -40), (0.1, 1.6, 0), 5.9)
    scene.render.filepath = os.path.join(OUT, "icon-FastEgg.png")
    bpy.ops.render.render(write_still=True)
    say("roll speed picture drawn")
    bpy.data.collections.remove(studio)

if "export" in MODES:
    export_for_roblox(scene, pieces, objects, os.path.join(OUT, "BeeEmpire-rollarea.fbx"))

say("done")
