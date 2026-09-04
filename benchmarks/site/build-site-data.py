#!/usr/bin/env python3
"""Build the single JSON the results page renders.

Every field here is read from a file on disk and carries the path it came
from, so a reader can check any number on the page against the evaluator's
own output. Nothing is entered by hand and nothing is inferred.

Sources:
  benchmarks/code/conditions.json          condition ids, labels, tiers
  benchmarks/code/suites.json              suite and subset pointer
  benchmarks/code/subsets/*.json           the frozen task list
  benchmarks/code/external-sources.lock.json  evaluator and dataset pins
  results/code/evaluation/*.json           official evaluator reports
  results/code/evaluation/logs/...         per-instance evaluator reports
  results/code/runs/*/*/<cond>/            run manifests and provider logs

Only standardized-benchmark material is read. The retired document suite under
benchmarks/ is not a source here and must never become one.
"""
import argparse
import glob
import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pricing as pricing_mod  # noqa: E402

# A seed>1 cell names its prediction co-evolution-condition-B.r2, and the
# evaluator names the report after that, so the seed is recoverable from the
# report file name alone.
REPORT_NAME_RE = re.compile(
    r'^co-evolution-condition-(?P<cond>[A-Za-z0-9_-]+?)(?:\.r(?P<seed>\d+))?\.(?P<run_id>[^.]+)\.json$')
MODEL_NAME_RE = re.compile(r'^co-evolution-condition-(?P<cond>[A-Za-z0-9_-]+?)(?:\.r(?P<seed>\d+))?$')
GOLD_NAME_RE = re.compile(r'^gold\.(?P<run_id>.+)\.json$')


def read_json(path):
    with open(path, encoding='utf-8') as handle:
        return json.load(handle)


RESULTS_ROOT = None


def rel(root, path):
    """Repo-relative path for an evidence file.

    The results tree is ignored by git and may live in a sibling checkout (the
    runs are produced in a long-lived runtime worktree). A path under it is
    always written as benchmarks/results/code/..., the location the README
    documents, so evidence paths on the page do not depend on which checkout
    built it.
    """
    path = os.path.abspath(path)
    if RESULTS_ROOT:
        try:
            inside = os.path.relpath(path, RESULTS_ROOT)
        except ValueError:
            inside = '..'
        if not inside.startswith('..'):
            return 'benchmarks/results/code/' + inside.replace(os.sep, '/')
    try:
        return os.path.relpath(path, root).replace(os.sep, '/')
    except ValueError:
        return path.replace(os.sep, '/')


