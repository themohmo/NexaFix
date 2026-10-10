"""Shared helpers of the shim generators in this directory (see ../../README.md, "Regenerating").

Each generator (swiftui.py, uikit.py, arkit.py, realitykit.py, roomplan.py, cg.py, small.py) imports this, reads Apple's
documentation pages through ../docs.py (cache: $NEXAFIX_DOCS_CACHE, default ~/.cache/nexafix-apple-docs; `docs.py crawl` /
`docs.py refs` fill it) and writes declarations into ../../shims, each tagged with the page it came from.
"""
import sys, os, io, re, contextlib
GEN_DIR = os.path.dirname(os.path.abspath(__file__))
TC_DIR = os.path.abspath(os.path.join(GEN_DIR, '..', '..'))
SHIMS = os.path.join(TC_DIR, 'shims') + '/'
sys.path.insert(0, os.path.join(TC_DIR, 'docs'))
import docs

def pub(sh, on=True, cls_open=False):
    if not on or sh.lstrip().startswith('case '):
        return sh
    m = re.match(r'^((?:@[A-Za-z_][A-Za-z0-9_.]*(?:\([^)]*\))?\s+)*)(.*)$', sh)
    rest = m.group(2)
    acc = 'public'
    # members of an Objective-C class that app code may override must be `open` (UIKit/ARKit classes are open)
    if cls_open and re.match(r'^(nonisolated\s+)?(class\s+)?(func|var|subscript)\b', rest) and not rest.lstrip().startswith(('static', 'final')):
        acc = 'open'
    return m.group(1) + acc + ' ' + rest

def emit_members(paths, ctx='type', indent='    ', public=True, cls_open=False):
    """Return tagged shim lines for doc pages."""
    out = []
    for p in paths:
        d = docs.fetch(p)
        if not d:
            out.append(f'{indent}// NO PAGE: {p}'); continue
        av = docs.availability(d).get('iOS', {})
        PR = load_prune()
        _decls = docs.declarations(d)
        for _i, decl in enumerate(_decls):
            _key = docs.page_path(d) if len(_decls) == 1 else f'{docs.page_path(d)}#{_i}'
            if _key in PR:
                continue
            note = ''
            try:
                if av.get('introduced') and float(av['introduced'].split('.')[0]) > 17: note += f"  [iOS {av['introduced']}]"
            except Exception: pass
            if av.get('deprecated'): note += '  [deprecated]'
            out.append(f"{indent}// doc: {_key}{note}")
            sh = docs.shimify(decl, ctx)
            out.append(indent + pub(sh, public and ctx != 'protocol', cls_open))
    return '\n'.join(out)

SHIM_PATTERNS = [
    (r'^public (required )?init\?\(coder: NSCoder\)', 'NSCoding requirement, not an Apple signature'),
    (r'^public func encode\(with ', 'NSCoding requirement'),
    (r'^public func copy\(with ', 'NSCopying requirement'),
    (r'^public static var supportsSecureCoding', 'NSSecureCoding requirement'),
    (r'^public (convenience )?(override )?init\(\)', 'inherited NSObject initializer made explicit so subclasses and callers compile'),
    (r'^public (override )?init\(nibName', 'inherited designated initializer made explicit'),
    (r'^public (override )?init\(frame', 'inherited designated initializer made explicit'),
    (r'^public init\(rawValue: ', 'RawRepresentable / OptionSet storage'),
    (r'^public let rawValue', 'RawRepresentable / OptionSet storage'),
    (r'^public init\(stringLiteral', 'ExpressibleByStringLiteral requirement'),
]
# Declarations whose documented text is known to be lossy: (page, old text, new text, reason). The tag line becomes
# `// doc-fixed: page | old => new | reason`, which docs/verify_shims.py applies to the docs text before comparing, so a
# fix can change exactly the stated substring and nothing else.
DOC_FIXES = [
    ('SwiftUI/View/toolbar(content:)', '@ContentBuilder content: () -> Content) -> some View where Content : ToolbarContent', '@ToolbarContentBuilder content: () -> Content) -> some View where Content : ToolbarContent',
     'the docs print every result-builder attribute as ContentBuilder; for a ToolbarContent closure the builder has to be ToolbarContentBuilder (ViewBuilder cannot build ToolbarItem)'),
    ('SwiftUI/View/toolbar(content:)-5w0tj', '@ContentBuilder content: () -> Content) -> some View where Content : ToolbarContent', '@ToolbarContentBuilder content: () -> Content) -> some View where Content : ToolbarContent',
     'the docs print every result-builder attribute as ContentBuilder; for a ToolbarContent closure the builder has to be ToolbarContentBuilder (ViewBuilder cannot build ToolbarItem)'),
    ('SwiftUI/PresentationDetent/Context', '@dynamicMemberLookup ', '',
     'a @dynamicMemberLookup type needs a subscript(dynamicMember:) that the docs do not list; the shim type is never looked up by key path'),
]

