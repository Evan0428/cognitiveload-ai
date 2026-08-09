"""Generate cute chibi (big-head, short-body) cartoon characters as .glb.

All characters share one style: oversized head, small rounded body, stubby
limbs — the proportions that read as "cute" — so the roster feels consistent.
"""
import numpy as np
import trimesh
from trimesh.creation import icosphere, cylinder, box

OUT = "assets/models"


def C(hexstr, alpha=255):
    h = hexstr.lstrip("#")
    return [int(h[i:i + 2], 16) for i in (0, 2, 4)] + [alpha]


def put(mesh, color, pos=(0, 0, 0), scale=(1, 1, 1)):
    m = mesh.copy()
    m.apply_scale(scale)
    m.apply_translation(pos)
    m.visual.face_colors = color
    return m


def sphere(r=1.0, sub=3):
    return icosphere(subdivisions=sub, radius=r)


def capsule_body(r, h):
    """Rounded body: cylinder + domed top/bottom."""
    parts = [cylinder(radius=r, height=h, sections=32)]
    parts.append(put(sphere(r), [0, 0, 0, 255], (0, 0, h / 2)))
    parts.append(put(sphere(r), [0, 0, 0, 255], (0, 0, -h / 2)))
    return trimesh.util.concatenate(parts)


def chibi(skin, outfit, hair, accent, *, hair_style="short", ears=False,
          antenna=False, visor=False):
    """One cute chibi: head ~= 55% of total height."""
    parts = []
    HEAD_R = 0.62
    HEAD_Y = 1.15

    # --- body (small, rounded), lifted so the feet show below it ---
    body = capsule_body(0.34, 0.30)
    parts.append(put(body, outfit, (0, 0, 0.58)))

    # --- head (big!) ---
    parts.append(put(sphere(HEAD_R), skin, (0, 0, HEAD_Y)))

    # --- eyes (big cute eyes) ---
    for sx in (-1, 1):
        parts.append(put(sphere(0.155), C("1A1A2E"),
                         (sx * 0.24, -0.52, HEAD_Y + 0.06)))
        # sparkle highlight
        parts.append(put(sphere(0.055), C("FFFFFF"),
                         (sx * 0.20, -0.63, HEAD_Y + 0.14)))

    # --- rosy cheeks ---
    for sx in (-1, 1):
        parts.append(put(sphere(0.10), C("FF9AA2", 210),
                         (sx * 0.42, -0.40, HEAD_Y - 0.14)))

    # --- wide smiling mouth (flattened, not a nose-dot) ---
    parts.append(put(sphere(0.10), C("B3305C"),
                     (0, -0.55, HEAD_Y - 0.28), (1.7, 0.45, 0.55)))

    # --- hair / cap ---
    if hair_style == "short":
        cap = sphere(HEAD_R * 1.02)
        cap = put(cap, hair, (0, 0.03, HEAD_Y + 0.20), (1.0, 1.0, 0.62))
        parts.append(cap)
    elif hair_style == "bun":
        parts.append(put(sphere(HEAD_R * 1.02), hair,
                         (0, 0.03, HEAD_Y + 0.18), (1.0, 1.0, 0.66)))
        parts.append(put(sphere(0.26), hair, (0, 0.30, HEAD_Y + 0.62)))
    elif hair_style == "metal":  # robot dome
        parts.append(put(sphere(HEAD_R * 1.03), hair,
                         (0, 0, HEAD_Y + 0.22), (1.0, 1.0, 0.55)))

    if ears:  # cute round side ears
        for sx in (-1, 1):
            parts.append(put(sphere(0.17), accent,
                             (sx * 0.62, 0, HEAD_Y + 0.02)))
    if antenna:
        parts.append(put(cylinder(radius=0.035, height=0.34, sections=12),
                         accent, (0, 0, HEAD_Y + 0.78)))
        parts.append(put(sphere(0.11), accent, (0, 0, HEAD_Y + 0.98)))
    if visor:
        parts.append(put(sphere(0.60), C("7FD8FF", 130),
                         (0, -0.12, HEAD_Y + 0.02), (1.0, 0.62, 0.72)))

    # --- stubby arms ---
    for sx in (-1, 1):
        parts.append(put(sphere(0.145), outfit, (sx * 0.40, 0, 0.66)))
        parts.append(put(sphere(0.115), skin, (sx * 0.47, 0, 0.44)))

    # --- stubby legs ---
    for sx in (-1, 1):
        parts.append(put(sphere(0.17), accent, (sx * 0.18, -0.03, 0.12),
                         (1.0, 1.35, 0.62)))

    mesh = trimesh.util.concatenate(parts)
    mesh.apply_translation([0, 0, -mesh.bounds[0][2]])  # feet on ground
    # glTF is Y-up; our build is Z-up.
    mesh.apply_transform(trimesh.transformations.rotation_matrix(
        -np.pi / 2, [1, 0, 0]))
    return mesh


CHARACTERS = {
    "buddy": dict(  # cheerful cartoon boy
        skin=C("F6C89F"), outfit=C("6366F1"), hair=C("3A2A22"),
        accent=C("EF4444"), hair_style="short"),
    "mia": dict(  # cute girl with a bun
        skin=C("F7CDA8"), outfit=C("EC4899"), hair=C("4A2F2A"),
        accent=C("8B5CF6"), hair_style="bun"),
    "nova": dict(  # cute pastel robot
        skin=C("D9E6F2"), outfit=C("8B5CF6"), hair=C("AFC4DB"),
        accent=C("22D3EE"), hair_style="metal", antenna=True, ears=True),
    "astro": dict(  # chibi astronaut
        skin=C("F2D2B6"), outfit=C("F1F5F9"), hair=C("E2E8F0"),
        accent=C("F59E0B"), hair_style="metal", visor=True),
    "leo": dict(  # sporty cartoon guy
        skin=C("C98B62"), outfit=C("10B981"), hair=C("1F1B18"),
        accent=C("F59E0B"), hair_style="short"),
}

if __name__ == "__main__":
    import os
    os.makedirs(OUT, exist_ok=True)
    for name, kw in CHARACTERS.items():
        m = chibi(**kw)
        path = f"{OUT}/{name}.glb"
        m.export(path)
        print(f"{name:8s} verts={len(m.vertices):6d}  {os.path.getsize(path)/1024:.0f} KB")