def harness_commit(root):
    proc = subprocess.run(('git', '-C', root, 'rev-parse', 'HEAD'),
                          capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    return proc.stdout.strip()


def harness_dirty(root):
    proc = subprocess.run(('git', '-C', root, 'status', '--porcelain'),
                          capture_output=True, text=True)
    return bool(proc.stdout.strip()) if proc.returncode == 0 else None


def newest_reports(eval_dir, run_label=None):
    """Latest evaluator report per condition, plus the ones it supersedes.

    A report is named only for the evaluator run that produced it, so reports
    from two benchmark runs of the same condition are indistinguishable and a
    page built across them silently mixes subsets. run_label restricts the scan
    to one batch, which is what makes a per-run page possible.
    """
    latest, superseded = {}, []
    for path in sorted(glob.glob(os.path.join(eval_dir, '*.json'))):
        match = REPORT_NAME_RE.match(os.path.basename(path))
        if not match:
            continue
        cond, run_id = match.group('cond'), match.group('run_id')
        seed = int(match.group('seed') or 1)
        # The label is everything before the final "-"; the evaluator's
        # timestamp suffix contains none. A prefix test would make "base50"
        # match "base50-light-2026...", so a frontier page would silently
        # render light-tier results.
        if run_label is not None and run_id.rsplit('-', 1)[0] != run_label:
            continue
        key = (cond, seed)
        previous = latest.get(key)
        if previous is None or run_id > previous[0]:
            if previous is not None:
                superseded.append((cond, seed, previous[0], previous[1]))
            latest[key] = (run_id, path)
        else:
            superseded.append((cond, seed, run_id, path))
    return latest, superseded


def gold_canary(eval_dir):
    best = None
    for path in sorted(glob.glob(os.path.join(eval_dir, 'gold.*.json'))):
        match = GOLD_NAME_RE.match(os.path.basename(path))
        if not match:
            continue
        if best is None or match.group('run_id') > best[0]:
            best = (match.group('run_id'), path)
    if best is None:
        return None
    data = read_json(best[1])
    return {
        'run_id': best[0],
        'report_file': best[1],
        'submitted': data.get('submitted_instances'),
        'resolved': data.get('resolved_instances'),
    }


def per_instance_reports(eval_dir, run_id, model_name):
    """Read the evaluator's own per-instance verdicts for one scored run."""
    base = os.path.join(eval_dir, 'logs', 'run_evaluation', run_id, model_name)
    verdicts = {}
    if not os.path.isdir(base):
        return verdicts
    for instance in sorted(os.listdir(base)):
        report = os.path.join(base, instance, 'report.json')
        if not os.path.isfile(report):
            continue
        try:
            payload = read_json(report)
        except ValueError:
            continue
        entry = payload.get(instance) or {}
        tests = entry.get('tests_status') or {}
        f2p = tests.get('FAIL_TO_PASS') or {}
        p2p = tests.get('PASS_TO_PASS') or {}
        verdicts[instance] = {
            'resolved': bool(entry.get('resolved')),
            'patch_applied': bool(entry.get('patch_successfully_applied')),
            'fail_to_pass_passed': len(f2p.get('success') or []),
            'fail_to_pass_failed': len(f2p.get('failure') or []),
            'pass_to_pass_failed': len(p2p.get('failure') or []),
            'report_file': report,
        }
    return verdicts


def scored_patches(eval_dir, run_id, model_name):
    """The exact patch text the evaluator scored, per instance."""
    base = os.path.join(eval_dir, 'logs', 'run_evaluation', run_id, model_name)
    patches = {}
    if not os.path.isdir(base):
        return patches
    for instance in sorted(os.listdir(base)):
        diff = os.path.join(base, instance, 'patch.diff')
        if os.path.isfile(diff):
            with open(diff, encoding='utf-8', errors='replace') as handle:
                patches[instance] = handle.read()
    return patches


def index_cells(runs_root, run_id=None):
    """Map (condition, instance, patch text) -> cell directory.

    Scoped to one benchmark run. Two runs of the same condition on the same
    instance can produce byte-identical patches, and an unscoped index lets the
    later one win the key: a frontier row then reads its models and telemetry
    out of a light-tier cell, and the page reports the wrong experiment.
    """
    index = {}
    pattern = os.path.join(runs_root, run_id or '*', '*', '*', 'prediction.json')
    for path in glob.glob(pattern):
        try:
            record = read_json(path)
        except ValueError:
            continue
        match = MODEL_NAME_RE.match(record.get('model_name_or_path', ''))
        if not match:
            continue
        key = (match.group('cond'), int(match.group('seed') or 1),
               record.get('instance_id'),
               (record.get('model_patch') or '').strip())
        index[key] = os.path.dirname(path)
    return index


def index_attempts(runs_root, run_id=None):
    """Cells that ran and recorded an outcome, keyed by (condition, instance).

    A single-shot cell that never produced an applicable patch writes an
    outcome.json and no prediction. Without this index such a cell is
    indistinguishable from one that was never run, which would read on the page
    as missing data rather than as the failure it is.
    """
    attempts = {}
    for path in glob.glob(os.path.join(runs_root, run_id or '*', '*', '*', 'outcome.json')):
        try:
            record = read_json(path)
        except ValueError:
            continue
        key = (record.get('condition'), int(record.get('seed') or 1), record.get('instance'))
        attempts[key] = {
            'outcome': record.get('outcome'),
            'attempts': record.get('attempts'),
            'cell_dir': os.path.dirname(path),
        }
    return attempts


SEAT_DEFAULT_MODEL = {'glm': 'glm-5.3-flash', 'kimi': 'kimi-k3'}


def cell_telemetry(cell_dir, pricing=None):
    """Provider effort for one cell, from the CLI's own envelope figures.

    Claude cost is the CLI's own dollar figure. Codex, GLM and Kimi report
    tokens only; those are priced at the tracked list rates by the pricing
    module, which also says whether the figure is exact or an estimate from a
    total-only log.
    """
    out = {
        'cell_dir': cell_dir,
        'claude_dispatches': 0,
        'claude_cost_usd': 0.0,
        'claude_input_tokens': 0,
        'claude_cached_tokens': 0,
        'claude_output_tokens': 0,
        'claude_wall_seconds': 0,
        'codex_phases': 0,
        'codex_wall_seconds': 0,
        'codex_tokens': 0,
        'codex_input_tokens': 0,
        'codex_cached_tokens': 0,
        'codex_output_tokens': 0,
        'codex_cost_usd': 0.0,
        'codex_cost_low_usd': 0.0,
        'codex_cost_high_usd': 0.0,
        'codex_precision': [],
        'codex_cli_versions': set(),
        'glm_calls': 0,
        'glm_cost_usd': 0.0,
        'glm_precision': [],
        'kimi_calls': 0,
        'kimi_cost_usd': 0.0,
        'kimi_precision': [],
        'single_shot_attempts': None,
        'sandbox': None,
        'model_tier': None,
        'models': {},
        'effort': {},
    }
    manifest = os.path.join(cell_dir, 'run-manifest.json')
    if os.path.isfile(manifest):
        try:
            data = read_json(manifest)
            out['sandbox'] = (data.get('sandbox') or {}).get('codex')
            # What actually ran, so the page states the configuration rather
            # than assuming the default one.
            models = data.get('models') or {}
            effort = data.get('effort') or {}
            out['model_tier'] = data.get('model_tier')
            out['models'] = {
                'claude': models.get('claude'),
                'codex': models.get('codex'),
                'glm': models.get('glm'),
                'kimi': models.get('kimi'),
                # A single-shot manifest names its one model directly.
                'single_shot': data.get('model'),
            }
            if data.get('agent') in SEAT_DEFAULT_MODEL and data.get('model'):
                out['models'][data['agent']] = data['model']
            out['effort'] = {'claude': effort.get('claude'),
                             'codex': effort.get('codex')}
            out['schema'] = data.get('schema')
        except ValueError:
            pass
    outcome = os.path.join(cell_dir, 'outcome.json')
    if os.path.isfile(outcome):
        try:
            out['single_shot_attempts'] = read_json(outcome).get('attempts')
        except ValueError:
            pass
    logs = os.path.join(cell_dir, 'logs')
    if os.path.isdir(logs):
        for name in sorted(os.listdir(logs)):
            path = os.path.join(logs, name)
            if name.startswith('fable-') and name.endswith('.json'):
                try:
                    data = read_json(path)
                except ValueError:
                    continue
                out['claude_dispatches'] += 1
                out['claude_cost_usd'] += float(data.get('total_cost_usd') or 0)
                usage = data.get('usage') or {}
                out['claude_input_tokens'] += (int(usage.get('input_tokens') or 0)
                                               + int(usage.get('cache_creation_input_tokens') or 0))
                out['claude_cached_tokens'] += int(usage.get('cache_read_input_tokens') or 0)
                out['claude_output_tokens'] += int(usage.get('output_tokens') or 0)
                out['claude_wall_seconds'] += int((data.get('duration_ms') or 0) / 1000)
            elif (name.startswith('codex-') and name.endswith('.stderr.log')):
                # Each Codex phase writes a transcript and a stderr log; the
                # pair is one phase. The stderr log is the anchor because the
                # transcript may be JSONL events or prose depending on the
                # CLI flags the run used.
                out['codex_phases'] += 1
                transcript = path[:-len('.stderr.log')] + '.log'
                phase = pricing_mod.price_codex_phase(
                    pricing or {'models': {}, 'codex_total_only': {'assumed_split': {}}},
                    out['models'].get('codex'), transcript, path)
                out['codex_wall_seconds'] += phase['wall_seconds']
                out['codex_tokens'] += phase['total_tokens'] or 0
                out['codex_input_tokens'] += phase['input_tokens'] or 0
                out['codex_cached_tokens'] += phase['cached_input_tokens'] or 0
                out['codex_output_tokens'] += phase['output_tokens'] or 0
                out['codex_cost_usd'] += phase['cost_usd'] or 0.0
                out['codex_cost_low_usd'] += phase['cost_low_usd'] or 0.0
                out['codex_cost_high_usd'] += phase['cost_high_usd'] or 0.0
                out['codex_precision'].append(phase['precision'])
                if phase['cli_version']:
                    out['codex_cli_versions'].add(phase['cli_version'])
    # GLM and Kimi calls: a critique review or a single-shot response, each
    # with a usage sidecar when the adapter captured one. A call without a
    # sidecar is counted and left unpriced, which keeps the arm's cost flagged
    # incomplete rather than silently short.
    for seat in ('glm', 'kimi'):
        artifacts = []
        artifacts += glob.glob(os.path.join(logs, '%s-response-*.md' % seat))
        artifacts += [p for p in glob.glob(os.path.join(cell_dir, 'reviews', 'reviewer-*.md'))
                      if _review_seat(cell_dir, p) == seat]
        for artifact in artifacts:
            out[seat + '_calls'] += 1
            priced = None
            if pricing:
                model = out['models'].get(seat) or SEAT_DEFAULT_MODEL[seat]
                priced = pricing_mod.price_sidecar(pricing, model, artifact + '.usage.json')
            if priced:
                out[seat + '_cost_usd'] += priced['cost_usd']
                out[seat + '_precision'].append('exact')
            else:
                out[seat + '_precision'].append('unpriced')
    out['codex_cli_versions'] = sorted(out['codex_cli_versions'])
    return out


def _review_seat(cell_dir, review_path):
    """Which critic wrote reviewer-N.md, from the manifest's ordered roster."""
    manifest = os.path.join(cell_dir, 'run-manifest.json')
    try:
        critics = read_json(manifest).get('critics') or []
    except (OSError, ValueError):
        return None
    match = re.search(r'reviewer-(\d+)\.md$', os.path.basename(review_path))
    if not match:
        return None
    index = int(match.group(1)) - 1
    return critics[index] if 0 <= index < len(critics) else None


SUMMED_TELEMETRY = (
    'claude_dispatches', 'claude_cost_usd', 'claude_input_tokens',
    'claude_cached_tokens', 'claude_output_tokens', 'claude_wall_seconds',
    'codex_phases', 'codex_wall_seconds', 'codex_tokens', 'codex_input_tokens',
    'codex_cached_tokens', 'codex_output_tokens', 'codex_cost_usd',
    'codex_cost_low_usd', 'codex_cost_high_usd', 'glm_calls', 'glm_cost_usd',
    'kimi_calls', 'kimi_cost_usd',
)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo-root', required=True)
    ap.add_argument('--results-root', required=True)
    ap.add_argument('--suite', default='swebench-verified-canary')
    ap.add_argument('--output', required=True)
    ap.add_argument('--generated-at', required=True,
                    help='UTC timestamp supplied by the caller')
    ap.add_argument('--run-label', default=None,
                    help='only read evaluator reports from this labelled batch')
    ap.add_argument('--run-id', default=None,
                    help='benchmark run whose cells back this page; defaults to --run-label')
    args = ap.parse_args()

    global RESULTS_ROOT
    root = os.path.abspath(args.repo_root)
    results = os.path.abspath(args.results_root)
    RESULTS_ROOT = results
    code_dir = os.path.join(root, 'benchmarks', 'code')
    eval_dir = os.path.join(results, 'evaluation')
    runs_root = os.path.join(results, 'runs')

    conditions = read_json(os.path.join(code_dir, 'conditions.json'))['conditions']
    suites = read_json(os.path.join(code_dir, 'suites.json'))['suites']
    suite = next((s for s in suites if s['id'] == args.suite), None)
    if suite is None:
        sys.exit('ERROR: unknown suite %s' % args.suite)
    subset_path = os.path.join(code_dir, suite['subset_file'])
    subset = read_json(subset_path)
    instances = [row['instance_id'] for row in subset['instances']]
    repos = {row['instance_id']: row['repo'] for row in subset['instances']}
    lock = read_json(os.path.join(code_dir, 'external-sources.lock.json'))
    pricing_path = os.path.join(code_dir, 'pricing.json')
    pricing = pricing_mod.load_pricing(pricing_path)

    latest, superseded = newest_reports(eval_dir, args.run_label)
    cell_scope = args.run_id or args.run_label
    cells = index_cells(runs_root, cell_scope)
    attempts_index = index_attempts(runs_root, cell_scope)

    # What the run was actually configured with, gathered from the cells rather
    # than assumed. A page that hardcodes its model names lies the first time
    # someone runs a different tier.
    configuration = {'tiers': set(), 'claude': set(), 'codex': set(),
                     'glm': set(), 'kimi': set(),
                     'single_shot': set(), 'claude_effort': set(),
                     'codex_effort': set()}

    rows = []
    for condition in conditions:
        cond_id = condition['id']
        row = {
            'condition': cond_id,
            'label': condition['label'],
            'tier': condition['tier'],
            'description': condition['description'],
            'declared_dispatches': condition['dispatches'],
            'measured': False,
            'attempted': False,
            'report_file': None,
            'evaluator_run_id': None,
            'submitted': 0,
            'resolved': 0,
            'per_task': [],
            'telemetry': {
                'claude_dispatches': 0,
                'claude_cost_usd': 0.0,
                'claude_input_tokens': 0,
                'claude_cached_tokens': 0,
                'claude_output_tokens': 0,
                'claude_wall_seconds': 0,
                'codex_phases': 0,
                'codex_wall_seconds': 0,
                'codex_tokens': 0,
                'codex_input_tokens': 0,
                'codex_cached_tokens': 0,
                'codex_output_tokens': 0,
                'codex_cost_usd': 0.0,
                'codex_cost_low_usd': 0.0,
                'codex_cost_high_usd': 0.0,
                'codex_cli_versions': [],
                'glm_calls': 0,
                'glm_cost_usd': 0.0,
                'kimi_calls': 0,
                'kimi_cost_usd': 0.0,
                'cells_linked': 0,
                'sandbox_modes': [],
                'single_shot_attempts': [],
            },
        }
        precision_parts = []
        entry = latest.get((cond_id, 1))
        if entry is not None:
            run_id, report_path = entry
            report = read_json(report_path)
            model_name = 'co-evolution-condition-%s' % cond_id
            verdicts = per_instance_reports(eval_dir, run_id, model_name)
            patches = scored_patches(eval_dir, run_id, model_name)
            row['measured'] = True
            row['attempted'] = True
            row['report_file'] = rel(root, report_path)
            row['evaluator_run_id'] = run_id
            row['submitted'] = report.get('submitted_instances') or 0
            row['resolved'] = report.get('resolved_instances') or 0
            row['dataset_total_instances'] = report.get('total_instances')

            sandboxes, attempts = set(), []
            for instance in instances:
                verdict = verdicts.get(instance)
                if verdict is None:
                    attempt = attempts_index.get((cond_id, 1, instance))
                    row['per_task'].append({
                        'instance_id': instance, 'repo': repos[instance],
                        'status': 'no-patch' if attempt else 'not-submitted',
                        'attempt_outcome': attempt['outcome'] if attempt else None,
                        'attempts': attempt['attempts'] if attempt else None,
                        'evidence': (rel(root, os.path.join(attempt['cell_dir'], 'outcome.json'))
                                     if attempt else None),
                    })
                    if attempt:
                        row['attempted'] = True
                    continue
                cell = cells.get((cond_id, 1, instance,
                                  (patches.get(instance) or '').strip()))
                task = {
                    'instance_id': instance,
                    'repo': repos[instance],
                    'status': 'resolved' if verdict['resolved'] else 'unresolved',
                    'patch_applied': verdict['patch_applied'],
                    'fail_to_pass_passed': verdict['fail_to_pass_passed'],
                    'fail_to_pass_failed': verdict['fail_to_pass_failed'],
                    'pass_to_pass_failed': verdict['pass_to_pass_failed'],
                    'evidence': rel(root, verdict['report_file']),
                    'cell_dir': rel(root, cell) if cell else None,
                }
                row['per_task'].append(task)
                if cell:
                    telemetry = cell_telemetry(cell, pricing)
                    row['telemetry']['cells_linked'] += 1
                    for key in SUMMED_TELEMETRY:
                        row['telemetry'][key] += telemetry[key]
                    row['telemetry']['codex_cli_versions'] = sorted(
                        set(row['telemetry']['codex_cli_versions'])
                        | set(telemetry['codex_cli_versions']))
                    precision_parts += (telemetry['codex_precision']
                                        + telemetry['glm_precision']
                                        + telemetry['kimi_precision'])
                    if telemetry['sandbox']:
                        sandboxes.add(telemetry['sandbox'])
                    if telemetry.get('model_tier'):
                        configuration['tiers'].add(telemetry['model_tier'])
                    for key, value in (telemetry.get('models') or {}).items():
                        if value:
                            configuration[key].add(value)
                    for key, value in (telemetry.get('effort') or {}).items():
                        if value:
                            configuration[key + '_effort'].add(value)
                    if telemetry['single_shot_attempts'] is not None:
                        attempts.append(telemetry['single_shot_attempts'])
            row['telemetry']['sandbox_modes'] = sorted(sandboxes)
            row['telemetry']['single_shot_attempts'] = attempts
        else:
            for instance in instances:
                attempt = attempts_index.get((cond_id, 1, instance))
                if attempt:
                    row['attempted'] = True
                row['per_task'].append({
                    'instance_id': instance, 'repo': repos[instance],
                    'status': 'no-patch' if attempt else 'not-run',
                    'attempt_outcome': attempt['outcome'] if attempt else None,
                    'attempts': attempt['attempts'] if attempt else None,
                    'evidence': (rel(root, os.path.join(attempt['cell_dir'], 'outcome.json'))
                                 if attempt else None),
                })
        for key in ('claude_cost_usd', 'codex_cost_usd', 'codex_cost_low_usd',
                    'codex_cost_high_usd', 'glm_cost_usd', 'kimi_cost_usd'):
            row['telemetry'][key] = round(row['telemetry'][key], 4)

        # A task the arm actually ran, whether or not it yielded a patch. The
        # distinction matters: a task that ran and produced nothing is a zero,
        # but a task that was never reached is not a result at all. Scoring an
        # unreached task as zero understates an interrupted run as badly as
        # dropping a failed one would flatter a finished one.
        ran = [task for task in row['per_task']
               if task['status'] in ('resolved', 'unresolved', 'no-patch')]
        row['attempted_count'] = len(ran)
        row['complete'] = len(ran) == len(instances)

        # Effort per arm. Every seat that ran is priced at list rate from its
        # own token log; a seat that ran without a priceable figure leaves the
        # arm's cost flagged incomplete rather than silently short. The
        # precision says whether any seat was priced from a total-only log.
        telemetry = row['telemetry']
        telemetry['total_wall_seconds'] = (telemetry['claude_wall_seconds']
                                           + telemetry['codex_wall_seconds'])
        telemetry['cost_precision'] = pricing_mod.combine_precision(precision_parts)
        telemetry['cost_is_complete'] = (
            row['telemetry']['cells_linked'] > 0
            and telemetry['cost_precision'] != 'unpriced')
        telemetry['cost_usd'] = round(telemetry['claude_cost_usd']
                                      + telemetry['codex_cost_usd']
                                      + telemetry['glm_cost_usd']
                                      + telemetry['kimi_cost_usd'], 4)
        telemetry['cost_low_usd'] = round(telemetry['cost_usd'] - telemetry['codex_cost_usd']
                                          + telemetry['codex_cost_low_usd'], 4)
        telemetry['cost_high_usd'] = round(telemetry['cost_usd'] - telemetry['codex_cost_usd']
                                           + telemetry['codex_cost_high_usd'], 4)
        resolved = row['resolved'] or 0
        # An unpriced seat is not a free one. Emitting a per-resolved figure
        # for an arm whose cost is incomplete would read as cheap rather than
        # as unmeasured, so the figure is withheld until every seat is priced.
        telemetry['cost_per_resolved'] = (
            round(telemetry['cost_usd'] / resolved, 4)
            if resolved and telemetry['cost_usd'] and telemetry['cost_is_complete'] else None)
        telemetry['cost_per_task'] = (
            round(telemetry['cost_usd'] / telemetry['cells_linked'], 4)
            if telemetry['cells_linked'] and telemetry['cost_is_complete'] else None)
        telemetry['seconds_per_resolved'] = (
            round(telemetry['total_wall_seconds'] / resolved) if resolved else None)
        rows.append(row)

    payload = {
        'schema': 'code-bench-site/1.0',
        'generated_at': args.generated_at,
        'configuration': {key: sorted(value)
                          for key, value in configuration.items()},
        'harness': {
            'repo_commit': harness_commit(root),
            'working_tree_dirty': harness_dirty(root),
            'swebench_commit': lock.get('swebench', {}).get('commit'),
            'dataset': suite.get('dataset'),
            'dataset_revision': lock.get('dataset', {}).get('revision'),
            'lock_file': rel(root, os.path.join(code_dir, 'external-sources.lock.json')),
        },
        'pricing': {
            'file': rel(root, pricing_path),
            'recorded_on': pricing.get('recorded_on'),
            'codex_total_only_split': pricing['codex_total_only']['assumed_split'],
        },
        'suite': {
            'id': suite['id'],
            'dataset': suite['dataset'],
            'split': suite['split'],
            'task_count': suite['task_count'],
            'subset_file': rel(root, subset_path),
            'instances': [{'instance_id': i, 'repo': repos[i]} for i in instances],
        },
        'gold_canary': gold_canary(eval_dir),
        'rows': rows,
        'superseded_reports': [
            {'condition': cond, 'seed': seed, 'evaluator_run_id': run_id,
             'report_file': rel(root, path)}
            for cond, seed, run_id, path in sorted(superseded)
        ],
        'caveat': ('Frozen five-task probe of SWE-bench Verified, scored by the '
                   'official evaluator. One task is 20 points; these numbers are '
                   'not comparable to published full-500 SWE-bench Verified scores.'),
    }

    gold = payload['gold_canary']
    if gold:
        gold['report_file'] = rel(root, gold['report_file'])

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, 'w', encoding='utf-8', newline='\n') as handle:
        json.dump(payload, handle, indent=2, sort_keys=False)
        handle.write('\n')
    print(args.output)


if __name__ == '__main__':
    main()
