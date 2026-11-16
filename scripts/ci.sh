#!/bin/bash
set -euo pipefail
CHAI_CI_PHASE="${1:-all}"
if (( $# > 1 )); then
  echo 'Usage: scripts/ci.sh [all|verify|unit|build|ui]' >&2
  exit 64
fi
verify() {
ruby -c fastlane/Fastfile
bash -n scripts/select_xcode.sh
python3 scripts/check_compatibility.py
python3 scripts/verify_sudoku.py --report sudoku-verification.json
python3 scripts/create_project.py
git diff --exit-code -- ChaiClassics.xcodeproj
}
unit() {
swift test
}
build() {
xcodebuild -project ChaiClassics.xcodeproj -scheme ChaiClassics -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
}
ui() {
CHAI_SIM_DESTINATION=$(python3 - <<'PY'
import json,subprocess,platform
x=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones=[d for runtime,devices in x['devices'].items() if 'iOS' in runtime for d in devices if d['name'].startswith('iPhone')]
if not phones: raise SystemExit('No available iPhone simulator')
print('platform=iOS Simulator,arch='+platform.machine()+',id='+phones[0]['udid'])
PY
)
# Intel CI measured 162s for the complete bilingual legal flow. Keep every
# assertion and serial execution; bound each case instead of killing valid work
# at the previous 120s maximum and cascading into app-termination failures.
xcodebuild -project ChaiClassics.xcodeproj -scheme ChaiClassics -destination "$CHAI_SIM_DESTINATION" -derivedDataPath build/DerivedData -resultBundlePath build/UITests.xcresult CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240 test
}
case "$CHAI_CI_PHASE" in
  all) verify; unit; build; ui ;;
  verify) verify ;;
  unit) unit ;;
  build) build ;;
  ui) ui ;;
  *) echo 'Usage: scripts/ci.sh [all|verify|unit|build|ui]' >&2; exit 64 ;;
esac
