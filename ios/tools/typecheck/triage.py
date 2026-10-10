#!/usr/bin/env python3
"""Classify the diagnostics of one swiftc pass.

    triage.py <swiftc log> <app root> [<root as it appears in the log>]

Prints each distinct error (path relative to the app root) and a one-line summary, exit status 1 if there is any error
that is not an allow-listed harness artifact.

A harness artifact is a diagnostic produced by the Linux toolchain, not by the code. The only one so far (see README):
with Objective-C interop switched on, a Linux standard library has no `AutoreleasingUnsafeMutablePointer`, and the compiler
then refuses every inout-to-pointer argument (`f(&x)` for an `UnsafeMutablePointer<T>` parameter) with
"broken standard library: cannot find intrinsic operations on UnsafeMutablePointer<T>". known-harness-artifacts.tsv pins
each such site by file, line and a hash of the line's text, so a new `&x` argument elsewhere, or an edit of the pinned
line, is an error again until someone has looked at it.
"""
import hashlib, os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ARTIFACT_MSG = re.compile(r'broken standard library: cannot find intrinsic operations on UnsafeMutablePointer<T>')


def line_hash(root, rel, line):
    try:
        text = open(os.path.join(root, rel), errors='replace').read().split('\n')[line - 1]
    except Exception:
        return ''
    return hashlib.sha1(text.strip().encode()).hexdigest()[:12]


def load_allow():
    out = {}
    p = os.path.join(HERE, 'known-harness-artifacts.tsv')
    if os.path.exists(p):
        for l in open(p):
            if l.strip() and not l.startswith('#'):
                f = l.rstrip('\n').split('\t')
                out[(f[0], int(f[1]))] = f[2]
    return out


def main():
    log, root = sys.argv[1], os.path.abspath(sys.argv[2])
    logroot = os.path.abspath(sys.argv[3]) if len(sys.argv) > 3 else root
    allow = load_allow()
    errs, arts, seen = [], [], set()
    for l in open(log, errors='replace'):
        m = re.match(r'^(?P<file>/\S+?\.swift):(?P<line>\d+):(?P<col>\d+): error: (?P<msg>.*)$', l.rstrip('\n'))
        if not m:
            m2 = re.match(r'^(?P<file>macro expansion \S+):(?P<line>\d+):(?P<col>\d+): error: (?P<msg>.*)$', l.rstrip('\n'))
            if not m2:
                continue
            m = m2
        f, ln, msg = m.group('file'), int(m.group('line')), m.group('msg')
        rel = os.path.relpath(f, logroot) if f.startswith('/') else f
        key = (rel, ln, m.group('col'), msg)
        if key in seen:
            continue
        seen.add(key)
        if ARTIFACT_MSG.search(msg) and (rel, ln) in allow and allow[(rel, ln)] == line_hash(root, rel, ln):
            arts.append((rel, ln, msg))
        else:
            errs.append((rel, ln, m.group('col'), msg))
    for rel, ln, col, msg in errs:
        print(f'  {rel}:{ln}:{col}: error: {msg}')
    sites = sorted({(r, n) for r, n, _ in arts})
    print(f'  -> {len(errs)} errors' + (f'; {len(arts)} harness-artifact diagnostics at {len(sites)} pinned site(s): ' + ', '.join(f'{r}:{n}' for r, n in sites) if arts else ''))
    sys.exit(1 if errs else 0)


main()
