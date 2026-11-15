#!/bin/sh

set -eu

# Usage: ./scripts/run-studio-tests.sh
# Both phases use disposable Rojo builds. The companion suite runs in Edit;
# native boarding runs with physics active and every bootstrap disabled. No
# authored place is opened, published or used to run profile bootstraps.
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPOSITORY_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
STUDIO_EXECUTABLE=/Applications/RobloxStudio.app/Contents/MacOS/RobloxStudio
RUN_DIRECTORY=$(mktemp -d "${TMPDIR:-/private/tmp}/brainrot-studio-tests.XXXXXX")
PLACE_FILE="$RUN_DIRECTORY/BrainrotExpedition-tests.rbxlx"
COMPANION_RUNNER="$SCRIPT_DIR/studio-test-runner.luau"
BOARDING_RUNNER="$SCRIPT_DIR/studio-native-boarding-test-runner.luau"

if ! command -v rojo >/dev/null 2>&1; then
	printf '%s\n' "Rojo is unavailable on PATH." >&2
	exit 1
fi

if [ ! -x "$STUDIO_EXECUTABLE" ]; then
	printf 'Roblox Studio is unavailable at %s\n' "$STUDIO_EXECUTABLE" >&2
	exit 1
fi

printf 'Studio test artifacts: %s\n' "$RUN_DIRECTORY"
# default.project.json no longer maps the map (the place file owns it); build-project.py adds the last export back.
python3 -I "$SCRIPT_DIR/build-project.py" "$REPOSITORY_ROOT" "$RUN_DIRECTORY/build.project.json"
rojo build "$RUN_DIRECTORY/build.project.json" --output "$PLACE_FILE"

run_suite() {
	SUITE_NAME=$1
	SUITE_RUNNER=$2
	SUITE_OUTPUT="$RUN_DIRECTORY/$SUITE_NAME-tests.log"
	set +e
	"$STUDIO_EXECUTABLE" \
		--task RunScript \
		--localPlaceFile "$PLACE_FILE" \
		--runScriptFile "$SUITE_RUNNER" \
		--outputFile "$SUITE_OUTPUT" \
		--quitAfterExecution
	SUITE_STATUS=$?
	set -e
	if [ -f "$SUITE_OUTPUT" ]; then
		cat "$SUITE_OUTPUT"
	else
		printf '%s suite produced no log. Studio exit status: %d\n' "$SUITE_NAME" "$SUITE_STATUS" >&2
		return 1
	fi
	if grep -Fxq '[BRAINROT_TEST_RESULT] PASS' "$SUITE_OUTPUT"; then
		printf '%s suite passed. Studio exit status: %d\n' "$SUITE_NAME" "$SUITE_STATUS"
		return 0
	fi
	printf '%s suite failed. Studio exit status: %d. Output: %s\n' \
		"$SUITE_NAME" "$SUITE_STATUS" "$SUITE_OUTPUT" >&2
	return 1
}

TEST_STATUS=0
if run_suite companion "$COMPANION_RUNNER"; then
	:
else
	TEST_STATUS=1
fi
# Run independently even if the companion suite fails so native regressions are
# still reported; the overall command succeeds only when both phases pass.
if run_suite native-boarding "$BOARDING_RUNNER"; then
	:
else
	TEST_STATUS=1
fi
exit "$TEST_STATUS"
