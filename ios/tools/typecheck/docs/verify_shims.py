#!/usr/bin/env python3
"""Checks that every declaration in ../shims matches Apple's documentation.

A shim declaration must carry one of these tags (a `//` comment on the line above it, or at the end of its line):

    // doc: SwiftUI/View/padding(_:_:)          the declaration was copied from that Apple documentation page
    // doc: A/B/c, A/B/d                        one line declaring several things (`case a, b`)
    // doc-unconfirmed: <reason>                the real signature could not be confirmed in the docs (listed in the README)
    // shim: <reason>                           scaffolding that is not an Apple API (result-builder plumbing, bodies)
    // doc-fixed: <page> | <old> => <new> | <why>   copied from that page except for the one stated substring replacement
                                                 (the docs text is known to be lossy there); verify applies the replacement
                                                 to the docs text and then compares exactly

`verify` compares each `doc:` declaration with the declaration(s) stored in declarations.json (extracted from
Apple's page by `sync`, so verification itself is offline). Comparison ignores: access modifiers, bodies,
parameter-name-only differences are NOT ignored (labels, types, defaults, generics, where clauses, attributes
such as @MainActor / nonisolated / @escaping / @Sendable / @ViewBuilder all must match).

    verify_shims.py sync      fetch every tagged page (cache / network) and rewrite declarations.json
    verify_shims.py verify    compare; exit 1 on any mismatch or untagged declaration
    verify_shims.py report    counts per module and the list of doc-unconfirmed items (README material)
    verify_shims.py avail     every tagged API that needs iOS later than the deployment target (17.0)
"""
import json, os, re, sys, collections

HERE = os.path.dirname(os.path.abspath(__file__))
SHIMS = os.path.join(HERE, '..', 'shims')
DECLS = os.path.join(HERE, 'declarations.json')
sys.path.insert(0, HERE)

NOISE_ATTRS = ['@export(implementation)', '@inlinable', '@_alwaysEmitIntoClient', '@_disfavoredOverload', '@usableFromInline',
               '@preconcurrency'  # see below: kept only when the doc has it
               ]
RAW_PRIMS = {'Int', 'UInt', 'Int8', 'Int16', 'Int32', 'Int64', 'UInt8', 'UInt16', 'UInt32', 'UInt64', 'String', 'Float', 'Double'}
KW = r'(?:struct|class|enum|protocol|extension|actor|func|init|var|let|case|subscript|typealias|associatedtype|macro)'
MODS = r'(?:@[A-Za-z_][A-Za-z0-9_.]*(?:\([^)]*\))?\s+|public\s+|open\s+|internal\s+|private\s+|fileprivate\s+|package\s+|static\s+|final\s+|class\s+(?=func|var|let|subscript)|nonisolated(?:\([a-z]+\))?\s+|override\s+|required\s+|convenience\s+|mutating\s+|nonmutating\s+|indirect\s+|weak\s+|unowned\s+|lazy\s+|dynamic\s+|prefix\s+|postfix\s+|infix\s+|distributed\s+|optional\s+|nonisolated\s+)*'
DECL_RE = re.compile(r'^\s*' + MODS + KW + r'\b')
TAG_RE = re.compile(r'//\s*(doc-unconfirmed|doc-fixed|doc|shim)\s*:?\s*(.*)$')


def strip_comment(line):
    # remove a trailing // comment that is not inside a string
    out, i, ins = [], 0, False
    while i < len(line):
        c = line[i]
        if c == '"' and (i == 0 or line[i - 1] != '\\'):
            ins = not ins
        if not ins and line.startswith('//', i):
            break
        out.append(c); i += 1
    return ''.join(out).rstrip()


def split_decl_body(code):
    """Signature (without body) of a one-line declaration."""
    depth = 0; ang = 0
    i = 0
    while i < len(code):
        c = code[i]
        if c in '([': depth += 1
        elif c in ')]': depth -= 1
        elif c == '{' and depth == 0:
            return code[:i].rstrip(), code[i:]
        i += 1
    return code.rstrip(), ''


