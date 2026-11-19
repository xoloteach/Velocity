#!/usr/bin/env python3
"""Generate smooth-skinned, high-detail GLB character rigs for Project Velocity.

Builds three original, distinct, multi-bone smooth-skinned GLB models with all
29 required gameplay animation clips:
  - assets/velocity-runner.glb   (Hero: Crimson & Gold Speedster)
  - assets/nullstride-boss.glb   (Boss 1: Nullstride — Obsidian Void Predator)
  - assets/afterlight-boss.glb   (Boss 2: Afterlight — Ivory & Gold Temporal Ace)

Pure Python 3 (stdlib only, no Blender required). Right-handed glTF 2.0 Y-up,
facing -Z to match Godot CharacterBody3D forward orientation.
"""
from __future__ import annotations

import json
import math
import struct
from pathlib import Path
from typing import Dict, List, Sequence, Tuple

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"

Vec3 = Tuple[float, float, float]
Quat = Tuple[float, float, float, float]


# ---------------------------------------------------------------------------
# Math helpers
# ---------------------------------------------------------------------------
def v_sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def v_cross(a: Vec3, b: Vec3) -> Vec3:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def v_norm(a: Vec3) -> Vec3:
    l = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    if l < 1e-8:
        return (0.0, 1.0, 0.0)
    return (a[0] / l, a[1] / l, a[2] / l)


def euler_xyz_to_quat(rx: float, ry: float, rz: float) -> Quat:
    """Intrinsic Z-Y-X / extrinsic X-Y-Z rotation matching intuitive pitch/yaw/roll."""
    cx, sx = math.cos(rx * 0.5), math.sin(rx * 0.5)
    cy, sy = math.cos(ry * 0.5), math.sin(ry * 0.5)
    cz, sz = math.cos(rz * 0.5), math.sin(rz * 0.5)
    # Apply X, then Y, then Z: q = qz * qy * qx
    w = cz * cy * cx + sz * sy * sx
    x = cz * cy * sx - sz * sy * cx
    y = cz * sy * cx + sz * cy * sx
    z = sz * cy * cx - cz * sy * sx
    l = math.sqrt(x * x + y * y + z * z + w * w)
    return (x / l, y / l, z / l, w / l)


def clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)


