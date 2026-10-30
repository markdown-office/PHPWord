#!/usr/bin/env bash
#
# Builds the patch that carries our fixes into the released PHPWord.
#
# The patch is *not* `git diff 1.4.0..<branch> -- <files>`. That carries every
# upstream change to those files as well, and one of them is a feature rather
# than a fix: upstream writes a style of its own for a title depth that was
# used without `addTitleStyle()`, and its style id collides with the one this
# suite registers for its own headings. Two styles with one id is a document
# Word repairs, and it breaks the reader here.
#
# So each file is merged instead: the released file, with our change applied on
# top of upstream's `master` as the common ancestor. What comes out is the
# released file with our fix in it, and the diff of that against the release is
# the patch.
#
# Two files need the conflict resolved by hand, and the resolutions differ:
#
#   Part/Styles.php    the released file, with our change. Upstream's addition
#                       is the feature above.
#   Style/Paragraph.php upstream's file, with our change. Upstream's addition
#                       moves the outline level of a numbered paragraph to the
#                       end of its properties, which is where the schema names
#                       it, and a numbered paragraph is invalid without it.

set -euo pipefail

repository="${1:?the PHPWord repository}"
branch="${2:?the branch carrying the fixes}"
output="${3:?the patch file to write}"
worktree="${4:?the worktree checked out at the released tag}"

cd "$repository"

files=$(git diff --name-only "upstream/master..$branch" -- src/)

mkdir -p patches
rm -f patches/.base patches/.other

for file in $files; do
    git show "upstream/master:$file" > patches/.base
    git show "$branch:$file" > patches/.other

    git merge-file --quiet "$worktree/$file" patches/.base patches/.other || true
done

rm -f patches/.base patches/.other

# The two resolutions.
git show "$branch:src/PhpWord/Writer/Word2007/Style/Paragraph.php" \
    > "$worktree/src/PhpWord/Writer/Word2007/Style/Paragraph.php"

python3 - "$worktree/src/PhpWord/Writer/Word2007/Part/Styles.php" <<'PY'
import pathlib
import re
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()

pattern = re.compile(r'<<<<<<< [^\n]*\n(.*?)=======\n(.*?)>>>>>>> [^\n]*\n', re.S)


def resolve(match):
    theirs = match.group(2)
    assert 'styleLink' in theirs
    # The common ancestor is upstream's `master`, which has an outline level of
    # its own; the release has not. What our change needs here is the link, so
    # that the `w:link` can be written after the name.
    return '        $styleLink = null;\n'


resolved = pattern.sub(resolve, text)
assert '<<<<<<<' not in resolved
path.write_text(resolved)
PY

cd "$worktree"
git diff -- src/ > "$output"

echo "$(wc -l < "$output" | tr -d ' ') lines, $(grep -c '^diff --git' "$output") file(s)"
echo "sha256: $(shasum -a 256 "$output" | cut -d' ' -f1)"
