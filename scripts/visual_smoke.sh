#!/bin/bash
set -euo pipefail
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
xcodebuild -project ChaiClassics.xcodeproj -scheme ChaiClassics \
  -destination "platform=iOS Simulator,arch=$CHAI_VISUAL_ARCH,id=$CHAI_VISUAL_SIM" \
  -derivedDataPath build/VisualDerivedData -resultBundlePath build/VisualSmoke.xcresult \
  -only-testing:ChaiClassicsUITests/ChaiClassicsVisualSmokeTests \
  CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=YES \
  -parallel-testing-enabled NO -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 180 -maximum-test-execution-time-allowance 240 test
