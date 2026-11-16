#!/usr/bin/env python3
"""Development-only seeded generator. Never regenerate the shipped v1 pack.
Generator: randomized full-grid construction + bitmask MRV uniqueness pruning.
Grader: naked singles / hidden singles / branching after singles.
Verifier is separately implemented Algorithm X in verify_sudoku.py.
"""
import argparse, collections, json, pathlib, random
ROOT = pathlib.Path(__file__).resolve().parents[1]
UNITS = [[r*9+c for c in range(9)] for r in range(9)] + [[r*9+c for r in range(9)] for c in range(9)] + [[(b//3*3+r)*9+b%3*3+c for r in range(3) for c in range(3)] for b in range(9)]
PEERS = [set().union(*(set(u) for u in UNITS if i in u))-{i} for i in range(81)]

def count_solutions(grid, limit=2):
    g = grid[:]
    def search():
        best, options = -1, None
        for i, v in enumerate(g):
            if v: continue
            opts = set(range(1,10)) - {g[j] for j in PEERS[i]}
            if not opts: return 0
            if options is None or len(opts)<len(options): best, options = i, opts
            if len(opts)==1: break
        if best<0: return 1
        total=0
        for v in sorted(options):
            g[best]=v; total+=search()
            if total>=limit: break
        g[best]=0
        return total
    return search()

def grade(grid):
    g=grid[:]; naked=hidden=0
    while 0 in g:
        opts={i:set(range(1,10))-{g[j] for j in PEERS[i]} for i,v in enumerate(g) if not v}
        singles=[(i,next(iter(v))) for i,v in opts.items() if len(v)==1]
        if singles:
            i,v=singles[0]; g[i]=v; naked+=1; continue
        placed=False
        for unit in UNITS:
            for d in range(1,10):
                places=[i for i in unit if i in opts and d in opts[i]]
                if len(places)==1:
                    g[places[0]]=d; hidden+=1; placed=True; break
            if placed: break
        if not placed: return 'hard', {'nakedSingles':naked,'hiddenSingles':hidden,'requiresBranching':True}
    return ('medium' if hidden else 'easy'), {'nakedSingles':naked,'hiddenSingles':hidden,'requiresBranching':False}

def full_grid(rng):
    def shuffled(a): return rng.sample(list(a),len(a))
    rows=[b*3+r for b in shuffled(range(3)) for r in shuffled(range(3))]
    cols=[b*3+c for b in shuffled(range(3)) for c in shuffled(range(3))]
    digits=shuffled(range(1,10))
    return [digits[(r*3+r//3+c)%9] for r in rows for c in cols]

def generate(seed, per_difficulty):
    rng=random.Random(seed); packs=collections.defaultdict(list); seen=set(); attempts=0
    while any(len(packs[d])<per_difficulty for d in ('easy','medium','hard')):
        attempts+=1; grid=full_grid(rng); positions=list(range(81)); rng.shuffle(positions)
        for i in positions:
            old=grid[i]; grid[i]=0
            if count_solutions(grid)!=1: grid[i]=old
            difficulty,metrics=grade(grid)
            clues=sum(v>0 for v in grid)
            if difficulty=='easy' and clues>36: continue
            if len(packs[difficulty])>=per_difficulty: continue
            # Take at most one puzzle from a complete solution to avoid nested duplicates.
            key=tuple(grid)
            if key in seen: continue
            seen.add(key); n=len(packs[difficulty])+1
            packs[difficulty].append(dict(id=f'sudoku.{difficulty}.{n:04d}',difficulty=difficulty,number=n,givens=grid[:]))
            print(f'{difficulty} {n:03d} ({clues} clues) attempt {attempts}',flush=True)
            break
    return [p for d in ('easy','medium','hard') for p in packs[d]]

if __name__=='__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('--seed',type=int,default=20261116); ap.add_argument('--count',type=int,default=50); ap.add_argument('--output',required=True)
    args=ap.parse_args(); path=pathlib.Path(args.output)
    if path.exists(): raise SystemExit('Refusing to overwrite an existing immutable pack')
    path.write_text(json.dumps(generate(args.seed,args.count),ensure_ascii=False,indent=2)+'\n')