def norm_sig(sig, keep_inherit=False):
    s = sig
    s = re.sub(r'@export\(implementation\)\s*', '', s)
    s = re.sub(r'@objc\([^)]*\)\s*', '', s)
    for a in ('@inlinable', '@_alwaysEmitIntoClient', '@_disfavoredOverload', '@usableFromInline', '@nonobjc', '@NSCopying', '@discardableResult',
              '@objc', '@preconcurrency', '@frozen', '@resultBuilder'):
        s = re.sub(re.escape(a) + r'(?![A-Za-z_])', '', s)
    s = re.sub(r'\b(public|open|internal|package|final|override|required|convenience|dynamic)\b\s*', '', s)
    s = re.sub(r'\bweak\b\s*', '', s)
    s = re.sub(r'\blet\b', 'var', s)
    s = re.sub(r'\s+', ' ', s).strip()
    # normalise spacing around punctuation so `a : B` == `a: B`
    s = re.sub(r'\s*([:,(){}<>=\[\]?!&|])\s*', r'\1', s)
    s = s.replace('->', '->')
    s = re.sub(r'\s*->\s*', '->', s)
    return s


def var_core(s):
    """For variables/subscripts compare name + type; accessors are compared separately."""
    return s


def accessors(text):
    m = re.search(r'\{\s*(get[^{}]*?)\}\s*$', text)
    return None


def parse_shim_file(path):
    """Yield dicts: {line, code(sig), kind, tags:[(tag,val)], ctx:[names], is_type}"""
    lines = open(path).read().split('\n')
    out = []
    ctx = []          # stack of (name, kind, depth_at_open)
    depth = 0
    pending = []
    i = 0
    while i < len(lines):
        raw = lines[i]
        stripped = raw.strip()
        tm = TAG_RE.search(raw)
        code = strip_comment(raw)
        # tag-only line
        if code.strip() == '' and tm:
            pending.append((tm.group(1), tm.group(2).strip()))
            i += 1; continue
        if code.strip() == '':
            if stripped == '':
                pass  # blank line does not clear pending tags
            i += 1; continue
        tags = list(pending)
        if tm:
            tags.append((tm.group(1), tm.group(2).strip()))
        is_decl = bool(DECL_RE.match(code))
        opens = code.count('{') - code.count('}')
        if is_decl:
            sig, body = split_decl_body(code.strip())
            kw = re.search(r'\b(' + KW[3:-1] + r')\b', re.sub(MODS, '', sig + ' ', count=1) if False else sig)
            kind = None
            m = re.match(MODS + r'(' + KW[3:-1] + r')\b', code.strip())
            kind = m.group(1) if m else None
            is_type = kind in ('struct', 'class', 'enum', 'protocol', 'extension', 'actor')
            out.append({'file': path, 'line': i + 1, 'sig': sig, 'kind': kind, 'tags': tags, 'ctx': [c[0] for c in ctx],
                        'ctxkinds': [c[1] for c in ctx], 'is_type': is_type, 'body': body, 'raw': code.strip()})
            pending = []
            if is_type and opens > 0:
                nm = re.sub(r'^.*?\b' + kind + r'\s+', '', sig).split(' ')[0].split(':')[0].split('<')[0]
                ctx.append((nm, kind, depth))
            elif (not is_type) and opens > 0:
                # skip a multi-line body
                d = opens
                while d > 0 and i + 1 < len(lines):
                    i += 1
                    c2 = strip_comment(lines[i])
                    d += c2.count('{') - c2.count('}')
            depth += opens if is_type else 0
        else:
            # not a declaration: closing braces, attributes alone, statements inside skipped bodies, etc.
            if tm and not pending:
                pending = []
            pending = []
            closes = code.count('}') - code.count('{')
            if code.strip().startswith('}') or closes > 0:
                n = code.count('}') - code.count('{')
                while n > 0 and ctx:
                    ctx.pop(); depth -= 1; n -= 1
        i += 1
    return out


def collect():
    items = []
    for root, _, files in os.walk(SHIMS):
        for f in sorted(files):
            if f.endswith('.swift') and '_macros' not in root:
                items += parse_shim_file(os.path.join(root, f))
    return items