def apply_doc_fixes(text):
    lines = text.split('\n')
    for i, l in enumerate(lines[:-1]):
        m = re.match(r'^(\s*)// doc: (\S+)', l)
        if not m:
            continue
        for page, old, new, why in DOC_FIXES:
            if m.group(2) == page and old in lines[i + 1]:
                lines[i] = f"{m.group(1)}// doc-fixed: {page} | {old} => {new} | {why}"
                lines[i + 1] = lines[i + 1].replace(old, new)
    return '\n'.join(lines)

def finalize(text):
    """Insert `// shim:` tags before scaffolding declarations that carry no tag, and a `// doc:` tag before conformance
    extensions (`extension Rectangle: InsettableShape`), whose conformance the verifier then checks against the page."""
    import re as _re
    out = []
    lines = text.split('\n')

    def tagged_above():
        # the contiguous comment block right above (a tag may sit in the first line of a multi-line comment)
        j = len(out) - 1
        while j >= 0 and out[j].strip().startswith('//'):
            if _re.match(r'//\s*(doc|doc-fixed|doc-unconfirmed|shim)\b', out[j].strip()):
                return True
            j -= 1
        return False

    text = apply_doc_fixes(text)
    lines = text.split('\n')
    for i, l in enumerate(lines):
        st = l.strip()
        tagged = tagged_above()
        if not tagged:
            mx = _re.match(r'^extension ([A-Za-z0-9_.]+)(?:<[^>]*>)?\s*:\s*([^{]*?)\s*(?:where\b[^{]*)?\{', st)
            if mx:
                prefix = os.environ.get('SHIM_MODULE', 'SwiftUI')
                first = mx.group(2).split(',')[0].strip()
                if first.startswith('_'):
                    out.append(l[:len(l) - len(l.lstrip())] + '// shim: primitive-view / toolbar / gesture plumbing conformance')
                else:
                    out.append(l[:len(l) - len(l.lstrip())] + '// doc: ' + prefix + '/' + mx.group(1).replace('.', '/'))
                tagged = True
        if not tagged:
            for pat, why in SHIM_PATTERNS:
                if _re.match(pat, st):
                    out.append(l[:len(l) - len(l.lstrip())] + '// shim: ' + why)
                    break
        out.append(l)
    return '\n'.join(out)


# ------------------------------------------------------------------ whole-type emission
SAFE_CONF = ['Equatable', 'Hashable', 'Comparable', 'Sendable', 'Identifiable', 'CaseIterable', 'Codable', 'ShapeStyle', 'OptionSet']
PRUNE_FILE = os.path.join(GEN_DIR, 'prune.txt')

def _read_prune():
    """prune.txt: `page<TAB>reason` per line, '#' lines are comments. Declarations on it are not emitted."""
    if not os.path.exists(PRUNE_FILE):
        return set()
    return {l.split('\t')[0].strip() for l in open(PRUNE_FILE) if l.strip() and not l.startswith('#')}

def load_prune():
    return _read_prune()

def _ios(d):
    return docs.availability(d).get('iOS')

_REFS_DONE = set()

def member_pages(path):
    """All documented members of a type page that apply to iOS: the pages its topic lists name (collection groups
    flattened) PLUS every cached page one path segment below it (this picks up the per-overload pages such as
    ForEach/init(_:content:)-6if9a that no topic list names). Fetches linked pages on first use."""
    d = docs.fetch(path)
    if not d:
        return []
    pp = docs.page_path(d)
    if pp.lower() not in _REFS_DONE:
        _REFS_DONE.add(pp.lower())
        if docs.fetch_refs([pp]):
            docs._INDEX = None
    out = []
    def flatten(p):
        dd = docs.fetch(p)
        if not dd: return
        for t, f, mp in docs.members(dd):
            md = docs.fetch(mp)
            if not md: continue
            role = md.get('metadata', {}).get('role')
            if role in ('collectionGroup', 'collection', 'article', 'sampleCode'):
                flatten(mp); continue
            if role == 'symbol':
                out.append(md)
    flatten(path)
    pre = pp.lower() + '/'
    for k, md in docs.index().items():
        if k.startswith(pre) and '/' not in k[len(pre):] and md.get('metadata', {}).get('role') == 'symbol':
            out.append(md)
    res, seen_p = [], set()
    for md in out:
        av = _ios(md)
        if av is None or av.get('unavailable'):
            continue
        pth = docs.page_path(md)
        if pth in seen_p: continue
        seen_p.add(pth); res.append(md)
    return res

