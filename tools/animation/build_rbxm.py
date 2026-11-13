#!/usr/bin/env python3
"""Turn keyframe dumps from Studio into .rbxm KeyframeSequences (via rojo build).

Usage: build_rbxm.py OUT_DIR DUMP [DUMP ...]
Dump lines:  A|name|loop|priority|length|speed   K|time   P|bone|parent|px|py|pz|rx|ry|rz|weight
A dump may be raw text or the JSON wrapper the tool harness writes ([{"type":"text","text":...}]).
"""
import json, math, os, subprocess, sys, tempfile


def matrix(rx, ry, rz):
    cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
    return [[cy * cz, -cy * sz, sy],
            [sx * sy * cz + cx * sz, -sx * sy * sz + cx * cz, -sx * cy],
            [-cx * sy * cz + sx * sz, cx * sy * sz + sx * cz, cx * cy]]


def load(path):
    text = open(path).read()
    if text.lstrip().startswith("["):
        text = "".join(part["text"] for part in json.loads(text))
    return text.splitlines()


def main():
    out_dir = sys.argv[1]
    os.makedirs(out_dir, exist_ok=True)
    animations, current, keyframe, nodes = {}, None, None, None
    for path in sys.argv[2:]:
        for line in load(path):
            f = line.split("|")
            if f[0] == "A":
                current = {"Name": f[1], "ClassName": "KeyframeSequence",
                           "Properties": {"Loop": f[2] == "true", "Priority": f[3]}, "Children": []}
                animations[f[1]] = {"model": current, "length": float(f[4]), "speed": None if f[5] == "nil" else float(f[5]),
                                    "loop": f[2] == "true", "priority": f[3]}
            elif f[0] == "K":
                keyframe = {"Name": "Keyframe", "ClassName": "Keyframe", "Properties": {"Time": float(f[1])}, "Children": []}
                current["Children"].append(keyframe)
                nodes = {}
            elif f[0] == "P":
                pose = {"Name": f[1], "ClassName": "Pose", "Properties": {
                    "CFrame": {"CFrame": {"position": [float(f[3]), float(f[4]), float(f[5])],
                                          "orientation": matrix(float(f[6]), float(f[7]), float(f[8]))}},
                    "Weight": float(f[9]), "EasingStyle": "Linear"}, "Children": []}
                (nodes[f[2]]["Children"] if f[2] else keyframe["Children"]).append(pose)
                nodes[f[1]] = pose
    index = {}
    with tempfile.TemporaryDirectory() as tmp:
        for name, entry in sorted(animations.items()):
            json.dump(entry["model"], open(os.path.join(tmp, name + ".model.json"), "w"))
            project = os.path.join(tmp, name + ".project.json")
            json.dump({"name": name, "tree": {"$path": name + ".model.json"}}, open(project, "w"))
            target = os.path.join(out_dir, name + ".rbxm")
            subprocess.check_call(["rojo", "build", project, "--output", target], stdout=subprocess.DEVNULL)
            index[name] = {"length": entry["length"], "speed": entry["speed"], "loop": entry["loop"],
                           "priority": entry["priority"], "keyframes": len(entry["model"]["Children"]),
                           "bytes": os.path.getsize(target)}
    json.dump(index, open(os.path.join(out_dir, "index.json"), "w"), indent=1)
    print(len(index), "animations", sum(v["keyframes"] for v in index.values()), "keyframes")


if __name__ == "__main__":
    main()
