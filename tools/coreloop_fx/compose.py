"""Core Loop V2 review packages (L6 / L7.6): side-by-side composites and GIFs with PIL.

ImageMagick and ffmpeg are not installed on this machine; PIL (a user-site package, so run without -I) does the same job:
  composite  mockup-left | build-right, labelled, at compare/<group>/<board>__<element>.png
  gif        frames -> animated GIF

Usage:
  python3 tools/coreloop_fx/compose.py composite <mockup.png> <x,y,w,h|full> <build.png> <x,y,w,h|full> <out.png> <title>
  python3 tools/coreloop_fx/compose.py board3 <cell 1-8> <build.png> <x,y,w,h|full> <out.png> <title>
  python3 tools/coreloop_fx/compose.py gif <out.gif> <ms per frame> <frame1.png> [frame2.png ...]
"""
import sys
from PIL import Image, ImageDraw, ImageFont

LABEL_H = 34
BG = (29, 33, 51)
FG = (247, 245, 252)


def crop(path, box):
    image = Image.open(path).convert("RGB")
    if box == "full":
        return image
    x, y, w, h = (int(v) for v in box.split(","))
    return image.crop((x, y, x + w, y + h))


def font(size):
    for candidate in ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", "/System/Library/Fonts/Helvetica.ttc"):
        try:
            return ImageFont.truetype(candidate, size)
        except OSError:
            continue
    return ImageFont.load_default()


def composite(left, right, out, title):
    height = max(left.height, right.height)
    # Match heights so proportions compare (the build is scaled to the mockup's height).
    if right.height != height:
        right = right.resize((round(right.width * height / right.height), height), Image.LANCZOS)
    if left.height != height:
        left = left.resize((round(left.width * height / left.height), height), Image.LANCZOS)
    gap = 12
    canvas = Image.new("RGB", (left.width + right.width + gap, height + LABEL_H), BG)
    canvas.paste(left, (0, LABEL_H))
    canvas.paste(right, (left.width + gap, LABEL_H))
    draw = ImageDraw.Draw(canvas)
    draw.text((8, 8), f"MOCKUP  ·  {title}", fill=FG, font=font(16))
    draw.text((left.width + gap + 8, 8), "BUILD (Studio)", fill=FG, font=font(16))
    canvas.save(out)
    print(out)


def board3_box(cell):
    # StarTags.dc.html: 24 px padding, 4 columns of 250 x 262, gaps 18 (x) and 20 (y); @1x render.
    i = int(cell) - 1
    col, row = i % 4, i // 4
    return f"{24 + col * 268},{24 + row * 282},250,262"


def main():
    mode = sys.argv[1]
    if mode == "composite":
        _, _, mock, mbox, build, bbox, out, title = sys.argv
        composite(crop(mock, mbox), crop(build, bbox), out, title)
    elif mode == "board3":
        _, _, cell, build, bbox, out, title = sys.argv
        mock = "docs/coreloop/2026-11/reference/mockups/captures/StarTags@1x.png"
        composite(crop(mock, board3_box(cell)), crop(build, bbox), out, title)
    elif mode == "gif":
        out, ms, frames = sys.argv[2], int(sys.argv[3]), sys.argv[4:]
        images = [Image.open(f).convert("RGB") for f in frames]
        images[0].save(out, save_all=True, append_images=images[1:], duration=ms, loop=0)
        print(out, len(images), "frames")
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
