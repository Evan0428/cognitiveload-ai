"""Generate the cute chibi 3D assistants (assets/models/*.glb).

Each character is built by its OWN function so they differ in silhouette —
head shape, headwear, hair, outfit and accessories — not just colour.

Run from the project root:   python3 tools/generate_chibi_avatars.py
"""
import numpy as np
import trimesh
from trimesh.creation import icosphere, cylinder, box, cone

OUT = "assets/models"


# ---------------------------------------------------------------- helpers
def C(hexstr, alpha=255):
    h = hexstr.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)] + [alpha]


def put(mesh, color, pos=(0, 0, 0), scale=(1, 1, 1), rot=None):
    m = mesh.copy()
    m.apply_scale(scale)
    if rot is not None:
        angle, axis = rot
        m.apply_transform(trimesh.transformations.rotation_matrix(angle, axis))
    m.apply_translation(pos)
    m.visual.face_colors = color
    return m


def sphere(r=1.0, sub=3):
    return icosphere(subdivisions=sub, radius=r)


def rounded_body(r, h):
    parts = [cylinder(radius=r, height=h, sections=32),
             put(sphere(r), [0, 0, 0, 255], (0, 0, h / 2)),
             put(sphere(r), [0, 0, 0, 255], (0, 0, -h / 2))]
    return trimesh.util.concatenate(parts)


HEAD_R = 0.62
HEAD_Y = 1.15

SKIN_LIGHT = C("F7CDA8")
SKIN_TAN = C("E0A87B")
SKIN_DEEP = C("B87A50")
DARK = C("1A1A2E")
WHITE = C("FFFFFF")


def face(parts, *, skin_for_cheeks=True, eye_r=0.155, happy=True):
    """Shared cute face: big sparkly eyes, blush, smile."""
    for sx in (-1, 1):
        parts.append(put(sphere(eye_r), DARK,
                         (sx * 0.24, -0.52, HEAD_Y + 0.06)))
        parts.append(put(sphere(eye_r * 0.36), WHITE,
                         (sx * 0.20, -0.63, HEAD_Y + 0.14)))
    if skin_for_cheeks:
        for sx in (-1, 1):
            parts.append(put(sphere(0.10), C("FF9AA2", 210),
                             (sx * 0.42, -0.40, HEAD_Y - 0.14)))
    if happy:
        parts.append(put(sphere(0.10), C("B3305C"),
                         (0, -0.55, HEAD_Y - 0.28), (1.7, 0.45, 0.55)))


def arms(parts, sleeve, skin, y=0.66):
    for sx in (-1, 1):
        parts.append(put(sphere(0.145), sleeve, (sx * 0.40, 0, y)))
        parts.append(put(sphere(0.115), skin, (sx * 0.47, 0, y - 0.22)))


def feet(parts, color, shape="round"):
    for sx in (-1, 1):
        if shape == "round":
            parts.append(put(sphere(0.17), color, (sx * 0.18, -0.03, 0.12),
                             (1.0, 1.35, 0.62)))
        else:  # chunky boots
            parts.append(put(box(extents=(0.26, 0.42, 0.24)), color,
                             (sx * 0.19, -0.05, 0.12)))


def finish(parts):
    mesh = trimesh.util.concatenate(parts)
    mesh.apply_translation([0, 0, -mesh.bounds[0][2]])
    mesh.apply_transform(trimesh.transformations.rotation_matrix(
        -np.pi / 2, [1, 0, 0]))          # Z-up build -> glTF Y-up
    return mesh


# ---------------------------------------------------------------- cast
def make_buddy():
    """Cheerful kid in a hoodie + backwards cap."""
    p = []
    hoodie = C("6366F1")
    p.append(put(rounded_body(0.34, 0.30), hoodie, (0, 0, 0.58)))
    p.append(put(sphere(0.30), hoodie, (0, 0.28, 0.80), (1.1, 0.8, 0.9)))  # hood
    p.append(put(sphere(HEAD_R), SKIN_LIGHT, (0, 0, HEAD_Y)))
    face(p)
    # backwards baseball cap: dome + brim pointing back
    p.append(put(sphere(HEAD_R * 1.03), C("EF4444"),
                 (0, 0, HEAD_Y + 0.22), (1.0, 1.0, 0.55)))
    p.append(put(box(extents=(0.62, 0.42, 0.07)), C("DC2626"),
                 (0, 0.66, HEAD_Y + 0.24)))
    # drawstrings
    for sx in (-1, 1):
        p.append(put(sphere(0.05), WHITE, (sx * 0.14, -0.30, 0.62)))
    arms(p, hoodie, SKIN_LIGHT)
    feet(p, C("F8FAFC"))
    return finish(p)


def make_mia():
    """Warm coach: hair bun with a bow, little dress."""
    p = []
    dress = C("EC4899")
    hair = C("4A2F2A")
    # cone skirt gives a distinct silhouette
    p.append(put(cone(radius=0.46, height=0.52, sections=28), dress,
                 (0, 0, 0.20)))
    p.append(put(rounded_body(0.30, 0.20), dress, (0, 0, 0.66)))
    p.append(put(sphere(HEAD_R), SKIN_LIGHT, (0, 0, HEAD_Y)))
    face(p)
    p.append(put(sphere(HEAD_R * 1.02), hair,
                 (0, 0.03, HEAD_Y + 0.18), (1.0, 1.0, 0.66)))
    p.append(put(sphere(0.26), hair, (0, 0.30, HEAD_Y + 0.62)))       # bun
    p.append(put(sphere(0.11), C("F59E0B"), (0.22, 0.24, HEAD_Y + 0.60)))  # bow
    p.append(put(sphere(0.11), C("F59E0B"), (-0.22, 0.24, HEAD_Y + 0.60)))
    for sx in (-1, 1):  # side strands
        p.append(put(sphere(0.14), hair, (sx * 0.56, 0.10, HEAD_Y - 0.18),
                     (0.7, 0.8, 1.5)))
    arms(p, dress, SKIN_LIGHT, y=0.70)
    feet(p, C("8B5CF6"))
    return finish(p)


