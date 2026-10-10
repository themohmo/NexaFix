#!/usr/bin/env python3
"""Apple documentation lookup used to write and audit the typecheck shims.

Apple publishes the JSON behind developer.apple.com/documentation at
    https://developer.apple.com/tutorials/data/documentation/<framework>/<symbol path lowercased>.json
Each symbol page carries its Swift declaration(s) token by token (attributes, labels, generics, defaults,
availability). The shims under ../shims copy those declarations; `verify` (verify_shims.py) re-checks them.

Commands (cache: $NEXAFIX_DOCS_CACHE, default ~/.cache/nexafix-apple-docs; network needed only on a miss)
    docs.py show   swiftui/view/padding(_:_:)       declarations + availability + abstract of one page
    docs.py members swiftui/text                   list the member pages a type/protocol page links to
    docs.py crawl  swiftui/view [--depth 1]        fetch the page and all its member pages (recursively)
    docs.py grep   'func padding'                  regex search over every cached declaration
"""
import json, os, re, sys, time, urllib.request, urllib.error, hashlib, concurrent.futures as cf

BASE = 'https://developer.apple.com/tutorials/data/documentation/'
CACHE = os.environ.get('NEXAFIX_DOCS_CACHE', os.path.expanduser('~/.cache/nexafix-apple-docs'))


def norm(path):
    p = path.strip().strip('/')
    p = re.sub(r'^(https://developer\.apple\.com)?/?(tutorials/data/)?documentation/', '', p)
    p = re.sub(r'\.json$', '', p)
    return p.lower()


def cache_file(path):
    p = norm(path)
    safe = re.sub(r'[^a-z0-9_.()\-]+', '_', p.replace('/', '__'))
    if len(safe) > 150:
        safe = safe[:120] + '_' + hashlib.sha1(p.encode()).hexdigest()[:12]
    return os.path.join(CACHE, safe + '.json')


def fetch(path, retries=3):
    """Return the page JSON, or None if Apple has no such page (404). Cached on disk."""
    os.makedirs(CACHE, exist_ok=True)
    f = cache_file(path)
    if os.path.exists(f):
        d = json.load(open(f))
        return None if d.get('_404') else d
    url = BASE + urllib.request.quote(norm(path), safe="/()_:,-.~!$&'*+;=@") + '.json'
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'nexafix-typecheck-docs'}), timeout=40) as r:
                data = r.read()
            open(f, 'wb').write(data)
            return json.loads(data)
        except urllib.error.HTTPError as e:
            if e.code == 404:
                json.dump({'_404': True}, open(f, 'w'))
                return None
            time.sleep(1.5 * (attempt + 1))
        except Exception:
            time.sleep(1.5 * (attempt + 1))
    return None


def text_of(tokens):
    return ''.join(t.get('text', '') for t in tokens)


def declarations(doc, platform='iOS'):
    """All Swift declarations on a page that apply to `platform`, as plain text (a page may carry several
    for one name: overloads, or one per platform family). Whitespace-trimmed."""
    out = []
    for sec in doc.get('primaryContentSections', []):
        if sec.get('kind') == 'declarations':
            for d in sec.get('declarations', []):
                if 'swift' not in d.get('languages', ['swift']):
                    continue
                plats = d.get('platforms') or []
                if platform and plats and platform not in plats:
                    continue
                out.append(re.sub(r'\s*\n\s*', ' ', text_of(d['tokens'])).strip())
    return out


def availability(doc):
    r = {}
    for p in doc.get('metadata', {}).get('platforms', []):
        r[p['name']] = {'introduced': p.get('introducedAt'), 'deprecated': p.get('deprecated', False),
                        'unavailable': p.get('unavailable', False), 'beta': p.get('beta', False)}
    return r


def page_path(doc):
    u = doc.get('identifier', {}).get('url', '')
    return u.split('/documentation/', 1)[-1]


