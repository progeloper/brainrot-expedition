# Two-shot matte for Studio portrait captures (auto-exposure makes a black/white difference matte drift):
#   color = model on pure-black Neon backdrop; mask = same camera, model as flat white Neon on black.
#   alpha = mask luminance (normalised), colour = color / alpha (black premultiplied), clamped.
# Then crop square around the alpha bounds so the model fills 85% of the side, resize to 512x512.
import sys, numpy as np
from PIL import Image
color_p, mask_p, out_p = sys.argv[1:4]
c = np.asarray(Image.open(color_p).convert("RGB"), float)
m = np.asarray(Image.open(mask_p).convert("L"), float)
lo, hi = 12.0, max(200.0, np.percentile(m[m > 128], 50) if (m > 128).any() else 255)
a = np.clip((m - lo) / (hi - lo), 0, 1)
a[a < 0.02] = 0
rgb = np.clip(c / np.maximum(a, 1e-3)[..., None], 0, 255)
rgb[a == 0] = 0
# Studio auto-exposure drifts per frame: normalise so the bright end (eye whites, highlights)
# lands near the same level for every species, within a gentle gain range.
lum = rgb @ np.array([0.299, 0.587, 0.114])
solid = a > 0.9
if solid.any():
    p92 = np.percentile(lum[solid], 92)
    gain = float(np.clip(228.0 / max(p92, 1.0), 0.85, 1.5))
    rgb = np.clip(rgb * gain, 0, 255)
ys, xs = np.nonzero(a > 0.05)
y0, y1, x0, x1 = ys.min(), ys.max(), xs.min(), xs.max()
side = int(max(y1 - y0, x1 - x0) / 0.85)
cy, cx = (y0 + y1) / 2, (x0 + x1) / 2
H, W = a.shape
canvas = np.zeros((side, side, 4), float)
ty, tx = int(cy - side / 2), int(cx - side / 2)
sy0, sx0 = max(ty, 0), max(tx, 0); sy1, sx1 = min(ty + side, H), min(tx + side, W)
canvas[sy0 - ty:sy1 - ty, sx0 - tx:sx1 - tx, :3] = rgb[sy0:sy1, sx0:sx1]
canvas[sy0 - ty:sy1 - ty, sx0 - tx:sx1 - tx, 3] = a[sy0:sy1, sx0:sx1] * 255
img = Image.fromarray(canvas.astype(np.uint8), "RGBA")
# premultiply-safe resize
img = img.resize((512, 512), Image.LANCZOS)
img.save(out_p)
print(out_p, "ok", side)
