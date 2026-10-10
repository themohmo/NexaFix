#!/usr/bin/env python3
"""Which APIs does the app use that are newer than its iOS 17.0 deployment target, and is each one guarded?

The Linux compiler cannot enforce `@available` / `#available` for iOS (it rejects an iOS target triple), so this does
what Xcode would do, in two steps:

  1. `swiftc -dump-ast` resolves every call the app makes to the exact declaration it picked (overloads included) and
     says where that declaration is in the shim. The shim tags each declaration with the Apple documentation page it was
     copied from, and the page says which iOS version introduced it (docs/declarations.json). A member of a type is
     as new as the type itself.
  2. Each such use must lie inside `if #available(iOS V, *) { ... }` (the then-branch), after `guard #available(iOS V, *)`
     in the same scope, inside the else-branch of `if #unavailable(iOS ..)`, or inside a declaration marked
     `@available(iOS V, *)`, with V at least the version needed. Uses of the app's own `@available` declarations
     are held to the same rule.

    check_availability.py <app root> <build dir> <swiftc flags...>
Exit status 1 if any use is unguarded. The usage list is printed so a human can check the fallbacks (an `else`, or the
code after the guard) by reading them: this script does not judge whether a fallback works.
"""
import json, os, re, subprocess, sys, collections
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from swiftscan import blank, match_brace, swift_files, line_of

DEPLOY = 17.0
app = os.path.abspath(sys.argv[1])
out = sys.argv[2]
flags = sys.argv[3:]
DECLS = json.load(open(os.path.join(HERE, '..', 'docs', 'declarations.json')))
SHIMS = os.path.abspath(os.path.join(HERE, '..', 'shims'))

files = sorted(swift_files(app))
ast_path = os.path.join(out, 'ast.txt')
with open(ast_path, 'w') as fh:
    subprocess.run(['swiftc', '-dump-ast', *flags, '-D', 'DEBUG', *files], stdout=subprocess.DEVNULL, stderr=fh)


def ver(s):
    try:
        return float(s)
    except Exception:
        return None


def intro_of(page):
    """Effective introduction of a documented symbol: the max over the page and its enclosing types."""
    best, parts = 0.0, page.split('#')[0].split('/')
    for n in range(2, len(parts) + 1):
        p = '/'.join(parts[:n])
        d = DECLS.get(p) or DECLS.get(p + '#0')
        if d:
            v = ver(((d.get('iOS') or {}).get('introduced')))
            if v: best = max(best, v)
    return best


def deprecated(page):
    d = DECLS.get(page)
    return bool(d and (d.get('iOS') or {}).get('deprecated'))


_shim_lines = {}


def shim_tag(path, line):
    """The `// doc:` page the shim declaration at path:line was copied from (searching up to 6 lines above)."""
    if path not in _shim_lines:
        _shim_lines[path] = open(path, errors='replace').read().split('\n')
    L = _shim_lines[path]
    for k in range(line - 1, max(-1, line - 8), -1):
        t = L[k].strip()
        m = re.match(r'//\s*doc: (\S+)', t) or re.match(r'//\s*doc-fixed: (\S+)', t)
        if m:
            return m.group(1)
        if t.startswith('// shim:') or t.startswith('// doc-unconfirmed'):
            return None
        if t.startswith('}') or (t.startswith('public ') and k < line - 1 and '{' in t and 'func' not in t and 'init' not in t and 'var' not in t):
            break
    return None


# ---- the app's own @available declarations
src, clean, line_starts = {}, {}, {}
for p in files:
    s = open(p, errors='replace').read()
    src[p] = s; clean[p] = blank(s)
    ls = [0]
    for m in re.finditer('\n', s): ls.append(m.end())
    line_starts[p] = ls

AVAIL_RE = re.compile(r'@available\(([^)]*)\)')


def ios_ver(cond):
    m = re.search(r'iOS(?:ApplicationExtension)?\s+(\d+(?:\.\d+)?)', cond) or re.search(r'iOS\s*,\s*introduced:\s*(\d+(?:\.\d+)?)', cond)
    return float(m.group(1)) if m else None


