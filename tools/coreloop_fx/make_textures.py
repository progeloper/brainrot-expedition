"""Core Loop V2 (Part L2) texture generator.

Makes the CL_* particle/beam/decal textures as white-on-transparent PNGs (the engine tints them), plus the
coloured UI icons. Same approach as the Voxel V4 overlays. No Toolbox or Marketplace content.
Output: assets/coreloop_fx/textures/*.png and UPLOAD_CHECKLIST.md (until the ids come back, CoreLoopFx
keeps the L2 fallbacks live).

Usage: python3 -I tools/coreloop_fx/make_textures.py
"""
import math
import pathlib
import random

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "coreloop_fx" / "textures"
INK = (0x1D, 0x21, 0x33, 255)
WHITE = (255, 255, 255, 255)


def canvas(w, h=None):
    return Image.new("RGBA", (w, h or w), (0, 0, 0, 0))


def soft(img, radius):
    return img.filter(ImageFilter.GaussianBlur(radius))


def stud_chunk():
    s = 128
    shadow = canvas(s)
    ImageDraw.Draw(shadow).rounded_rectangle((18, 24, 114, 120), 18, fill=(255, 255, 255, 90))
    img = soft(shadow, 4)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((14, 14, 110, 110), 18, fill=WHITE)
    d.ellipse((40, 32, 84, 66), fill=(255, 255, 255, 255), outline=(200, 200, 200, 255), width=4)
    d.ellipse((44, 30, 80, 58), fill=WHITE)
    return img


def dust():
    s = 256
    img = canvas(s)
    d = ImageDraw.Draw(img)
    for cx, cy, r in ((96, 150, 62), (160, 140, 70), (128, 96, 60)):
        d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=WHITE)
    return soft(img, 6)


def crack():
    s = 512
    img = canvas(s)
    d = ImageDraw.Draw(img)
    rng = random.Random(6)
    c = s / 2
    colour = (INK[0], INK[1], INK[2], int(255 * 0.7))
    for arm in range(6):
        angle = arm * math.pi / 3 + rng.uniform(-0.25, 0.25)
        x, y, width = c, c, 26
        for step in range(5):
            angle += rng.uniform(-0.35, 0.35)
            nx, ny = x + math.cos(angle) * 44, y + math.sin(angle) * 44
            d.line((x, y, nx, ny), fill=colour, width=int(width))
            d.ellipse((nx - width / 2, ny - width / 2, nx + width / 2, ny + width / 2), fill=colour)
            x, y, width = nx, ny, max(6, width * 0.72)
    d.ellipse((c - 34, c - 34, c + 34, c + 34), fill=colour)
    return img


def ring():
    s = 512
    img = canvas(s)
    d = ImageDraw.Draw(img)
    width = int(s * 0.12)
    d.ellipse((20, 20, s - 20, s - 20), outline=WHITE, width=width)
    glow = soft(img.copy(), 10)
    return Image.alpha_composite(glow, img)


def beam_stud():
    w, h = 64, 512
    img = canvas(w, h)
    px = img.load()
    for y in range(h):
        alpha = int(255 * (y / (h - 1)))  # opaque bottom -> clear top (bottom is y = h)
        for x in range(w):
            edge = 1 - abs(x - w / 2) / (w / 2)
            px[x, y] = (255, 255, 255, int(alpha * (0.55 + 0.45 * edge)))
    d = ImageDraw.Draw(img)
    for y in range(16, h, 32):
        a = int(255 * (y / h))
        d.ellipse((w / 2 - 7, y - 7, w / 2 + 7, y + 7), fill=(255, 255, 255, a))
    return img


def sparkle(d, cx, cy, r, alpha=255):
    pts = []
    for i in range(8):
        ang = i * math.pi / 4
        rr = r if i % 2 == 0 else r * 0.28
        pts.append((cx + math.cos(ang) * rr, cy + math.sin(ang) * rr))
    d.polygon(pts, fill=(255, 255, 255, alpha))