def smoothstep(e0: float, e1: float, x: float) -> float:
    if abs(e1 - e0) < 1e-7:
        return 1.0 if x >= e1 else 0.0
    t = clamp((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------------------
# Skeleton definition (19 bones, Y-up, -Z forward, identity bind rotations)
# Preserves all 15 original bone names plus spine, neck, cloakL, cloakR.
# Note: Following original GLB convention, +X is labeled L and -X is R.
# ---------------------------------------------------------------------------
def build_skeleton(scale_y: float = 1.0, shoulder_w: float = 0.215, hip_w: float = 0.102):
    sy = scale_y
    # (name, parent_name, world_pos)
    bones = [
        ("hips", None, (0.0, 0.96 * sy, 0.0)),
        ("spine", "hips", (0.0, 1.12 * sy, 0.0)),
        ("chest", "spine", (0.0, 1.32 * sy, 0.0)),
        ("neck", "chest", (0.0, 1.52 * sy, -0.005)),
        ("head", "neck", (0.0, 1.60 * sy, -0.008)),
        ("armL", "chest", (shoulder_w, 1.44 * sy, 0.005)),
        ("foreL", "armL", (shoulder_w + 0.055, 1.16 * sy, 0.01)),
        ("handL", "foreL", (shoulder_w + 0.075, 0.91 * sy, -0.01)),
        ("armR", "chest", (-shoulder_w, 1.44 * sy, 0.005)),
        ("foreR", "armR", (-(shoulder_w + 0.055), 1.16 * sy, 0.01)),
        ("handR", "foreR", (-(shoulder_w + 0.075), 0.91 * sy, -0.01)),
        ("thighL", "hips", (hip_w, 0.93 * sy, 0.0)),
        ("shinL", "thighL", (hip_w + 0.008, 0.51 * sy, -0.012)),
        ("footL", "shinL", (hip_w + 0.010, 0.105 * sy, 0.015)),
        ("thighR", "hips", (-hip_w, 0.93 * sy, 0.0)),
        ("shinR", "thighR", (-(hip_w + 0.008), 0.51 * sy, -0.012)),
        ("footR", "shinR", (-(hip_w + 0.010), 0.105 * sy, 0.015)),
        ("capeL", "chest", (0.09, 1.42 * sy, 0.12)),
        ("capeR", "chest", (-0.09, 1.42 * sy, 0.12)),
    ]
    idx = {b[0]: i for i, b in enumerate(bones)}
    world = {b[0]: b[2] for b in bones}
    return bones, idx, world


# ---------------------------------------------------------------------------
# Smooth-skinned geometry builder
# ---------------------------------------------------------------------------
class PrimitiveBucket:
    def __init__(self, mat_idx: int):
        self.mat_idx = mat_idx
        self.positions: List[Vec3] = []
        self.normals: List[Vec3] = []
        self.joints: List[Tuple[int, int, int, int]] = []
        self.weights: List[Tuple[float, float, float, float]] = []
        self.indices: List[int] = []

    def add_mesh(
        self,
        verts: List[Vec3],
        tris: List[Tuple[int, int, int]],
        skin_fn,
        flat: bool = False,
    ) -> None:
        if flat:
            for a, b, c in tris:
                va, vb, vc = verts[a], verts[b], verts[c]
                n = v_norm(v_cross(v_sub(vb, va), v_sub(vc, va)))
                base = len(self.positions)
                for v in (va, vb, vc):
                    self.positions.append(v)
                    self.normals.append(n)
                    j, w = skin_fn(v)
                    self.joints.append(j)
                    self.weights.append(w)
                self.indices.extend((base, base + 1, base + 2))
            return

        accum = [(0.0, 0.0, 0.0)] * len(verts)
        for a, b, c in tris:
            va, vb, vc = verts[a], verts[b], verts[c]
            fn = v_cross(v_sub(vb, va), v_sub(vc, va))
            for k in (a, b, c):
                accum[k] = v_add(accum[k], fn)
        base = len(self.positions)
        for i, v in enumerate(verts):
            self.positions.append(v)
            self.normals.append(v_norm(accum[i]))
            j, w = skin_fn(v)
            self.joints.append(j)
            self.weights.append(w)
        for a, b, c in tris:
            self.indices.extend((base + a, base + b, base + c))


def norm_weights(pairs: Sequence[Tuple[int, float]]) -> Tuple[Tuple[int, int, int, int], Tuple[float, float, float, float]]:
    cleaned = [(j, max(0.0, w)) for j, w in pairs if w > 1e-4]
    if not cleaned:
        return (0, 0, 0, 0), (1.0, 0.0, 0.0, 0.0)
    cleaned.sort(key=lambda t: t[1], reverse=True)
    cleaned = cleaned[:4]
    total = sum(w for _, w in cleaned)
    j = [0, 0, 0, 0]
    w = [0.0, 0.0, 0.0, 0.0]
    for k, (ji, wi) in enumerate(cleaned):
        j[k] = ji
        w[k] = wi / total
    return (j[0], j[1], j[2], j[3]), (w[0], w[1], w[2], w[3])


def rigid_skin(joint_idx: int):
    j = (joint_idx, 0, 0, 0)
    w = (1.0, 0.0, 0.0, 0.0)
    return lambda _v: (j, w)


def y_blend_skin(joints_and_heights: Sequence[Tuple[int, float]], softness: float = 0.11):
    """Smoothly blends weights along Y across sequential joints (torso/limbs)."""
    def fn(v: Vec3):
        y = v[1]
        if len(joints_and_heights) == 1:
            return (joints_and_heights[0][0], 0, 0, 0), (1.0, 0.0, 0.0, 0.0)
        pairs: List[Tuple[int, float]] = []
        # Find bracketing segments
        for i in range(len(joints_and_heights)):
            ji, yi = joints_and_heights[i]
            w = 1.0
            if i > 0:
                prev_y = joints_and_heights[i - 1][1]
                mid = 0.5 * (prev_y + yi)
                w *= smoothstep(mid - softness, mid + softness, y)
            if i < len(joints_and_heights) - 1:
                next_y = joints_and_heights[i + 1][1]
                mid = 0.5 * (yi + next_y)
                w *= 1.0 - smoothstep(mid - softness, mid + softness, y)
            if w > 1e-4:
                pairs.append((ji, w))
        return norm_weights(pairs)
    return fn


def add_loft(
    bucket: PrimitiveBucket,
    rings: Sequence[Tuple[float, float, float, float, float]],
    skin_fn,
    seg: int = 20,
    cap_bottom: bool = True,
    cap_top: bool = True,
    sculpt_fn=None,
) -> None:
    """Loft closed elliptical rings in Y-up coords: (y, cx, cz, rx, rz)."""
    verts: List[Vec3] = []
    for r_idx, (y, cx, cz, rx, rz) in enumerate(rings):
        for i in range(seg):
            ang = i * math.tau / seg
            # cos -> +X, sin -> +Z so winding is outward when advancing i then r_idx
            px = cx + rx * math.cos(ang)
            pz = cz + rz * math.sin(ang)
            py = y
            if sculpt_fn is not None:
                px, py, pz = sculpt_fn(r_idx, ang, px, py, pz)
            verts.append((px, py, pz))
    tris: List[Tuple[int, int, int]] = []
    for r in range(len(rings) - 1):
        off = r * seg
        nxt = (r + 1) * seg
        for i in range(seg):
            ni = (i + 1) % seg
            # Outward normal for right-handed Y-up (X=cos, Z=sin -> dP/dang = (-sin,0,cos), dP/dy = (0,1,0))
            # (dP/dy) x (dP/dang) = (cos, 0, sin) -> outward!
            # So triangle (off+i, nxt+i, nxt+ni) and (off+i, nxt+ni, off+ni) faces outward!
            tris.append((off + i, nxt + i, nxt + ni))
            tris.append((off + i, nxt + ni, off + ni))
    if cap_bottom and len(rings) >= 1:
        y0, cx0, cz0, _, _ = rings[0]
        c_idx = len(verts)
        verts.append((cx0, y0, cz0))
        for i in range(seg):
            ni = (i + 1) % seg
            tris.append((c_idx, i, ni))
    if cap_top and len(rings) >= 1:
        y1, cx1, cz1, _, _ = rings[-1]
        c_idx = len(verts)
        verts.append((cx1, y1, cz1))
        top_off = (len(rings) - 1) * seg
        for i in range(seg):
            ni = (i + 1) % seg
            tris.append((c_idx, top_off + ni, top_off + i))
    bucket.add_mesh(verts, tris, skin_fn)


def add_ellipsoid(
    bucket: PrimitiveBucket,
    center: Vec3,
    radii: Vec3,
    skin_fn,
    seg: int = 16,
    stacks: int = 10,
) -> None:
    cx, cy, cz = center
    rx, ry, rz = radii
    rings = []
    for s in range(1, stacks):
        phi = s * math.pi / stacks
        y = cy - ry * math.cos(phi)
        k = math.sin(phi)
        rings.append((y, cx, cz, rx * k, rz * k))
    add_loft(bucket, rings, skin_fn, seg=seg, cap_bottom=True, cap_top=True)


def add_tube(
    bucket: PrimitiveBucket,
    points: Sequence[Vec3],
    radius: float,
    skin_fn,
    seg: int = 8,
    taper_end: float = 1.0,
) -> None:
    if len(points) < 2:
        return
    verts: List[Vec3] = []
    n_pts = len(points)
    for idx, p in enumerate(points):
        p_prev = points[max(0, idx - 1)]
        p_next = points[min(n_pts - 1, idx + 1)]
        tang = v_norm(v_sub(p_next, p_prev))
        ref = (0.0, 1.0, 0.0) if abs(tang[1]) < 0.85 else (1.0, 0.0, 0.0)
        right = v_norm(v_cross(tang, ref))
        up = v_norm(v_cross(right, tang))
        t = idx / max(1, n_pts - 1)
        r = radius * (1.0 + (taper_end - 1.0) * t)
        for s in range(seg):
            ang = s * math.tau / seg
            ca, sa = math.cos(ang), math.sin(ang)
            verts.append((
                p[0] + (right[0] * ca + up[0] * sa) * r,
                p[1] + (right[1] * ca + up[1] * sa) * r,
                p[2] + (right[2] * ca + up[2] * sa) * r,
            ))
    tris: List[Tuple[int, int, int]] = []
    for idx in range(n_pts - 1):
        a0 = idx * seg
        b0 = (idx + 1) * seg
        for s in range(seg):
            ns = (s + 1) % seg
            tris.append((a0 + s, b0 + s, b0 + ns))
            tris.append((a0 + s, b0 + ns, a0 + ns))
    # Caps
    c0 = len(verts)
    verts.append(points[0])
    for s in range(seg):
        ns = (s + 1) % seg
        tris.append((c0, ns, s))
    c1 = len(verts)
    verts.append(points[-1])
    last = (n_pts - 1) * seg
    for s in range(seg):
        ns = (s + 1) % seg
        tris.append((c1, last + s, last + ns))
    bucket.add_mesh(verts, tris, skin_fn)


def add_fin_blade(
    bucket: PrimitiveBucket,
    outline: Sequence[Vec3],
    thickness_vec: Vec3,
    skin_fn,
    flat: bool = True,
) -> None:
    """Extrude a sharp aerodynamic fin/crest/wing plate with beveled edges."""
    n = len(outline)
    if n < 3:
        return
    tx, ty, tz = thickness_vec
    front = [(p[0] + tx, p[1] + ty, p[2] + tz) for p in outline]
    back = [(p[0] - tx, p[1] - ty, p[2] - tz) for p in outline]
    verts = front + back
    tris: List[Tuple[int, int, int]] = []
    for i in range(1, n - 1):
        tris.append((0, i, i + 1))
        tris.append((n, n + i + 1, n + i))
    for i in range(n):
        ni = (i + 1) % n
        tris.append((i, n + i, n + ni))
        tris.append((i, n + ni, ni))
    bucket.add_mesh(verts, tris, skin_fn, flat=flat)


def add_ribbon(
    bucket: PrimitiveBucket,
    rows: Sequence[Tuple[Vec3, Vec3]],
    skin_fn,
    thickness: float = 0.012,
) -> None:
    """Build a thick double-sided cape/scarf/coattail ribbon from left/right edge pairs."""
    verts: List[Vec3] = []
    for l, r in rows:
        verts.append((l[0], l[1], l[2] + thickness))
        verts.append((r[0], r[1], r[2] + thickness))
        verts.append((r[0], r[1], r[2] - thickness))
        verts.append((l[0], l[1], l[2] - thickness))
    tris: List[Tuple[int, int, int]] = []
    for i in range(len(rows) - 1):
        a = i * 4
        b = (i + 1) * 4
        for s in range(4):
            ns = (s + 1) % 4
            tris.append((a + s, b + s, b + ns))
            tris.append((a + s, b + ns, a + ns))
    # Cap bottom
    last = (len(rows) - 1) * 4
    tris.append((last, last + 2, last + 1))
    tris.append((last, last + 3, last + 2))
    bucket.add_mesh(verts, tris, skin_fn)


# ---------------------------------------------------------------------------
# Character Mesh Builders
# ---------------------------------------------------------------------------
def build_character_geometry(archetype: str):
    """Return (bones, bone_idx, materials, buckets) for 'hero', 'nullstride', or 'afterlight'."""
    if archetype == "nullstride":
        scale_y = 1.07
        shoulder_w = 0.245
        hip_w = 0.112
        materials = [
            # Keep standard material names compatible with combat/power shaders
            ("Oxblood fabric", (0.08, 0.085, 0.125, 1.0), 0.14, 0.58, (0.0, 0.0, 0.0)),
            ("Crimson ceramic", (0.14, 0.15, 0.22, 1.0), 0.52, 0.28, (0.0, 0.0, 0.0)),
            ("Graphite weave", (0.035, 0.035, 0.055, 1.0), 0.12, 0.72, (0.0, 0.0, 0.0)),
            ("Amber conductor", (0.76, 0.34, 1.0, 1.0), 0.35, 0.20, (0.85, 0.35, 1.0)),
            ("Rose alloy", (0.28, 0.24, 0.36, 1.0), 0.82, 0.24, (0.0, 0.0, 0.0)),
            ("Flexible shell", (0.05, 0.04, 0.08, 1.0), 0.20, 0.62, (0.0, 0.0, 0.0)),
            ("Smoked visor", (0.05, 0.02, 0.09, 1.0), 0.85, 0.12, (0.95, 0.22, 0.55)),
            ("Lower face", (0.11, 0.11, 0.16, 1.0), 0.45, 0.34, (0.0, 0.0, 0.0)),
            ("Lips", (0.68, 0.18, 0.95, 1.0), 0.25, 0.25, (0.8, 0.18, 1.0)),
        ]
    elif archetype == "afterlight":
        scale_y = 1.03
        shoulder_w = 0.215
        hip_w = 0.100
        materials = [
            ("Oxblood fabric", (0.84, 0.82, 0.78, 1.0), 0.18, 0.44, (0.0, 0.0, 0.0)),
            ("Crimson ceramic", (0.94, 0.92, 0.88, 1.0), 0.32, 0.24, (0.0, 0.0, 0.0)),
            ("Graphite weave", (0.18, 0.19, 0.24, 1.0), 0.22, 0.58, (0.0, 0.0, 0.0)),
            ("Amber conductor", (1.0, 0.84, 0.35, 1.0), 0.45, 0.18, (1.0, 0.78, 0.26)),
            ("Rose alloy", (0.88, 0.69, 0.28, 1.0), 0.88, 0.20, (0.0, 0.0, 0.0)),
            ("Flexible shell", (0.30, 0.27, 0.24, 1.0), 0.25, 0.52, (0.0, 0.0, 0.0)),
            ("Smoked visor", (0.10, 0.16, 0.24, 1.0), 0.88, 0.10, (0.45, 0.88, 1.0)),
            ("Lower face", (0.76, 0.56, 0.44, 1.0), 0.02, 0.56, (0.0, 0.0, 0.0)),
            ("Lips", (0.58, 0.33, 0.26, 1.0), 0.02, 0.55, (0.0, 0.0, 0.0)),
        ]
    else:  # hero
        scale_y = 1.0
        shoulder_w = 0.218
        hip_w = 0.102
        materials = [
            ("Oxblood fabric", (0.42, 0.032, 0.045, 1.0), 0.10, 0.54, (0.0, 0.0, 0.0)),
            ("Crimson ceramic", (0.64, 0.048, 0.058, 1.0), 0.36, 0.26, (0.0, 0.0, 0.0)),
            ("Graphite weave", (0.075, 0.068, 0.088, 1.0), 0.14, 0.68, (0.0, 0.0, 0.0)),
            ("Amber conductor", (1.0, 0.62, 0.14, 1.0), 0.40, 0.22, (0.98, 0.54, 0.10)),
            ("Rose alloy", (0.82, 0.58, 0.20, 1.0), 0.82, 0.22, (0.0, 0.0, 0.0)),
            ("Flexible shell", (0.12, 0.030, 0.042, 1.0), 0.18, 0.58, (0.0, 0.0, 0.0)),
            ("Smoked visor", (0.03, 0.07, 0.12, 1.0), 0.85, 0.12, (0.14, 0.42, 0.60)),
            ("Lower face", (0.68, 0.45, 0.34, 1.0), 0.02, 0.58, (0.0, 0.0, 0.0)),
            ("Lips", (0.48, 0.24, 0.19, 1.0), 0.02, 0.55, (0.0, 0.0, 0.0)),
        ]

    M_FABRIC, M_ARMOR, M_WEAVE, M_GOLD, M_ALLOY, M_SHELL, M_VISOR, M_SKIN, M_LIP = range(9)
    bones, bidx, bworld = build_skeleton(scale_y=scale_y, shoulder_w=shoulder_w, hip_w=hip_w)
    buckets = [PrimitiveBucket(i) for i in range(len(materials))]
    sy = scale_y
    w_mult = 1.12 if archetype == "nullstride" else (0.96 if archetype == "afterlight" else 1.0)

    # Skin functions
    torso_skin = y_blend_skin([
        (bidx["hips"], 0.96 * sy),
        (bidx["spine"], 1.13 * sy),
        (bidx["chest"], 1.36 * sy),
        (bidx["neck"], 1.54 * sy),
    ], softness=0.095)
    head_skin = y_blend_skin([
        (bidx["chest"], 1.46 * sy),
        (bidx["neck"], 1.55 * sy),
        (bidx["head"], 1.63 * sy),
    ], softness=0.05)
    hips_skin = y_blend_skin([
        (bidx["hips"], 0.98 * sy),
        (bidx["spine"], 1.15 * sy),
    ], softness=0.08)

    # -----------------------------------------------------------------------
    # 1. CONTINUOUS ATHLETIC TORSO & PELVIS (zero boxy waist seam!)
    # -----------------------------------------------------------------------
    def torso_sculpt(r_idx: int, ang: float, x: float, y: float, z: float) -> Vec3:
        # Slight anatomical chest-pectoral contour (-Z is front) and back lat-taper (+Z is back)
        front_factor = max(0.0, -math.sin(ang))
        back_factor = max(0.0, math.sin(ang))
        side_factor = abs(math.cos(ang))
        # Subtle chest definition around rings 5-7
        if 5 <= r_idx <= 7:
            z -= front_factor * 0.016 * (1.0 - 0.35 * abs(math.cos(ang * 2.0)))
            z += back_factor * 0.010 * (0.4 + 0.6 * side_factor)
        # Subtle spine groove on back
        if 2 <= r_idx <= 7 and back_factor > 0.7:
            z -= 0.012 * ((back_factor - 0.7) / 0.3)
        return (x, y, z)

    torso_rings = [
        (0.84 * sy, 0.0, 0.005, 0.095 * w_mult, 0.072 * w_mult),
        (0.91 * sy, 0.0, 0.004, 0.168 * w_mult, 0.112 * w_mult),
        (0.99 * sy, 0.0, 0.000, 0.164 * w_mult, 0.116 * w_mult),
        (1.07 * sy, 0.0, -0.002, 0.150 * w_mult, 0.108 * w_mult),  # athletic tapered waist
        (1.16 * sy, 0.0, -0.003, 0.162 * w_mult, 0.114 * w_mult),  # lower ribs
        (1.26 * sy, 0.0, -0.004, 0.194 * w_mult, 0.126 * w_mult),  # mid chest/lats
        (1.37 * sy, 0.0, -0.004, 0.222 * w_mult, 0.134 * w_mult),  # broad heroic chest
        (1.45 * sy, 0.0, -0.002, 0.210 * w_mult, 0.118 * w_mult),  # clavicles
        (1.50 * sy, 0.0, -0.003, 0.118 * w_mult, 0.082 * w_mult),  # trapezius
        (1.54 * sy, 0.0, -0.004, 0.068, 0.064),                    # neck base
    ]
    add_loft(buckets[M_FABRIC], torso_rings, torso_skin, seg=24, sculpt_fn=torso_sculpt)

    # Athletic belt / hip armor chevron (wraps smoothly around waist)
    belt_rings = [
        (0.99 * sy, 0.0, 0.000, 0.171 * w_mult, 0.123 * w_mult),
        (1.02 * sy, 0.0, -0.002, 0.172 * w_mult, 0.126 * w_mult),
        (1.055 * sy, 0.0, -0.002, 0.162 * w_mult, 0.120 * w_mult),
    ]
    add_loft(buckets[M_WEAVE], belt_rings, hips_skin, seg=22)
    # Golden speed belt V-chevron front & back
    add_tube(buckets[M_GOLD], [
        (-0.155 * w_mult, 1.045 * sy, -0.045),
        (-0.085 * w_mult, 1.032 * sy, -0.118 * w_mult),
        (0.0, 1.008 * sy, -0.132 * w_mult),
        (0.085 * w_mult, 1.032 * sy, -0.118 * w_mult),
        (0.155 * w_mult, 1.045 * sy, -0.045),
    ], 0.011, hips_skin, seg=8)
    add_tube(buckets[M_ALLOY], [
        (-0.155 * w_mult, 1.045 * sy, 0.045),
        (-0.085 * w_mult, 1.035 * sy, 0.116 * w_mult),
        (0.0, 1.018 * sy, 0.128 * w_mult),
        (0.085 * w_mult, 1.035 * sy, 0.116 * w_mult),
        (0.155 * w_mult, 1.045 * sy, 0.045),
    ], 0.010, hips_skin, seg=8)

    # Sculpted Dorsal Spine Armor & Back Speed Emblem (Heroic back silhouette!)
    add_loft(buckets[M_SHELL], [
        (1.08 * sy, 0.0, 0.106 * w_mult, 0.042, 0.020),
        (1.20 * sy, 0.0, 0.118 * w_mult, 0.062, 0.024),
        (1.34 * sy, 0.0, 0.130 * w_mult, 0.072, 0.028),
        (1.44 * sy, 0.0, 0.108 * w_mult, 0.064, 0.026),
        (1.49 * sy, 0.0, 0.088 * w_mult, 0.046, 0.018),
    ], torso_skin, seg=14)
    # Raised segmented spine chevrons
    for k in range(5):
        yk = (1.13 + k * 0.056) * sy
        zk = (0.122 + 0.016 * math.sin(k * 0.65)) * w_mult
        add_tube(buckets[M_ALLOY], [
            (-0.048, yk + 0.012, zk - 0.008),
            (0.0, yk - 0.006, zk + 0.014),
            (0.048, yk + 0.012, zk - 0.008),
        ], 0.007, torso_skin, seg=6)
    # Glowing back lightning insignia / core
    if archetype == "nullstride":
        # Glowing violet singularity core on chest AND back
        add_ellipsoid(buckets[M_GOLD], (0.0, 1.35 * sy, -0.145 * w_mult), (0.055, 0.065, 0.024), rigid_skin(bidx["chest"]))
        add_ellipsoid(buckets[M_GOLD], (0.0, 1.35 * sy, 0.148 * w_mult), (0.048, 0.062, 0.024), rigid_skin(bidx["chest"]))
        # Jagged armored dorsal collar crest
        add_fin_blade(buckets[M_ARMOR], [
            (-0.15, 1.46 * sy, 0.08), (-0.19, 1.59 * sy, 0.14),
            (0.0, 1.54 * sy, 0.15), (0.19, 1.59 * sy, 0.14), (0.15, 1.46 * sy, 0.08),
        ], (0.0, 0.0, 0.014), rigid_skin(bidx["chest"]))
    else:
        # Iconic lightning bolt crest on back & chest
        bolt_back = [
            (-0.042, 1.39 * sy, 0.146 * w_mult),
            (0.016, 1.425 * sy, 0.156 * w_mult),
            (-0.012, 1.355 * sy, 0.158 * w_mult),
            (0.046, 1.375 * sy, 0.148 * w_mult),
            (-0.020, 1.295 * sy, 0.144 * w_mult),
        ]
        add_tube(buckets[M_GOLD], bolt_back, 0.0095, rigid_skin(bidx["chest"]), seg=8)
        bolt_front = [
            (0.036, 1.415 * sy, -0.142 * w_mult),
            (-0.018, 1.365 * sy, -0.156 * w_mult),
            (0.020, 1.360 * sy, -0.156 * w_mult),
            (-0.036, 1.295 * sy, -0.144 * w_mult),
        ]
        add_tube(buckets[M_GOLD], bolt_front, 0.0105, rigid_skin(bidx["chest"]), seg=8)

    # Sculpted Pectoral & Scapula Armor Plates
    for sign in (1.0, -1.0):
        # Front pectoral plate
        add_ellipsoid(
            buckets[M_ARMOR],
            (sign * 0.105 * w_mult, 1.36 * sy, -0.095 * w_mult),
            (0.092 * w_mult, 0.068 * sy, 0.056 * w_mult),
            rigid_skin(bidx["chest"]),
        )
        # Back scapula wing-plate
        add_ellipsoid(
            buckets[M_ARMOR],
            (sign * 0.118 * w_mult, 1.38 * sy, 0.092 * w_mult),
            (0.082 * w_mult, 0.088 * sy, 0.046 * w_mult),
            rigid_skin(bidx["chest"]),
        )
        # Glowing dorsal & rib conduits
        add_tube(buckets[M_GOLD], [
            (sign * 0.185 * w_mult, 1.44 * sy, 0.068 * w_mult),
            (sign * 0.145 * w_mult, 1.37 * sy, 0.128 * w_mult),
            (sign * 0.095 * w_mult, 1.27 * sy, 0.126 * w_mult),
            (sign * 0.072 * w_mult, 1.15 * sy, 0.116 * w_mult),
        ], 0.007, torso_skin, seg=6)
        add_tube(buckets[M_GOLD], [
            (sign * 0.165 * w_mult, 1.31 * sy, -0.092 * w_mult),
            (sign * 0.148 * w_mult, 1.21 * sy, -0.098 * w_mult),
            (sign * 0.132 * w_mult, 1.11 * sy, -0.096 * w_mult),
        ], 0.006, torso_skin, seg=6)

    # -----------------------------------------------------------------------
    # 2. NECK, SCULPTED HELMET / MASK, VISOR & SIGNATURE CRESTS
    # -----------------------------------------------------------------------
    add_loft(buckets[M_WEAVE], [
        (1.48 * sy, 0.0, -0.002, 0.102, 0.080),
        (1.54 * sy, 0.0, -0.004, 0.068, 0.064),
        (1.61 * sy, 0.0, -0.006, 0.060, 0.058),
    ], head_skin, seg=18)

    # Main aerodynamic helmet cranium (faces -Z)
    helmet_rings = [
        (1.595 * sy, 0.0, -0.012, 0.054, 0.064),
        (1.635 * sy, 0.0, -0.010, 0.078, 0.086),
        (1.685 * sy, 0.0, -0.004, 0.095, 0.102),
        (1.745 * sy, 0.0, 0.004, 0.097, 0.105),
        (1.798 * sy, 0.0, 0.012, 0.086, 0.096),
        (1.835 * sy, 0.0, 0.014, 0.058, 0.066),
        (1.855 * sy, 0.0, 0.012, 0.022, 0.024),
    ]
    add_loft(buckets[M_ARMOR], helmet_rings, rigid_skin(bidx["head"]), seg=22)

    # Lower face / chin armor + visor
    add_loft(buckets[M_SKIN], [
        (1.600 * sy, 0.0, -0.052, 0.028, 0.036),
        (1.628 * sy, 0.0, -0.058, 0.052, 0.044),
        (1.662 * sy, 0.0, -0.058, 0.068, 0.048),
        (1.690 * sy, 0.0, -0.054, 0.072, 0.050),
    ], rigid_skin(bidx["head"]), seg=16)
    add_loft(buckets[M_VISOR], [
        (1.692 * sy, 0.0, -0.064, 0.068, 0.034),
        (1.712 * sy, 0.0, -0.062, 0.088, 0.052),
        (1.738 * sy, 0.0, -0.056, 0.089, 0.058),
        (1.756 * sy, 0.0, -0.060, 0.074, 0.044),
    ], rigid_skin(bidx["head"]), seg=18)

    # Helmet center ridge + archetype signature headgear
    add_tube(buckets[M_ALLOY], [
        (0.0, 1.755 * sy, -0.100),
        (0.0, 1.825 * sy, -0.062),
        (0.0, 1.862 * sy, 0.012),
        (0.0, 1.820 * sy, 0.095),
        (0.0, 1.720 * sy, 0.110),
        (0.0, 1.645 * sy, 0.092),
    ], 0.0085, rigid_skin(bidx["head"]), seg=6)

    if archetype == "hero":
        # Iconic swept-back golden ear-wings on helmet temples!
        for sign in (1.0, -1.0):
            add_ellipsoid(buckets[M_WEAVE], (sign * 0.094, 1.718 * sy, 0.006), (0.020, 0.036, 0.038), rigid_skin(bidx["head"]))
            add_fin_blade(buckets[M_GOLD], [
                (sign * 0.102, 1.715 * sy, -0.018),
                (sign * 0.116, 1.745 * sy, 0.042),
                (sign * 0.132, 1.792 * sy, 0.125),
                (sign * 0.114, 1.748 * sy, 0.088),
                (sign * 0.122, 1.720 * sy, 0.112),
                (sign * 0.102, 1.702 * sy, 0.032),
            ], (sign * 0.007, 0.003, 0.002), rigid_skin(bidx["head"]))
        # Brow gold conductor strip
        add_tube(buckets[M_GOLD], [
            (-0.076, 1.734 * sy, -0.088),
            (0.0, 1.722 * sy, -0.114),
            (0.076, 1.734 * sy, -0.088),
        ], 0.006, rigid_skin(bidx["head"]), seg=6)
    elif archetype == "nullstride":
        # Menacing swept predator horns + glowing crimson/violet visor slit + chin respirator
        for sign in (1.0, -1.0):
            add_fin_blade(buckets[M_ALLOY], [
                (sign * 0.078, 1.755 * sy, -0.045),
                (sign * 0.118, 1.835 * sy, 0.035),
                (sign * 0.155, 1.935 * sy, 0.145),
                (sign * 0.115, 1.875 * sy, 0.130),
                (sign * 0.082, 1.785 * sy, 0.055),
            ], (sign * 0.012, 0.006, 0.006), rigid_skin(bidx["head"]))
        # Glowing aggressive visor slash
        add_tube(buckets[M_LIP], [
            (-0.082, 1.726 * sy, -0.095),
            (0.0, 1.708 * sy, -0.122),
            (0.082, 1.726 * sy, -0.095),
        ], 0.010, rigid_skin(bidx["head"]), seg=6)
    elif archetype == "afterlight":
        # Imperial tall golden twin aero-crown fins + high white-gold collar
        for sign in (1.0, -1.0):
            add_fin_blade(buckets[M_GOLD], [
                (sign * 0.068, 1.745 * sy, -0.065),
                (sign * 0.098, 1.835 * sy, 0.025),
                (sign * 0.112, 1.945 * sy, 0.140),
                (sign * 0.086, 1.865 * sy, 0.110),
                (sign * 0.092, 1.790 * sy, 0.135),
                (sign * 0.072, 1.715 * sy, 0.045),
            ], (sign * 0.009, 0.003, 0.003), rigid_skin(bidx["head"]))
        # High sculpted aero-collar on chest
        add_loft(buckets[M_ALLOY], [
            (1.48 * sy, 0.0, 0.022, 0.132, 0.104),
            (1.56 * sy, 0.0, 0.042, 0.122, 0.106),
            (1.61 * sy, 0.0, 0.052, 0.108, 0.094),
        ], rigid_skin(bidx["chest"]), seg=18, cap_top=False)

    # -----------------------------------------------------------------------
    # 3. SMOOTH-SKINNED ARMS, PAULDRONS, GAUNTLETS & BLADES
    # -----------------------------------------------------------------------
    for side, sign in (("L", 1.0), ("R", -1.0)):
        arm_j = bidx["arm" + side]
        fore_j = bidx["fore" + side]
        hand_j = bidx["hand" + side]
        chest_j = bidx["chest"]
        sx_sh = sign * shoulder_w
        sx_el = sign * (shoulder_w + 0.055)
        sx_wr = sign * (shoulder_w + 0.075)

        arm_skin = y_blend_skin([
            (hand_j, 0.90 * sy),
            (fore_j, 1.13 * sy),
            (arm_j, 1.38 * sy),
            (chest_j, 1.50 * sy),
        ], softness=0.065)

        # Continuous smooth-skinned arm from shoulder deltoid -> bicep -> elbow -> forearm -> wrist
        arm_rings = [
            (0.92 * sy, sx_wr, -0.008, 0.033 * w_mult, 0.036 * w_mult),
            (1.01 * sy, sx_wr - sign * 0.006, -0.002, 0.044 * w_mult, 0.046 * w_mult),
            (1.10 * sy, sx_el + sign * 0.006, 0.006, 0.052 * w_mult, 0.050 * w_mult),
            (1.16 * sy, sx_el, 0.010, 0.048 * w_mult, 0.048 * w_mult),  # elbow
            (1.26 * sy, sx_sh + sign * 0.036, 0.006, 0.058 * w_mult, 0.060 * w_mult),  # bicep
            (1.37 * sy, sx_sh + sign * 0.014, 0.005, 0.068 * w_mult, 0.072 * w_mult),  # deltoid
            (1.45 * sy, sx_sh - sign * 0.012, 0.004, 0.062 * w_mult, 0.068 * w_mult),  # shoulder cap
            (1.49 * sy, sx_sh - sign * 0.045, 0.002, 0.045 * w_mult, 0.052 * w_mult),
        ]
        add_loft(buckets[M_FABRIC], arm_rings, arm_skin, seg=18)

        # Shoulder pauldron armor
        if archetype == "nullstride":
            # Massive jagged layered obsidian pauldrons!
            add_ellipsoid(buckets[M_ARMOR], (sx_sh + sign * 0.038, 1.455 * sy, 0.004), (0.095, 0.072, 0.098), rigid_skin(arm_j))
            add_fin_blade(buckets[M_ALLOY], [
                (sx_sh + sign * 0.01, 1.48 * sy, -0.06),
                (sx_sh + sign * 0.145, 1.56 * sy, 0.02),
                (sx_sh + sign * 0.125, 1.44 * sy, 0.08),
                (sx_sh + sign * 0.02, 1.41 * sy, 0.05),
            ], (0.0, 0.012, 0.0), rigid_skin(arm_j))
            add_tube(buckets[M_GOLD], [
                (sx_sh + sign * 0.06, 1.50 * sy, -0.04),
                (sx_sh + sign * 0.115, 1.52 * sy, 0.01),
                (sx_sh + sign * 0.08, 1.45 * sy, 0.06),
            ], 0.008, rigid_skin(arm_j), seg=6)
        elif archetype == "afterlight":
            # Sleek winged golden shoulder guards
            add_ellipsoid(buckets[M_ALLOY], (sx_sh + sign * 0.024, 1.445 * sy, 0.005), (0.076, 0.056, 0.078), rigid_skin(arm_j))
            add_fin_blade(buckets[M_GOLD], [
                (sx_sh + sign * 0.02, 1.46 * sy, -0.04),
                (sx_sh + sign * 0.115, 1.51 * sy, 0.05),
                (sx_sh + sign * 0.06, 1.43 * sy, 0.07),
            ], (0.0, 0.008, 0.0), rigid_skin(arm_j))
        else:
            # Heroic sculpted crimson shoulder armor + gold deltoid bolt
            add_ellipsoid(buckets[M_ARMOR], (sx_sh + sign * 0.022, 1.44 * sy, 0.004), (0.076, 0.064, 0.076), rigid_skin(arm_j))
            add_tube(buckets[M_GOLD], [
                (sx_sh + sign * 0.056, 1.46 * sy, 0.048),
                (sx_sh + sign * 0.086, 1.425 * sy, 0.014),
                (sx_sh + sign * 0.076, 1.38 * sy, -0.022),
            ], 0.0065, rigid_skin(arm_j), seg=6)

        # Forearm armored bracer + gold speed conduit
        add_loft(buckets[M_ARMOR], [
            (0.935 * sy, sx_wr, -0.008, 0.038 * w_mult, 0.040 * w_mult),
            (1.035 * sy, sx_wr - sign * 0.008, -0.001, 0.051 * w_mult, 0.050 * w_mult),
            (1.135 * sy, sx_el + sign * 0.004, 0.008, 0.054 * w_mult, 0.052 * w_mult),
        ], rigid_skin(fore_j), seg=16)
        add_tube(buckets[M_GOLD], [
            (sx_el + sign * 0.048, 1.13 * sy, 0.012),
            (sx_wr + sign * 0.040, 1.03 * sy, 0.002),
            (sx_wr + sign * 0.036, 0.94 * sy, -0.006),
        ], 0.006, rigid_skin(fore_j), seg=6)

        # Afterlight forearm phase-blades / Nullstride elbow spikes
        if archetype == "afterlight":
            add_fin_blade(buckets[M_GOLD], [
                (sx_wr + sign * 0.032, 0.96 * sy, -0.010),
                (sx_el + sign * 0.052, 1.15 * sy, 0.025),
                (sx_el + sign * 0.078, 1.24 * sy, 0.145),
                (sx_el + sign * 0.045, 1.10 * sy, 0.065),
            ], (sign * 0.006, 0.0, 0.003), rigid_skin(fore_j))
        elif archetype == "nullstride":
            add_fin_blade(buckets[M_ALLOY], [
                (sx_el + sign * 0.04, 1.12 * sy, 0.02),
                (sx_el + sign * 0.08, 1.22 * sy, 0.10),
                (sx_el + sign * 0.03, 1.16 * sy, 0.05),
            ], (sign * 0.008, 0.0, 0.005), rigid_skin(fore_j))

        # Sculpted gloved fist (natural heroic clenched fist)
        add_ellipsoid(buckets[M_WEAVE], (sx_wr, 0.875 * sy, -0.012), (0.042, 0.058, 0.046), rigid_skin(hand_j))
        add_ellipsoid(buckets[M_ALLOY], (sx_wr + sign * 0.012, 0.865 * sy, -0.042), (0.036, 0.024, 0.018), rigid_skin(hand_j))

    # -----------------------------------------------------------------------
    # 4. SMOOTH-SKINNED ATHLETIC LEGS, KNEE GUARDS & SPEED BOOTS
    # -----------------------------------------------------------------------
    for side, sign in (("L", 1.0), ("R", -1.0)):
        thigh_j = bidx["thigh" + side]
        shin_j = bidx["shin" + side]
        foot_j = bidx["foot" + side]
        hips_j = bidx["hips"]
        lx_hi = sign * hip_w
        lx_kn = sign * (hip_w + 0.008)
        lx_an = sign * (hip_w + 0.010)

        leg_skin = y_blend_skin([
            (foot_j, 0.10 * sy),
            (shin_j, 0.45 * sy),
            (thigh_j, 0.78 * sy),
            (hips_j, 0.96 * sy),
        ], softness=0.065)

        # Continuous smooth-skinned leg from hip -> muscular quad/hamstring -> knee -> athletic calf -> ankle
        leg_rings = [
            (0.11 * sy, lx_an, 0.012, 0.044 * w_mult, 0.050 * w_mult),   # ankle
            (0.22 * sy, lx_an, 0.014, 0.054 * w_mult, 0.058 * w_mult),   # lower calf
            (0.35 * sy, lx_an, 0.016, 0.068 * w_mult, 0.072 * w_mult),   # athletic calf bulge
            (0.47 * sy, lx_kn, 0.002, 0.064 * w_mult, 0.066 * w_mult),   # upper shin
            (0.52 * sy, lx_kn, -0.008, 0.062 * w_mult, 0.065 * w_mult),  # knee
            (0.64 * sy, lx_hi + sign * 0.004, -0.006, 0.078 * w_mult, 0.084 * w_mult),  # lower thigh
            (0.79 * sy, lx_hi, -0.002, 0.094 * w_mult, 0.098 * w_mult),  # muscular quad
            (0.92 * sy, lx_hi - sign * 0.004, 0.002, 0.094 * w_mult, 0.096 * w_mult),  # upper thigh
            (0.98 * sy, lx_hi - sign * 0.016, 0.002, 0.076 * w_mult, 0.082 * w_mult),  # hip blend
        ]
        add_loft(buckets[M_FABRIC], leg_rings, leg_skin, seg=20)

        # Outer thigh armor panel + glowing speed conduit
        add_ellipsoid(
            buckets[M_ARMOR],
            (lx_hi + sign * 0.068 * w_mult, 0.76 * sy, 0.004),
            (0.034 * w_mult, 0.135 * sy, 0.068 * w_mult),
            rigid_skin(thigh_j),
        )
        add_tube(buckets[M_GOLD], [
            (lx_hi + sign * 0.094 * w_mult, 0.87 * sy, 0.022),
            (lx_hi + sign * 0.098 * w_mult, 0.76 * sy, 0.014),
            (lx_kn + sign * 0.078 * w_mult, 0.62 * sy, 0.022),
        ], 0.006, rigid_skin(thigh_j), seg=6)

        # Knee guard & shin armor greave
        add_ellipsoid(buckets[M_ARMOR], (lx_kn, 0.525 * sy, -0.062 * w_mult), (0.058 * w_mult, 0.074 * sy, 0.036), rigid_skin(shin_j))
        add_loft(buckets[M_WEAVE], [
            (0.14 * sy, lx_an, 0.008, 0.050 * w_mult, 0.056 * w_mult),
            (0.30 * sy, lx_an, 0.010, 0.072 * w_mult, 0.076 * w_mult),
            (0.45 * sy, lx_kn, 0.004, 0.068 * w_mult, 0.070 * w_mult),
        ], rigid_skin(shin_j), seg=16)
        add_tube(buckets[M_GOLD], [
            (lx_kn + sign * 0.064 * w_mult, 0.45 * sy, 0.028),
            (lx_an + sign * 0.074 * w_mult, 0.32 * sy, 0.036),
            (lx_an + sign * 0.056 * w_mult, 0.18 * sy, 0.032),
        ], 0.0065, rigid_skin(shin_j), seg=6)

        # Grounded sculpted speedster boot (sole sits flush at Y = 0.000!)
        boot_mat = M_ALLOY if archetype in ("hero", "afterlight") else M_ARMOR
        boot_rings = [
            (0.000, lx_an, -0.035, 0.060 * w_mult, 0.128),
            (0.030, lx_an, -0.038, 0.064 * w_mult, 0.132),
            (0.068, lx_an, -0.032, 0.060 * w_mult, 0.122),
            (0.105 * sy, lx_an, -0.005, 0.054 * w_mult, 0.088),
            (0.165 * sy, lx_an, 0.010, 0.052 * w_mult, 0.064),
            (0.220 * sy, lx_an, 0.012, 0.056 * w_mult, 0.062),
        ]
        add_loft(buckets[boot_mat], boot_rings, rigid_skin(foot_j), seg=18)
        # Dark rubber traction sole + golden ankle aero-wing
        add_loft(buckets[M_WEAVE], [
            (0.000, lx_an, -0.038, 0.063 * w_mult, 0.132),
            (0.024, lx_an, -0.038, 0.065 * w_mult, 0.134),
        ], rigid_skin(foot_j), seg=16)
        add_fin_blade(buckets[M_GOLD], [
            (lx_an + sign * 0.056, 0.135 * sy, 0.010),
            (lx_an + sign * 0.078, 0.195 * sy, 0.095),
            (lx_an + sign * 0.056, 0.165 * sy, 0.060),
            (lx_an + sign * 0.052, 0.105 * sy, 0.030),
        ], (sign * 0.005, 0.002, 0.002), rigid_skin(foot_j))

    # -----------------------------------------------------------------------
    # 5. BOSS-SPECIFIC FLOWING CLOAKS / COATTAILS (Distinct Silhouettes!)
    # -----------------------------------------------------------------------
    if archetype == "nullstride":
        # Twin ragged dark void-scarf / cloak streamers flowing from shoulders
        for side, sign in (("L", 1.0), ("R", -1.0)):
            cj = bidx["cape" + side]
            rows = []
            for k in range(8):
                t = k / 7.0
                y = (1.42 - t * 0.92) * sy
                z = 0.135 + t * 0.12 + 0.025 * math.sin(t * math.pi)
                x_in = sign * (0.025 + t * 0.03)
                x_out = sign * (0.175 + t * 0.08 - t * t * 0.06)
                if sign > 0:
                    rows.append(((x_in, y, z), (x_out, y, z - 0.02)))
                else:
                    rows.append(((x_out, y, z - 0.02), (x_in, y, z)))
            add_ribbon(buckets[M_SHELL], rows, rigid_skin(cj), thickness=0.009)
            # Glowing violet edge trim along outer cloak hem
            add_tube(buckets[M_GOLD], [
                (sign * (0.175 + (k / 7.0) * 0.08 - (k / 7.0) ** 2 * 0.06), (1.42 - (k / 7.0) * 0.92) * sy, 0.12 + (k / 7.0) * 0.12)
                for k in range(8)
            ], 0.006, rigid_skin(cj), seg=5)
    elif archetype == "afterlight":
        # Split ivory & gold speedster aero-coattails flowing behind hips
        for side, sign in (("L", 1.0), ("R", -1.0)):
            cj = bidx["cape" + side]
            rows = []
            for k in range(7):
                t = k / 6.0
                y = (1.06 - t * 0.58) * sy
                z = 0.125 + t * 0.14
                x_in = sign * (0.03 + t * 0.05)
                x_out = sign * (0.165 + t * 0.06 - t * t * 0.07)
                if sign > 0:
                    rows.append(((x_in, y, z), (x_out, y, z - 0.025)))
                else:
                    rows.append(((x_out, y, z - 0.025), (x_in, y, z)))
            add_ribbon(buckets[M_ARMOR], rows, rigid_skin(cj), thickness=0.008)
            add_tube(buckets[M_GOLD], [
                (sign * (0.165 + (k / 6.0) * 0.06 - (k / 6.0) ** 2 * 0.07), (1.06 - (k / 6.0) * 0.58) * sy, 0.105 + (k / 6.0) * 0.14)
                for k in range(7)
            ], 0.0065, rigid_skin(cj), seg=5)

    return bones, bidx, bworld, materials, buckets


# ---------------------------------------------------------------------------
# Animation Synthesizer (All 29 Required Gameplay Clips)
# ---------------------------------------------------------------------------
def build_animations(bones, bidx, bworld, archetype: str):
    """Build smooth, biomechanically grounded keyframed poses for all 29 clips.

    Coordinate convention (identity bind pose, Y-up, -Z forward):
      - +rx pitches forward/up for legs? Let's verify exact right-hand rule around +X!
        Pointing thumb along +X (right in Blender / L in our coords):
        +rx rotates +Y toward +Z (leaning BACKWARD), and rotates -Y (downward limb) toward -Z (FORWARD)!
        Wait — double check!
        y' = y cos(a) - z sin(a)
        z' = y sin(a) + z cos(a)
        - For a limb pointing DOWN (0, -L, 0):
          y' = -L cos(a), z' = -L sin(a).
          So +rx swings a hanging leg/arm FORWARD (toward -Z)!
          And -rx swings a hanging leg/arm BACKWARD (toward +Z)!
        - For torso/hips pointing UP (0, +H, 0):
          y' = +H cos(a), z' = +H sin(a).
          So -rx leans the torso FORWARD (toward -Z)!
          And +rx leans the torso BACKWARD (toward +Z)!
        - For forearm bending forward/up from hanging arm: +rx bends elbow FORWARD (anatomical flexion)!
        - For shin bending backward from hanging thigh: -rx bends knee BACKWARD (anatomical flexion)!
        - For +rz on left arm (+X side, hanging down 0, -L, 0):
          x' = x cos(a) - y sin(a) = +L sin(a) -> +rz abducts armL OUTWARD (+X)!
          And -rz abducts armR OUTWARD (-X)!
    That right-hand rule check guarantees 100% anatomically correct joint bends!
    """
    fps = 30.0

    def sample_pose(clip: str, phase: float, t01: float) -> Tuple[Dict[str, Vec3], Dict[str, Vec3]]:
        rot: Dict[str, List[float]] = {b[0]: [0.0, 0.0, 0.0] for b in bones}
        trans: Dict[str, Vec3] = {}
        hips_base = bworld["hips"]

        def add_r(name: str, rx: float = 0.0, ry: float = 0.0, rz: float = 0.0):
            r = rot[name]
            r[0] += rx
            r[1] += ry
            r[2] += rz

        # Locomotion parameter table
        loco = {
            "Walk":   (0.36, 0.06, 0.018, 0.55),
            "Jog":    (0.62, 0.16, 0.036, 0.85),
            "Sprint": (1.02, 0.34, 0.055, 1.15),
            "Boost":  (1.22, 0.52, 0.064, 1.25),
            "Wall":   (0.86, 0.28, 0.045, 1.05),
            "Water":  (1.06, 0.38, 0.042, 1.20),
        }

        if clip == "Idle":
            breath = math.sin(phase)
            shift = math.sin(phase * 0.5)
            # Athletic superhero ready stance (never a stiff A-pose!)
            trans["hips"] = (hips_base[0] + shift * 0.012, hips_base[1] - 0.025 + breath * 0.008, hips_base[2])
            add_r("hips", -0.04, 0.10, shift * 0.018)
            add_r("spine", -0.03 + breath * 0.018, -0.05, -shift * 0.015)
            add_r("chest", 0.02 + breath * 0.024, -0.06, 0.0)
            add_r("head", 0.03 - breath * 0.015, -0.04 + math.sin(phase * 0.5) * 0.06, 0.0)
            # Planted athletic stance
            add_r("thighL", 0.14, 0.04, 0.07)
            add_r("shinL", -0.22, 0.0, 0.0)
            add_r("footL", 0.08, 0.0, -0.04)
            add_r("thighR", -0.08, -0.06, -0.07)
            add_r("shinR", -0.14, 0.0, 0.0)
            add_r("footR", 0.22, 0.0, 0.04)
            # Relaxed athletic superhero arms with slightly bent elbows
            add_r("armL", -0.06 + breath * 0.02, 0.06, 0.14 + breath * 0.015)
            add_r("foreL", 0.42 + breath * 0.03, 0.0, -0.08)
            add_r("armR", 0.04 - breath * 0.02, -0.06, -0.14 - breath * 0.015)
            add_r("foreR", 0.46 - breath * 0.03, 0.0, 0.08)
            add_r("capeL", -0.08 - breath * 0.04, 0.0, 0.04)
            add_r("capeR", -0.08 - breath * 0.04, 0.0, -0.04)

        elif clip in loco:
            stride, lean, bob, arm_drive = loco[clip]
            # Double-frequency vertical bounce (highest at mid-flight, lowest at mid-stance)
            bounce = -abs(math.cos(phase)) * bob - (0.04 * lean)
            trans["hips"] = (hips_base[0] + math.sin(phase) * 0.018 * stride, hips_base[1] + bounce, hips_base[2])
            add_r("hips", -lean * 0.45, -math.sin(phase) * 0.16 * stride, math.sin(phase) * 0.04 * stride)
            add_r("spine", -lean * 0.35, math.sin(phase) * 0.14 * stride, -math.sin(phase) * 0.03 * stride)
            add_r("chest", -lean * 0.25, math.sin(phase) * 0.22 * stride, -math.sin(phase) * 0.04 * stride)
            add_r("neck", lean * 0.42, -math.sin(phase) * 0.12 * stride, 0.0)
            add_r("head", lean * 0.48, -math.sin(phase) * 0.08 * stride, 0.0)
            for side, shift, sign in (("L", 0.0, 1.0), ("R", math.pi, -1.0)):
                s = math.sin(phase + shift)
                c = math.cos(phase + shift)
                # Leg swing: +rx is forward
                thigh_x = s * stride + 0.18 * stride
                # Knee flexion peaks during swing-through (when s is rising/trailing)
                knee_bend = -stride * (0.22 + max(0.0, -c) * 0.85 + max(0.0, -s) * 0.45)
                if clip in ("Sprint", "Boost", "Water"):
                    knee_bend = clamp(knee_bend, -1.85, -0.15)
                foot_x = -0.25 * thigh_x - 0.35 * knee_bend + 0.22 * stride * c
                add_r("thigh" + side, thigh_x, 0.0, sign * 0.035)
                add_r("shin" + side, knee_bend, 0.0, 0.0)
                add_r("foot" + side, clamp(foot_x, -0.65, 0.65), 0.0, 0.0)
                # Opposite arm pump
                arm_x = -s * stride * 0.92 * arm_drive - 0.10 * lean
                fore_x = 0.72 + stride * 0.62 + max(0.0, -s) * 0.35
                add_r("arm" + side, arm_x, sign * 0.08, sign * (0.11 + 0.06 * stride))
                add_r("fore" + side, clamp(fore_x, 0.35, 1.95), 0.0, -sign * 0.08)
            # Dynamic billowing capes/coattails at speed
            flutter = math.sin(phase * 2.0) * 0.12 * stride
            add_r("capeL", -(0.28 + lean * 1.15) + flutter, 0.0, 0.08 + 0.05 * stride)
            add_r("capeR", -(0.28 + lean * 1.15) - flutter, 0.0, -(0.08 + 0.05 * stride))

        elif clip == "Air":
            hover = math.sin(phase) * 0.06
            trans["hips"] = (hips_base[0], hips_base[1] + 0.04 + hover * 0.3, hips_base[2])
            add_r("hips", -0.22, 0.08, 0.0)
            add_r("spine", -0.10, -0.06, 0.0)
            add_r("head", 0.20, 0.0, 0.0)
            add_r("thighL", 0.78 + hover, 0.0, 0.08)
            add_r("shinL", -1.18, 0.0, 0.0)
            add_r("footL", -0.25, 0.0, 0.0)
            add_r("thighR", -0.36 - hover, 0.0, -0.08)
            add_r("shinR", -0.82, 0.0, 0.0)
            add_r("armL", -0.35 + hover, 0.0, 0.42)
            add_r("foreL", 0.95, 0.0, 0.0)
            add_r("armR", 0.58 - hover, 0.0, -0.32)
            add_r("foreR", 1.05, 0.0, 0.0)
            add_r("capeL", -0.75 + hover, 0.0, 0.14)
            add_r("capeR", -0.75 - hover, 0.0, -0.14)

        elif clip == "Brake":
            trans["hips"] = (hips_base[0], hips_base[1] - 0.14, hips_base[2])
            add_r("hips", 0.28, -0.22, 0.0)
            add_r("spine", 0.12, 0.14, 0.0)
            add_r("head", -0.28, 0.10, 0.0)
            add_r("thighL", 0.72, 0.0, 0.12)
            add_r("shinL", -0.45, 0.0, 0.0)
            add_r("footL", 0.35, 0.0, 0.0)
            add_r("thighR", -0.34, 0.0, -0.14)
            add_r("shinR", -0.78, 0.0, 0.0)
            add_r("armL", -0.32, 0.0, 0.55)
            add_r("foreL", 0.55, 0.0, 0.0)
            add_r("armR", 0.42, 0.0, -0.48)
            add_r("foreR", 0.72, 0.0, 0.0)
            add_r("capeL", -0.35, 0.0, 0.15)
            add_r("capeR", -0.35, 0.0, -0.15)

        else:
            # Action & gesture clips with snappy windup -> impact -> recovery curves
            beat = math.sin(t01 * math.pi)
            snap = math.sin(clamp((t01 - 0.10) / 0.75, 0.0, 1.0) * math.pi) ** 0.75
            if clip in ("Jab", "Heavy", "Counter", "Takedown", "Cast", "Redirect"):
                heavy = clip in ("Heavy", "Takedown")
                windup = -math.sin(clamp(t01 / 0.25, 0.0, 1.0) * math.pi) * (0.45 if heavy else 0.20)
                drive = snap * (1.68 if heavy else 1.42)
                trans["hips"] = (hips_base[0], hips_base[1] - 0.08 * snap, hips_base[2] - 0.06 * snap)
                add_r("hips", -0.24 * snap, (-0.52 if heavy else -0.35) * snap + windup, 0.0)
                add_r("chest", -0.16 * snap, (-0.68 if heavy else -0.48) * snap + windup, 0.0)
                add_r("head", 0.28 * snap, 0.55 * snap, 0.0)
                # Right striking arm extends powerfully forward (+rx)
                add_r("armR", drive + windup * 1.4, -0.12 * snap, -0.16)
                add_r("foreR", 0.95 * (1.0 - snap) + 0.12, 0.0, 0.0)
                # Left guard arm pulls back for torque
                add_r("armL", -0.45 * snap, 0.10, 0.26)
                add_r("foreL", 1.35 * snap + 0.45, 0.0, 0.0)
                # Lunging legs
                add_r("thighL", 0.58 * snap + 0.12, 0.0, 0.08)
                add_r("shinL", -0.68 * snap - 0.15, 0.0, 0.0)
                add_r("thighR", -0.44 * snap - 0.08, 0.0, -0.08)
                add_r("shinR", -0.32 * snap - 0.12, 0.0, 0.0)
                add_r("capeL", -0.55 * snap, 0.0, 0.12)
                add_r("capeR", -0.55 * snap, 0.0, -0.12)

            elif clip in ("Dodge", "Slide", "Launch", "Land", "Fall", "Rise"):
                if clip == "Land":
                    # Iconic superhero 3-point crouch landing!
                    crouch = math.sin(t01 * math.pi) ** 0.7
                    trans["hips"] = (hips_base[0], hips_base[1] - 0.42 * crouch, hips_base[2])
                    add_r("hips", -0.58 * crouch, 0.16 * crouch, 0.0)
                    add_r("spine", -0.32 * crouch, 0.0, 0.0)
                    add_r("head", 0.65 * crouch, -0.12 * crouch, 0.0)
                    add_r("thighL", 1.28 * crouch, 0.0, 0.16 * crouch)
                    add_r("shinL", -1.65 * crouch, 0.0, 0.0)
                    add_r("thighR", 0.65 * crouch, 0.0, -0.16 * crouch)
                    add_r("shinR", -1.42 * crouch, 0.0, 0.0)
                    add_r("armR", 1.15 * crouch, 0.0, -0.12)
                    add_r("foreR", 0.25 * crouch, 0.0, 0.0)
                    add_r("armL", -0.65 * crouch, 0.0, 0.62 * crouch)
                    add_r("foreL", 0.72 * crouch, 0.0, 0.0)
                elif clip == "Slide":
                    trans["hips"] = (hips_base[0], hips_base[1] - 0.48 * beat, hips_base[2])
                    add_r("hips", 0.68 * beat, 0.22 * beat, 0.0)
                    add_r("spine", -0.22 * beat, 0.0, 0.0)
                    add_r("head", -0.35 * beat, 0.0, 0.0)
                    add_r("thighL", 1.25 * beat, 0.0, 0.06)
                    add_r("shinL", -0.25 * beat, 0.0, 0.0)
                    add_r("thighR", 0.42 * beat, 0.0, -0.18)
                    add_r("shinR", -1.55 * beat, 0.0, 0.0)
                    add_r("armL", -0.35 * beat, 0.0, 0.55 * beat)
                    add_r("armR", 0.45 * beat, 0.0, -0.45 * beat)
                elif clip == "Launch":
                    trans["hips"] = (hips_base[0], hips_base[1] + 0.08 * beat - 0.12 * (1.0 - beat), hips_base[2])
                    add_r("hips", -0.28 * beat, 0.0, 0.0)
                    add_r("thighL", 0.92 * beat, 0.0, 0.06)
                    add_r("shinL", -1.20 * beat, 0.0, 0.0)
                    add_r("thighR", -0.35 * beat, 0.0, -0.06)
                    add_r("armL", 0.95 * beat, 0.0, 0.25 * beat)
                    add_r("foreL", 0.85 * beat, 0.0, 0.0)
                    add_r("armR", -0.45 * beat, 0.0, -0.25 * beat)
                elif clip in ("Fall", "Rise"):
                    fall_amt = smoothstep(0.0, 0.85, t01) if clip == "Fall" else 1.0 - smoothstep(0.15, 1.0, t01)
                    trans["hips"] = (hips_base[0], hips_base[1] - 0.72 * fall_amt, hips_base[2] + 0.15 * fall_amt)
                    add_r("hips", 1.15 * fall_amt, 0.0, 0.0)
                    add_r("thighL", -0.30 * fall_amt, 0.0, 0.18 * fall_amt)
                    add_r("shinL", -0.55 * fall_amt, 0.0, 0.0)
                    add_r("thighR", 0.20 * fall_amt, 0.0, -0.18 * fall_amt)
                    add_r("armL", 0.45 * fall_amt, 0.0, 0.65 * fall_amt)
                    add_r("armR", 0.45 * fall_amt, 0.0, -0.65 * fall_amt)
                else:  # Dodge
                    trans["hips"] = (hips_base[0], hips_base[1] - 0.22 * beat, hips_base[2])
                    add_r("hips", -0.45 * beat, 0.28 * beat, 0.22 * beat)
                    add_r("head", 0.35 * beat, -0.22 * beat, 0.0)
                    add_r("thighL", 0.82 * beat, 0.0, 0.15)
                    add_r("shinL", -1.15 * beat, 0.0, 0.0)
                    add_r("thighR", -0.32 * beat, 0.0, -0.15)
                    add_r("armL", 0.55 * beat, 0.0, 0.48 * beat)
                    add_r("foreL", 1.10 * beat, 0.0, 0.0)
                    add_r("armR", -0.55 * beat, 0.0, -0.42 * beat)

            else:
                # Hit, Phase, Portal, Slow, Mirage, Tornado, Shockwave, Turn
                if clip == "Hit":
                    trans["hips"] = (hips_base[0], hips_base[1] - 0.08 * beat, hips_base[2] + 0.10 * beat)
                    add_r("hips", 0.35 * beat, -0.20 * beat, 0.0)
                    add_r("chest", 0.28 * beat, -0.18 * beat, 0.0)
                    add_r("head", 0.32 * beat, 0.15 * beat, 0.0)
                    add_r("armL", 0.35 * beat, 0.0, 0.55 * beat)
                    add_r("armR", 0.35 * beat, 0.0, -0.55 * beat)
                elif clip == "Shockwave":
                    slam = math.sin(t01 * math.pi)
                    trans["hips"] = (hips_base[0], hips_base[1] - 0.32 * slam, hips_base[2])
                    add_r("hips", -0.52 * slam, 0.0, 0.0)
                    add_r("thighL", 0.85 * slam, 0.0, 0.18 * slam)
                    add_r("shinL", -1.15 * slam, 0.0, 0.0)
                    add_r("thighR", 0.85 * slam, 0.0, -0.18 * slam)
                    add_r("shinR", -1.15 * slam, 0.0, 0.0)
                    add_r("armL", 1.15 * slam, 0.0, 0.55 * slam)
                    add_r("armR", 1.15 * slam, 0.0, -0.55 * slam)
                elif clip == "Tornado":
                    spin = t01 * math.tau
                    trans["hips"] = (hips_base[0], hips_base[1] - 0.10 * beat, hips_base[2])
                    add_r("hips", -0.18 * beat, spin, 0.0)
                    add_r("armL", 1.25 * beat, 0.0, 0.65 * beat)
                    add_r("foreL", 0.45 * beat, 0.0, 0.0)
                    add_r("armR", 1.25 * beat, 0.0, -0.65 * beat)
                    add_r("foreR", 0.45 * beat, 0.0, 0.0)
                elif clip in ("Portal", "Slow"):
                    trans["hips"] = (hips_base[0], hips_base[1] - 0.06 * beat, hips_base[2])
                    add_r("chest", 0.14 * beat, 0.0, 0.0)
                    add_r("armL", 1.35 * beat, -0.25 * beat, 0.72 * beat)
                    add_r("foreL", 0.35 * beat, 0.0, 0.0)
                    add_r("armR", 1.35 * beat, 0.25 * beat, -0.72 * beat)
                    add_r("foreR", 0.35 * beat, 0.0, 0.0)
                else:  # Phase, Mirage, Turn
                    trans["hips"] = (hips_base[0], hips_base[1] - 0.10 * beat, hips_base[2])
                    add_r("hips", -0.22 * beat, 0.35 * beat if clip == "Turn" else 0.0, 0.0)
                    add_r("chest", -0.12 * beat, 0.42 * beat if clip == "Turn" else 0.0, 0.0)
                    add_r("armL", 0.85 * beat, -0.35 * beat, 0.25 * beat)
                    add_r("foreL", 1.25 * beat, 0.0, 0.0)
                    add_r("armR", 0.85 * beat, 0.35 * beat, -0.25 * beat)
                    add_r("foreR", 1.25 * beat, 0.0, 0.0)
                add_r("capeL", -0.45 * beat, 0.0, 0.16 * beat)
                add_r("capeR", -0.45 * beat, 0.0, -0.16 * beat)

        return {k: (v[0], v[1], v[2]) for k, v in rot.items()}, trans

    clips_spec = [
        ("Idle", 60), ("Walk", 36), ("Jog", 26), ("Sprint", 20), ("Boost", 16),
        ("Wall", 18), ("Water", 16), ("Air", 18), ("Brake", 18),
        ("Jab", 12), ("Heavy", 18), ("Counter", 14), ("Dodge", 12), ("Slide", 20),
        ("Hit", 12), ("Launch", 12), ("Land", 14), ("Fall", 26), ("Rise", 24),
        ("Takedown", 20), ("Cast", 14), ("Phase", 16), ("Portal", 22), ("Slow", 18),
        ("Mirage", 16), ("Tornado", 24), ("Shockwave", 18), ("Redirect", 14), ("Turn", 14),
    ]

    result = []
    for name, frames in clips_spec:
        step = 2
        frame_indices = list(range(0, frames + 1, step))
        if frame_indices[-1] != frames:
            frame_indices.append(frames)
        times = [f / fps for f in frame_indices]
        bone_quats: Dict[str, List[Quat]] = {b[0]: [] for b in bones}
        hips_trans: List[Vec3] = []
        for f in frame_indices:
            t01 = f / frames
            phase = t01 * math.tau
            rots, trs = sample_pose(name, phase, t01)
            for b in bones:
                bn = b[0]
                rx, ry, rz = rots[bn]
                bone_quats[bn].append(euler_xyz_to_quat(rx, ry, rz))
            hips_trans.append(trs.get("hips", bworld["hips"]))
        result.append((name, times, bone_quats, hips_trans))
    return result


# ---------------------------------------------------------------------------
# glTF 2.0 Binary (.glb) Writer
# ---------------------------------------------------------------------------
def write_glb(path: Path, archetype: str) -> Tuple[int, int]:
    bones, bidx, bworld, materials, buckets = build_character_geometry(archetype)
    animations = build_animations(bones, bidx, bworld, archetype)

    bin_data = bytearray()
    buffer_views: List[dict] = []
    accessors: List[dict] = []

    def append_bytes(raw: bytes, target: int | None = None) -> int:
        while len(bin_data) % 4 != 0:
            bin_data.append(0)
        offset = len(bin_data)
        bin_data.extend(raw)
        bv = {"buffer": 0, "byteOffset": offset, "byteLength": len(raw)}
        if target is not None:
            bv["target"] = target
        bv_idx = len(buffer_views)
        buffer_views.append(bv)
        return bv_idx

    def add_accessor(raw: bytes, comp_type: int, acc_type: str, count: int, target=None, minmax=None) -> int:
        bv_idx = append_bytes(raw, target=target)
        acc = {
            "bufferView": bv_idx,
            "componentType": comp_type,
            "count": count,
            "type": acc_type,
        }
        if minmax is not None:
            acc["min"] = minmax[0]
            acc["max"] = minmax[1]
        idx = len(accessors)
        accessors.append(acc)
        return idx

    # Build mesh primitives
    primitives = []
    total_verts = 0
    total_tris = 0
    for bucket in buckets:
        if not bucket.positions:
            continue
        n = len(bucket.positions)
        total_verts += n
        total_tris += len(bucket.indices) // 3
        pmin = [min(p[k] for p in bucket.positions) for k in range(3)]
        pmax = [max(p[k] for p in bucket.positions) for k in range(3)]
        pos_raw = b"".join(struct.pack("<3f", *p) for p in bucket.positions)
        nrm_raw = b"".join(struct.pack("<3f", *nm) for nm in bucket.normals)
        jnt_raw = b"".join(struct.pack("<4B", *j) for j in bucket.joints)
        wgt_raw = b"".join(struct.pack("<4f", *w) for w in bucket.weights)
        idx_raw = b"".join(struct.pack("<H", i) for i in bucket.indices)

        pos_acc = add_accessor(pos_raw, 5126, "VEC3", n, target=34962, minmax=(pmin, pmax))
        nrm_acc = add_accessor(nrm_raw, 5126, "VEC3", n, target=34962)
        jnt_acc = add_accessor(jnt_raw, 5121, "VEC4", n, target=34962)
        wgt_acc = add_accessor(wgt_raw, 5126, "VEC4", n, target=34962)
        idx_acc = add_accessor(idx_raw, 5123, "SCALAR", len(bucket.indices), target=34963)

        primitives.append({
            "attributes": {
                "POSITION": pos_acc,
                "NORMAL": nrm_acc,
                "JOINTS_0": jnt_acc,
                "WEIGHTS_0": wgt_acc,
            },
            "indices": idx_acc,
            "material": bucket.mat_idx,
        })

    # Inverse bind matrices (column-major 4x4 translation(-world_pos))
    ibm_raw = bytearray()
    for _, _, wp in bones:
        mat = [
            1.0, 0.0, 0.0, 0.0,
            0.0, 1.0, 0.0, 0.0,
            0.0, 0.0, 1.0, 0.0,
            -wp[0], -wp[1], -wp[2], 1.0,
        ]
        ibm_raw.extend(struct.pack("<16f", *mat))
    ibm_acc = add_accessor(bytes(ibm_raw), 5126, "MAT4", len(bones))

    # Nodes: 0..N-1 are bones, N is RunnerSuit mesh, N+1 is RunnerRig root
    n_bones = len(bones)
    children_map: Dict[int, List[int]] = {i: [] for i in range(n_bones)}
    for i, (name, parent, wp) in enumerate(bones):
        if parent is not None:
            children_map[bidx[parent]].append(i)

    nodes = []
    for i, (name, parent, wp) in enumerate(bones):
        if parent is None:
            local_t = wp
        else:
            pw = bworld[parent]
            local_t = (wp[0] - pw[0], wp[1] - pw[1], wp[2] - pw[2])
        nd = {
            "name": name,
            "translation": [round(local_t[0], 6), round(local_t[1], 6), round(local_t[2], 6)],
        }
        if children_map[i]:
            nd["children"] = children_map[i]
        nodes.append(nd)

    mesh_node_idx = n_bones
    nodes.append({"name": "RunnerSuit", "mesh": 0, "skin": 0})
    root_node_idx = n_bones + 1
    nodes.append({"name": "RunnerRig", "children": [mesh_node_idx, 0]})

    # Materials
    gltf_mats = []
    for name, rgba, metal, rough, emiss in materials:
        m = {
            "name": name,
            "pbrMetallicRoughness": {
                "baseColorFactor": list(rgba),
                "metallicFactor": metal,
                "roughnessFactor": rough,
            },
            "doubleSided": False,
        }
        if any(e > 0.001 for e in emiss):
            m["emissiveFactor"] = list(emiss)
        gltf_mats.append(m)

    # Animations
    gltf_anims = []
    for clip_name, times, bone_quats, hips_trans in animations:
        t_raw = b"".join(struct.pack("<f", t) for t in times)
        t_acc = add_accessor(t_raw, 5126, "SCALAR", len(times), minmax=([times[0]], [times[-1]]))
        samplers = []
        channels = []
        # Hips translation
        ht_raw = b"".join(struct.pack("<3f", *p) for p in hips_trans)
        ht_acc = add_accessor(ht_raw, 5126, "VEC3", len(hips_trans))
        samplers.append({"input": t_acc, "interpolation": "LINEAR", "output": ht_acc})
        channels.append({"sampler": 0, "target": {"node": 0, "path": "translation"}})
        # All bone rotations
        for i, (bn, _, _) in enumerate(bones):
            qs = bone_quats[bn]
            q_raw = b"".join(struct.pack("<4f", *q) for q in qs)
            q_acc = add_accessor(q_raw, 5126, "VEC4", len(qs))
            s_idx = len(samplers)
            samplers.append({"input": t_acc, "interpolation": "LINEAR", "output": q_acc})
            channels.append({"sampler": s_idx, "target": {"node": i, "path": "rotation"}})
        gltf_anims.append({"name": clip_name, "channels": channels, "samplers": samplers})

    while len(bin_data) % 4 != 0:
        bin_data.append(0)

    gltf = {
        "asset": {"version": "2.0", "generator": "Project Velocity Neon 4 Character Builder"},
        "scene": 0,
        "scenes": [{"name": "Scene", "nodes": [root_node_idx]}],
        "nodes": nodes,
        "meshes": [{"name": "RunnerSuitMesh", "primitives": primitives}],
        "skins": [{"name": "RunnerSkeleton", "inverseBindMatrices": ibm_acc, "joints": list(range(n_bones)), "skeleton": 0}],
        "materials": gltf_mats,
        "animations": gltf_anims,
        "accessors": accessors,
        "bufferViews": buffer_views,
        "buffers": [{"byteLength": len(bin_data)}],
    }

    json_bytes = json.dumps(gltf, separators=(",", ":")).encode("utf-8")
    while len(json_bytes) % 4 != 0:
        json_bytes += b" "

    total_len = 12 + 8 + len(json_bytes) + 8 + len(bin_data)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total_len))
        f.write(struct.pack("<I4s", len(json_bytes), b"JSON"))
        f.write(json_bytes)
        f.write(struct.pack("<I4s", len(bin_data), b"BIN\x00"))
        f.write(bin_data)
    return total_verts, total_tris


def main() -> None:
    specs = [
        ("hero", ASSETS / "velocity-runner.glb"),
        ("nullstride", ASSETS / "nullstride-boss.glb"),
        ("afterlight", ASSETS / "afterlight-boss.glb"),
    ]
    for arch, out in specs:
        v, t = write_glb(out, arch)
        print(f"Built {out.name}: {v} verts, {t} tris, {out.stat().st_size // 1024} KB")


if __name__ == "__main__":
    main()
