#!/usr/bin/env python3
"""Draw 30 s movement paths (flags off vs on) as one SVG. No dependencies.

Usage: plot_paths.py off.json on.json out.svg
Each JSON is the MotionSample written by the Checkpoint A sampler:
{"tracks": [{"k": id, "kind": "B"|"V", "x": species/type, "path": [[x, z], ...]}, ...]}
"""
import json
import sys

COLOURS = ["#e6194b", "#3cb44b", "#4363d8", "#f58231", "#911eb4", "#008080", "#9a6324", "#000075"]


def panel(tracks, kind, title, ox, oy, size):
    rows = [t for t in tracks if t["kind"] == kind and t.get("path")]
    out = [f'<text x="{ox}" y="{oy - 8}" font-size="15" font-family="sans-serif" font-weight="bold">{title}</text>',
           f'<rect x="{ox}" y="{oy}" width="{size}" height="{size}" fill="#f7f7f2" stroke="#999"/>']
    points = [p for t in rows for p in t["path"]]
    if not points:
        return out
    xs, zs = [p[0] for p in points], [p[1] for p in points]
    span = max(max(xs) - min(xs), max(zs) - min(zs), 10)
    cx, cz = (max(xs) + min(xs)) / 2, (max(zs) + min(zs)) / 2
    scale = (size - 30) / span

    def at(p):
        return ox + size / 2 + (p[0] - cx) * scale, oy + size / 2 + (p[1] - cz) * scale

    for i, t in enumerate(rows):
        colour = COLOURS[i % len(COLOURS)]
        pts = " ".join(f"{x:.1f},{y:.1f}" for x, y in map(at, t["path"]))
        out.append(f'<polyline points="{pts}" fill="none" stroke="{colour}" stroke-width="2" stroke-linejoin="round"/>')
        x0, y0 = at(t["path"][0])
        x1, y1 = at(t["path"][-1])
        out.append(f'<circle cx="{x0:.1f}" cy="{y0:.1f}" r="4" fill="white" stroke="{colour}" stroke-width="2"/>')
        out.append(f'<circle cx="{x1:.1f}" cy="{y1:.1f}" r="4" fill="{colour}"/>')
        label = f'{t.get("x") or ""} {t["dist"]:.0f} studs, {t["still"]:.0f}% still'
        out.append(f'<text x="{ox + 6}" y="{oy + size - 8 - 15 * i}" font-size="11" font-family="sans-serif" fill="{colour}">{label}</text>')
    bar = 20 * scale
    out.append(f'<line x1="{ox + size - 12 - bar}" y1="{oy + 14}" x2="{ox + size - 12}" y2="{oy + 14}" stroke="#333" stroke-width="2"/>')
    out.append(f'<text x="{ox + size - 12 - bar}" y="{oy + 28}" font-size="10" font-family="sans-serif">20 studs</text>')
    return out


def main():
    off = json.load(open(sys.argv[1]))["tracks"]
    on = json.load(open(sys.argv[2]))["tracks"]
    size, gap = 420, 30
    body = []
    body += panel(off, "B", "Brainrots, today (flags off)", gap, 40, size)
    body += panel(on, "B", "Brainrots, natural movement (flags on)", gap * 2 + size, 40, size)
    body += panel(off, "V", "Villagers, today (flags off)", gap, 90 + size, size)
    body += panel(on, "V", "Villagers, natural movement (flags on)", gap * 2 + size, 90 + size, size)
    width, height = gap * 3 + size * 2, 110 + size * 2
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">'
           f'<rect width="100%" height="100%" fill="white"/>' + "".join(body) + "</svg>")
    open(sys.argv[3], "w").write(svg)


if __name__ == "__main__":
    main()