def members(doc):
    """[(title, fragments_text, path)] for everything the page lists in its topic sections."""
    refs = doc.get('references', {})
    out, seen = [], set()
    for sec in doc.get('topicSections', []):
        for ident in sec.get('identifiers', []):
            r = refs.get(ident)
            if not r or ident in seen:
                continue
            seen.add(ident)
            url = r.get('url', '')
            if '/documentation/' not in url:
                continue
            out.append((r.get('title', ''), text_of(r.get('fragments', [])), url.split('/documentation/', 1)[1]))
    return out


def crawl(path, depth=1, workers=6, quiet=False):
    seen, level, n = set(), [norm(path)], 0
    for d in range(depth + 1):
        nxt = []
        with cf.ThreadPoolExecutor(workers) as ex:
            docs = list(ex.map(fetch, level))
        for p, doc in zip(level, docs):
            if p in seen:
                continue
            seen.add(p); n += 1
            if doc and d < depth:
                for _t, _f, mp in members(doc):
                    if norm(mp) not in seen:
                        nxt.append(norm(mp))
        level = list(dict.fromkeys(nxt))
        if not quiet:
            print(f'crawl {path}: depth {d} done, {n} pages, {len(level)} queued', file=sys.stderr)
    return seen


def iter_cache():
    if not os.path.isdir(CACHE):
        return
    for fn in os.listdir(CACHE):
        if fn.endswith('.json'):
            try:
                d = json.load(open(os.path.join(CACHE, fn)))
            except Exception:
                continue
            if not d.get('_404'):
                yield d


_INDEX = None


def index():
    """{lowercased path: page JSON} over everything in the cache."""
    global _INDEX
    if _INDEX is None:
        _INDEX = {}
        for d in iter_cache():
            _INDEX[page_path(d).lower()] = d
    return _INDEX


def pages_named(parent, name):
    """Every cached page for member `name` (any overload / labels) of `parent`, e.g. ('SwiftUI/View', 'padding')."""
    pre = parent.lower() + '/' + name.lower()
    out = []
    for k, d in index().items():
        if k == pre or k.startswith(pre + '(') or k.startswith(pre + '-'):
            out.append(d)
    return sorted(out, key=lambda d: page_path(d))


def swift_body(decl, self_ok):
    """A body for a shim declaration: `self` for modifiers that return `some P` where Self is known to conform to P,
    else a trap. self_ok: set of protocol names the extension's Self conforms to (e.g. {'View'})."""
    d = decl.strip()
    if re.search(r'\bfunc\b', d):
        m = re.search(r'->\s*some\s+([A-Za-z]+)\b\s*(?:where\b.*)?$', d)
        if self_ok and m and m.group(1) in self_ok and not re.search(r'<[A-Za-z]+>\s*$', d):
            return ' { self }'
        return ' { fatalError() }'
    if re.match(r'(?:@\w+(?:\([^)]*\))?\s+|nonisolated\s+|static\s+|final\s+|class\s+|convenience\s+|required\s+|override\s+|dynamic\s+)*init\b', d):
        return ' { fatalError() }'
    return ''


def shimify(decl, ctx):
    """Turn a documented member declaration into compilable shim source.
    ctx: 'view-ext' (extension of a View-conforming type: `some View` modifiers return self), 'type' (body in a
    struct/class/enum/extension), 'protocol' (requirement only: no body)."""
    d = re.sub(r'@export\(implementation\)\s*', '', decl)
    d = re.sub(r'@(?:nonobjc|NSCopying|inlinable|_alwaysEmitIntoClient)\s*', '', d)
    if ctx == 'protocol':
        return d
    m = re.search(r'\s*\{\s*get(\s+nonmutating\s+set|\s+set)?\s*(async\s+)?(throws\s+)?\}\s*$', d)
    if m and re.match(r'.*\b(var|subscript)\b', d):
        head = d[:m.start()]
        head = re.sub(r'\bweak\s+', '', head)
        setter = m.group(1)
        if not setter:
            return head + ' { fatalError() }'
        if 'nonmutating' in setter:
            return head + ' { get { fatalError() } nonmutating set { } }'
        return head + ' { get { fatalError() } set { } }'
    if re.match(r'.*\b(var|let)\b[^(]*:[^=]*$', d) and not re.search(r'\bfunc\b|\binit\b', d):
        if d.startswith('case'):
            return d
        # a documented stored property (`var x: T`, `weak var x: T?`, `let x: T`): optional ones default to nil, the rest
        # are computed so the shim type needs no initialiser; `let` becomes a get-only computed property
        plain = re.sub(r'\bweak\s+', '', d)
        if re.search(r'\blet\b', plain):
            return re.sub(r'\blet\b', 'var', plain) + ' { fatalError() }'
        if re.search(r'[?!]\s*$', plain):
            return plain + ' = nil'
        return plain + ' { get { fatalError() } set { } }'
    self_ok = {'View'} if ctx == 'view-ext' else (set(ctx[5:].split(',')) if ctx.startswith('self:') else set())
    return d + swift_body(d, self_ok)


