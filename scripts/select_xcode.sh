#!/bin/bash
set -euo pipefail
# Prefer the highest installed stable Xcode >=26. Fail rather than silently use an old SDK.
XCODE_PATH=$(python3 - <<'PY'
import glob,os,re
c=[]
for p in glob.glob('/Applications/Xcode*.app'):
    m=re.search(r'Xcode_(\d+)(?:\.(\d+))?(?:\.(\d+))?\.app$',p)
    if m and int(m[1])>=26: c.append((tuple(int(v or 0) for v in m.groups()),p))
if not c: raise SystemExit('No stable Xcode 26+ installed. Update runner image; do not bypass this check.')
print(max(c)[1])
PY
)
sudo xcode-select --switch "$XCODE_PATH/Contents/Developer"
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
