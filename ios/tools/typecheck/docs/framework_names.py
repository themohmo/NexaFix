#!/usr/bin/env python3
"""Module-level type names of Apple frameworks, from Apple's documentation index, and the name-collision lint.

The shims define only part of each framework, so a name clash between NexaFixCore / the app and a type the shims do
NOT define would pass the typecheck here and break in Xcode. This closes that gap by checking against Apple's
complete list of module-level types.

    framework_names.py fetch       download the index of each framework in FRAMEWORKS (network) -> framework-types.json
    framework_names.py collisions  Core public types and app types that share a name with a type of an imported framework
"""
import json, os, re, sys, urllib.request, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'framework-types.json')
IOS = os.path.abspath(os.path.join(HERE, '..', '..', '..'))
# The app's imports plus what they re-export on iOS (SwiftUI re-exports CoreGraphics ... through UIKit/Foundation).
FRAMEWORKS = ['swiftui', 'uikit', 'arkit', 'realitykit', 'roomplan', 'avfoundation', 'accessibility', 'foundation', 'coregraphics',
              'quartzcore', 'simd', 'swift', 'developertoolssupport', 'coreimage', 'coretext', 'uniformtypeidentifiers', 'os',
              'corefoundation', 'coremedia', 'corevideo', 'metal']
TYPE_KINDS = {'struct', 'class', 'enum', 'protocol', 'typealias', 'macro', 'actor'}


def cmd_fetch():
    out = {}
    for m in FRAMEWORKS:
        req = urllib.request.Request(f'https://developer.apple.com/tutorials/data/index/{m}', headers={'User-Agent': 'nexafix-typecheck'})
        d = json.load(urllib.request.urlopen(req, timeout=120))
        names = set()

        def walk(n):
            path = n.get('path') or ''
            if n.get('type') in TYPE_KINDS and re.fullmatch(r'/documentation/' + m + r'/[^/]+', path) and n.get('title'):
                names.add(re.split(r'[<\s(]', n['title'].lstrip('#'))[0])
            for c in n.get('children', []) or []:
                walk(c)
        for root in d.get('interfaceLanguages', {}).get('swift', []):
            walk(root)
        out[m] = sorted(names)
        print(f'{m:24s} {len(names)} module-level types')
    json.dump(out, open(OUT, 'w'), indent=0, sort_keys=True)


def source_types(root, public_only):
    pat = re.compile(r'^\s*(?:@\w+(?:\([^)]*\))?\s+)*((?:public|open|package)\s+)?(?:final\s+)?(?:indirect\s+)?(struct|class|enum|protocol|typealias|actor)\s+([A-Za-z_][A-Za-z0-9_]*)', re.M)
    found = {}
    for dp, _, fs in os.walk(root):
        if '.build' in dp or '/Tests' in dp:
            continue
        for f in fs:
            if f.endswith('.swift'):
                p = os.path.join(dp, f)
                for i, line in enumerate(open(p, errors='ignore').read().split('\n'), 1):
                    m = pat.match(line)
                    if m and (m.group(1) or not public_only) and not line.startswith(' ') and not line.startswith('\t'):
                        found.setdefault(m.group(3), []).append(f'{os.path.relpath(p, IOS)}:{i}')
    return found


def cmd_collisions():
    fw = json.load(open(OUT))
    apple = {}
    for m, names in fw.items():
        for n in names:
            apple.setdefault(n, []).append(m)
    core = source_types(os.path.join(IOS, 'NexaFixCore', 'Sources'), True)
    app = source_types(os.path.join(IOS, 'NexaFixScan'), False)
    bad = 0
    print('NexaFixCore public type vs an imported framework (AMBIGUOUS where both are imported):')
    for n in sorted(core):
        if n in apple:
            bad += 1; print(f'  {n}: Core {core[n][0]}  /  {", ".join(apple[n])}')
    print('app type vs NexaFixCore type (the app one silently shadows the Core one):')
    for n in sorted(app):
        if n in core:
            bad += 1; print(f'  {n}: app {app[n][0]}  /  Core {core[n][0]}')
    print('app type vs an Apple type (the app one shadows the Apple one inside the app; informational):')
    k = 0
    for n in sorted(app):
        if n in apple:
            k += 1; print(f'  {n}: app {app[n][0]}  /  {", ".join(apple[n])}')
    if k == 0: print('  none')
    print(f'\n{len(core)} Core public types, {len(app)} app types, {sum(len(v) for v in fw.values())} Apple module-level types checked; {bad} Core-related collisions')
    return 1 if bad else 0


if __name__ == '__main__':
    fn = {'fetch': cmd_fetch, 'collisions': cmd_collisions}.get(sys.argv[1] if len(sys.argv) > 1 else '')
    if not fn: print(__doc__); sys.exit(2)
    sys.exit(fn() or 0)
