#!/bin/bash
set -euo pipefail
python3 scripts/verify_sudoku.py --report sudoku-verification.json
python3 scripts/create_project.py
git diff --exit-code -- ChaiClassics.xcodeproj
swift test --parallel
xcodebuild -project ChaiClassics.xcodeproj -scheme ChaiClassics -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build
DESTINATION=$(python3 - <<'PY'
import json,subprocess
x=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
phones=[d for runtime,devices in x['devices'].items() if 'iOS' in runtime for d in devices if d['name'].startswith('iPhone')]
if not phones: raise SystemExit('No available iPhone simulator')
print('platform=iOS Simulator,id='+phones[0]['udid'])
PY
)
xcodebuild -project ChaiClassics.xcodeproj -scheme ChaiClassics -destination "$DESTINATION" -derivedDataPath build/DerivedData -resultBundlePath build/UITests.xcresult CODE_SIGNING_ALLOWED=NO test