regions = {p: [] for p in files}      # (start, end, version, kind, line)
app_decl_ver = {}                      # (file, line) -> version for the app's own @available declarations


def decl_extent(c, i):
    """End offset of the declaration that starts after offset i (attributes already consumed)."""
    k, depth, n = i, 0, len(c)
    while k < n:
        ch = c[k]
        if ch in '([<': depth += 1
        elif ch in ')]>': depth -= 1
        elif ch == '{' and depth <= 0: return match_brace(c, k) + 1
        elif ch == '\n' and depth <= 0:
            seg = c[i:k]
            # a stored property or a bodiless declaration ends at the line end (a following `{` on the next line is a body)
            nxt = c[k:k + 80].lstrip()
            if not nxt.startswith('{') and re.search(r'\b(let|var|case|typealias|import)\b', seg) and '=' in seg and not seg.rstrip().endswith(('{', ',')):
                return k
        k += 1
    return n


for p in files:
    c = clean[p]
    # @available(iOS V, *) declarations
    for m in AVAIL_RE.finditer(c):
        v = ios_ver(m.group(1))
        if v is None: continue
        j = m.end()
        # skip further attributes
        while True:
            mm = re.match(r'\s*@[A-Za-z_]\w*(?:\([^)]*\))?', c[j:])
            if not mm: break
            j += mm.end()
        end = decl_extent(c, j)
        regions[p].append((j, end, v, '@available', line_of(src[p], m.start())))
        app_decl_ver[(p, line_of(src[p], j + len(c[j:]) - len(c[j:].lstrip())))] = v
    # #available / #unavailable
    for m in re.finditer(r'#(available|unavailable)\s*\(', c):
        k = m.end(); depth = 1
        while k < len(c) and depth:
            depth += {'(': 1, ')': -1}.get(c[k], 0); k += 1
        v = ios_ver(c[m.end():k - 1])
        if v is None: continue
        ln = line_of(src[p], m.start())
        # statement keyword before the condition
        pre = c[max(0, c.rfind('\n', 0, m.start())):m.start()]
        stmt_start = c.rfind('\n', 0, m.start()) + 1
        # look back over the whole condition list (may start on an earlier line): find the nearest if/guard/while keyword
        back = c[max(0, m.start() - 160):m.start()]
        kw = None
        for km in re.finditer(r'\b(if|guard|while)\b', back):
            kw = km.group(1)
        if kw is None: continue
        # the block that follows the condition list
        q, d = k, 0
        while q < len(c):
            ch = c[q]
            if ch in '([': d += 1
            elif ch in ')]': d -= 1
            elif ch == '{' and d <= 0: break
            q += 1
        if q >= len(c): continue
        e = match_brace(c, q)
        kind = m.group(1)
        if kw == 'guard':
            # guarded for the rest of the enclosing block: the guard's own else-body is the unavailable path
            depth, r, enclosing_end = 0, e + 1, len(c)
            while r < len(c):
                if c[r] == '{': depth += 1
                elif c[r] == '}':
                    if depth == 0: enclosing_end = r; break
                    depth -= 1
                r += 1
            if kind == 'available':
                regions[p].append((e + 1, enclosing_end, v, 'guard #available', ln))
        elif kind == 'available':
            els = re.match(r'\s*else\b', c[e + 1:]) is not None
            regions[p].append((q + 1, e, v, 'if #available' + (' (with else fallback)' if els else ' (no else)'), ln))
        else:   # if #unavailable(iOS V) { fallback } else { new }
            mm = re.match(r'\s*else\s*\{', c[e + 1:])
            if mm:
                q2 = e + 1 + mm.end() - 1
                regions[p].append((q2 + 1, match_brace(c, q2), v + 0.0, 'else of #unavailable', ln))


def region_for(p, off, need):
    for a, b, v, kind, ln in regions[p]:
        if a <= off < b and v >= need:
            return (kind, v, ln)
    return None


