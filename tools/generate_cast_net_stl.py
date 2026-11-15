#!/usr/bin/env python3
"""Generate a low-poly spherical net STL with an attached string.

The mesh is intentionally simple for Roblox workflows:
- a faceted spherical cage built from tubular longitude/latitude strands
- a small connector ring at the top
- a curved hand line/string extending from that ring

Units are written as generic scene units and can be treated as Roblox studs.
"""

from __future__ import annotations

import argparse
import math
from dataclasses import dataclass
from pathlib import Path
from typing import List, Sequence, Tuple

Vec3 = Tuple[float, float, float]
Triangle = Tuple[Vec3, Vec3, Vec3]


@dataclass(frozen=True)
class MeshStats:
    triangles: int
    vertices: int
    bounds_min: Vec3
    bounds_max: Vec3


def v_add(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def v_sub(a: Vec3, b: Vec3) -> Vec3:
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def v_scale(v: Vec3, scalar: float) -> Vec3:
    return (v[0] * scalar, v[1] * scalar, v[2] * scalar)


def v_dot(a: Vec3, b: Vec3) -> float:
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def v_cross(a: Vec3, b: Vec3) -> Vec3:
    return (
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    )


def v_length(v: Vec3) -> float:
    return math.sqrt(v_dot(v, v))


def v_normalize(v: Vec3) -> Vec3:
    length = v_length(v)
    if length == 0.0:
        return (0.0, 0.0, 0.0)
    return (v[0] / length, v[1] / length, v[2] / length)


def orthonormal_basis(direction: Vec3) -> Tuple[Vec3, Vec3]:
    axis = v_normalize(direction)
    helper = (0.0, 1.0, 0.0) if abs(axis[1]) < 0.9 else (1.0, 0.0, 0.0)
    tangent = v_normalize(v_cross(axis, helper))
    bitangent = v_normalize(v_cross(axis, tangent))
    return tangent, bitangent


def spherical_point(radius: float, theta: float, phi: float, center: Vec3) -> Vec3:
    sin_phi = math.sin(phi)
    return (
        center[0] + radius * sin_phi * math.cos(theta),
        center[1] + radius * math.cos(phi),
        center[2] + radius * sin_phi * math.sin(theta),
    )


def append_quad(triangles: List[Triangle], a: Vec3, b: Vec3, c: Vec3, d: Vec3) -> None:
    triangles.append((a, b, c))
    triangles.append((a, c, d))


def capped_tube(start: Vec3, end: Vec3, radius: float, sides: int = 6) -> List[Triangle]:
    direction = v_sub(end, start)
    length = v_length(direction)
    if length == 0.0:
        return []

    tangent, bitangent = orthonormal_basis(direction)
    start_ring: List[Vec3] = []
    end_ring: List[Vec3] = []

    for index in range(sides):
        angle = (2.0 * math.pi * index) / sides
        offset = v_add(v_scale(tangent, math.cos(angle) * radius), v_scale(bitangent, math.sin(angle) * radius))
        start_ring.append(v_add(start, offset))
        end_ring.append(v_add(end, offset))

    triangles: List[Triangle] = []

    for index in range(sides):
        next_index = (index + 1) % sides
        append_quad(
            triangles,
            start_ring[index],
            start_ring[next_index],
            end_ring[next_index],
            end_ring[index],
        )

    for index in range(sides):
        next_index = (index + 1) % sides
        triangles.append((start, start_ring[next_index], start_ring[index]))
        triangles.append((end, end_ring[index], end_ring[next_index]))

    return triangles


def ring_loop(center: Vec3, radius: float, tube_radius: float, segments: int) -> List[Triangle]:
    points: List[Vec3] = []
    for index in range(segments):
        angle = (2.0 * math.pi * index) / segments
        points.append(
            (
                center[0] + math.cos(angle) * radius,
                center[1],
                center[2] + math.sin(angle) * radius,
            )
        )

    triangles: List[Triangle] = []
    for index in range(segments):
        triangles.extend(capped_tube(points[index], points[(index + 1) % segments], tube_radius, sides=6))
    return triangles


def build_spherical_net(
    radius: float = 2.6,
    center: Vec3 = (0.0, 3.4, 0.0),
    longitudes: int = 10,
    latitudes: int = 6,
    strand_radius: float = 0.06,
) -> List[Triangle]:
    triangles: List[Triangle] = []

    phi_values = [math.pi * i / (latitudes + 1) for i in range(1, latitudes + 1)]
    theta_values = [(2.0 * math.pi * i) / longitudes for i in range(longitudes)]
    top = (center[0], center[1] + radius, center[2])
    bottom = (center[0], center[1] - radius, center[2])

    for theta in theta_values:
        previous = top
        for phi in phi_values:
            current = spherical_point(radius, theta, phi, center)
            triangles.extend(capped_tube(previous, current, strand_radius, sides=6))
            previous = current
        triangles.extend(capped_tube(previous, bottom, strand_radius, sides=6))

    for phi in phi_values:
        ring_points = [spherical_point(radius, theta, phi, center) for theta in theta_values]
        for index in range(longitudes):
            triangles.extend(
                capped_tube(
                    ring_points[index],
                    ring_points[(index + 1) % longitudes],
                    strand_radius,
                    sides=6,
                )
            )

    triangles.extend(ring_loop(center, radius * 1.02, strand_radius * 1.35, longitudes))
    return triangles


def build_attachment(
    sphere_center: Vec3,
    sphere_radius: float,
    line_length: float = 5.2,
    line_radius: float = 0.08,
) -> List[Triangle]:
    triangles: List[Triangle] = []

    top_anchor = (sphere_center[0], sphere_center[1] + sphere_radius, sphere_center[2])
    ring_center = (top_anchor[0], top_anchor[1] + 0.28, top_anchor[2])
    line_start = (ring_center[0], ring_center[1] + 0.14, ring_center[2])

    triangles.extend(capped_tube(top_anchor, ring_center, 0.08, sides=6))
    triangles.extend(ring_loop(ring_center, 0.22, 0.045, segments=8))

    string_points = [
        line_start,
        (0.45, line_start[1] + 0.3, 0.15),
        (1.35, line_start[1] + 0.7, -0.1),
        (2.7, line_start[1] + 0.45, -0.55),
        (3.8, line_start[1] + 0.05, -0.45),
        (4.9, line_start[1] - 0.15, 0.0),
    ]

    if line_length != 5.2:
        scale = line_length / 5.2
        string_points = [
            (point[0] * scale, line_start[1] + (point[1] - line_start[1]) * scale, point[2] * scale)
            for point in string_points
        ]

    for index in range(len(string_points) - 1):
        triangles.extend(capped_tube(string_points[index], string_points[index + 1], line_radius, sides=6))

    triangles.extend(ring_loop(string_points[-1], 0.18, 0.04, segments=8))
    return triangles


def compute_stats(triangles: Sequence[Triangle]) -> MeshStats:
    xs: List[float] = []
    ys: List[float] = []
    zs: List[float] = []
    for tri in triangles:
        for vertex in tri:
            xs.append(vertex[0])
            ys.append(vertex[1])
            zs.append(vertex[2])

    return MeshStats(
        triangles=len(triangles),
        vertices=len(triangles) * 3,
        bounds_min=(min(xs), min(ys), min(zs)),
        bounds_max=(max(xs), max(ys), max(zs)),
    )


def facet_normal(triangle: Triangle) -> Vec3:
    edge_a = v_sub(triangle[1], triangle[0])
    edge_b = v_sub(triangle[2], triangle[0])
    return v_normalize(v_cross(edge_a, edge_b))


def write_ascii_stl(triangles: Sequence[Triangle], output_path: Path, solid_name: str) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="ascii") as handle:
        handle.write(f"solid {solid_name}\n")
        for triangle in triangles:
            normal = facet_normal(triangle)
            handle.write(f"  facet normal {normal[0]:.6f} {normal[1]:.6f} {normal[2]:.6f}\n")
            handle.write("    outer loop\n")
            for vertex in triangle:
                handle.write(f"      vertex {vertex[0]:.6f} {vertex[1]:.6f} {vertex[2]:.6f}\n")
            handle.write("    endloop\n")
            handle.write("  endfacet\n")
        handle.write(f"endsolid {solid_name}\n")


