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
CHAI_UI_FILTERS=$(python3 scripts/ui_test_scope.py "${CHAI_UI_SCOPE:-full}")
CHAI_UI_ARGS=()
if [[ -n "$CHAI_UI_FILTERS" ]]; then
  while IFS= read -r filter; do CHAI_UI_ARGS+=("$filter"); done <<< "$CHAI_UI_FILTERS"
fi
CHAI_SIM_DESTINATION=$(python3 - <<'PY'
import json,subprocess,platform,re
x=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones=[d for runtime,devices in x['devices'].items() if 'iOS' in runtime for d in devices if d['name'].startswith('iPhone')]
if not phones: raise SystemExit('No available iPhone simulator')
# The complete layout suite exercises up to 430pt inside the actual window.
# Prefer the newest installed Pro Max/Plus; viewport tests still assert its width.
phones.sort(key=lambda d: ('Pro Max' in d['name'], 'Plus' in d['name'], [int(n) for n in re.findall(r'\d+',d['name'])]), reverse=True)
print('platform=iOS Simulator,arch='+platform.machine()+',id='+phones[0]['udid'])
PY
)
# Intel CI measured 162s for the complete bilingual legal flow. Keep every
# assertion and serial execution; bound each case instead of killing valid work
# at the previous 120s maximum and cascading into app-termination failures.
CHAI_UI_EXIT=0
mkdir -p build
xcodebuild -project ChaiClassics.xcodeproj -scheme ChaiClassics -destination "$CHAI_SIM_DESTINATION" -derivedDataPath build/DerivedData -resultBundlePath build/UITests.xcresult CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES "${CHAI_UI_ARGS[@]}" -parallel-testing-enabled NO -test-timeouts-enabled YES -default-test-execution-time-allowance 420 -maximum-test-execution-time-allowance 600 test 2>&1 | tee build/UITests.log || CHAI_UI_EXIT=$?
if [[ -d build/UITests.xcresult ]]; then
  xcrun xcresulttool get test-results summary --path build/UITests.xcresult > build/UITests-summary.json || CHAI_UI_EXIT=1
fi
return "$CHAI_UI_EXIT"
}
case "$CHAI_CI_PHASE" in
  all) verify; unit; build; ui ;;
  verify) verify ;;
  unit) unit ;;
  build) build ;;
  ui) ui ;;
  *) echo 'Usage: scripts/ci.sh [all|verify|unit|build|ui]' >&2; exit 64 ;;
esac
