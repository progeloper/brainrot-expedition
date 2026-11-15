# Generates Stud Pop white-on-transparent effect images: Rays (24), Sparkle (4-point), Glow (radial).
import math, sys, numpy as np
from PIL import Image, ImageDraw, ImageFilter
out = sys.argv[1]
N = 512; c = N / 2
# Rays: 24 wedges, soft falloff toward the edge
img = Image.new("L", (N*2, N*2), 0); d = ImageDraw.Draw(img); C = N
for i in range(24):
    a = 2*math.pi*i/24; w = math.pi/24*0.55
    pts = [(C, C)] + [(C + 2*N*math.cos(a+t), C + 2*N*math.sin(a+t)) for t in (-w, w)]
    d.polygon(pts, fill=255)
img = img.resize((N, N), Image.LANCZOS)
y, x = np.mgrid[0:N, 0:N]; r = np.hypot(x-c, y-c)/c
fall = np.clip(1 - r, 0, 1)**0.8 * np.clip(r/0.12, 0, 1)
a = (np.asarray(img, float) * fall).astype(np.uint8)
Image.fromarray(np.dstack([np.full((N,N),255,np.uint8)]*3 + [a]), "RGBA").save(f"{out}/rays.png")
# Sparkle: 4-point star with concave sides + soft core
s = Image.new("L", (N*2, N*2), 0); d = ImageDraw.Draw(s); C = N; pts = []
for i in range(64):
    t = 2*math.pi*i/64
    k = abs(math.cos(2*t))**6
    rr = (0.12 + 0.86*k) * N * 0.98
    pts.append((C + rr*math.cos(t - math.pi/2), C + rr*math.sin(t - math.pi/2)))
d.polygon(pts, fill=255); s = s.resize((N, N), Image.LANCZOS)
glow = s.filter(ImageFilter.GaussianBlur(10))
sa = np.maximum(np.asarray(s, float), np.asarray(glow, float)*0.8).astype(np.uint8)
Image.fromarray(np.dstack([np.full((N,N),255,np.uint8)]*3 + [sa]), "RGBA").save(f"{out}/sparkle.png")
# Glow: soft radial
g = (np.clip(1 - r, 0, 1)**2.2 * 255).astype(np.uint8)
Image.fromarray(np.dstack([np.full((N,N),255,np.uint8)]*3 + [g]), "RGBA").save(f"{out}/glow.png")
print("ok")