def _split_top(s, seps):
    parts, depth, cur, i = [], 0, '', 0
    while i < len(s):
        c = s[i]
        if c in '<([': depth += 1
        elif c in '>)]': depth -= 1
        matched = None
        if depth == 0:
            for sep in seps:
                if s.startswith(sep, i): matched = sep; break
        if matched:
            parts.append(cur); cur = ''; i += len(matched); continue
        cur += c; i += 1
    parts.append(cur)
    return [p.strip() for p in parts if p.strip()]

def constraint_clause(md):
    """The `where` clause of the constrained extension a member lives in ('' if none), read from the page's
    'Available when ...' metadata."""
    cf = md.get('metadata', {}).get('conformance')
    if not cf or 'availabilityPrefix' not in cf:
        return ''
    t = ''.join(x.get('code') or x.get('text', '') for x in cf.get('constraints', [])).strip().rstrip('.')
    items = []
    for chunk in _split_top(t, [', and ', ' and ', ', ']):
        chunk = re.sub(r'^and\s+', '', chunk)
        m = re.match(r'^(.+?) conforms to (.+)$', chunk)
        if m:
            items.append(f'{m.group(1).strip()}: {m.group(2).strip()}'); continue
        m = re.match(r'^(.+?) is (.+)$', chunk)
        if m:
            rhs = m.group(2).strip()
            items.append(f'{m.group(1).strip()} == {rhs}'); continue
        return None  # unparseable
    return ', '.join(items)

def _strip_type_attrs(decl):
    d = re.sub(r'@frozen\s+', '', decl)
    d = re.sub(r'\bnonisolated\s+(?=(struct|class|enum|protocol|actor)\b)', '', d)
    return d.strip()

def conformances(md, allow=None):
    rel = {r['title']: [i.split('/')[-1].split('-swift')[0] for i in r['identifiers']] for r in md.get('relationshipsSections', [])}
    c = rel.get('Conforms To', [])
    return [x for x in SAFE_CONF if x in c and (allow is None or x in allow)]

SKIP_CLAUSE_TERMS = ['DefaultButtonLabel', 'DefaultDateProgressLabel', 'SearchUnavailableContent', 'PrimitiveButtonStyleConfiguration.Label', 'ToggleStyleConfiguration']


def _callshape(dd):
    d0 = re.sub(r'\s=\s[^,)]*', '', dd)          # drop default values
    d0 = re.sub(r'\?(?=[,)\s]|$)', '', d0)         # drop optionality
    d0 = re.sub(r'@(export\(implementation\)|inlinable|MainActor|preconcurrency|_alwaysEmitIntoClient)\s*|\bnonisolated\s+', '', d0)
    d0 = re.sub(r'\s*->.*$', '', d0)                 # the return type does not decide which call the overload matches
    return re.sub(r'\s+', ' ', d0).strip()

def _iv(x):
    try: return float((_ios(x) or {}).get('introduced', '0').split('.')[0] or 0)
    except Exception: return 0

def _groups(pages):
    g = {}
    for m in pages:
        key = re.sub(r'-[a-z0-9]{3,6}$', '', docs.page_path(m)).lower()
        g.setdefault(key, []).append(m)
    return g

# Overloads the docs list as equally available whose bare call is ambiguous for the compiler. The real SDK must rank one
# of them (an availability or attribute the docs page does not print); the older/original one is marked disfavored here.
MANUAL_DISFAVOR = {
    'swiftui/animation/interactivespring(response:dampingfraction:blendduration:)':
        'docs: both interactiveSpring overloads are iOS 13.0 with all-default parameters, so `.interactiveSpring()` would be ambiguous; the duration/extraBounce form is the newer API',
    'swiftui/stepper/init(value:in:step:label:oneditingchanged:)':
        'docs: this @export(implementation) overload and init(value:in:step:onEditingChanged:label:) are both iOS 13.0 and both accept `Stepper(value:in:) { label }`, which would be ambiguous; the original parameter order wins',
    'swiftui/stepper/init(value:step:label:oneditingchanged:)':
        'docs: as for the ranged form, init(value:step:onEditingChanged:label:) is the original; the label-first order is the later @export(implementation) addition',
}

