#!/usr/bin/env python3
"""Record an approved brainrot: add it to CreatureAnimations and CreatureRigs and mark the logs.

Usage: approve_species.py BRT_### "Display Name" Archetype rigVersion "Torso>Head,..." "notes" DATE
Reads assets/animations/brainrots/<id>/index.json (written by build_rbxm.py). Ids stay 0
until the animations are uploaded.
"""
import json, sys

sid, name, archetype, rig_version, joints, notes, date = sys.argv[1:8]
ORDER = ["IdleDisplay", "IdleWild", "IdleWild2", "Walk", "Run", "Alert", "Hit", "Carried", "Sleep", "Celebrate", "Signature"]
index = json.load(open(f"assets/animations/brainrots/{sid}/index.json"))
rows = []
for clip in ORDER:
    v = index[clip]
    speed = f", speed = {v['speed']:g}" if v["speed"] else ""
    rows.append(f'\t\t\t{clip} = {{ id = 0, length = {v["length"]:g}, loop = {str(v["loop"]).lower()}, priority = "{v["priority"]}"{speed} }},')

path = "src/shared/Config/CreatureAnimations.lua"
text = open(path).read()
anchor = "}\n\nlocal Module = { Species"
assert text.count(anchor) == 1 and f"\t{sid} = " not in text
text = text.replace(anchor, f'\t{sid} = table.freeze({{\n\t\tapproved = true,\n\t\tapprovedOn = "{date}",\n\t\tanimations = table.freeze({{\n' + "\n".join(rows) + "\n\t\t}),\n\t}),\n" + anchor)
open(path, "w").write(text)

path = "src/shared/Config/CreatureRigs.lua"
text = open(path).read().rstrip()
assert text.endswith("})") and f"\t{sid} = " not in text
joint_rows = "".join(f'\t\t\t"{"Root>" + j if ">" not in j else j}",\n' for j in joints.split(","))
text = text[:-2] + f'\t{sid} = table.freeze({{\n\t\tarchetype = "{archetype}",\n\t\trigVersion = {rig_version},\n\t\tjoints = table.freeze({{\n{joint_rows}\t\t}}),\n\t\tnotes = "{notes}",\n\t}}),\n}})\n'
open(path, "w").write(text)

for path in ("docs/animation/2026-11/APPROVALS.md", "docs/animation/2026-11/REPORT.md"):
    lines = open(path).read().split("\n")
    for i, line in enumerate(lines):
        if line.startswith(f"| {sid} ") and ("Waiting" in line or "(waiting)" in line):
            cells = line.split("|")
            if path.endswith("APPROVALS.md"):
                cells[-3] = " Approved as sent. Upload blocked (ids 0, not live). "
                cells[-2] = " 13 Nov 2026 "
            else:
                cells[-4], cells[-3], cells[-2] = " 1 ", " 13 Nov 2026 ", " not uploaded "
            lines[i] = "|".join(cells)
    open(path, "w").write("\n".join(lines))
print("recorded", sid, name)