def cmd_emit(args):
    """emit [--ctx view-ext|type|protocol] <doc path>...  -> tagged shim lines (iOS declarations only)."""
    ctx = 'type'
    if '--ctx' in args:
        i = args.index('--ctx'); ctx = args[i + 1]; args = args[:i] + args[i + 2:]
    for p in args:
        d = fetch(p)
        if not d:
            print(f'    // NO PAGE: {p}'); continue
        av = availability(d).get('iOS', {})
        for decl in declarations(d):
            note = ''
            if av.get('introduced') and av['introduced'] not in ('None',):
                try:
                    if float(av['introduced'].split('.')[0]) > 17: note += f"  [iOS {av['introduced']}]"
                except Exception: pass
            if av.get('deprecated'): note += '  [deprecated]'
            print(f"    // doc: {page_path(d)}{note}")
            print('    ' + shimify(decl, ctx))


def cmd_scaffold(args):
    """scaffold <Module/Parent> <name> [name...] [--view]  -> shim lines with // doc: tags for every cached overload."""
    view = '--view' in args
    args = [a for a in args if a != '--view']
    parent, names = args[0], args[1:]
    for n in names:
        pgs = pages_named(parent, n)
        if not pgs:
            print(f'    // NO CACHED PAGE for {parent}/{n}')
        for d in pgs:
            av = availability(d).get('iOS', {})
            if av.get('unavailable'):
                continue
            for decl in declarations(d):
                tags = f"    // doc: {page_path(d)}"
                if av.get('introduced') and av['introduced'] not in ('13.0', '1.0') and not av.get('introduced', '').startswith('1.'):
                    tags += f"   [iOS {av['introduced']}]"
                if av.get('deprecated'):
                    tags += '   [deprecated]'
                print(tags)
                print('    ' + decl + swift_body(decl, {'View'} if view else set()))


def cmd_dump(args):
    """dump <path> [--nested]: the page's declaration and every member page's declarations (one level;
    --nested also descends into member types)."""
    nested = '--nested' in args
    args = [a for a in args if a != '--nested']

    def one(path, indent):
        d = fetch(path)
        if not d:
            print(' ' * indent + f'NO PAGE {path}'); return
        av = availability(d).get('iOS', {})
        tag = f"[iOS {av.get('introduced')}]" if av.get('introduced') else ''
        if av.get('deprecated'): tag += '[deprecated]'
        if av.get('unavailable'): tag += '[unavailable on iOS]'
        decls = declarations(d)
        for x in decls or ['(no declaration)']:
            print(' ' * indent + f'{x}   // {page_path(d)} {tag}')
        return d

    for p in args:
        d = one(p, 0)
        if not d: continue
        rel = {r['title']: [i.split('/')[-1] for i in r['identifiers']] for r in d.get('relationshipsSections', [])}
        for k, v in rel.items():
            print(f'    {k}: {", ".join(v)}')
        for t, f, mp in members(d):
            md = fetch(mp)
            if md and md.get('metadata', {}).get('role') == 'collectionGroup':
                continue
            kind = (md or {}).get('metadata', {}).get('symbolKind', '')
            one(mp, 4)
            if nested and md and kind in ('struct', 'class', 'enum', 'protocol'):
                for t2, f2, mp2 in members(md):
                    one(mp2, 8)


