#!/usr/bin/env python3
"""Keep only the parts of a unified diff that touch drivers/gpu/drm/{xe,i915}/."""
import re, sys
KEEP = re.compile(r'^[^/ ]+/drivers/gpu/drm/(xe|i915)/')
lines = sys.stdin.read().splitlines(keepends=True)
out, cur, keep = [], [], False
def flush():
    if keep and cur:
        out.extend(cur)
i = 0
while i < len(lines):
    l = lines[i]
    start = l.startswith('diff --git ') or (
        l.startswith('--- ') and i + 1 < len(lines) and lines[i+1].startswith('+++ ')
        and not (cur and cur[0].startswith('diff --git ') and not any(x.startswith('--- ') for x in cur)))
    if start:
        flush()
        cur, keep = [], False
    if l.startswith('diff --git '):
        keep = bool(KEEP.match(l.split()[2]))
    elif l.startswith('+++ ') and i > 0 and lines[i-1].startswith('--- '):
        keep = bool(KEEP.match(l[4:].split()[0])) or bool(KEEP.match(lines[i-1][4:].split()[0]))
    cur.append(l)
    i += 1
flush()
sys.stdout.write(''.join(out))
