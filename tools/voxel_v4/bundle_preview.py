#!/usr/bin/env python3
"""Inline a preview sheet's local <script src> files so it renders as one file."""
import pathlib, re, sys
src = pathlib.Path(sys.argv[1]).resolve()
html = src.read_text()
def inline(m):
    path = (src.parent / m.group(1)).resolve()
    return "<script>\n" + path.read_text() + "\n</script>"
out = re.sub(r'<script src="([^"]+)"></script>', inline, html)
target = src.with_name(src.stem + "_inline.html")
target.write_text(out)
print(target)
