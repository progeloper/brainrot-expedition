#!/usr/bin/env python3
"""Writes a disposable Rojo project for test builds.

default.project.json no longer maps Workspace.MapBlockout: the Studio place file owns the map, and a
live Rojo connect used to put the October export back over newer native work (12 Nov 2026). Test builds
have no place file, so they still load that last export here.

Usage: build-project.py <repository root> <output project.json> [--with-specs]
"""
import json
import os
import sys

MAP_EXPORT = "assets/native/phase14_20261023/MapBlockout.rbxm"


def main() -> None:
    root, out = sys.argv[1], sys.argv[2]
    project = json.load(open(os.path.join(root, "default.project.json")))
    if "--with-specs" in sys.argv[3:]:
        project.pop("globIgnorePaths", None)
    project["tree"]["Workspace"].setdefault(
        "MapBlockout", {"$path": MAP_EXPORT, "$ignoreUnknownInstances": True}
    )

    def absolute(node):
        if isinstance(node, dict):
            for key, value in node.items():
                if key == "$path":
                    node[key] = os.path.join(root, value)
                else:
                    absolute(value)

    absolute(project["tree"])
    json.dump(project, open(out, "w"))


if __name__ == "__main__":
    main()