def beam_sparkle():
    w, h = 128, 512
    img = canvas(w, h)
    d = ImageDraw.Draw(img)
    rng = random.Random(4)
    for _ in range(14):
        x, y, r = rng.uniform(20, w - 20), rng.uniform(20, h - 20), rng.uniform(8, 18)
        for oy in (0, -h, h):  # tile vertically
            sparkle(d, x, y + oy, r)
    return img


def spiral():
    s = 512
    img = canvas(s)
    d = ImageDraw.Draw(img)
    c = s / 2
    for arm in range(3):
        base = arm * 2 * math.pi / 3
        for i in range(140):
            t = i / 140
            ang = base + t * 3.2
            r = 20 + t * 220
            w = 34 * (1 - t) + 4
            x, y = c + math.cos(ang) * r, c + math.sin(ang) * r
            d.ellipse((x - w / 2, y - w / 2, x + w / 2, y + w / 2), fill=(255, 255, 255, int(255 * (1 - t * 0.6))))
    return soft(img, 2)


def bolt():
    w, h = 128, 512
    img = canvas(w, h)
    d = ImageDraw.Draw(img)
    rng = random.Random(9)
    x, pts = w / 2, [(w / 2, 0)]
    for y in range(48, h, 48):
        x = max(24, min(w - 24, x + rng.uniform(-34, 34)))
        pts.append((x, y))
    pts.append((w / 2, h))
    d.line(pts, fill=WHITE, width=18, joint="curve")
    return Image.alpha_composite(soft(img.copy(), 8), img)


def confetti():
    img = canvas(64)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle((8, 8, 56, 56), 8, fill=WHITE)
    d.ellipse((22, 18, 42, 34), fill=(225, 225, 225, 255))
    return img


def star4():
    img = canvas(128)
    sparkle(ImageDraw.Draw(img), 64, 64, 60)
    return Image.alpha_composite(soft(img.copy(), 5), img)


def zzz():
    img = canvas(256)
    d = ImageDraw.Draw(img)
    z = [(54, 50), (202, 50), (202, 84), (110, 172), (202, 172), (202, 206), (54, 206), (54, 172), (146, 84), (54, 84)]
    d.polygon(z, fill=INK)
    inner = [(70, 64), (188, 64), (188, 80), (90, 186), (188, 186), (188, 192), (68, 192), (68, 178), (166, 70), (70, 70)]
    d.polygon(inner, fill=WHITE)
    return img


def sweat():
    img = canvas(128)
    d = ImageDraw.Draw(img)
    d.polygon([(64, 10), (100, 74), (28, 74)], fill=WHITE)
    d.ellipse((28, 46, 100, 118), fill=WHITE)
    d.ellipse((46, 66, 62, 86), fill=(200, 230, 255, 255))
    return img


def dizzy_star():
    img = canvas(128)
    d = ImageDraw.Draw(img)
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        r = 58 if i % 2 == 0 else 24
        pts.append((64 + math.cos(ang) * r, 64 + math.sin(ang) * r))
    d.polygon(pts, fill=WHITE, outline=INK)
    return img


def icon(draw_fn):
    img = canvas(128)
    draw_fn(ImageDraw.Draw(img))
    return img


def clover(d):
    for cx, cy in ((44, 44), (84, 44), (44, 84), (84, 84)):
        d.ellipse((cx - 30, cy - 30, cx + 30, cy + 30), fill=(0x3B, 0xD1, 0x6F, 255), outline=INK, width=6)
    d.ellipse((52, 52, 76, 76), fill=(0x8D, 0xFF, 0x3A, 255))


def star_badge(d):
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        r = 58 if i % 2 == 0 else 26
        pts.append((64 + math.cos(ang) * r, 66 + math.sin(ang) * r))
    d.polygon(pts, fill=(0xFF, 0xE1, 0x4A, 255), outline=INK, width=6)


