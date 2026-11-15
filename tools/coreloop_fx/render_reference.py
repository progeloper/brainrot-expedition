"""Local shim render of the Core Loop V2 mockup boards (.dc.html) to PNG.

The .dc.html files need the canvas runtime; this shim lifts <helmet> into <head>
and the <x-dc> body into <body> so headless Chrome can draw them. Output is a
LOCAL RENDER of the pinned source, not a capture of the canvas page.
Usage: python3 -I tools/coreloop_fx/render_reference.py <reference_dir>
"""
import json, re, subprocess, sys, pathlib, tempfile

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
ref = pathlib.Path(sys.argv[1])
boards = json.loads((ref / "mockups/canvas.json").read_text())["boards"]
out = ref / "mockups/captures"
out.mkdir(parents=True, exist_ok=True)
tmp = pathlib.Path(tempfile.mkdtemp())
for name, b in boards.items():
    src = (ref / "mockups" / name).read_text()
    helmet = re.search(r"<helmet>(.*?)</helmet>", src, re.S).group(1)
    body = re.search(r"</helmet>(.*?)</x-dc>", src, re.S).group(1)
    page = f"<!doctype html><html><head><meta charset='utf-8'>{helmet}</head><body>{body}</body></html>"
    html = tmp / (name.replace(".dc.html", ".html"))
    html.write_text(page)
    stem = name.replace(".dc.html", "")
    for scale in (1, 2):
        png = out / f"{stem}@{scale}x.png"
        subprocess.run([CHROME, "--headless=new", "--hide-scrollbars", "--disable-gpu",
                        f"--force-device-scale-factor={scale}", "--virtual-time-budget=4000",
                        f"--window-size={b['w']},{b['h']}", f"--screenshot={png.resolve()}",
                        html.resolve().as_uri()], check=True, capture_output=True)
        print(png, b["title"])
