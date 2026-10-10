"""Small, dependency-free helpers for the static audits: blank out comments and strings, find declarations and their
brace-delimited bodies. Not a Swift parser; good enough for the declaration shapes this app uses (and each audit prints what
it matched so a human can see what it did)."""
import os, re


def blank(src):
    """Same length as `src`; comments and string-literal contents become spaces (newlines kept)."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if src.startswith('//', i):
            j = src.find('\n', i); j = n if j < 0 else j
            out.append(' ' * (j - i)); i = j
        elif src.startswith('/*', i):
            depth, j = 1, i + 2
            while j < n and depth:
                if src.startswith('/*', j): depth += 1; j += 2
                elif src.startswith('*/', j): depth -= 1; j += 2
                else: j += 1
            out.append(re.sub(r'[^\n]', ' ', src[i:j])); i = j
        elif src.startswith('"""', i):
            j = src.find('"""', i + 3); j = n if j < 0 else j + 3
            out.append(re.sub(r'[^\n]', ' ', src[i:j])); i = j
        elif c == '"':
            j = i + 1
            while j < n and src[j] != '"' and src[j] != '\n':
                j += 2 if src[j] == '\\' else 1
            j = min(j + 1, n)
            out.append('"' + ' ' * (j - i - 2) + '"' if j - i >= 2 else ' ' * (j - i)); i = j
        else:
            out.append(c); i += 1
    return ''.join(out)


def match_brace(clean, open_idx):
    depth = 0
    for k in range(open_idx, len(clean)):
        if clean[k] == '{': depth += 1
        elif clean[k] == '}':
            depth -= 1
            if depth == 0: return k
    return len(clean) - 1


def line_of(src, idx):
    return src.count('\n', 0, idx) + 1


TYPE_RE = re.compile(r'^[ \t]*(?:@[A-Za-z_]\w*(?:\([^)\n]*\))?[ \t]+)*(?:(?:public|internal|private|fileprivate|final|indirect|open)[ \t]+)*(struct|class|enum|actor|extension)[ \t]+([A-Za-z_][\w.]*)', re.M)


def types(clean):
    """[(kind, name, body_start, body_end)] for every type/extension declaration, nested ones included."""
    out = []
    for m in TYPE_RE.finditer(clean):
        k = m.end(); depth = 0
        while k < len(clean):
            c = clean[k]
            if c in '(<[': depth += 1
            elif c in ')>]': depth -= 1
            elif c == '{' and depth <= 0: break
            elif c == '\n' and depth <= 0 and re.match(r'\s*(?:\n|$)', clean[k:k + 1]) and False: pass
            k += 1
        if k >= len(clean): continue
        out.append((m.group(1), m.group(2), k, match_brace(clean, k)))
    return out


def swift_files(root):
    for dp, _, fs in os.walk(root):
        for f in sorted(fs):
            if f.endswith('.swift'):
                yield os.path.join(dp, f)


def innermost(spans, idx):
    best = None
    for s in spans:
        if s[2] <= idx <= s[3] and (best is None or s[2] > best[2]):
            best = s
    return best
