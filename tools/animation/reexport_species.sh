#!/bin/sh
# Re-export one Voxel V4 species after a rig change: ./tools/animation/reexport_species.sh BRT_003
# Passes the species' mutation overrides file when it has one (forgetting it drops the
# per-mutation colours), keeps the iris family already in the data, and formats the result.
set -eu
ID=$1
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
DATA="$ROOT/src/shared/Config/VoxelCreatures/$ID.lua"
IRIS=$(sed -n 's/.*irisFamily = "\([A-Za-z]*\)".*/\1/p' "$DATA" | head -1)
cd "$ROOT/tools/voxel_v4"
if [ -f "builds/$ID.overrides.json" ]; then
	node export_lua.js "builds/$ID.js" "$ID" "$IRIS" "builds/$ID.overrides.json" >/dev/null
else
	node export_lua.js "builds/$ID.js" "$ID" "$IRIS" >/dev/null
fi
"$HOME/.rokit/bin/stylua" "$DATA"
echo "re-exported $ID (iris $IRIS)"
