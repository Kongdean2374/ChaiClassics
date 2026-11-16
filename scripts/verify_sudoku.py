#!/usr/bin/env python3
"""Independent exact-cover / Algorithm X solution counter (no generator solver).
Also checks all released IDs, clue hashes and strategy grading. No answers emitted.
"""
import argparse, collections, hashlib, json, pathlib
from generate_sudoku import grade
ROOT=pathlib.Path(__file__).resolve().parents[1]

def exact_cover_count(grid, limit=2):
    # 324 constraints: cell, row-digit, column-digit, box-digit.
    columns={i:set() for i in range(324)}; rows={}
    for r in range(9):
        for c in range(9):
            for d in range(1,10):
                if grid[r*9+c] not in (0,d): continue
                key=(r,c,d); box=r//3*3+c//3
                cs=(r*9+c,81+r*9+d-1,162+c*9+d-1,243+box*9+d-1)
                rows[key]=cs
                for col in cs: columns[col].add(key)
    def search():
        if not columns: return 1
        col=min(columns,key=lambda c:len(columns[c]))
        total=0
        for row in list(columns[col]):
            removed=[]
            for c in rows[row]:
                members=columns.pop(c)
                removed.append((c,members))
                for rr in members:
                    for other in rows[rr]:
                        if other in columns: columns[other].discard(rr)
            total+=search()
            for c,members in reversed(removed):
                columns[c]=members
                for rr in members:
                    for other in rows[rr]:
                        if other in columns and other!=c: columns[other].add(rr)
            if total>=limit: break
        return total
    return search()

def clue_hash(p): return hashlib.sha256(bytes(p['givens'])).hexdigest()

def verify(pack, baseline):
    assert len(pack)>=150, f'Only {len(pack)} puzzles'
    ids=set(); grids=set(); counts=collections.Counter(); metrics={}
    by_id={p['id']:p for p in pack}
    for entry in baseline:
        p=by_id[entry['id']]
        assert (p['difficulty'],p['number'],clue_hash(p))==(entry['difficulty'],entry['number'],entry['sha256']), f'Modified released puzzle {p["id"]}'
    for p in pack:
        g=p['givens']; ident=p['id']; d=p['difficulty']; n=p['number']
        assert ident==f'sudoku.{d}.{n:04d}' and ident not in ids
        assert len(g)==81 and all(type(v)==int and 0<=v<=9 for v in g)
        assert tuple(g) not in grids, f'Duplicate {ident}'
        for unit in ([[r*9+c for c in range(9)] for r in range(9)]+[[r*9+c for r in range(9)] for c in range(9)]+[[(b//3*3+r)*9+b%3*3+c for r in range(3) for c in range(3)] for b in range(9)]):
            given=[g[i] for i in unit if g[i]]; assert len(given)==len(set(given))
        assert exact_cover_count(g)==1, f'Not unique: {ident}'
        actual, m=grade(g); assert actual==d, (ident,actual)
        metrics[ident]=m; ids.add(ident); grids.add(tuple(g)); counts[d]+=1
    for d in ('easy','medium','hard'):
        assert counts[d]>=50
        assert sorted(p['number'] for p in pack if p['difficulty']==d)==list(range(1,counts[d]+1))
    return dict(puzzles=len(pack),uniqueSolutions=len(pack),failures=0,difficulties=dict(counts),strategies=metrics)

if __name__=='__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('--pack',default=str(ROOT/'Core/Resources/sudoku-v1.json')); ap.add_argument('--baseline',default=str(ROOT/'docs/sudoku-manifest-v1.json')); ap.add_argument('--report'); args=ap.parse_args()
    report=verify(json.loads(pathlib.Path(args.pack).read_text()),json.loads(pathlib.Path(args.baseline).read_text()))
    if args.report: pathlib.Path(args.report).write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='strategies'},ensure_ascii=False))
