# Build A Bee Empire - menu pictures for the Settings window, made in Blender (chunky toy style).
#
# Run:  blender --background --factory-startup --python uiicons.py -- <output folder>
#
# Pictures only (nothing here goes into the 3D world):
#   Gear       the Settings button and the Settings window's title
#   Music      a pair of music notes (the music volume)
#   Speaker    a loudspeaker with three sound bars (the sound effects volume)
#
# Each model's FRONT is the side towards -z, the side the camera looks at.
# Seen from the front, +x is on the LEFT, so the makers below write "sx" (screen x, to the right)
# and flip it.

import math
import os
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mathutils import Matrix  # noqa: E402
from toykit import (Piece, add_camera, add_sun, box, new_collection, paint_material, put, rgb, say,  # noqa: E402
                    setup_render, start, tube, turned)

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = ARGS[0] if ARGS else os.path.join(os.path.dirname(os.path.abspath(__file__)), "out")
os.makedirs(OUT, exist_ok=True)

STEEL = rgb(206, 212, 230)
STEEL_LIGHT = rgb(236, 240, 250)
STEEL_DARK = rgb(140, 148, 176)
HOLE = rgb(56, 58, 78)
PINK = rgb(255, 96, 196)
PINK_DARK = rgb(222, 58, 160)
PINK_LIGHT = rgb(255, 176, 226)
BLUE = rgb(62, 146, 255)
BLUE_DARK = rgb(40, 104, 214)
BLUE_LIGHT = rgb(150, 208, 255)
SUNNY = rgb(255, 214, 60)
SUNNY_DARK = rgb(240, 160, 30)

MIDDLE = 1.5  # every picture is built round (0, 1.5, 0)


def coin(radius, depth, sides=28, soften=0.0):
    """A round plate that faces the camera, with its rims softened."""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=sides, radius1=radius, radius2=radius, depth=depth)
    if soften > 0:
        rims = [e for e in bm.edges if abs(e.verts[0].co.z - e.verts[1].co.z) < 1e-6]
        bmesh.ops.bevel(bm, geom=rims, offset=min(soften, depth * 0.45), offset_type="OFFSET", segments=2,
                        profile=0.5, affect="EDGES", clamp_overlap=True)
    return bm


def make_gear():
    p = Piece("Gear")
    teeth = 8
    for index in range(teeth):
        angle = index * 360 / teeth
        a = math.radians(angle)
        # a tooth: a brick whose "up" points away from the middle
        p.add(box((0.62, 0.62, 0.52), round_all=0.1), (-math.sin(a) * 1.22, MIDDLE + math.cos(a) * 1.22, 0), STEEL_DARK,
              turned(0, 0, angle))
    p.add(coin(1.12, 0.56, 32, soften=0.1), (0, MIDDLE, 0), STEEL)
    p.add(coin(0.84, 0.1, 32, soften=0.03), (0, MIDDLE, -0.3), STEEL_LIGHT)
    p.add(coin(0.46, 0.12, 24, soften=0.03), (0, MIDDLE, -0.34), STEEL_DARK)
    p.add(coin(0.33, 0.14, 24), (0, MIDDLE, -0.36), HOLE)
    return p


def make_music():
    p = Piece("Music")

    def at(sx, y, z=0.0):
        return (-sx, y, z)

    # two note heads (leaning a little), a stem on the right of each, and the bar that joins them
    heads = ((-0.72, 0.52), (0.82, 0.86))
    stem_top = 1.95
    for sx, y in heads:
        p.add(box((0.98, 0.7, 0.56), round_all=0.2, segments=3), at(sx, y), PINK, turned(0, 0, 18))
        p.add(box((0.4, 0.2, 0.1), round_all=0.04), at(sx - 0.14, y + 0.16, -0.3), PINK_LIGHT, turned(0, 0, 18))
        stem_x = sx + 0.36
        p.add(box((0.26, stem_top, 0.42), round_all=0.07), at(stem_x, y + stem_top / 2 + 0.05), PINK_DARK)
    left, right = heads[0], heads[1]
    start_point = (left[0] + 0.36, left[1] + stem_top)
    end_point = (right[0] + 0.36, right[1] + stem_top)
    length = math.hypot(end_point[0] - start_point[0], end_point[1] - start_point[1]) + 0.26
    slope = math.degrees(math.atan2(end_point[1] - start_point[1], end_point[0] - start_point[0]))
    p.add(box((length, 0.52, 0.5), round_all=0.1), at((start_point[0] + end_point[0]) / 2, (start_point[1] + end_point[1]) / 2 - 0.1),
          PINK, turned(0, 0, -slope))
    return p


def make_speaker():
    p = Piece("Speaker")

    def at(sx, y, z=0.0):
        return (-sx, y, z)

    # the box at the back, then the cone that opens towards the right
    p.add(box((0.72, 1.0, 0.8), round_all=0.14), at(-1.25, MIDDLE), BLUE_DARK)
    p.add(tube(1.12, 1.05, axis="x", sides=4, tip_radius=0.5), at(-0.5, MIDDLE), BLUE, turned(45, 0, 0))
    p.add(box((0.16, 1.5, 1.5), round_all=0.05), at(0.04, MIDDLE), BLUE_LIGHT)
    # three sound bars, each taller than the last
    for index, tall in enumerate((0.8, 1.4, 2.0)):
        p.add(box((0.3, tall, 0.4), round_all=0.1), at(0.6 + index * 0.52, MIDDLE), SUNNY if index < 2 else SUNNY_DARK)
    return p


MAKERS = [make_gear, make_music, make_speaker]
VIEWS = {"Gear": (-22, 4.0), "Music": (-22, 4.3), "Speaker": (-26, 4.3)}  # turn (degrees), picture width (studs)

scene = start()
library = new_collection("Pieces")
library.hide_render = True
paint = paint_material()
for maker in MAKERS:
    piece = maker()
    low, high = piece.bounds()
    say("piece", piece.name, "triangles", piece.triangles(), "size", [round(high[i] - low[i], 2) for i in range(3)])
    source = piece.to_object(library)
    studio = new_collection("Studio")
    turn, wide = VIEWS[piece.name]
    put(source, studio, Matrix.Translation((0, 0, 0)) @ turned(0, turn, 0), paint)
    add_sun(studio, (-0.45, 0.75, -0.6), 2.3)
    setup_render(scene, 768, 768, samples=64, sky=(1, 1, 1, 1), sky_strength=0.75, see_through=True)
    add_camera(studio, scene, (0, 9, -40), (0, MIDDLE, 0), wide)
    scene.render.filepath = os.path.join(OUT, "icon-" + piece.name + ".png")
    bpy.ops.render.render(write_still=True)
    say("picture drawn", piece.name)
    bpy.data.collections.remove(studio)

say("done")
