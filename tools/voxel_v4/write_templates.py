#!/usr/bin/env python3
"""Turn the headless Studio dump of VoxelCreatureBuilder output into Rojo
.model.json native templates at src/assets/CreaturesV4/<ID>_V4.model.json
(ReplicatedStorage.CodeAssets.CreaturesV4.<ID>_V4). Serialisation only: every
instance and property comes from the Luau builder's dump.

Usage: python3 -I write_templates.py <dump.log>
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
OUT = ROOT / "src" / "assets" / "CreaturesV4"


def cframe(c):
    r = c["rotation"]
    return {"position": c["position"], "orientation": [r[0:3], r[3:6], r[6:9]]}


def attrs(a):
    out = {}
    if not a:  # Luau encodes an empty table as []
        return out
    for name, v in sorted(a.items()):
        (kind, value), = v.items()
        out[name] = value if kind in ("Bool", "Float64", "String") else {kind: value}
    return out


def convert(node, is_root=False, ref="V4Root", sid="V4"):
    out = {"className": node["className"]}
    rid = lambda key: ref if key == "Root" else f"V4_{sid}_{key}"
    if not is_root:
        out["name"] = node["name"]
    props, attributes = {}, attrs(node["attributes"])
    if "part" in node:
        p = node["part"]
        props = {
            "Size": p["Size"],
            "CFrame": {"CFrame": cframe(p["CFrame"])},
            "Color": p["Color"],
            "Material": p["Material"],
            "Transparency": p["Transparency"],
            "Reflectance": p["Reflectance"],
            "Anchored": p["Anchored"],
            "Massless": p["Massless"],
            "CanCollide": p["CanCollide"],
            "CanQuery": p["CanQuery"],
            "CanTouch": p["CanTouch"],
            "CastShadow": p["CastShadow"],
            "TopSurface": "Smooth",
            "BottomSurface": "Smooth",
        }
        if p["MaterialVariant"]:
            props["MaterialVariant"] = p["MaterialVariant"]
    elif "emitter" in node:
        e = node["emitter"]
        seq = lambda v: {"NumberSequence": {"keypoints": [{"time": 0, "value": v[0], "envelope": 0}, {"time": 1, "value": v[1], "envelope": 0}]}}
        props = {
            "Texture": {"ContentId": e["Texture"]},
            "Rate": e["Rate"],
            "Lifetime": {"NumberRange": e["Lifetime"]},
            "Size": seq(e["Size"]),
            "Transparency": seq(e["Transparency"]),
            "Color": {"ColorSequence": {"keypoints": [{"time": 0, "color": e["Color"][0]}, {"time": 1, "color": e["Color"][1]}]}},
            "LightEmission": e["LightEmission"],
            "Speed": {"NumberRange": e["Speed"]},
            "SpreadAngle": {"Vector2": e["SpreadAngle"]},
            "EmissionDirection": {"Enum": ["Right", "Top", "Back", "Left", "Bottom", "Front"].index(e["EmissionDirection"])},
            "Acceleration": {"Vector3": e["Acceleration"]},
            "RotSpeed": {"NumberRange": e["RotSpeed"]},
        }
    elif "joint" in node:
        j = node["joint"]
        props = {"C0": {"CFrame": cframe(j["C0"])}, "C1": {"CFrame": cframe(j["C1"])}}
        attributes["Rojo_Target_Part0"] = rid(j["Part0"])
        attributes["Rojo_Target_Part1"] = rid(j["Part1"])
    elif "weld" in node:
        w = node["weld"]
        attributes["Rojo_Target_Part0"] = rid(w["Part0"])
        attributes["Rojo_Target_Part1"] = rid(w["Part1"])
    elif "attachment" in node:
        props = {"CFrame": {"CFrame": cframe(node["attachment"]["CFrame"])}}
    elif "model" in node:
        m = node["model"]
        props = {
            "ModelStreamingMode": m["ModelStreamingMode"],
            "WorldPivotData": {"OptionalCFrame": cframe(m["WorldPivot"])},
        }
    if props:
        out["properties"] = props
    if "part" in node and node.get("ref"):
        attributes["Rojo_Id"] = rid(node["ref"])
    out["children"] = [convert(child, ref=ref, sid=sid) for child in node["children"]]
    if "model" in node and node["model"].get("PrimaryPart"):
        target = node["model"]["PrimaryPart"]
        attributes["Rojo_Target_PrimaryPart"] = ref
        roots = [c for c in out["children"] if c.get("name") == target]
        assert len(roots) == 1, "primary part must be a unique direct child"
        roots[0].setdefault("attributes", {})["Rojo_Id"] = ref
    if attributes:
        out["attributes"] = attributes
    return out


def main():
    text = pathlib.Path(sys.argv[1]).read_text(errors="replace")
    chunks = {}
    for m in re.finditer(r"\[V4DUMP\] (\S+) (\d+)/(\d+) (.*)", text):
        sid, i, n, body = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)
        chunks.setdefault(sid, {"n": n, "parts": {}})["parts"][i] = body
    OUT.mkdir(parents=True, exist_ok=True)
    report = []
    for sid, c in sorted(chunks.items()):
        assert len(c["parts"]) == c["n"], f"{sid}: missing dump chunks"
        dump = json.loads("".join(c["parts"][i] for i in range(1, c["n"] + 1)))
        # Rojo_Id must be unique across the whole place build.
        tree = convert(dump["tree"], is_root=True, ref=f"V4Root_{sid}", sid=sid)
        path = OUT / f"{sid}_V4.model.json"
        path.write_text(json.dumps(tree, indent=1) + "\n")
        parts = sum(1 for _ in re.finditer(r'"className": "Part"', path.read_text()))
        report.append({"id": sid, "signature": dump["signature"], "file": str(path.relative_to(ROOT)), "parts": parts})
    print(json.dumps(report, indent=1))


if __name__ == "__main__":
    main()
