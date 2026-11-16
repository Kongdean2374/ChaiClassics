#!/usr/bin/env python3
import os,sys
names=['ASC_KEY_ID','ASC_ISSUER_ID','ASC_API_KEY_P8_BASE64']
if '--signing' in sys.argv:
    names += ['APPLE_TEAM_ID','DISTRIBUTION_CERT_P12_BASE64','DISTRIBUTION_CERT_PASSWORD','APPSTORE_PROFILE_BASE64']
missing=[name for name in names if not os.environ.get(name)]
if missing:
    raise SystemExit('Missing GitHub Secrets (values never printed): '+', '.join(missing)+'. See docs/RELEASING.md')
print('Required secret names are configured; Apple validity will be checked during signing/upload.')
