#!/usr/bin/env python3
"""Pruning loop for the generated SwiftUI shim.

The shim's generated declarations are copied from Apple's pages. Some of them name a type the shim does not define (an
App Intent, LocalizedStringResource ...) or clash with another page's copy of the same declaration. This regenerates the
shim, type-checks it standalone against the modules built before it, and for every error that lands on a generated
declaration (the line right after its `// doc:` tag) appends that declaration to prune.txt with the compiler's reason, then
repeats until no declaration is left to drop. Type headers are never pruned. A page that was documented twice is only
dropped once nothing else is left to prune (which of the two copies stays is arbitrary).

    autoprune.py          (needs the shim modules built first:  ONLY_SHIMS=1 ../../run.sh)
"""
import os, re, subprocess, sys

GEN = os.path.dirname(os.path.abspath(__file__)) + '/'
TC = os.path.abspath(os.path.join(GEN, '..', '..'))
SWIFTUI = os.path.join(TC, 'shims', 'SwiftUI')
MODS = os.path.join(os.environ.get('TYPECHECK_OUT', os.path.join(TC, '.build')), 'modules')
PRUNE = GEN + 'prune.txt'
LOG = '/tmp/nexafix_swiftui_tc.log'


def tc():
    files = sorted(os.path.join(SWIFTUI, f) for f in os.listdir(SWIFTUI) if f.endswith('.swift'))
    r = subprocess.run(['swiftc', '-typecheck', '-module-name', 'SwiftUI', '-parse-as-library', '-swift-version', '5', '-I', MODS,
                        '-Xfrontend', '-enable-objc-interop', '-Xfrontend', '-disable-objc-attr-requires-foundation-module',
                        '-Xfrontend', '-import-module', '-Xfrontend', 'ObjectiveC', *files], capture_output=True, text=True)
    open(LOG, 'w').write(r.stderr)
    return r.stderr


def pruned():
    return {l.split('\t')[0].strip() for l in open(PRUNE) if l.strip() and not l.startswith('#')} if os.path.exists(PRUNE) else set()


def one_round(gen='swiftui.py'):
    sys.path.insert(0, GEN); os.chdir(GEN)
    exec(compile(open(GEN + gen).read(), gen, 'exec'), {'__name__': 'gen'})
    out = tc()
    errs = re.findall(r'^(\S+\.swift):(\d+):(\d+): error: ([^\n]*)', out, flags=re.M)
    added = pruned()
    new, other, cache, reasons = set(), [], {}, {}
    for f, ln, col, msg in errs:
        lines = cache.setdefault(f, open(f).read().split('\n'))
        i = int(ln) - 1
        if i >= 1 and lines[i - 1].strip().startswith('// doc') and '/Gen_' in f:
            tag = lines[i - 1].strip().split(':', 1)[1].split()[0]
            decl = lines[i].strip()
            if re.match(r'(?:@\w+\s+)*(?:public\s+)?(?:struct|class|enum|protocol|extension)\b', decl):
                other.append((f, ln, 'TYPE HEADER ' + tag + ': ' + msg))
            else:
                new.add(tag); reasons[tag] = msg
        else:
            other.append((f, ln, msg))
    new -= added
    redecl = {t for t in new if reasons.get(t, '').startswith('invalid redeclaration')}
    if new - redecl:
        new -= redecl
    if new:
        with open(PRUNE, 'a') as fh:
            for p in sorted(new):
                fh.write(f"{p}\t{reasons.get(p, '')}\n")
    return new, other


if __name__ == '__main__':
    gen = sys.argv[1] if len(sys.argv) > 1 else 'swiftui.py'
    for r in range(1, 40):
        new, other = one_round(gen)
        print(f'round {r}: pruned {len(new)}, remaining non-prunable {len(other)}')
        if not new:
            break
    seen = set()
    for f, ln, m in other:
        key = (os.path.basename(f), ln, m)
        if key not in seen:
            seen.add(key); print(key[0], key[1], key[2][:200])
