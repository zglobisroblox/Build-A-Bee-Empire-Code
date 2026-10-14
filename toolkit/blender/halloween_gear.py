# Build A Bee Empire - what the three Halloween bees wear (2026-10-12).
#
# These makers are used by two scripts: bees.py (to draw the bees for previews and menu
# pictures) and halloween.py (to put the outfits in the file Roblox Studio imports). Each of
# those has its own drawing helpers, so every maker here takes "k": a little bag holding
# Piece, box, ball, tube, turned and rgb.
#
# Bee space: x = to the bee's right, y = up, z = towards its tail. The bee faces -z.
# The head is the block round (0, 0.1, -1.5); the body is the block round (0, 0, 0.3).
#
#   BatGear          - bat ears, two bat wings, little fangs, a dark collar      (Bat Bee)
#   GhostGear        - a white sheet with a hood and a wisp, and a tiny ghost    (Ghost Bee)
#   PumpkinKingGear  - a pumpkin helmet with a crown, and a purple cape          (Pumpkin King Bee)
#   PumpkinGlow      - WHITE: the helmet's carved face and a few sparks. The game makes it glow.


def palette(k):
    rgb = k.rgb
    return {
        "INK": rgb(35, 30, 30), "WHITE": rgb(255, 255, 255),
        "PLUM": rgb(132, 78, 190), "PLUM_DARK": rgb(74, 42, 112), "PINK": rgb(255, 150, 200),
        "SHEET": rgb(250, 250, 255), "SHEET_SHADE": rgb(196, 206, 240),
        "PUMPKIN": rgb(255, 128, 24), "PUMPKIN_DARK": rgb(222, 88, 10), "STEM": rgb(92, 160, 60),
        "GOLD": rgb(255, 206, 60), "CAPE": rgb(104, 52, 170), "CAPE_TRIM": rgb(255, 150, 30), "GEM": rgb(140, 255, 90),
    }


def cape(k, p, cloth, trim, top_y=0.99):
    """The same cape the Royal Bee wears (see bees.py), in other colours."""
    flare = 9
    p.add(k.box((2.04, 0.12, 2.3), round_axis="y", round_axis_by=0.3), (0, top_y, 0.66), cloth)
    p.both_sides(lambda: k.box((0.12, 1.1, 2.3), round_axis="x", round_axis_by=0.25), (1.1, top_y - 0.52, 0.66), cloth,
                 lambda side: k.turned(0, 0, flare * side))
    p.add(k.box((2.04, 1.05, 0.12), round_axis="z", round_axis_by=0.25), (0, top_y - 0.5, 1.88), cloth, k.turned(-flare, 0, 0))
    p.both_sides(lambda: k.box((0.17, 0.17, 2.34), round_all=0.05, segments=1), (1.19, top_y - 1.08, 0.66), trim)
    p.add(k.box((2.3, 0.17, 0.17), round_all=0.05, segments=1), (0, top_y - 1.03, 1.97), trim)


def triangle(k, p, at, wide, tall, deep, color, upside_down=False):
    """A chunky triangle made of three steps (point up, or down)."""
    x, y, z = at
    for step, share in enumerate((1.0, 0.66, 0.32)):
        offset = (step - 1) * tall / 3
        p.add(k.box((wide * share, tall / 3 + 0.01, deep)), (x, y - offset if upside_down else y + offset, z), color)


def grin(k, p, at, wide, deep, color, teeth=5):
    """A zigzag jack-o'-lantern grin: a strip with teeth sticking up and down."""
    x, y, z = at
    p.add(k.box((wide, wide * 0.13, deep)), (x, y, z), color)
    step = wide / teeth
    for index in range(teeth):
        tooth_x = x + (index - (teeth - 1) / 2) * step
        up = index % 2 == 0
        p.add(k.box((step * 0.62, wide * 0.15, deep)), (tooth_x, y + (wide * 0.12 if up else -wide * 0.12), z), color)
    # the corners of the mouth turn up
    for side in (1, -1):
        p.add(k.box((step * 0.5, wide * 0.2, deep)), (x + side * (wide / 2 + step * 0.1), y + wide * 0.13, z), color)


