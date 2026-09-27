#!/usr/bin/env python3
"""Normalize t3-field-list-table indentation in RST files.

The field-list tables used throughout Documentation/ (``.. t3-field-list-table::``)
must be internally consistent: every item's bullet, its field keys and its field
values start in the same columns within a table. The columns of a table are
defined by its header item (the first item, used with ``:header-rows: 1``).
Hand edits easily shift a single item by one or two spaces, which breaks the
alignment and makes the rendered table ragged.

How it works
------------
A field-list item is a *rigid block*: its bullet line, its ``:Key:`` lines and
its value lines are all offset from the header item by the same per-item amount
(value lines that are indented further, e.g. a nested ``0 { … }`` default, keep
their offset relative to the item's first value line). Therefore the fix for a
drifted item is simply to shift every one of its non-blank lines by

    delta = (header item's bullet column) - (this item's bullet column)

which preserves every relative offset inside the item. Only whole items move;
non-whitespace content is never touched. Tables without a ``:header-rows:``
option are left alone.

Usage
-----
    python3 normalize-field-list-tables.py [PATH ...]        # rewrite in place
    python3 normalize-field-list-tables.py --check [PATH ...]  # report only;
    # exit 1 if any file would be changed (useful in CI)

Paths may be files or directories (searched recursively for *.rst / *.txt).
With no paths, the Documentation/ directory of the repository is used.
"""

import os
import re
import sys

def lead(line):
    return len(line) - len(line.lstrip(' '))


DIRECTIVE = '.. t3-field-list-table'
BULLET_RE = re.compile(r'^( *)- :[A-Za-z][A-Za-z0-9 ]*:(\s|$)')


def table_groups(lines):
    """Yield (directive_index, end_index) for each header-row table group."""
    n = len(lines)
    i = 0
    while i < n:
        if lines[i].strip().startswith(DIRECTIVE):
            has_header = False
            j = i + 1
            while j < n and (not lines[j].strip() or lines[j].startswith(' ')):
                if lines[j].strip().startswith(':header-rows:'):
                    has_header = True
                j += 1
            if has_header:
                yield i, j
            i = j
        else:
            i += 1


def item_indices(lines, start, end):
    """Return the start index of every item in lines[start:end]."""
    out = []
    i = start
    while i < end:
        if BULLET_RE.match(lines[i]):
            out.append(i)
            i += 1
            while i < end and not BULLET_RE.match(lines[i]):
                i += 1
        else:
            i += 1
    return out


def table_columns(lines, start, end):
    """Return the first item's bullet column (the table's standard bullet col)."""
    items = item_indices(lines, start, end)
    if not items:
        return None
    return lead(lines[items[0]])


def normalize_table(lines, start, end):
    """Shift every drifted item so its bullet returns to the table's standard
    bullet column, preserving the item's internal layout.

    A field-list item renders correctly when its bullet sits in the same
    column as every other item in the table and its field keys/values keep a
    constant offset from that bullet. Hand edits typically shift the *whole*
    item by a few spaces (bullet, keys and values together), which leaves the
    internal layout intact but moves the bullet off the table's column. The
    fix is therefore to shift every non-blank line of the item by the same
    delta; that re-centres the bullet and keeps every relative offset (keys,
    values and even nested blocks) exactly as the author wrote them.

    It deliberately does NOT re-align keys or values to a global column,
    because a valid table may legitimately use different value offsets for
    different items, which the renderer accepts without warning.

    Return the number of shifted lines.
    """
    base = table_columns(lines, start, end)
    if base is None:
        return 0
    items = item_indices(lines, start, end)
    changed = 0
    for pos, item in enumerate(items):
        if pos == 0:
            continue
        delta = base - lead(lines[item])
        if delta == 0:
            continue
        nxt = items[pos + 1] if pos + 1 < len(items) else end
        for k in range(item, nxt):
            line = lines[k]
            if not line.strip():
                continue
            if delta > 0:
                new = ' ' * delta + line
            else:
                stripped = line.lstrip(' ')
                removed = len(line) - len(stripped)
                take = min(removed, -delta)
                new = ' ' * (removed - take) + stripped if take >= -delta else stripped
            if new != line:
                lines[k] = new
                changed += 1
    return changed


def normalize_file_content(text):
    lines = text.split('\n')
    changed = 0
    for directive, end in table_groups(lines):
        changed += normalize_table(lines, directive, end)
    return '\n'.join(lines), changed


def iter_files(paths):
    for path in paths:
        if os.path.isdir(path):
            for root, _dirs, files in os.walk(path):
                for name in sorted(files):
                    if name.endswith(('.rst', '.txt')):
                        yield os.path.join(root, name)
        else:
            yield path


def main(argv):
    check = '--check' in argv
    argv = [a for a in argv if a != '--check']
    if not argv:
        repo = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
        argv = [os.path.join(repo, 'Documentation')]
    bad = 0
    for path in iter_files(argv):
        with open(path, encoding='utf-8') as f:
            original = f.read()
        normalized, changed = normalize_file_content(original)
        if changed:
            if check:
                print('%s: needs normalization' % path)
                bad += 1
            else:
                with open(path, 'w', encoding='utf-8') as f:
                    f.write(normalized)
                print('%s: normalized (%d line(s) realigned)' % (path, changed))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
