#!/usr/bin/env bash
# Pull the unified diff out of a chat response.
#
# Single-shot seats answer in prose-plus-fence, and the fence label varies
# (```diff, ```patch, or bare ```). Some answers skip the fence and trail
# explanation after the patch. This reads the response and writes just the
# diff; it exits non-zero when the response contains no git-style diff at all,
# which is a cell failure rather than a patch.
set -euo pipefail

RESPONSE="${1:-}"
OUT="${2:-}"
[[ -f "$RESPONSE" && -n "$OUT" ]] || { printf 'usage: extract-diff.sh RESPONSE OUT\n' >&2; exit 2; }

raw="${OUT}.raw"
awk '
  /^[[:space:]]*```/ {
    if (inblock) { exit }
    if (seen == 0) { inblock = 1; seen = 1; next }
    next
  }
  inblock { print }
' "$RESPONSE" > "$raw"
grep -q '^diff --git ' "$raw" || cp "$RESPONSE" "$raw"

# Keep the run of diff lines and drop the prose on either side of it. Anything
# that is not recognisable diff syntax ends the patch.
awk '
  BEGIN { started = 0 }
  !started && /^diff --git / { started = 1 }
  started {
    if ($0 ~ /^(diff --git |index |--- |\+\+\+ |@@ |[+-]|[[:space:]]|\\ No newline|new file mode |deleted file mode |old mode |new mode |similarity index |rename from |rename to |Binary files |GIT binary patch)/ || $0 == "") {
      print
    } else {
      exit
    }
  }
' "$raw" > "$OUT"
rm -f "$raw"

grep -q '^diff --git ' "$OUT"
