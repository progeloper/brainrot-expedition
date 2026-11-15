#!/usr/bin/env python3
"""Cut a transparent display shot out of a Studio photo-booth capture.

Single backdrop (green / magenta / blue Neon, auto-detected from the border):
    key_display_shot.py RAW.jpg OUT.png
Two backdrops of the same staged model (green + magenta difference matting),
for models whose own colours collide with every key:
    key_display_shot.py RAW_GREEN.jpg OUT.png --second RAW_MAGENTA.jpg

Key strength is normalised by the backdrop's median (sampled on the image
border) because Studio auto-exposes each frame. Alpha ramps from opaque at 22%
key to transparent at 80% key; despill only where alpha < 1. The result is
cropped to alpha > 0.05 plus 12 px, scaled so the longest side is <= 560 px,
and saved as RGBA. Existing files are never overwritten unless --overwrite.
"""
import argparse
import os
import sys

import numpy as np
from PIL import Image

LO, HI = 0.22, 0.80
PAD = 12
MAX_SIDE = 560


def load(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.float32)


def border(img, w=6):
    return np.concatenate([
        img[:w].reshape(-1, 3), img[-w:].reshape(-1, 3),
        img[:, :w].reshape(-1, 3), img[:, -w:].reshape(-1, 3)])


def key_values(img, kind):
    r, g, b = img[..., 0], img[..., 1], img[..., 2]
    if kind == "green":
        return g - np.maximum(r, b)
    if kind == "magenta":
        return np.minimum(r, b) - g
    return b - np.maximum(r, g)


def detect(img):
    med = np.median(border(img), axis=0)
    r, g, b = med
    scores = {"green": g - max(r, b), "magenta": min(r, b) - g, "blue": b - max(r, g)}
    kind = max(scores, key=scores.get)
    return kind, med


def ramp(k):
    return np.clip((HI - k) / (HI - LO), 0.0, 1.0)


def despill(img, alpha, kind):
    out = img.copy()
    r, g, b = out[..., 0], out[..., 1], out[..., 2]
    m = alpha < 1.0
    if kind == "green":
        g[m] = np.minimum(g, np.maximum(r, b))[m]
    elif kind == "magenta":
        spill = np.clip(np.minimum(r, b) - g, 0, None)
        r[m] -= spill[m]
        b[m] -= spill[m]
    else:
        b[m] = np.minimum(b, np.maximum(r, g))[m]
    return out


def single(path):
    img = load(path)
    kind, _ = detect(img)
    kv = key_values(img, kind)
    ref = np.median(key_values(border(img)[None], kind))
    if ref < 40:
        sys.exit(f"{path}: backdrop key too weak ({ref:.1f})")
    alpha = ramp(kv / ref)
    return despill(img, alpha, kind), alpha, kind


def dual(path_a, path_b):
    a, b = load(path_a), load(path_b)
    if a.shape != b.shape:
        sys.exit("capture sizes differ")
    ba = np.median(border(a), axis=0)
    bb = np.median(border(b), axis=0)
    d = ba - bb
    # (1 - alpha) = projection of the per-pixel difference on the backdrop difference
    k = ((a - b) @ d) / float(d @ d)
    k = np.clip(k, 0.0, 1.0)
    alpha = ramp(k)
    # recover foreground from both plates and average
    fa = a - k[..., None] * ba
    fb = b - k[..., None] * bb
    fg = 0.5 * (fa + fb) / np.maximum(1.0 - k, 1e-3)[..., None]
    fg = np.where((alpha >= 1.0)[..., None], 0.5 * (a + b), fg)
    kind_a, _ = detect(a)
    kind_b, _ = detect(b)
    fg = despill(despill(fg, alpha, kind_a), alpha, kind_b)
    return fg, alpha, f"{kind_a}+{kind_b}"


def finish(rgb, alpha, out, overwrite):
    if os.path.exists(out) and not overwrite:
        sys.exit(f"refusing to overwrite {out}")
    ys, xs = np.where(alpha > 0.05)
    if len(xs) == 0:
        sys.exit("empty matte")
    h, w = alpha.shape
    y0, y1 = max(0, ys.min() - PAD), min(h, ys.max() + 1 + PAD)
    x0, x1 = max(0, xs.min() - PAD), min(w, xs.max() + 1 + PAD)
    touches = ys.min() == 0 or xs.min() == 0 or ys.max() == h - 1 or xs.max() == w - 1
    rgba = np.dstack([np.clip(rgb, 0, 255), alpha * 255.0])[y0:y1, x0:x1]
    # premultiply for resampling, then unpremultiply
    pre = rgba.copy()
    pre[..., :3] *= rgba[..., 3:4] / 255.0
    ph, pw = pre.shape[:2]
    scale = min(1.0, MAX_SIDE / max(pw, ph))
    if scale < 1.0:
        size = (max(1, round(pw * scale)), max(1, round(ph * scale)))
        chans = [Image.fromarray(np.ascontiguousarray(pre[..., i], dtype=np.float32)).resize(size, Image.LANCZOS)
                 for i in range(4)]
        pre = np.dstack([np.asarray(c) for c in chans])
    pre = np.clip(pre, 0, 255)
    a = pre[..., 3:4]
    rgb_out = np.where(a > 0.5, pre[..., :3] * 255.0 / np.maximum(a, 1e-3), 0)
    final = np.dstack([np.clip(rgb_out, 0, 255), a]).round().astype(np.uint8)
    Image.fromarray(final).save(out)
    return final.shape[1], final.shape[0], touches


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("raw")
    ap.add_argument("out")
    ap.add_argument("--second", help="same framing captured on a second backdrop (dual matting)")
    ap.add_argument("--overwrite", action="store_true")
    args = ap.parse_args()
    if args.second:
        rgb, alpha, kind = dual(args.raw, args.second)
    else:
        rgb, alpha, kind = single(args.raw)
    w, h, touches = finish(rgb, alpha, args.out, args.overwrite)
    print(f"{os.path.basename(args.out)} {w}x{h} key={kind}{' TOUCHES-EDGE' if touches else ''}")


if __name__ == "__main__":
    main()