def cmd_find(args):
    """find <parent path> <regex on member name>  -> every cached member page under parent whose name matches."""
    parent, rx = args[0].lower(), re.compile(args[1])
    for k, d in sorted(index().items()):
        if k.startswith(parent + '/') and '/' not in k[len(parent) + 1:]:
            name = k[len(parent) + 1:]
            if rx.search(name):
                av = availability(d).get('iOS', {})
                for x in declarations(d) or ['(none)']:
                    print(f"{page_path(d)} [{av.get('introduced')}{'/dep' if av.get('deprecated') else ''}]  {x}")


def _ref_urls():
    """Every /documentation/... URL that any cached page links to. Kept in a side file and updated incrementally
    (only cache files not scanned before are parsed)."""
    idxf = os.path.join(CACHE, '_refs_urls.json')
    st = json.load(open(idxf)) if os.path.exists(idxf) else {'scanned': [], 'urls': []}
    scanned, urls = set(st['scanned']), set(st['urls'])
    changed = False
    for fn in os.listdir(CACHE):
        if not fn.endswith('.json') or fn.startswith('_') or fn in scanned:
            continue
        scanned.add(fn); changed = True
        try:
            d = json.load(open(os.path.join(CACHE, fn)))
        except Exception:
            continue
        if d.get('_404'):
            continue
        for r in d.get('references', {}).values():
            u = r.get('url', '')
            if u.startswith('/documentation/'):
                urls.add(u[len('/documentation/'):])
    if changed:
        json.dump({'scanned': sorted(scanned), 'urls': sorted(urls)}, open(idxf, 'w'))
    return urls


def fetch_refs(prefixes, workers=6):
    """Fetch every page linked from any cached page whose path starts with one of the prefixes. Returns the count."""
    urls = _ref_urls()
    pres = [norm(p) for p in prefixes]
    todo = sorted(u for u in urls if any(u.lower().startswith(p) for p in pres))
    todo = [u for u in todo if not os.path.exists(cache_file(u))]
    if todo:
        with cf.ThreadPoolExecutor(workers) as ex:
            list(ex.map(fetch, todo))
    return len(todo)


def cmd_refs(args):
    """refs <path prefix>...: fetch every page that ANY cached page links to under the prefix (this finds the
    per-platform overload pages like init(color:)-5zgo5 that a type's topic list does not name)."""
    n = fetch_refs(args)
    print(f'{n} referenced pages fetched', file=sys.stderr)


def cmd_show(args):
    for p in args:
        d = fetch(p)
        if not d:
            print(f'{p}: NO PAGE (404)'); continue
        m = d.get('metadata', {})
        print(f"== {page_path(d)}  [{m.get('roleHeading')}]  " +
              ' '.join(f"{k}:{v['introduced']}{'(dep)' if v['deprecated'] else ''}{'(beta)' if v['beta'] else ''}" for k, v in availability(d).items() if k in ('iOS',)))
        for x in declarations(d):
            print('   ', x)
        ab = text_of(d.get('abstract', []))
        if ab: print('    --', ab[:200])


def cmd_members(args):
    for p in args:
        d = fetch(p)
        if not d: print('NO PAGE', p); continue
        for sec in d.get('topicSections', []):
            print('##', sec.get('title'))
        for t, f, mp in members(d):
            print(f'{mp}\t{f}')


def cmd_crawl(args):
    depth = 1
    if '--depth' in args:
        i = args.index('--depth'); depth = int(args[i + 1]); args = args[:i] + args[i + 2:]
    for p in args:
        crawl(p, depth)


def cmd_grep(args):
    rx = re.compile(args[0])
    for d in iter_cache():
        for x in declarations(d):
            if rx.search(x):
                print(page_path(d), '::', x)


if __name__ == '__main__':
    if len(sys.argv) < 2 or sys.argv[1] not in ('show', 'members', 'crawl', 'grep', 'scaffold', 'dump', 'emit', 'find', 'refs'):
        print(__doc__); sys.exit(1)
    {'show': cmd_show, 'members': cmd_members, 'crawl': cmd_crawl, 'grep': cmd_grep, 'scaffold': cmd_scaffold, 'dump': cmd_dump, 'emit': cmd_emit, 'find': cmd_find, 'refs': cmd_refs}[sys.argv[1]](sys.argv[2:])
