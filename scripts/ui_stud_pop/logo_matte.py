# Difference matte for UI captures (no auto-exposure on UI): alpha = 1 - (white - black)/255, colour = black/alpha.
import sys, numpy as np
from PIL import Image
b = np.asarray(Image.open(sys.argv[1]).convert("RGB"), float)
w = np.asarray(Image.open(sys.argv[2]).convert("RGB"), float)
a = np.clip(1 - (w - b).mean(axis=2) / 255.0, 0, 1)
a[a < 0.03] = 0
rgb = np.clip(b / np.maximum(a, 1e-3)[..., None], 0, 255); rgb[a == 0] = 0
ys, xs = np.nonzero(a > 0.05); pad = 24
y0, y1, x0, x1 = max(ys.min()-pad,0), min(ys.max()+pad, a.shape[0]), max(xs.min()-pad,0), min(xs.max()+pad, a.shape[1])
img = Image.fromarray(np.dstack([rgb, a[..., None] * 255]).astype(np.uint8)[y0:y1, x0:x1])
W = 1024; H = int(img.height * W / img.width)
logo = img.resize((W, H), Image.LANCZOS)
canvas = Image.new("RGBA", (1024, 1024), (0, 0, 0, 0)); canvas.alpha_composite(logo, (0, (1024 - H) // 2))
canvas.save(sys.argv[3])
# square icon on a teal -> violet gradient
N = 512; t = np.linspace(0, 1, N)[:, None, None]
top, bot = np.array([0x14, 0xC7, 0x9F], float), np.array([0x5A, 0x1F, 0xC2], float)
grad = (top * (1 - t) + bot * t).repeat(N, axis=1)
icon = Image.fromarray(np.dstack([grad, np.full((N, N, 1), 255.0)]).astype(np.uint8))
small = logo.resize((480, int(H * 480 / 1024)), Image.LANCZOS)
icon.alpha_composite(small, ((N - small.width) // 2, (N - small.height) // 2))
icon.save(sys.argv[4]); print("ok", logo.size)
