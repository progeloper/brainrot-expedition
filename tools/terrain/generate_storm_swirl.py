#!/usr/bin/env python3
"""Generate the shared tiling Storm curtain texture (StormSwirl.png, 256x256 RGBA, no dependencies).

White swirl streaks on transparent; the Beam's Color tints it violet. Every term uses whole-number
periods across the tile, so it wraps seamlessly in both directions (TextureMode = Wrap).
Run: python3 -I tools/terrain/generate_storm_swirl.py
"""
import math, os, struct, zlib

W = H = 256
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "terrain_v5", "StormSwirl.png")


def pixel(x, y):
    u, v = x / W, y / H
    warp = 0.18 * math.sin(2 * math.pi * (2 * v + u)) + 0.08 * math.sin(2 * math.pi * (3 * u - v))
    a = 0.5 + 0.5 * math.sin(2 * math.pi * (4 * u + 2 * v) + 6 * warp)
    b = 0.5 + 0.5 * math.sin(2 * math.pi * (-3 * u + 5 * v) + 5 * warp)
    streak = a ** 6 + 0.6 * b ** 8
    alpha = min(1.0, 0.18 + 0.82 * streak)
    shade = 0.82 + 0.18 * a
    return (int(255 * shade), int(255 * shade), 255, int(255 * alpha))


def main():
    rows = bytearray()
    for y in range(H):
        rows.append(0)
        for x in range(W):
            rows.extend(pixel(x, y))
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(rows), 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    open(OUT, "wb").write(png)
    print(OUT, len(png))


if __name__ == "__main__":
    main()
