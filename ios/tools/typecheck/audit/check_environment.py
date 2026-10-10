#!/usr/bin/env python3
"""Static check of `@Environment(SomeModel.self)` injection (a runtime crash the compiler cannot see).

A view that reads `@Environment(AppModel.self)` stops the app with a fatal error when no ancestor wrote that object with
`.environment(model)`. The audit builds, from the sources alone:

  readers      every type with an `@Environment(X.self)` property (X an Observable class), X from its declaration
  needs(T)     the objects T reads, plus (transitively) the objects read by every app view T constructs in its source,
               minus the ones T injects itself with `.environment(...)`
  roots        the App's scene content and every `#Preview` body: each must inject all that it needs
  order        a view that injects X must do so AFTER (outside) its `.sheet` / `.fullScreenCover` / `.popover` presentations
               that build content needing X: presented content gets the environment of the view that presents it

It is a textual check (no type information): `.environment(arg)` is matched to an object type by the type named in the
argument or, for a plain identifier, by the property it refers to in the same type.
    check_environment.py <app root>
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from swiftscan import blank, types, swift_files, line_of, innermost, match_brace

root = os.path.abspath(sys.argv[1])
files = {}
for p in swift_files(root):
    src = open(p, errors='replace').read()
    files[p] = (src, blank(src))

REL = lambda p: os.path.relpath(p, root)
spans = {p: types(c) for p, (s, c) in files.items()}
decl_types = {}   # name -> [(file, span)]
for p, sp in spans.items():
    for sp1 in sp:
        if sp1[0] != 'extension':
            decl_types.setdefault(sp1[1].split('.')[-1], []).append((p, sp1))

ENV_RE = re.compile(r'@Environment\(\s*([A-Z]\w*)\.self\s*\)')
reads = {}   # type name -> set of objects
for p, (s, c) in files.items():
    for m in ENV_RE.finditer(c):
        sp1 = innermost([x for x in spans[p] if x[0] != 'extension'], m.start())
        if sp1:
            reads.setdefault(sp1[1].split('.')[-1], set()).add(m.group(1))
objects = sorted({o for v in reads.values() for o in v})


def obj_of(arg, ctx_src):
    for o in objects:
        if re.search(r'\b' + o + r'\b', arg):
            return o
    m = re.fullmatch(r'\s*([a-z]\w*)\s*', arg)
    if m:   # a property of the enclosing type: `var router = AppRouter()` / `let model: AppModel`
        pm = re.search(r'\bvar\s+' + m.group(1) + r'\s*(?::\s*([A-Z]\w*))?\s*(?:=\s*([A-Z]\w*)\()?', ctx_src) or \
             re.search(r'\blet\s+' + m.group(1) + r'\s*(?::\s*([A-Z]\w*))?\s*(?:=\s*([A-Z]\w*)\()?', ctx_src)
        if pm:
            t = pm.group(1) or pm.group(2)
            if t in objects: return t
    return None


def injections(text, ctx_src, base_off=0):
    """[(object, offset)] for each `.environment(<object>)` in `text`."""
    out = []
    for m in re.finditer(r'\.environment\(', text):
        k = m.end(); depth = 1
        while k < len(text) and depth:
            depth += {'(': 1, ')': -1}.get(text[k], 0); k += 1
        arg = text[m.end():k - 1]
        if re.match(r'\s*\\', arg):    # key-path form: .environment(\.foo, value)
            continue
        o = obj_of(arg, ctx_src)
        if o: out.append((o, base_off + m.start()))
    return out


def body_of(name):
    res = []
    for p, (kind, n, a, b) in [(p, sp1) for _, v in decl_types.items() for p, sp1 in v if sp1[1].split('.')[-1] == name]:
        res.append((p, a, b))
    return res


names = set(decl_types)
CALL = re.compile(r'\b([A-Z]\w*)\s*\(')
METHOD_CALL = re.compile(r'\.([a-z]\w*)\s*\(')

# `extension View { func statusBanners() -> some View { modifier(StatusBanners()) } }`: calling `.statusBanners()` builds
# StatusBanners, so a method of an extension counts as constructing what its body constructs
method_builds = {}
for p, sp in spans.items():
    s_, c_ = files[p]
    for kind, n, a, b in sp:
        if kind == 'extension':
            for fm in re.finditer(r'\bfunc\s+([a-z]\w*)\s*[<(]', c_[a:b]):
                q = c_.find('{', a + fm.end()); 
                if q < 0 or q > b: continue
                method_builds.setdefault(fm.group(1), set()).update(
                    x for x in (m.group(1) for m in CALL.finditer(c_[q:match_brace(c_, q)])) if x in names)


def constructs(clean_text):
    out = {m.group(1) for m in CALL.finditer(clean_text) if m.group(1) in names}
    for m in METHOD_CALL.finditer(clean_text):
        out |= method_builds.get(m.group(1), set())
    return out


need_cache = {}


def needs(name, stack=()):
    if name in need_cache: return need_cache[name]
    if name in stack: return set()
    total, injected = set(reads.get(name, set())), set()
    for p, a, b in body_of(name):
        s, c = files[p]
        text = c[a:b]
        for o, _ in injections(text, s):
            injected.add(o)
        for ch in constructs(text):
            if ch != name:
                total |= needs(ch, stack + (name,))
    # members declared in extensions of the same type count too
    for p, sp in spans.items():
        for kind, n, a, b in sp:
            if kind == 'extension' and n.split('.')[-1] == name:
                s, c = files[p]
                for ch in constructs(c[a:b]):
                    if ch != name: total |= needs(ch, stack + (name,))
                for o, _ in injections(c[a:b], s): injected.add(o)
    res = total - injected
    need_cache[name] = res
    return res


problems = 0
print(f'  objects read through @Environment(X.self): {", ".join(objects) or "none"}')
for n in sorted(reads):
    print(f'  reader {n}: reads {sorted(reads[n])}; needs from above: {sorted(needs(n))}')

# roots: the App's scene and every #Preview
print('  roots:')
quiet_previews = 0
for p, (s, c) in sorted(files.items()):
    for m in re.finditer(r'#Preview\b', c):
        k = c.find('{', m.end())
        if k < 0: continue
        e = match_brace(c, k)
        text = c[k:e]
        inj = {o for o, _ in injections(text, s)}
        need = set()
        for ch in constructs(text): need |= needs(ch)
        miss = need - inj
        tag = 'FAIL' if miss else 'ok'
        if need or miss:
            print(f'    {tag} {REL(p)}:{line_of(s, m.start())} #Preview builds {sorted(constructs(text) & (set(reads) | set(n for n in names if needs(n))))} needs {sorted(need)} injects {sorted(inj)}' + (f'  MISSING {sorted(miss)}' if miss else ''))
        else:
            quiet_previews += 1
        problems += bool(miss)
    for kind, n, a, b in spans[p]:
        if kind == 'struct' and re.search(r':\s*[^{]*\bApp\b', c[max(0, a - 120):a]) and 'WindowGroup' in c[a:b]:
            text = c[a:b]
            inj = {o for o, _ in injections(text, s)}
            need = set()
            for ch in constructs(text): need |= needs(ch)
            miss = need - inj
            print(f'    {"FAIL" if miss else "ok"} {REL(p)}:{line_of(s, a)} App {n} scene needs {sorted(need)} injects {sorted(inj)}' + (f'  MISSING {sorted(miss)}' if miss else ''))
            problems += bool(miss)

print(f'    ok  {quiet_previews} more #Preview blocks build nothing that reads an injected object')

# order: presentations must sit inside the injection
print('  injection order (presentation modifiers must come before the .environment that supplies what they present):')
PRES = re.compile(r'\.(sheet|fullScreenCover|popover|navigationDestination)\(')
checked = 0
for n, objs in sorted(reads.items()):
    pass
for p, (s, c) in sorted(files.items()):
    for kind, n, a, b in spans[p]:
        if kind == 'extension': continue
        text = c[a:b]
        injs = injections(text, s, a)
        if not injs: continue
        for m in PRES.finditer(text):
            k = text.find('(', m.start()); depth = 0; e = k
            while e < len(text):
                depth += {'(': 1, ')': -1}.get(text[e], 0)
                e += 1
                if depth == 0: break
            end = e                       # end of the call's argument list; trailing closures follow
            while True:
                mm = re.match(r'\s*(?:[A-Za-z_]\w*\s*:\s*)?\{', text[end:])
                if not mm: break
                q = end + mm.end() - 1
                end = match_brace(text, q) + 1
            presented = constructs(text[m.start():end])
            need = set()
            for ch in presented: need |= needs(ch)
            for o, off in injs:
                if o in need:
                    checked += 1
                    pos = a + m.start()
                    ok = off > pos
                    print(f'    {"ok  " if ok else "FAIL"} {REL(p)}:{line_of(s, pos)} {n}: .{m.group(1)} presents {sorted(presented)} (needs {o}); .environment({o}) at line {line_of(s, off)}')
                    problems += (not ok)
if checked == 0:
    print('    none found')
print(f'  -> {problems} problems')
sys.exit(1 if problems else 0)
