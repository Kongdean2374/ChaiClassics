#!/bin/bash
set -euo pipefail
CHAI_VISUAL_PHASE="${1:-all}"
if (( $# > 1 )); then
  echo 'Usage: scripts/visual_smoke.sh [all|build|test]' >&2
  exit 64
fi
case "$CHAI_VISUAL_PHASE" in
  all|build|test) ;;
  *) echo 'Usage: scripts/visual_smoke.sh [all|build|test]' >&2; exit 64 ;;
esac
# Explicit, credential-free selection. The full game UI suite remains available
# through CI's full_ui option and is not added to routine pushes or TestFlight.
CHAI_VISUAL_SIM=$(python3 - <<'PY'
import json,subprocess
data=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones=[d for runtime,devices in data['devices'].items() if 'iOS' in runtime for d in devices if d['name'].startswith('iPhone')]
if not phones:raise SystemExit('No available iPhone simulator')
phones.sort(key=lambda d: ('Pro Max' in d['name'], 'Plus' in d['name'], d['name']))
print(phones[0]['udid'])
PY
)
CHAI_VISUAL_ARCH=$(uname -m)
CHAI_VISUAL_ARGS=(-project ChaiClassics.xcodeproj -scheme ChaiClassics \
  -destination "platform=iOS Simulator,arch=$CHAI_VISUAL_ARCH,id=$CHAI_VISUAL_SIM" \
  -derivedDataPath build/VisualDerivedData CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES)
build() {
  xcodebuild "${CHAI_VISUAL_ARGS[@]}" build-for-testing
}
test() {
  # Warm CoreSimulator before starting XCTest's automation session. Compiling,
  # booting and test execution now have separate visible workflow steps.
  xcrun simctl bootstatus "$CHAI_VISUAL_SIM" -b
  open -a Simulator --args -CurrentDeviceUDID "$CHAI_VISUAL_SIM"
  # Intel measured the complete fresh-win/restore/restart case at 207 seconds.
  # Keep every assertion; do not interrupt healthy work at the former 180s limit.
  xcodebuild "${CHAI_VISUAL_ARGS[@]}" -resultBundlePath build/VisualSmoke.xcresult \
    -only-testing:ChaiClassicsUITests/ChaiClassicsVisualSmokeTests \
    -parallel-testing-enabled NO -test-timeouts-enabled YES \
    -default-test-execution-time-allowance 300 -maximum-test-execution-time-allowance 360 test-without-building 2>&1 | tee build/VisualSmoke.log
}
case "$CHAI_VISUAL_PHASE" in
  all) build; test ;;
  build) build ;;
  test) test ;;
  *) echo 'Usage: scripts/visual_smoke.sh [all|build|test]' >&2; exit 64 ;;
esac