def shield_eye(d):
    d.polygon([(64, 8), (116, 26), (108, 84), (64, 120), (20, 84), (12, 26)], fill=(0xFF, 0x8A, 0x2A, 255), outline=INK, width=6)
    d.ellipse((34, 46, 94, 82), fill=WHITE, outline=INK, width=5)
    d.ellipse((54, 52, 74, 76), fill=INK)


def lightning(d):
    d.polygon([(72, 6), (20, 74), (58, 74), (48, 122), (106, 50), (68, 50)], fill=WHITE, outline=INK, width=6)


def crown(d):
    d.polygon([(10, 104), (18, 32), (44, 66), (64, 18), (84, 66), (110, 32), (118, 104)], fill=(0xFF, 0xD4, 0x47, 255), outline=INK, width=6)


def shimmer_q(d):
    sparkle(d, 40, 40, 32)
    d.text((62, 30), "?", fill=WHITE)
    d.ellipse((60, 40, 120, 120), outline=INK, width=6, fill=(0xCF, 0xF7, 0xFF, 255))


def clock(d):
    d.ellipse((10, 10, 118, 118), fill=(0xFF, 0x8A, 0x2A, 255), outline=INK, width=6)
    d.line((64, 64, 64, 28), fill=INK, width=8)
    d.line((64, 64, 90, 76), fill=INK, width=8)


TEXTURES = {
    "CL_StudChunk": (stud_chunk, "default square particle"),
    "CL_Dust": (dust, "default smoke particle"),
    "CL_Crack": (crack, "none (skip decal)"),
    "CL_Ring": (ring, "Neon cylinder part ring"),
    "CL_BeamStud": (beam_stud, "plain Beam"),
    "CL_BeamSparkle": (beam_sparkle, "none"),
    "CL_Spiral": (spiral, "CL_Ring"),
    "CL_Bolt": (bolt, "Neon parts zig-zag"),
    "CL_Confetti": (confetti, "default square"),
    "CL_Star4": (star4, "Sparkle4 (V4 overlay)"),
    "CL_Zzz": (zzz, 'TextLabel "Z"'),
    "CL_Sweat": (sweat, "none"),
    "CL_DizzyStar": (dizzy_star, "CL_Star4"),
    "CL_IconClover": (lambda: icon(clover), "text-only label"),
    "CL_IconStar": (lambda: icon(star_badge), "text-only label"),
    "CL_IconGuarded": (lambda: icon(shield_eye), "text-only label"),
    "CL_IconRush": (lambda: icon(lightning), "Theme.Icons.Bolt (in use)"),
    "CL_IconCrown": (lambda: icon(crown), "text-only label"),
    "CL_IconShimmer": (lambda: icon(shimmer_q), "text-only label"),
    "CL_IconClock": (lambda: icon(clock), "text-only label"),
}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for name, (fn, fallback) in TEXTURES.items():
        img = fn()
        path = OUT / f"{name}.png"
        img.save(path)
        rows.append(f"| `{name}` | `{path.relative_to(ROOT)}` | {img.size[0]}x{img.size[1]} | {fallback} | _pending_ |")
    checklist = OUT.parent / "UPLOAD_CHECKLIST.md"
    checklist.write_text(
        "# Core Loop V2 texture upload checklist (Part L2)\n\n"
        "Upload each PNG as a Decal/Image (Studio Asset Manager or Open Cloud, batches of <= 5), then paste the\n"
        "rbxassetid into `src/shared/Config/CoreLoopFx.lua` (`L2_Assets`). Until an id is set the fallback stays live.\n\n"
        "| Asset | File | Size | Fallback until uploaded | Asset id |\n|---|---|---|---|---|\n"
        + "\n".join(rows)
        + "\n"
    )
    print(f"wrote {len(rows)} textures to {OUT}")


if __name__ == "__main__":
    main()