# ---- uses, from the AST dump
uses, deprecated_uses = {}, {}
loc_re = re.compile(r'(?:location=|range=\[)(/\S+?\.swift):(\d+):(\d+)')
decl_re = re.compile(r'decl="[^"@]*@(/\S+?\.swift):(\d+):(\d+)')
for line in open(ast_path, errors='replace'):
    if 'decl="' not in line:
        continue
    dm = decl_re.search(line)
    if not dm: continue
    lm = loc_re.search(line)
    if not lm: continue
    up, ul, uc = lm.group(1), int(lm.group(2)), int(lm.group(3))
    if not up.startswith(app + os.sep):
        continue
    if re.search(r'\bimplicit\b', line.split('type=')[0]):
        continue
    dp, dl = dm.group(1), int(dm.group(2))
    need, name, dep = 0.0, None, False
    if dp.startswith(SHIMS + os.sep):
        page = shim_tag(dp, dl)
        if not page: continue
        need = intro_of(page); name = page
        dep = deprecated(page)
    elif dp.startswith(app + os.sep):
        need = 0.0
        for (fp, fl), v in app_decl_ver.items():
            if fp == dp and abs(fl - dl) <= 1:
                need = v; name = f'{os.path.relpath(dp, app)}:{fl} (app declaration)'
        dep = False
        if not need: continue
    else:
        continue
    if dep:
        deprecated_uses[(os.path.relpath(up, app), ul, name)] = True
    if need <= DEPLOY: continue
    uses[(up, ul, uc, name)] = need

rows = []
for (up, ul, uc, name), need in sorted(uses.items()):
    off = line_starts[up][ul - 1] + uc - 1
    r = region_for(up, off, need)
    rows.append((os.path.relpath(up, app), ul, name, need, r))

unguarded = [r for r in rows if r[4] is None]
print(f'  {len(rows)} uses of APIs newer than iOS {DEPLOY} (as resolved by the compiler), {len(unguarded)} unguarded')
# one line per (file, API) so repeated uses read as one
seen = set()
for rel, ln, name, need, r in rows:
    key = (rel, name, r[2] if r else ln)
    if key in seen: continue
    seen.add(key)
    n = sum(1 for x in rows if x[0] == rel and x[2] == name and (x[4][2] if x[4] else x[1]) == (r[2] if r else ln))
    print(f'    {"ok      " if r else "UNGUARDED"} iOS {need:<4} {rel}:{ln}  {name}' + (f'  x{n}' if n > 1 else '') + (f'  <- {r[0]} iOS {r[1]} at line {r[2]}' if r else ''))


# Types and typealiases newer than the target are also named in annotations and signatures, which the AST dump above
# does not resolve to a declaration use, so look for the names themselves.
new_types = sorted({k.split('/', 1)[1] for k in DECLS if k.count('/') == 1 and intro_of(k) > DEPLOY and re.fullmatch(r'[A-Za-z_]\w*', k.split('/', 1)[1])})
type_uses = []
for p in files:
    c = clean[p]
    for t in new_types:
        for m in re.finditer(r'(?<![\w.])' + re.escape(t) + r'\b', c):
            off = m.start()
            r = region_for(p, off, intro_of([k for k in DECLS if k.endswith('/' + t) and k.count('/') == 1][0]))
            type_uses.append((os.path.relpath(p, app), line_of(src[p], off), t, r))
print(f'  {len(new_types)} documented types newer than iOS {DEPLOY} in the shim ({", ".join(new_types)}); named in the app: {len(type_uses)}')
for rel, ln, t, r in type_uses:
    print(f'    {"ok      " if r else "UNGUARDED"} {rel}:{ln}  {t}' + (f'  <- {r[0]} iOS {r[1]} at line {r[2]}' if r else ''))
unguarded += [x for x in type_uses if x[3] is None]
if deprecated_uses:
    print(f'  deprecated by the docs and used: {len(deprecated_uses)}')
    for (rel, ln, name) in sorted(deprecated_uses): print(f'    {rel}:{ln}  {name}')
else:
    print('  deprecated by the docs and used: none')
sys.exit(1 if unguarded else 0)
