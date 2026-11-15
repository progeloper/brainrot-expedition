#!/bin/sh
# Usage: ./scripts/run-terrain-tests.sh — one disposable Rojo build, TerrainRedesign + guard specs only.
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
STUDIO=/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio
RUN=$(mktemp -d "${TMPDIR:-/private/tmp}/brainrot-terrain-tests.XXXXXX")
# The live project ignores Tests/specs; build a disposable copy that includes them.
python3 -I - "$ROOT" "$RUN/v4.project.json" <<'PY'
import json, os, sys
root, out = sys.argv[1], sys.argv[2]
project = json.load(open(os.path.join(root, "default.project.json")))
project["tree"]["Workspace"].setdefault("MapBlockout", {"$path": "assets/native/phase14_20261023/MapBlockout.rbxm", "$ignoreUnknownInstances": True})  # the live project no longer maps the map; tests still load the last export
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
rojo build "$RUN/v4.project.json" --output "$RUN/v4.rbxlx"
"$STUDIO" --task RunScript --localPlaceFile "$RUN/v4.rbxlx" --runScriptFile "$SCRIPT_DIR/studio-terrain-test-runner.luau" --outputFile "$RUN/v4-tests.log" --quitAfterExecution >/dev/null 2>&1 || true
grep -E '^\[BRAINROT_TEST|PASS|FAIL|Error' "$RUN/v4-tests.log" | grep -v 'CrashHandler' || true
grep -Fxq '[BRAINROT_TEST_RESULT] PASS' "$RUN/v4-tests.log"