def disfavor_prefix(m, mp, decl, groups):
    """'@_disfavoredOverload ' when a sibling overload of the same name (other hash page) has the same call
    shape (labels and parameter types, ignoring defaults, optionality and return type) and was introduced in a
    newer OS: the docs list both and the compiler must have some way to prefer one."""
    if mp.lower() in MANUAL_DISFAVOR:
        return '@_disfavoredOverload '
    sibs = [x for x in groups.get(re.sub(r'-[a-z0-9]{3,6}$', '', mp).lower(), []) if x is not m]
    shape = _callshape(decl)
    newer = [x for x in sibs if any(_callshape(dd) == shape and dd != decl for dd in docs.declarations(x))]
    if newer and _iv(m) < max(_iv(x) for x in newer):
        return '@_disfavoredOverload '
    return ''

def emit_type(path, header=None, indent='', skip=(), nested=True, ctx='type', cls_open=False, conf=None, inner_extra='',
              qual=None, trailer='', _ext_out=None):
    """Emit a documented type: header, every iOS member (nested types recursively), closing brace, then one
    `extension T where ...` block per distinct extension constraint the docs report for its members."""
    PRUNE = load_prune()
    md = docs.fetch(path)
    if not md:
        return f'{indent}// NO PAGE: {path}\n'
    pp = docs.page_path(md)
    qual = qual or pp.split('/', 1)[1].replace('/', '.')
    qual = re.sub(r'-swift\.\w+$', '', qual)
    qual = '.'.join(re.sub(r'-swift\.\w+$', '', x) for x in qual.split('.'))
    out, after, after_nested = [], {}, []
    decls = docs.declarations(md)
    kind = md.get('metadata', {}).get('symbolKind', '')
    if header is None:
        h = _strip_type_attrs(decls[0]) if decls else f'struct {pp.split("/")[-1]}'
        cf = conformances(md) if conf is None else conf
        if cf:
            base, _, wh = h.partition(' where ')
            if ':' not in re.sub(r'<.*?>', '', base):
                h = base + ': ' + ', '.join(cf) + ((' where ' + wh) if wh else '')
        header = pub(h, True)
    out.append(f'{indent}// doc: {pp}')
    out.append(f'{indent}{header} {{')
    if inner_extra:
        out.append(inner_extra.rstrip('\n'))
    ind2 = indent + '    '
    pages = member_pages(path)
    groups = {}
    for m in pages:
        key = re.sub(r'-[a-z0-9]{3,6}$', '', docs.page_path(m)).lower()
        groups.setdefault(key, []).append(m)
    for m in pages:
        mp = docs.page_path(m)
        if any(mp.startswith(s) for s in skip):
            continue
        mk = m.get('metadata', {}).get('symbolKind', '')
        cl = constraint_clause(m)
        if cl is None:
            out.append(f'{ind2}// NOT EMITTED (unparseable extension constraint): {mp}')
            continue
        if cl and any(t in cl for t in SKIP_CLAUSE_TERMS):
            continue
        all_decls = docs.declarations(m)
        for di, decl in enumerate(all_decls):
            key = mp if len(all_decls) == 1 else f'{mp}#{di}'
            if key in PRUNE:
                continue
            tagp = key
            av = _ios(m) or {}
            note = ''
            try:
                if av.get('introduced') and float(av['introduced'].split('.')[0]) > 17: note += f"  [iOS {av['introduced']}]"
            except Exception: pass
            if av.get('deprecated'): note += '  [deprecated]'
            if mk in ('struct', 'enum', 'class', 'protocol'):
                if nested and not cl:
                    ext_here = _ext_out if _ext_out is not None else []
                    out.append(emit_type(mp, indent=ind2, skip=skip, ctx=ctx, cls_open=cls_open, qual=qual + '.' + re.sub(r'-swift\.\w+$', '', mp.split('/')[-1]), _ext_out=ext_here).rstrip('\n'))
                    if _ext_out is None:
                        after_nested.extend(ext_here)
                break
            if decl.startswith('typealias') and '=' not in decl:
                continue
            if decl.startswith('associatedtype'):
                continue
            sh = docs.shimify(decl, 'protocol' if kind == 'protocol' else ctx)
            if kind == 'enum' and decl.startswith('case ') and not cl:
                out.append(f'{ind2}// doc: {tagp}{note}')
                out.append(ind2 + sh)
                continue
            disf = disfavor_prefix(m, mp, decl, groups)
            line = pub(disf + sh, True, cls_open)
            if kind == 'protocol':
                out.append(f'{ind2}// doc: {tagp}{note}'); out.append(ind2 + sh)
            elif cl:
                after.setdefault(cl, []).append((tagp, note, line))
            else:
                out.append(f'{ind2}// doc: {tagp}{note}')
                out.append(ind2 + line)
    if re.search(r'\bOptionSet\b', header):
        # an OptionSet needs real storage: the documented init(rawValue:) stores it, rawValue becomes a stored let
        rv_type = None
        for i, l in enumerate(out):
            m = re.match(r'^(\s*)public init\(rawValue(?: \w+)?: ([A-Za-z0-9]+)\) \{ fatalError\(\) \}$', l)
            if m:
                rv_type = m.group(2)
                out[i] = l.replace('{ fatalError() }', '{ self.rawValue = rawValue }')
        for i, l in enumerate(out):
            m = re.match(r'^(\s*)public var rawValue: ([A-Za-z0-9]+) \{ fatalError\(\) \}$', l)
            if m:
                out[i] = f'{m.group(1)}public let rawValue: {m.group(2)}'
        if not any(re.match(r'^\s*public let rawValue', l) for l in out):
            rv = rv_type or 'Int'
            extra = f'{ind2}// shim: OptionSet storage (the docs page set has no rawValue page for this type)\n{ind2}public let rawValue: {rv}'
            if not any('init(rawValue' in l for l in out):
                extra += f'\n{ind2}// shim: OptionSet requirement\n{ind2}public init(rawValue: {rv}) {{ self.rawValue = rawValue }}'
            out.insert(2, extra)
    out.append(f'{indent}}}')
    if trailer:
        out.append(trailer.rstrip('\n'))
    ext_lines = []
    for cl, items in after.items():
        ext_lines.append(f'extension {qual} where {cl} {{')
        for mp, note, line in items:
            ext_lines.append(f'    // doc: {mp}{note}')
            ext_lines.append('    ' + line)
        ext_lines.append('}')
    if _ext_out is not None:
        _ext_out.extend(ext_lines)
        return '\n'.join(out) + '\n'
    out.extend(ext_lines)
    out.extend(after_nested)
    return '\n'.join(out) + '\n'