def build_model(args: argparse.Namespace) -> List[Triangle]:
    center = (0.0, args.sphere_radius + 0.8, 0.0)
    triangles: List[Triangle] = []
    triangles.extend(
        build_spherical_net(
            radius=args.sphere_radius,
            center=center,
            longitudes=args.longitudes,
            latitudes=args.latitudes,
            strand_radius=args.strand_radius,
        )
    )
    triangles.extend(
        build_attachment(
            sphere_center=center,
            sphere_radius=args.sphere_radius,
            line_length=args.line_length,
            line_radius=args.line_radius,
        )
    )
    return triangles


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("assets/models/sphere_net_low_poly.stl"),
        help="Where to write the STL file.",
    )
    parser.add_argument("--sphere-radius", type=float, default=2.6, help="Radius of the spherical net.")
    parser.add_argument("--longitudes", type=int, default=10, help="Number of vertical strands around the sphere.")
    parser.add_argument("--latitudes", type=int, default=6, help="Number of horizontal ring bands.")
    parser.add_argument("--strand-radius", type=float, default=0.06, help="Thickness of net strands.")
    parser.add_argument("--line-length", type=float, default=5.2, help="Overall string length.")
    parser.add_argument("--line-radius", type=float, default=0.08, help="Thickness of the attached string.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    triangles = build_model(args)
    stats = compute_stats(triangles)
    write_ascii_stl(triangles, args.output, "sphere_net_low_poly")

    print(f"Wrote {args.output}")
    print(f"Triangles: {stats.triangles}")
    print(f"Serialized vertices: {stats.vertices}")
    print(
        "Bounds min/max: "
        f"{stats.bounds_min[0]:.3f}, {stats.bounds_min[1]:.3f}, {stats.bounds_min[2]:.3f} / "
        f"{stats.bounds_max[0]:.3f}, {stats.bounds_max[1]:.3f}, {stats.bounds_max[2]:.3f}"
    )


if __name__ == "__main__":
    main()