def make_bat_gear(k):
    c = palette(k)
    p = k.Piece("BatGear")
    # pointed ears, pink inside
    p.both_sides(lambda: k.tube(0.36, 0.8, "y", 4, tip_radius=0.0), (0.5, 1.22, -1.45), c["PLUM_DARK"],
                 lambda side: k.turned(0, 45, -14 * side))
    p.both_sides(lambda: k.tube(0.2, 0.5, "y", 4, tip_radius=0.0), (0.5, 1.14, -1.62), c["PINK"],
                 lambda side: k.turned(0, 45, -14 * side))
    # bat wings: a dark skin with three ribs, lifted at the tips
    for side in (1, -1):
        lift = k.turned(0, 0, 26 * side)
        p.add(k.box((1.9, 0.1, 1.7), round_axis="y", round_axis_by=0.4, axis_segments=4), (side * 2.0, 1.25, 0.5), c["PLUM"], lift)
        for z, long in ((-0.2, 1.95), (0.5, 2.05), (1.2, 1.8)):
            p.add(k.box((long, 0.17, 0.15), round_all=0.05, segments=1), (side * 2.0, 1.25, z), c["PLUM_DARK"], lift)
        # the thumb claw at the shoulder, and three points along the back edge
        p.add(k.box((0.5, 0.5, 0.5), round_all=0.12), (side * 1.1, 0.85, 0.3), c["PLUM_DARK"])
        for z in (-0.2, 0.5, 1.2):
            p.add(k.tube(0.13, 0.4, "x", 6, tip_radius=0.0), (side * 3.05, 1.76, z), c["PLUM_DARK"],
                  k.turned(0, 0 if side == 1 else 180, 26 if side == 1 else -26))
    # two little fangs under the smile
    p.both_sides(lambda: k.tube(0.07, 0.2, "y", 6, tip_radius=0.0), (0.14, -0.44, -2.22), c["WHITE"], k.turned(180, 0, 0))
    # a dark collar
    p.add(k.box((2.14, 1.98, 0.36), round_axis="z", round_axis_by=0.38), (0, 0.05, -0.7), c["PLUM_DARK"])
    return p


def make_ghost_gear(k):
    c = palette(k)
    p = k.Piece("GhostGear")
    cape(k, p, c["SHEET"], c["SHEET_SHADE"])
    # the hood over the top and sides of the head
    p.add(k.box((1.9, 0.46, 1.62), round_all=0.2), (0, 1.0, -1.5), c["SHEET"])
    p.both_sides(lambda: k.box((0.16, 1.0, 1.5), round_all=0.07), (0.92, 0.5, -1.42), c["SHEET"])
    p.add(k.box((2.14, 1.98, 0.36), round_axis="z", round_axis_by=0.38), (0, 0.05, -0.7), c["SHEET_SHADE"])
    # a wisp curling up from the top
    p.add(k.ball(0.36), (0, 1.36, -1.3), c["SHEET"])
    p.add(k.ball(0.26), (0.12, 1.7, -1.04), c["SHEET"])
    p.add(k.ball(0.16), (0.26, 1.93, -0.84), c["SHEET"])
    # a tiny ghost friend floating over the back
    x, y, z = -0.95, 2.0, 1.05
    p.add(k.ball(0.44), (x, y, z), c["SHEET"])
    p.add(k.box((0.88, 0.56, 0.88), round_all=0.2), (x, y - 0.36, z), c["SHEET"])
    for dx in (-0.27, 0.0, 0.27):
        p.add(k.ball(0.18), (x + dx, y - 0.66, z), c["SHEET"])
    for dx in (-0.16, 0.16):
        p.add(k.box((0.13, 0.19, 0.06)), (x + dx, y + 0.06, z - 0.42), c["INK"])
    p.add(k.box((0.15, 0.11, 0.06)), (x, y - 0.17, z - 0.44), c["INK"])
    return p


HELMET_Z = -1.5
HELMET_FRONT = HELMET_Z - 0.975


