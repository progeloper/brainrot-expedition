#!/bin/sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
STUDIO_EXECUTABLE=/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio
RUN_DIRECTORY=$(mktemp -d "${TMPDIR:-/private/tmp}/brainrot-cargo-stress.XXXXXX")
PLACE_FILE="$RUN_DIRECTORY/BrainrotExpedition-tests.rbxlx"
OUTPUT_FILE="$RUN_DIRECTORY/cargo-stress.log"

printf 'Cargo stress artifacts: %s\n' "$RUN_DIRECTORY"
# default.project.json no longer maps the map (the place file owns it); build-project.py adds the last export back.
python3 -I "$SCRIPT_DIR/build-project.py" "$REPOSITORY_ROOT" "$RUN_DIRECTORY/build.project.json"
rojo build "$RUN_DIRECTORY/build.project.json" --output "$PLACE_FILE"

set +e
"$STUDIO_EXECUTABLE" \
	--task RunScript \
	--localPlaceFile "$PLACE_FILE" \
	--runScriptFile "$SCRIPT_DIR/studio-cargo-fixture-stress-runner.luau" \
	--outputFile "$OUTPUT_FILE" \
	--quitAfterExecution
STUDIO_STATUS=$?
set -e

if [ -f "$OUTPUT_FILE" ]; then
	grep -E '\[CARGO_STRESS(_SUMMARY|_FAILURE|_TOTAL)?\]' "$OUTPUT_FILE" || true
else
	printf 'Studio did not create the expected output file. Exit status: %d\n' "$STUDIO_STATUS" >&2
	exit 1
fi

if grep -Fq '[CARGO_STRESS_SUMMARY] phase=Focused iterations=500 selectedRuns=1500 failures=0 pendingReturns=0' "$OUTPUT_FILE" \
	&& grep -Fq '[CARGO_STRESS_SUMMARY] phase=Broad iterations=500 selectedRuns=3000 failures=0 pendingReturns=0' "$OUTPUT_FILE" \
	&& grep -Fq '[CARGO_STRESS_SUMMARY] phase=Cascade iterations=500 selectedRuns=2000 failures=0 pendingReturns=0' "$OUTPUT_FILE" \
	&& grep -Fq '[CARGO_STRESS_SUMMARY] phase=LegacyIsolation iterations=500 selectedRuns=1500 failures=0 pendingReturns=0' "$OUTPUT_FILE" \
	&& grep -Fq '[CARGO_STRESS_TOTAL] phases=4 iterationsPerPhase=500 selectedRuns=8000 failures=0 pendingReturns=0' "$OUTPUT_FILE"; then
	exit 0
fi

printf 'Cargo stress failed. Studio exit status: %d. Output: %s\n' \
	"$STUDIO_STATUS" \
	"$OUTPUT_FILE" >&2
exit 1
