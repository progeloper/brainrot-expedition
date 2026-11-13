#!/bin/sh
# Regenerate the Voxel V4 native templates from the species data (headless Studio run of
# tools/voxel_v4/studio_dump_templates.luau, then write_templates.py). Prints the template
# files that changed. Run after a rig change is approved: ./tools/animation/regen_templates.sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
PATH="$HOME/.rokit/bin:$PATH"
RUN=$(mktemp -d "${TMPDIR:-/private/tmp}/brainrot-v4-templates.XXXXXX")
cd "$ROOT"
(cd src/assets/CreaturesV4 && shasum *.json > "$RUN/before.sha")
python3 -I - "$ROOT" "$RUN/v4.project.json" <<'PY'
import json, os, sys
root, out = sys.argv[1], sys.argv[2]
project = json.load(open(os.path.join(root, "default.project.json")))
project.pop("globIgnorePaths", None)
def fix(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "$path":
                node[key] = os.path.join(root, value)
            else:
                fix(value)
fix(project["tree"])
json.dump(project, open(out, "w"))
PY
rojo build "$RUN/v4.project.json" --output "$RUN/v4.rbxlx" >/dev/null
/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio --task RunScript --localPlaceFile "$RUN/v4.rbxlx" --runScriptFile "$ROOT/tools/voxel_v4/studio_dump_templates.luau" --outputFile "$RUN/dump.log" --quitAfterExecution >/dev/null 2>&1 || true
python3 -I tools/voxel_v4/write_templates.py "$RUN/dump.log" >/dev/null
(cd src/assets/CreaturesV4 && shasum *.json > "$RUN/after.sha")
echo "changed templates:"
diff "$RUN/before.sha" "$RUN/after.sha" | grep '^>' | awk '{print "  " $3}' || true
