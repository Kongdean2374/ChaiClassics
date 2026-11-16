#!/usr/bin/env python3
"""Compare released IDs against the actual parent/PR base, not a rewritten manifest."""
import json,os,subprocess,pathlib
from verify_sudoku import clue_hash
base=os.environ.get('COMPATIBILITY_BASE','')
if not base or set(base)=={'0'}:
    print('No previous commit supplied; immutable v1 manifest is still verified.'); raise SystemExit(0)
path='Core/Resources/sudoku-v1.json'
exists=subprocess.run(['git','cat-file','-e',f'{base}:{path}'],capture_output=True)
if exists.returncode:
    print('Base predates the first puzzle pack; immutable v1 manifest is still verified.'); raise SystemExit(0)
previous=json.loads(subprocess.check_output(['git','show',f'{base}:{path}']))
current=json.loads(pathlib.Path(path).read_text()); by_id={p['id']:p for p in current}
for p in previous:
    assert p['id'] in by_id, f'Removed stable ID {p["id"]}'
    assert by_id[p['id']]==p, f'Modified released puzzle {p["id"]}'
for p in current:
    old=[x['number'] for x in previous if x['difficulty']==p['difficulty']]
    if p['id'] not in {x['id'] for x in previous}: assert p['number']>max(old,default=0)
print(f'Compatibility passed: {len(previous)} existing IDs unchanged; {len(current)-len(previous)} appended.')