def make_nova():
    """Calm robot: boxy head, antenna, ear discs, chest light."""
    p = []
    shell = C("8B5CF6")
    metal = C("CBD5E1")
    glow = C("22D3EE")
    p.append(put(box(extents=(0.62, 0.44, 0.56)), shell, (0, 0, 0.60)))
    p.append(put(sphere(0.12), glow, (0, -0.24, 0.66)))               # chest light
    # boxy head with rounded feel
    p.append(put(box(extents=(1.06, 0.92, 0.98)), metal, (0, 0, HEAD_Y)))
    face(p, skin_for_cheeks=False)
    p.append(put(box(extents=(0.86, 0.10, 0.20)), glow,
                 (0, -0.48, HEAD_Y + 0.34)))                          # visor strip
    for sx in (-1, 1):                                                # ear discs
        p.append(put(cylinder(radius=0.17, height=0.10, sections=20), glow,
                     (sx * 0.58, 0, HEAD_Y),
                     rot=(np.pi / 2, [0, 1, 0])))
    p.append(put(cylinder(radius=0.035, height=0.34, sections=12), metal,
                 (0, 0, HEAD_Y + 0.66)))
    p.append(put(sphere(0.12), glow, (0, 0, HEAD_Y + 0.86)))          # antenna ball
    for sx in (-1, 1):                                                # blocky arms
        p.append(put(box(extents=(0.16, 0.16, 0.38)), metal,
                     (sx * 0.44, 0, 0.62)))
    feet(p, metal, shape="boot")
    return finish(p)


def make_astro():
    """Explorer: bubble helmet + backpack + chunky boots."""
    p = []
    suit = C("E2E8F0")
    trim = C("F59E0B")
    p.append(put(rounded_body(0.36, 0.32), suit, (0, 0, 0.58)))
    p.append(put(box(extents=(0.46, 0.26, 0.44)), C("94A3B8"),
                 (0, 0.34, 0.62)))                                    # backpack
    p.append(put(box(extents=(0.72, 0.30, 0.10)), trim, (0, 0, 0.44)))  # belt
    p.append(put(sphere(HEAD_R * 0.92), SKIN_TAN, (0, 0, HEAD_Y)))
    face(p)
    # OPEN-FACE helmet: shell over top/back/sides so the face stays visible
    p.append(put(sphere(HEAD_R * 1.16), C("F8FAFC"),
                 (0, 0.16, HEAD_Y + 0.06), (1.05, 1.0, 1.0)))
    for sx in (-1, 1):                                                # side pads
        p.append(put(sphere(0.24), C("E2E8F0"),
                     (sx * 0.60, 0.02, HEAD_Y + 0.02), (0.7, 1.0, 1.1)))
    p.append(put(box(extents=(0.90, 0.08, 0.12)), C("7DD3FC"),
                 (0, -0.56, HEAD_Y + 0.42)))                          # visor trim
    p.append(put(cylinder(radius=0.52, height=0.10, sections=28), trim,
                 (0, 0, HEAD_Y - 0.62)))                              # collar ring
    arms(p, suit, suit)
    feet(p, trim, shape="boot")
    return finish(p)


def make_leo():
    """Friendly buddy: spiky hair + headphones + varsity jacket."""
    p = []
    jacket = C("10B981")
    hair = C("1F1B18")
    p.append(put(rounded_body(0.34, 0.30), jacket, (0, 0, 0.58)))
    p.append(put(box(extents=(0.16, 0.30, 0.52)), C("F8FAFC"),
                 (0, -0.22, 0.60)))                                   # zip stripe
    p.append(put(sphere(HEAD_R), SKIN_DEEP, (0, 0, HEAD_Y)))
    face(p)
    p.append(put(sphere(HEAD_R * 1.01), hair,
                 (0, 0.02, HEAD_Y + 0.18), (1.0, 1.0, 0.60)))
    for i, (sx, sy) in enumerate([(-0.28, 0.0), (0.0, -0.10), (0.28, 0.05)]):
        p.append(put(cone(radius=0.16, height=0.34, sections=14), hair,
                     (sx, sy, HEAD_Y + 0.52)))                        # spikes
    # headphones: slim band arcing over the head + chunky ear cups
    for i, (bx, bz) in enumerate([(-0.52, 0.44), (-0.30, 0.60), (0.0, 0.66),
                                  (0.30, 0.60), (0.52, 0.44)]):
        p.append(put(box(extents=(0.20, 0.14, 0.12)), C("1E293B"),
                     (bx, 0.02, HEAD_Y + bz)))
    for sx in (-1, 1):
        p.append(put(cylinder(radius=0.21, height=0.14, sections=20),
                     C("F59E0B"), (sx * 0.62, 0.02, HEAD_Y + 0.06),
                     rot=(np.pi / 2, [0, 1, 0])))
    arms(p, jacket, SKIN_DEEP)
    feet(p, C("1E293B"), shape="boot")
    return finish(p)


CAST = {
    "buddy": make_buddy,
    "mia": make_mia,
    "nova": make_nova,
    "astro": make_astro,
    "leo": make_leo,
}

if __name__ == "__main__":
    import os
    os.makedirs(OUT, exist_ok=True)
    for name, fn in CAST.items():
        m = fn()
        path = f"{OUT}/{name}.glb"
        m.export(path)
        print(f"{name:8s} verts={len(m.vertices):6d}  "
              f"{os.path.getsize(path) / 1024:.0f} KB")
