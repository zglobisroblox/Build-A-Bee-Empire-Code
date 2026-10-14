# Build A Bee Empire - menu pictures for the reward windows, made in Blender (chunky toy style).
#
# Run:  blender --background --factory-startup --python rewards.py -- <ABSOLUTE output folder> [calendar]
#
# Pictures (768 x 768, see-through background; icon-tools\finish-blender-icons.ps1 trims them and
# adds the ink outline):
#   icon-Calendar.png   a tear-off calendar with a big green tick: the Daily Rewards button and window
#   icon-Backpack.png   a honey-coloured backpack with a honeycomb badge: the Inventory button and window
#                       (mode: backpack)
#
# Seen from the front (the camera's side, -z), +x is on the LEFT.

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Matrix  # noqa: E402
from toykit import (Piece, add_camera, add_sun, box, new_collection, paint_material, put, rgb, say,  # noqa: E402
                    setup_render, start, tube, turned)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
MODES = set(ARGS[1:]) or {"calendar"}
os.makedirs(OUT, exist_ok=True)

PAGE = rgb(252, 246, 230)
PAGE_BACK = rgb(226, 214, 190)
TOP = rgb(232, 62, 54)
TOP_DARK = rgb(190, 40, 40)
RING = rgb(70, 70, 88)
TICK = rgb(70, 208, 66)

R = 0.45  # how round the edges are (the same as the other pieces)


def make_calendar():
    p = Piece("Calendar")
    # a stack of pages: the front one bright, two more peeking out behind and below
    p.add(box((3.5, 3.5, 0.3), round_all=0.16 * R * 2), (-0.16, 1.82, 0.42), PAGE_BACK)
    p.add(box((3.55, 3.55, 0.3), round_all=0.16 * R * 2), (-0.08, 1.9, 0.2), PAGE_BACK)
    p.add(box((3.6, 3.6, 0.42), round_all=0.2 * R * 2), (0, 2.0, -0.1), PAGE)
    # the coloured strip across the top, with the two rings the pages hang on
    p.add(box((3.78, 1.1, 0.72), round_all=0.24 * R * 2), (0, 3.42, 0.02), TOP)
    p.add(box((3.78, 0.2, 0.74), round_all=0.08), (0, 2.93, 0.02), TOP_DARK)
    for x in (0.95, -0.95):
        p.add(tube(0.2, 0.95, axis="y", sides=14), (x, 3.98, 0.02), RING)
        p.add(box((0.62, 0.3, 0.9), round_all=0.12), (x, 3.52, 0.02), TOP_DARK)
    # the big tick. (+x is on the left: the short arm is on the left, the long arm rises to the right.)
    front = -0.42
    p.add(box((0.62, 1.34, 0.42), round_all=0.2), (0.72, 1.28, front), TICK, turned(0, 0, -45))
    p.add(box((0.62, 2.5, 0.42), round_all=0.2), (-0.44, 1.78, front), TICK, turned(0, 0, 38))
    p.add(box((0.66, 0.66, 0.42), round_all=0.2), (0.3, 0.86, front), TICK, turned(0, 0, -4))  # fills the corner
    return p


PACK = rgb(255, 178, 34)
PACK_DARK = rgb(238, 132, 26)
PACK_LIGHT = rgb(255, 214, 96)
STRAP = rgb(150, 84, 34)
BUCKLE = rgb(236, 238, 245)
EMBLEM = rgb(120, 66, 26)


def make_backpack():
    p = Piece("Backpack")
    # the body, with a carrying loop on top
    p.add(box((3.1, 3.3, 1.9), round_all=0.55), (0, 1.85, 0.1), PACK)
    p.add(box((1.25, 0.34, 0.34), round_all=0.14), (0, 3.9, 0.35), STRAP)
    for x in (0.52, -0.52):
        p.add(box((0.3, 0.5, 0.3), round_all=0.1), (x, 3.68, 0.35), STRAP)
    # the flap over the top third, held shut by a strap with a buckle
    p.add(box((3.24, 1.35, 2.0), round_all=0.45), (0, 2.98, 0.05), PACK_DARK)
    p.add(box((0.56, 1.5, 0.2), round_all=0.08), (0, 2.55, -0.98), STRAP)
    p.add(box((0.82, 0.5, 0.26), round_all=0.1), (0, 2.02, -1.0), BUCKLE)
    p.add(box((0.36, 0.2, 0.3), round_all=0.06), (0, 2.02, -1.03), STRAP)
    # the front pocket, with a honeycomb badge
    p.add(box((2.2, 1.3, 0.6), round_all=0.28), (0, 0.98, -1.0), PACK_LIGHT)
    p.add(box((2.3, 0.3, 0.66), round_all=0.12), (0, 1.56, -1.02), PACK_DARK)
    p.add(tube(0.4, 0.14, axis="z", sides=6), (0, 0.9, -1.34), EMBLEM)
    p.add(tube(0.24, 0.16, axis="z", sides=6), (0, 0.9, -1.36), PACK)
    # the shoulder straps, peeking out at the sides
    for x in (1.72, -1.72):
        p.add(box((0.36, 2.5, 0.6), round_all=0.16), (x, 1.9, 0.75), STRAP)
    return p


scene = start()
library = new_collection("Pieces")


def move(x, y, z, turn=0.0, size=1.0):
    return Matrix.Translation((x, y, z)) @ turned(0, turn, 0) @ Matrix.Scale(size, 4)


if "calendar" in MODES:
    library.hide_render = True
    studio = new_collection("Studio")
    paint = paint_material()
    calendar = make_calendar().to_object(library)
    put(calendar, studio, move(0, 0, 0, -18), paint)
    add_sun(studio, (-0.45, 0.75, -0.6), 2.3)
    setup_render(scene, 768, 768, samples=64, sky=(1, 1, 1, 1), sky_strength=0.75, see_through=True)
    add_camera(studio, scene, (0, 8, -40), (0, 2.15, 0), 5.6)
    scene.render.filepath = os.path.join(OUT, "icon-Calendar.png")
    bpy.ops.render.render(write_still=True)
    say("calendar picture drawn")
    bpy.data.collections.remove(studio)

if "backpack" in MODES:
    library.hide_render = True
    studio = new_collection("Studio")
    paint = paint_material()
    backpack = make_backpack().to_object(library)
    put(backpack, studio, move(0, 0, 0, -22), paint)
    add_sun(studio, (-0.45, 0.75, -0.6), 2.3)
    setup_render(scene, 768, 768, samples=64, sky=(1, 1, 1, 1), sky_strength=0.75, see_through=True)
    add_camera(studio, scene, (0, 9, -40), (0, 2.05, 0), 5.7)
    scene.render.filepath = os.path.join(OUT, "icon-Backpack.png")
    bpy.ops.render.render(write_still=True)
    say("backpack picture drawn")
    bpy.data.collections.remove(studio)

say("done")