def emit_ext(path, qual, skip_paths=(), names=None, ctx='type', indent='', skip_prefix=()):
    """Emit the documented members of a (hand-written) protocol/type as `extension qual [where ...]` blocks.
    names: optional set of lower-case member base names to restrict to."""
    PRUNE = load_prune()
    md = docs.fetch(path)
    if not md:
        return f'{indent}// NO PAGE: {path}\n'
    blocks = {}
    _pages = member_pages(path)
    _grp = _groups(_pages)
    for m in _pages:
        mp = docs.page_path(m)
        if mp in skip_paths or any(mp.startswith(p) for p in skip_prefix):
            continue
        base = mp.split('/')[-1]
        base = re.sub(r'-[a-z0-9]{3,6}$', '', base)
        base = re.sub(r'-swift\.\w+$', '', base)
        base = base.split('(')[0].lower()
        if names is not None and base not in names:
            continue
        mk = m.get('metadata', {}).get('symbolKind', '')
        if mk in ('struct', 'enum', 'class', 'protocol', 'macro'):
            continue
        cl = constraint_clause(m)
        if cl is None:
            continue
        all_decls = docs.declarations(m)
        for di, decl in enumerate(all_decls):
            key = mp if len(all_decls) == 1 else f'{mp}#{di}'
            if key in PRUNE:
                continue
            if decl.startswith('typealias') and '=' not in decl:
                continue
            if decl.startswith('associatedtype') or decl.startswith('@attached') or decl.startswith('@freestanding') or ' macro ' in decl:
                continue
            av = _ios(m) or {}
            note = ''
            try:
                if av.get('introduced') and float(av['introduced'].split('.')[0]) > 17: note += f"  [iOS {av['introduced']}]"
            except Exception: pass
            if av.get('deprecated'): note += '  [deprecated]'
            sh = docs.shimify(decl, ctx)
            blocks.setdefault(cl, []).append((key, note, pub(disfavor_prefix(m, mp, decl, _grp) + sh, True)))
    out = []
    ind2 = indent + '    '
    for cl, items in blocks.items():
        out.append(f"{indent}extension {qual}{(' where ' + cl) if cl else ''} {{")
        for key, note, line in items:
            out.append(f'{ind2}// doc: {key}{note}')
            out.append(ind2 + line)
        out.append(f'{indent}}}')
    return '\n'.join(out) + '\n'