def make_pumpkin_king_gear(k):
    c = palette(k)
    p = k.Piece("PumpkinKingGear")
    z = HELMET_Z
    # the pumpkin helmet, with darker grooves
    p.add(k.box((2.2, 1.95, 1.95), round_all=0.5, segments=3), (0, 0.12, z), c["PUMPKIN"])
    for x in (-0.62, 0.0, 0.62):
        # (rounded the same way as the helmet, so the grooves do not stick out at its corners)
        p.add(k.box((0.15, 2.0, 2.0), round_axis="x", round_axis_by=0.5), (x, 0.12, z), c["PUMPKIN_DARK"])
    # the stalk and a leaf
    p.add(k.tube(0.2, 0.6, "y", 8), (0.04, 1.42, z), c["STEM"], k.turned(0, 0, -10))
    p.add(k.box((0.5, 0.1, 0.3), round_all=0.04, segments=1), (-0.32, 1.5, z + 0.1), c["STEM"], k.turned(0, 20, -18))
    # the crown round the stalk
    p.add(k.box((1.36, 0.26, 1.36), round_axis="y", round_axis_by=0.22), (0, 1.17, z), c["GOLD"])
    for dx, dz in ((-0.52, -0.52), (0.52, -0.52), (-0.52, 0.52), (0.52, 0.52)):
        p.add(k.box((0.24, 0.4, 0.24), round_all=0.06, segments=1), (dx, 1.44, z + dz), c["GOLD"])
        p.add(k.ball(0.1, detail=1), (dx, 1.7, z + dz), c["GOLD"])
    for dx, dz in ((0, -0.58), (0, 0.58), (-0.58, 0), (0.58, 0)):
        p.add(k.box((0.24, 0.56, 0.24), round_all=0.06, segments=1), (dx, 1.52, z + dz), c["GOLD"])
        p.add(k.ball(0.11, detail=1), (dx, 1.86, z + dz), c["GOLD"])
    p.add(k.box((0.24, 0.2, 0.1), round_all=0.03, segments=1), (0, 1.17, z - 0.7), c["GEM"])
    # a purple cape with an orange edge and collar
    cape(k, p, c["CAPE"], c["CAPE_TRIM"])
    p.add(k.box((2.22, 2.04, 0.42), round_axis="z", round_axis_by=0.4), (0, 0.05, -0.7), c["CAPE_TRIM"])
    return p


def make_pumpkin_glow(k):
    """White: the game makes these glow. The carved face on the front of the helmet, and sparks."""
    c = palette(k)
    p = k.Piece("PumpkinGlow")
    front = HELMET_FRONT - 0.03
    deep = 0.12
    for side in (1, -1):
        triangle(k, p, (side * 0.5, 0.45, front), 0.56, 0.5, deep, c["WHITE"])
    triangle(k, p, (0, 0.02, front), 0.26, 0.24, deep, c["WHITE"])
    grin(k, p, (0, -0.42, front), 1.25, deep, c["WHITE"])
    for at in ((1.7, 1.5, -0.9), (-1.75, 1.2, 0.2), (-1.3, 2.05, -1.2), (1.5, 1.9, 1.3), (0.2, 2.5, -0.4)):
        p.add(k.box((0.2, 0.2, 0.2)), at, c["WHITE"], k.turned(45, 45, 0))
    return p


MAKERS = [make_bat_gear, make_ghost_gear, make_pumpkin_king_gear, make_pumpkin_glow]

# game key, shown name, body colour (0-255), what it wears, size, glowing pieces
BEES = [
    ("Bat", "Bat Bee", (96, 52, 130), ["BatGear"], 1.0, []),
    ("Ghost", "Ghost Bee", (236, 240, 255), ["GhostGear"], 1.0, []),
    ("PumpkinKing", "Pumpkin King Bee", (44, 38, 56), ["PumpkinKingGear"], 1.3, ["PumpkinGlow"]),
]
GLOW_COLOR = (255, 196, 60)  # what the game tints the white PumpkinGlow piece with
