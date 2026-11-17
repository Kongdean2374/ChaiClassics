#!/bin/bash
set -euo pipefail
CHAI_IPAD_PHASE="${1:-}"
if (( $# != 1 )); then
  echo 'Usage: scripts/ipad_screenshots.sh [build|test|export]' >&2
  exit 64
fi
case "$CHAI_IPAD_PHASE" in
  build|test|export) ;;
  *) echo 'Usage: scripts/ipad_screenshots.sh [build|test|export]' >&2; exit 64 ;;
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
CHAI_IPAD_ARCH=$(uname -m)
CHAI_IPAD_ARGS=(-project ChaiClassics.xcodeproj -scheme ChaiClassics -sdk iphonesimulator \
  -destination "platform=iOS Simulator,arch=$CHAI_IPAD_ARCH,id=$CHAI_IPAD_UDID" \
  -derivedDataPath build/IPadDerivedData CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES)

if [[ "$CHAI_IPAD_PHASE" == build ]]; then
  xcodebuild "${CHAI_IPAD_ARGS[@]}" build-for-testing 2>&1 | tee "$CHAI_IPAD_OUTPUT/build.log"
else
  xcrun simctl bootstatus "$CHAI_IPAD_UDID" -b 2>&1 | tee "$CHAI_IPAD_OUTPUT/simulator-boot.log"
  open -a Simulator --args -CurrentDeviceUDID "$CHAI_IPAD_UDID"
  xcrun simctl ui "$CHAI_IPAD_UDID" appearance dark
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
