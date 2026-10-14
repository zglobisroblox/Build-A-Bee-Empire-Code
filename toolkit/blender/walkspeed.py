# Build A Bee Empire - the menu picture of the Walk Speed upgrade, made in Blender (chunky toy style).
#
# Run:  blender --background --factory-startup --python walkspeed.py -- <ABSOLUTE output folder>
#
# Picture (768 x 768, see-through background; icon-tools\finish-blender-icons.ps1 trims it and adds
# the ink outline):
#   icon-WalkSpeed.png   a bee-striped sneaker with a little wing, running, with speed lines behind it
#
# Seen from the front (the camera's side, -z), +x is on the LEFT. The toe points to -x, so in the
# picture the shoe runs to the right and the speed lines trail off to the left.

import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Matrix  # noqa: E402
from toykit import (Piece, add_camera, add_sun, box, new_collection, paint_material, put, rgb, say,  # noqa: E402
                    setup_render, start, turned)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)

YELLOW = rgb(255, 204, 44)
YELLOW_LIGHT = rgb(255, 226, 110)
INK = rgb(35, 30, 30)
SOLE = rgb(250, 248, 240)
TREAD = rgb(206, 206, 220)
LACE = rgb(255, 255, 255)
TONGUE = rgb(255, 150, 40)
WING = rgb(214, 238, 255)
WING_EDGE = rgb(160, 210, 255)
SPEED = rgb(120, 205, 255)
SPEED_LIGHT = rgb(196, 236, 255)

R = 0.45  # how round the edges are (the same as the other pieces)


def make_shoe():
    p = Piece("Shoe")
    # the sole: white, with a grey tread underneath
    p.add(box((5.5, 0.72, 2.12), round_all=0.34), (0, 0.38, 0), SOLE)
    p.add(box((5.3, 0.26, 2.02), round_all=0.12), (0, 0.13, 0), TREAD)
    # the yellow shoe: low and round at the toe, rising to the ankle at the back
    p.add(box((2.0, 1.05, 1.96), round_all=0.5), (-1.7, 1.18, 0), YELLOW)
    p.add(box((2.7, 1.5, 1.92), round_all=0.5), (-0.25, 1.42, 0), YELLOW)
    p.add(box((2.3, 2.35, 1.88), round_all=0.62), (1.45, 1.86, 0), YELLOW)
    p.add(box((0.7, 0.9, 1.6), round_all=0.3), (2.55, 1.6, 0), YELLOW_LIGHT)  # the heel tab
    p.add(box((1.05, 0.75, 2.0), round_all=0.36), (-2.3, 0.98, 0), SOLE)  # a white rubber toe
    # two wide bee stripes
    p.add(box((0.66, 1.56, 2.0), round_axis="x", round_axis_by=0.5), (0.3, 1.42, 0), INK)
    p.add(box((0.66, 2.42, 1.96), round_axis="x", round_axis_by=0.62), (1.3, 1.86, 0), INK)
    # the opening at the top, and the tongue sticking out of it
    p.add(box((1.75, 0.28, 1.6), round_all=0.13), (1.5, 3.02, 0), INK)
    p.add(box((0.62, 0.95, 1.2), round_all=0.28), (0.55, 2.42, 0), TONGUE, turned(0, 0, 24))
    # white laces across the front
    for x, y in ((-1.0, 1.98), (-0.55, 2.08), (-0.1, 2.18)):
        p.add(box((0.26, 0.24, 1.62), round_all=0.09), (x, y + 0.04, 0), LACE, turned(0, 0, 16))
    # a little wing on the side that faces the camera
    side = -1.02
    for index, (long, lift) in enumerate(((1.9, 32), (1.6, 50), (1.25, 68))):
        p.add(box((long, 0.5, 0.18), round_all=0.2), (1.75 + long * 0.32, 2.35 + index * 0.32, side), WING if index % 2 == 0 else WING_EDGE,
              turned(0, 0, lift))
    p.add(box((0.7, 0.7, 0.24), round_all=0.25), (1.65, 2.25, side - 0.02), WING_EDGE)
    # speed lines behind the heel
    for y, long, color in ((0.8, 2.2, SPEED), (1.6, 2.8, SPEED_LIGHT), (2.4, 1.9, SPEED)):
        p.add(box((long, 0.36, 0.36), round_all=0.17), (3.15 + long / 2, y, 0.4), color)
    return p

scene = start()
library = new_collection("Pieces")
library.hide_render = True
studio = new_collection("Studio")
paint = paint_material()
shoe = make_shoe().to_object(library)
put(shoe, studio, Matrix.Translation((0, 0, 0)) @ turned(0, -14, 0) @ turned(0, 0, -5), paint)
add_sun(studio, (-0.45, 0.75, -0.6), 2.3)
setup_render(scene, 768, 768, samples=64, sky=(1, 1, 1, 1), sky_strength=0.75, see_through=True)
add_camera(studio, scene, (0, 16, -40), (0.9, 1.6, 0), 8.6)
scene.render.filepath = os.path.join(OUT, "icon-WalkSpeed.png")
bpy.ops.render.render(write_still=True)
say("walk speed picture drawn")
say("done")
