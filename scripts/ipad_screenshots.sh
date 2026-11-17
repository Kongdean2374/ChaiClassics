#!/bin/bash
set -euo pipefail
CHAI_IPAD_PHASE="${1:-}"
if (( $# != 1 )); then
  echo 'Usage: scripts/ipad_screenshots.sh [build|boot|test|games|export]' >&2
  exit 64
fi
case "$CHAI_IPAD_PHASE" in
  build|boot|test|games|export) ;;
  *) echo 'Usage: scripts/ipad_screenshots.sh [build|boot|test|games|export]' >&2; exit 64 ;;
esac
CHAI_IPAD_OUTPUT=build/ipad-screenshots
CHAI_IPAD_RESULT="$CHAI_IPAD_OUTPUT/IPadScreenshots.xcresult"
mkdir -p "$CHAI_IPAD_OUTPUT"

if [[ "$CHAI_IPAD_PHASE" == export ]]; then
  if [[ ! -d "$CHAI_IPAD_RESULT" ]]; then
    echo 'No iPad xcresult was created. See device/build diagnostics.' | tee "$CHAI_IPAD_OUTPUT/export.log" >&2
    exit 1
  fi
  # An incomplete bundle must fail export, while upload-artifact still preserves
  # the original xcresult and every screenshot successfully exported before it.
  CHAI_IPAD_EXPORT_EXIT=0
  if ! xcrun xcresulttool export attachments --path "$CHAI_IPAD_RESULT" \
    --output-path "$CHAI_IPAD_OUTPUT/attachments" 2>&1 | tee "$CHAI_IPAD_OUTPUT/export.log"; then
    CHAI_IPAD_EXPORT_EXIT=1
  fi
  if ! xcrun xcresulttool get test-results summary --path "$CHAI_IPAD_RESULT" \
    > "$CHAI_IPAD_OUTPUT/test-summary.json" 2> "$CHAI_IPAD_OUTPUT/test-summary-error.log"; then
    CHAI_IPAD_EXPORT_EXIT=1
  fi
  if [[ -d "$CHAI_IPAD_OUTPUT/IPadGames.xcresult" ]]; then
    if ! xcrun xcresulttool export attachments --path "$CHAI_IPAD_OUTPUT/IPadGames.xcresult" \
      --output-path "$CHAI_IPAD_OUTPUT/game-attachments" 2>&1 | tee "$CHAI_IPAD_OUTPUT/game-attachments-export.log"; then
      CHAI_IPAD_EXPORT_EXIT=1
    fi
    if ! xcrun xcresulttool get test-results summary --path "$CHAI_IPAD_OUTPUT/IPadGames.xcresult" \
      > "$CHAI_IPAD_OUTPUT/games-summary.json" 2> "$CHAI_IPAD_OUTPUT/games-summary-error.log"; then
      CHAI_IPAD_EXPORT_EXIT=1
    fi
  else
    echo 'The five new iPad game journeys did not produce an xcresult.' >&2
    CHAI_IPAD_EXPORT_EXIT=1
  fi
  exit "$CHAI_IPAD_EXPORT_EXIT"
fi

CHAI_IPAD_UDID=$(python3 - <<'PY'
import json,pathlib,re
data=json.loads(pathlib.Path('build/ipad-screenshots/device.json').read_text())
if data.get('status')!='ready':raise SystemExit('No validated iPad selection; refusing to build or boot a fallback device.')
udid=data.get('device_udid','')
if not re.fullmatch(r'[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}',udid):raise SystemExit('Selected iPad UDID is invalid.')
print(udid)
PY
)
if [[ "$CHAI_IPAD_PHASE" == boot ]]; then
  # Keep first-boot migration outside the test timeout, so a cold simulator
  # cannot interrupt xcresult finalization after otherwise completed cases.
  xcrun simctl bootstatus "$CHAI_IPAD_UDID" -b 2>&1 | tee "$CHAI_IPAD_OUTPUT/simulator-boot.log"
  open -a Simulator --args -CurrentDeviceUDID "$CHAI_IPAD_UDID"
  xcrun simctl ui "$CHAI_IPAD_UDID" appearance dark
  exit 0
fi
CHAI_IPAD_ARCH=$(uname -m)
CHAI_IPAD_ARGS=(-project ChaiClassics.xcodeproj -scheme ChaiClassics -sdk iphonesimulator \
  -destination "platform=iOS Simulator,arch=$CHAI_IPAD_ARCH,id=$CHAI_IPAD_UDID" \
  -derivedDataPath build/IPadDerivedData CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES)

if [[ "$CHAI_IPAD_PHASE" == build ]]; then
  xcodebuild "${CHAI_IPAD_ARGS[@]}" build-for-testing 2>&1 | tee "$CHAI_IPAD_OUTPUT/build.log"
elif [[ "$CHAI_IPAD_PHASE" == games ]]; then
  # Reuse the same unsigned bundle and selected physical-size Simulator. Keep
  # these five journeys separate so the original gallery collector stays strict4.
  xcodebuild "${CHAI_IPAD_ARGS[@]}" -resultBundlePath "$CHAI_IPAD_OUTPUT/IPadGames.xcresult" \
    -only-testing:ChaiClassicsUITests/ChaiClassicsV020UITests/testTicTacToeLocalRoundRestoresWinsAndReplays \
    -only-testing:ChaiClassicsUITests/ChaiClassicsV020UITests/testConnectFourLocalRoundRestoresWinsAndReplays \
    -only-testing:ChaiClassicsUITests/ChaiClassicsV020UITests/testTwentyFourRestoresExactCardsCompletesAndStartsNextPuzzle \
    -only-testing:ChaiClassicsUITests/ChaiClassicsV020UITests/testMemoryRestoresMatchesHidesUnturnedCardsCompletesAndReplays \
    -only-testing:ChaiClassicsUITests/ChaiClassicsV020UITests/testMazeRestoresPositionResumesCompletesAndGeneratesNextMaze \
    -parallel-testing-enabled NO -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 720 \
    test-without-building 2>&1 | tee "$CHAI_IPAD_OUTPUT/games.log"
else
  # Reuse the existing test target, helpers and isolated v0.1.0 seed data. Four
  # independent cases retain other screens when one game's assertions fail.
  xcodebuild "${CHAI_IPAD_ARGS[@]}" -resultBundlePath "$CHAI_IPAD_RESULT" \
    -only-testing:ChaiClassicsUITests/ChaiClassicsVisualSmokeTests/testIPadHomeScreenshot \
    -only-testing:ChaiClassicsUITests/ChaiClassicsVisualSmokeTests/testIPadSudokuScreenshot \
    -only-testing:ChaiClassicsUITests/ChaiClassicsVisualSmokeTests/testIPadMinesweeperScreenshot \
    -only-testing:ChaiClassicsUITests/ChaiClassicsVisualSmokeTests/testIPadSlidingPuzzleScreenshot \
    -parallel-testing-enabled NO -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 600 -maximum-test-execution-time-allowance 720 \
    test-without-building 2>&1 | tee "$CHAI_IPAD_OUTPUT/tests.log"
fi