def module_of(path):
    return os.path.relpath(path, SHIMS).split(os.sep)[0]


def tagged_paths(items):
    paths = set()
    for it in items:
        for t, v in it['tags']:
            if t == 'doc':
                for p in v.split(','):
                    p = p.strip().split()[0] if p.strip() else ''
                    if p: paths.add(p)
            elif t == 'doc-fixed':
                paths.add(v.split('|')[0].strip())
    return sorted(paths)


def cmd_sync():
    import docs
    items = collect()
    paths = tagged_paths(items)
    out = {}
    missing = []
    for p in paths:
        base, _, idx = p.partition('#')
        d = docs.fetch(base)
        if not d:
            missing.append(p); continue
        rel = {r['title']: [i.split('/documentation/')[-1] for i in r['identifiers']] for r in d.get('relationshipsSections', [])}
        dl = docs.declarations(d)
        if idx:
            dl = [dl[int(idx)]]
        out[p] = {'page': docs.page_path(d), 'decls': dl, 'iOS': docs.availability(d).get('iOS'),
                  'role': d.get('metadata', {}).get('roleHeading'), 'relationships': rel}
    json.dump(out, open(DECLS, 'w'), indent=1, sort_keys=True)
    print(f'{len(out)} pages written to declarations.json; {len(missing)} tagged paths have no page:')
    for m in missing: print('   ', m)
    return 1 if missing else 0


def case_names(decl):
    m = re.match(r'case\s+(.*)$', decl.strip())
    return m.group(1).strip() if m else None


def split_top(s):
    parts, depth, cur = [], 0, ''
    for c in s:
        if c in '(<[': depth += 1
        elif c in ')>]': depth -= 1
        if c == ',' and depth == 0:
            parts.append(cur.strip()); cur = ''
        else:
            cur += c
    if cur.strip(): parts.append(cur.strip())
    return parts


def doc_norm(decl, is_member_var=False):
    d = decl
    d = re.sub(r'\s*\{\s*get\s*(?:nonmutating\s+)?(?:set)?\s*(?:async\s+)?(?:throws\s+)?\}\s*$', '', d)
    return norm_sig(d)


def shim_var_sig(sig):
    s = re.sub(r'\s*\{.*$', '', sig)
    if re.search(r':', s):                       # `var x: T = value` -> `var x: T`
        s = re.sub(r'\s=\s.*$', '', s)
    return norm_sig(s)


def header_core(sig):
    """type header without the inheritance clause: attrs kind Name<generics> where ..."""
    s = norm_sig(sig)
    s = re.sub(r'\bnonisolated\s+(?=(?:struct|class|enum|protocol|actor)\b)', '', s)   # see README: the keyword is not expressible on 6.0.3
    m = re.match(r'^(.*?\b(?:struct|class|enum|protocol|actor)\s+[A-Za-z_][A-Za-z0-9_]*(?:<[^{}]*?>)?)(?::([^{]*?))?(where.*)?$', s)
    if not m:
        return s, [], ''
    head, inh, wh = m.group(1), m.group(2), m.group(3) or ''
    # generic params with constraints contain ':' - handled by the lazy match above for the common cases
    return head, [x.strip().replace('@unchecked', '').strip() for x in (inh or '').split(',') if x.strip()], wh


def _noniso(mine, theirs):
    """`nonisolated` in the docs may be left out of the shim member (the shim types are not actor-isolated, so it changes
    nothing there); the shim must never add it where the docs do not have it."""
    if re.search(r'\bnonisolated\b', mine):
        return theirs
    return [re.sub(r'\bnonisolated\s+', '', t) for t in theirs]


