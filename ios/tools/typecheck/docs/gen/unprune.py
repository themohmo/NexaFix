#!/usr/bin/env python3
"""unprune.py <regex on the reason>...: drop prune.txt entries whose recorded reason matches (e.g. after adding the
missing type to the shim), so the next generator run emits those declarations again."""
import re, sys, os
P = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'prune.txt')
pats = [re.compile(p) for p in sys.argv[1:]]
keep, drop = [], []
for l in open(P):
    if l.startswith('#') or not l.strip():
        keep.append(l); continue
    tag, _, reason = l.rstrip('\n').partition('\t')
    (drop if any(p.search(reason) for p in pats) else keep).append(l)
open(P, 'w').writelines(keep)
print('unpruned', len(drop))
for l in drop: print(' ', l.split('\t')[0])
