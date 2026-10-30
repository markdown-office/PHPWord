#!/usr/bin/env bash
#
# Merges our five fix branches into the branch that carries the patch.
#
# The changelog conflicts every time, because every branch appends its entry at
# the end of the same section; the resolution is ours followed by theirs, which
# is the order the entries were written in. The source files that conflict are
# resolved by hand, because the resolution is a composition of the two changes
# rather than a choice between them.

set -uo pipefail

cd "$(dirname "$0")"

branches=(
    fix/word2007-rpr-order
    fix/word2007-ppr-order
    fix/word2007-invalid-markup
    fix/word2007-style-order
    fix/word2007-table-values
)

for branch in "${branches[@]}"; do
    printf '%-36s ' "$branch"

    if git merge --no-edit -q "$branch" >/dev/null 2>&1; then
        echo 'ok'
        continue
    fi

    python3 - <<'PY'
import pathlib
import re

p = pathlib.Path('docs/changes/1.x/1.5.0.md')
s = p.read_text()
pattern = re.compile(r'<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n', re.S)


def resolve(match):
    ours = [line for line in match.group(1).split('\n') if line.strip()]
    theirs = [line for line in match.group(2).split('\n') if line.strip()]
    return '\n'.join(ours + theirs) + '\n'


resolved = pattern.sub(resolve, s)
if '<<<<<<<' not in resolved:
    p.write_text(resolved)
PY

    git add docs/changes/1.x/1.5.0.md

    remaining=$(git diff --name-only --diff-filter=U)
    if [ -n "$remaining" ]; then
        echo "CONFLICT: $remaining"
        exit 1
    fi

    git commit -q --no-edit
    echo 'ok (changelog resolved)'
done

echo
git log --oneline -1
git status --short