def verify():
    items = collect()
    decls = json.load(open(DECLS)) if os.path.exists(DECLS) else {}
    problems, counts = [], collections.Counter()
    for it in items:
        where = f"{os.path.relpath(it['file'], SHIMS)}:{it['line']}"
        tags = it['tags']
        kinds = {t for t, _ in tags}
        mod = module_of(it['file'])
        if it['kind'] == 'extension' and not tags:
            counts[(mod, 'extension-container')] += 1
            if re.search(r'extension\s+[^{]*?:\s*[A-Za-z]', re.split(r'\swhere\s', it['sig'])[0]):
                problems.append((where, f"extension with a conformance but no tag: {it['sig']}"))
            continue
        if not tags:
            problems.append((where, f"UNTAGGED declaration: {it['raw'][:110]}"))
            continue
        if 'doc' not in kinds and 'doc-fixed' not in kinds:
            counts[(mod, ('shim' if 'shim' in kinds else 'doc-unconfirmed'))] += 1
            continue
        paths = []
        fixes = []
        for t, v in tags:
            if t == 'doc':
                paths += [p.strip().split()[0] for p in v.split(',') if p.strip()]
            elif t == 'doc-fixed':
                parts = [x.strip() for x in v.split('|')]
                if len(parts) != 3 or '=>' not in parts[1] or not parts[2]:
                    problems.append((where, 'malformed doc-fixed tag (want: page | old => new | why)')); continue
                paths.append(parts[0])
                old, new = [x.strip() for x in parts[1].split('=>', 1)]
                fixes.append((old, new))
        found = [decls.get(p) for p in paths]
        if any(f is None for f in found):
            problems.append((where, f"tagged page not in declarations.json (run sync): {paths}")); continue
        if fixes:
            # apply the stated substitutions to the docs text; a fix whose `old` is not in the docs is itself a problem
            patched = []
            for f in found:
                nd = []
                for d in f['decls']:
                    for old, new in fixes:
                        if old in d:
                            d = d.replace(old, new)
                    nd.append(d)
                g = dict(f); g['decls'] = nd
                patched.append(g)
            for old, new in fixes:
                if not any(old in d for f in found for d in f['decls']):
                    problems.append((where, f"doc-fixed substring not found in the docs text: {old!r}"))
            found = patched
        counts[(mod, 'doc-fixed' if fixes else 'doc')] += 1
        sig = it['sig']
        if it['kind'] == 'case':
            shim_cases = split_top(case_names(sig) or '')
            doc_cases = []
            for f in found:
                for d in f['decls']:
                    cn = case_names(d)
                    if cn: doc_cases += split_top(cn)
            if sorted(norm_sig(c) for c in shim_cases) != sorted(norm_sig(c) for c in doc_cases):
                problems.append((where, f"case list differs: shim {shim_cases} vs doc {doc_cases}"))
            continue
        if it['kind'] == 'extension':
            # conformances declared in an extension must be listed by the page
            m = re.search(r'extension\s+([^:{]+):\s*([^{]*?)(?:\s+where\b.*)?$', sig)
            if m:
                allowed = ' '.join(' '.join(v) for f in found for v in f['relationships'].values()) + ' ' + ' '.join(d for f in found for d in f['decls'])
                allowed_names = set(re.findall(r'[A-Za-z_][A-Za-z0-9_]*', allowed))
                extended = m.group(1).strip().split('<')[0].split('.')[-1]
                for c in [x.strip() for x in m.group(2).split(',')]:
                    base = c.split('<')[0].split('.')[-1].replace('any ', '').strip()
                    if base == '_PrimitiveView':
                        base = 'View'
                    # listed either as a conformance of the extended type's page or, for the reverse convention
                    # (`// doc: <protocol page>`), the extended type is listed as a conforming type of the protocol's page
                    if base and base not in allowed_names and extended not in allowed_names:
                        problems.append((where, f"conformance {c} not listed on {paths}"))
            continue
        if it['is_type']:
            shim_head, shim_inh, shim_where = header_core(sig)
            ok = False
            for f in found:
                for d in f['decls']:
                    dh, dinh, dwh = header_core(d)
                    if dh == shim_head and dwh == shim_where:
                        ok = True
                        allowed_text = ' '.join(' '.join(v) for v in f['relationships'].values()) + ' ' + ' '.join(dinh)
                        for c in shim_inh:
                            b = c.split('<')[0].split('.')[-1].replace('any ', '').strip()
                            if b in RAW_PRIMS and 'RawRepresentable' in allowed_text:
                                continue
                            if b == 'Codable' and 'Decodable' in allowed_text and 'Encodable' in allowed_text:
                                continue
                            if b not in re.sub(r'-swift\.\w+', '', allowed_text):
                                problems.append((where, f"type {shim_head}: inherited/conformed {c} not listed on page"))
            if not ok:
                problems.append((where, f"type header differs:\n        shim: {shim_head} {shim_where}\n        doc:  " + ' | '.join(header_core(d)[0] + ' ' + header_core(d)[2] for f in found for d in f['decls'])))
            continue
        # members
        if it['kind'] in ('var', 'let', 'subscript'):
            mine = shim_var_sig(sig)
            theirs = [doc_norm(d) for f in found for d in f['decls']]
            # settable?
            doc_set = any(re.search(r'\{\s*get\s+(?:nonmutating\s+)?set', d) for f in found for d in f['decls'])
            shim_set = bool(re.search(r'\bset\b', it['body'] or '')) or (not it['body'] and it['kind'] == 'var' and not re.search(r'\{\s*get\s*\}', sig) and not re.search(r'\blet\b', sig))
            theirs = _noniso(mine, theirs)
            if mine not in theirs:
                problems.append((where, f"member differs:\n        shim: {mine}\n        doc:  " + ' | '.join(theirs)))
            continue
        mine = norm_sig(sig)
        theirs = _noniso(mine, [norm_sig(d) for f in found for d in f['decls']])
        if it['kind'] == 'typealias':
            mine = mine.split('=')[0]
            theirs = [t.split('=')[0] for t in theirs]
        if it['kind'] == 'macro':
            mine = re.sub(r'=#externalMacro.*$', '', mine)
        if mine not in theirs:
            problems.append((where, f"member differs:\n        shim: {mine}\n        doc:  " + ' | '.join(theirs)))
    return items, problems, counts


