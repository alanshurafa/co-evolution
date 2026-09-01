#!/usr/bin/env python3
"""Pick the repository files a single-shot patch attempt should see.

The single-shot tier has no agent loop: the model cannot open files, so the
harness must choose the context. Selection is deterministic and uses only
public inputs (the issue text and the repository at its base commit) so the
same cell always builds the same prompt.
"""
import argparse
import re
import subprocess
import sys

SOURCE_SUFFIXES = ('.py', '.pyx', '.pyi')

# Words that appear in nearly every issue report and match nearly every file.
STOPWORDS = frozenset("""
about above after again against all also always analysis and another any are
around because been before being below between both build call called calls
can case cases change changed changes check code coming compare could current
currently data default depending description details different does doing done
during each either else error errors even every example expect expected
failing fails false first fixed follow following from function functions
generate get gets github given gives group handle has have here how however
implementation import instead into issue itself just keep known last later
like line lines list little look make makes many maybe method methods might
more most much must name names need needs never new none not note now number
object objects only open option options order other output outside over own
part pass patch please point possible previous print problem produce python
raise raised raises rather read really reason regression release report
reported reproduce result results return returns run running same seems self
set should show shown side similar simple since small some something still
such support sure take test tests than that the their them then there these
they thing think this those three through time trying two type types under
until update use used user uses using value values version very want was way
what when where whether which while will with within without work working
would write wrong your
""".split())

FILE_PATH_RE = re.compile(r'\b((?:[\w.-]+/)+[\w.-]+\.(?:py|pyx|pyi))\b')
BACKTICK_RE = re.compile(r'`([^`\n]{2,120})`')
IDENT_RE = re.compile(r'\b([A-Za-z_][A-Za-z0-9_]{3,})\b')


def git(workspace, *args):
    proc = subprocess.run(('git', '-C', workspace) + args,
                          capture_output=True, text=True, errors='replace')
    return proc.returncode, proc.stdout


def tracked_source_files(workspace):
    rc, out = git(workspace, 'ls-files')
    if rc != 0:
        sys.exit('ERROR: git ls-files failed in %s' % workspace)
    return set(p for p in out.splitlines() if p.endswith(SOURCE_SUFFIXES))


def candidate_tokens(issue, limit):
    """Rank issue tokens: backticked and dotted names first, then identifiers."""
    weighted = {}

    def add(token, weight):
        token = token.strip()
        if len(token) < 4 or token.lower() in STOPWORDS:
            return
        weighted[token] = max(weighted.get(token, 0.0), weight)

    for span in BACKTICK_RE.findall(issue):
        add(span, 3.0)
        for part in re.split(r'[^A-Za-z0-9_]+', span):
            add(part, 2.0)
    for ident in IDENT_RE.findall(issue):
        add(ident, 1.0)

    ordered = sorted(weighted.items(), key=lambda kv: (-kv[1], kv[0]))
    return [token for token, _ in ordered[:limit]]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--workspace', required=True)
    ap.add_argument('--task', required=True)
    ap.add_argument('--max-files', type=int, default=6)
    ap.add_argument('--max-tokens', type=int, default=40)
    args = ap.parse_args()

    # Bash callers read this list line by line; Windows text mode would append
    # a carriage return to every path and break the lookups downstream.
    sys.stdout.reconfigure(newline=chr(10))

    with open(args.task, encoding='utf-8', errors='replace') as handle:
        issue = handle.read()

    tracked = tracked_source_files(args.workspace)
    if not tracked:
        sys.exit('ERROR: workspace has no tracked Python sources')

    scores = {}

    # A path spelled out in the issue is the strongest possible signal.
    for path in FILE_PATH_RE.findall(issue):
        for candidate in tracked:
            if candidate == path or candidate.endswith('/' + path):
                scores[candidate] = scores.get(candidate, 0.0) + 10.0

    for token in candidate_tokens(issue, args.max_tokens):
        rc, out = git(args.workspace, 'grep', '-l', '-F', '--', token)
        if rc != 0:
            continue
        hits = [p for p in out.splitlines() if p in tracked]
        # A token matching half the repository says nothing about where the bug
        # is; a token matching three files says a great deal.
        if not hits or len(hits) > 40:
            continue
        share = 1.0 / len(hits)
        for path in hits:
            scores[path] = scores.get(path, 0.0) + share

    if not scores:
        sys.exit('ERROR: no candidate files matched the issue text')

    # Test and example modules are legitimate context but they crowd out the
    # source file the patch has to touch, so they compete at half weight.
    for path in list(scores):
        parts = path.split('/')
        is_support = ('tests' in parts or 'test' in parts
                      or 'examples' in parts or parts[-1].startswith('test_'))
        if is_support:
            scores[path] *= 0.5

    ranked = sorted(scores.items(), key=lambda kv: (-kv[1], kv[0]))
    for path, _ in ranked[:args.max_files]:
        print(path)


if __name__ == '__main__':
    main()