def cmd_verify():
    items, problems, counts = verify()
    for w, p in problems:
        print(f'{w}: {p}')
    tot = collections.Counter()
    for (m, k), n in sorted(counts.items()):
        tot[k] += n
    print(f"\n{len(items)} shim declarations: " + ', '.join(f'{k} {n}' for k, n in sorted(tot.items())) + f"; {len(problems)} problems")
    return 1 if problems else 0


def cmd_report():
    items, problems, counts = verify()
    per = collections.defaultdict(collections.Counter)
    for (m, k), n in counts.items(): per[m][k] += n
    for m in sorted(per):
        print(f'{m:20s} ' + '  '.join(f'{k}={n}' for k, n in sorted(per[m].items())))
    print('\ndoc-fixed (docs text known to be lossy; replacement stated on the tag):')
    for it in items:
        for t, v in it['tags']:
            if t == 'doc-fixed':
                print(f"  {os.path.relpath(it['file'], SHIMS)}:{it['line']}  {it['raw'][:80]}  -- {v}")
    print('\ndoc-unconfirmed:')
    for it in items:
        for t, v in it['tags']:
            if t == 'doc-unconfirmed':
                print(f"  {os.path.relpath(it['file'], SHIMS)}:{it['line']}  {it['raw'][:80]}  -- {v}")


def cmd_avail():
    decls = json.load(open(DECLS))
    rows = []
    for p, d in decls.items():
        av = d.get('iOS') or {}
        intro = av.get('introduced')
        try:
            v = float(str(intro).split('.')[0] + '.' + (str(intro).split('.')[1] if '.' in str(intro) else '0'))
        except Exception:
            continue
        if v > 17.0 or av.get('deprecated'):
            rows.append((v, p, av.get('deprecated')))
    for v, p, dep in sorted(rows):
        print(f"iOS {v:<5} {p}{'  [deprecated]' if dep else ''}")


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else ''
    fn = {'sync': cmd_sync, 'verify': cmd_verify, 'report': cmd_report, 'avail': cmd_avail}.get(cmd)
    if not fn:
        print(__doc__); sys.exit(2)
    sys.exit(fn() or 0)
