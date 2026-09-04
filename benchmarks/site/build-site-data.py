#!/usr/bin/env python3
"""Build the single JSON the results site renders (schema code-bench-site/2.0).

Every field here is read from a file on disk and carries the path it came
from, so a reader can check any number on the page against the evaluator's
own output. Nothing is entered by hand and nothing is inferred.

Sources:
  benchmarks/code/conditions.json          condition ids, labels, tiers, phases, seats
  benchmarks/code/suites.json              suite and subset pointer
  benchmarks/code/subsets/*.json           the frozen task list with difficulty labels
  benchmarks/code/external-sources.lock.json  evaluator and dataset pins
  benchmarks/code/pricing.json             list prices, dated
  benchmarks/code/runs.json                registry of runs and their provenance flags
  benchmarks/code/preregistration.json     declared phases and primary contrasts
  results/code/evaluation/*.json           official evaluator reports
  results/code/evaluation/logs/...         per-instance evaluator reports and scored patches
  results/code/runs/<label>/<task>/<cell>/ run manifests, provider logs, repair and selection records

A row is a configuration: one condition run under one batch label (which
fixes the model tier), over one or more seeds. Rows from different batches on
the same suite share tasks, so they can be contrasted pairwise.

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
import stats  # noqa: E402

SCHEMA = 'code-bench-site/2.0'
TITLE = 'Co-Evolution: cross-vendor review benchmark for coding agents'

# A seed>1 cell names its prediction co-evolution-condition-B.r2, and the
# evaluator names the report after that, so the seed is recoverable from the
# report file name alone.
REPORT_NAME_RE = re.compile(
    r'^co-evolution-condition-(?P<cond>[A-Za-z0-9_-]+?)(?:\.r(?P<seed>\d+))?\.(?P<run_id>[^.]+)\.json$')
MODEL_NAME_RE = re.compile(r'^co-evolution-condition-(?P<cond>[A-Za-z0-9_-]+?)(?:\.r(?P<seed>\d+))?$')
GOLD_NAME_RE = re.compile(r'^gold\.(?P<run_id>.+)\.json$')

BOOTSTRAP_DRAWS = 2000
BOOTSTRAP_SEED = 20260904
DIFFICULTY_ORDER = ['<15 min fix', '15 min - 1 hour', '1-4 hours', '>4 hours']
SEAT_DEFAULT_MODEL = {'glm': 'glm-5.3-flash', 'kimi': 'kimi-k3'}
SOLO_CONDITIONS = {'A', 'E', 'F', 'G'}

RESULTS_ROOT = None


def read_json(path):
    with open(path, encoding='utf-8') as handle:
        return json.load(handle)


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
    return proc.stdout.strip() if proc.returncode == 0 else None


def harness_dirty(root):
    proc = subprocess.run(('git', '-C', root, 'status', '--porcelain'),
                          capture_output=True, text=True)
    return bool(proc.stdout.strip()) if proc.returncode == 0 else None


# --- evaluator output ---------------------------------------------------------

def newest_reports(eval_dir, run_label):
    """Latest evaluator report per (condition, seed) for one batch label.

    A report is named for the evaluator run that produced it. The label is
    everything before the final "-"; the evaluator's timestamp suffix contains
    none. An exact match is required: a prefix test would make "base50" match
    "base50-light-2026...", so a frontier page would silently render
    light-tier results.
    """
    latest, superseded = {}, []
    for path in sorted(glob.glob(os.path.join(eval_dir, '*.json'))):
        match = REPORT_NAME_RE.match(os.path.basename(path))
        if not match:
            continue
        cond, run_id = match.group('cond'), match.group('run_id')
        seed = int(match.group('seed') or 1)
        if run_id.rsplit('-', 1)[0] != run_label:
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
        if match and (best is None or match.group('run_id') > best[0]):
            best = (match.group('run_id'), path)
    if best is None:
        return None
    data = read_json(best[1])
    return {'run_id': best[0], 'report_file': best[1],
            'submitted': data.get('submitted_instances'),
            'resolved': data.get('resolved_instances')}


def per_instance_reports(eval_dir, run_id, model_name):
    """The evaluator's own per-instance verdicts for one scored run."""
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


# --- cells --------------------------------------------------------------------

def index_cells(runs_root, run_label):
    """(condition, seed, instance, patch text) -> cell directory, one batch."""
    index = {}
    for path in glob.glob(os.path.join(runs_root, run_label, '*', '*', 'prediction.json')):
        try:
            record = read_json(path)
        except ValueError:
            continue
        match = MODEL_NAME_RE.match(record.get('model_name_or_path', ''))
        if not match:
            continue
        key = (match.group('cond'), int(match.group('seed') or 1),
               record.get('instance_id'), (record.get('model_patch') or '').strip())
        index[key] = os.path.dirname(path)
    return index


def index_attempts(runs_root, run_label):
    """Cells that ran and produced no patch, keyed by (condition, seed, instance)."""
    attempts = {}
    for path in glob.glob(os.path.join(runs_root, run_label, '*', '*', 'outcome.json')):
        try:
            record = read_json(path)
        except ValueError:
            continue
        if record.get('outcome') == 'patch-applied':
            continue
        key = (record.get('condition'), int(record.get('seed') or 1), record.get('instance'))
        attempts[key] = {'outcome': record.get('outcome'), 'attempts': record.get('attempts'),
                         'cell_dir': os.path.dirname(path)}
    return attempts


def _review_seat(cell_dir, review_path):
    """Which critic wrote reviewer-N.md, from the manifest's ordered roster."""
    try:
        critics = read_json(os.path.join(cell_dir, 'run-manifest.json')).get('critics') or []
    except (OSError, ValueError):
        return None
    match = re.search(r'reviewer-(\d+)\.md$', os.path.basename(review_path))
    if not match:
        return None
    index = int(match.group(1)) - 1
    return critics[index] if 0 <= index < len(critics) else None


def cell_telemetry(cell_dir, pricing):
    """Provider effort, cost and provenance for one cell, from its own files.

    Claude cost is the CLI's own dollar figure. Codex, GLM and Kimi report
    tokens only; those are priced at the tracked list rates by the pricing
    module, which also says whether the figure is exact or an estimate from a
    total-only log.
    """
    out = {
        'cell_dir': cell_dir,
        'claude_dispatches': 0, 'claude_cost_usd': 0.0,
        'claude_input_tokens': 0, 'claude_cached_tokens': 0, 'claude_output_tokens': 0,
        'claude_wall_seconds': 0,
        'codex_phases': 0, 'codex_wall_seconds': 0, 'codex_tokens': 0,
        'codex_input_tokens': 0, 'codex_cached_tokens': 0, 'codex_output_tokens': 0,
        'codex_cost_usd': 0.0, 'codex_cost_low_usd': 0.0, 'codex_cost_high_usd': 0.0,
        'codex_precision': [], 'codex_cli_versions': set(),
        'glm_calls': 0, 'glm_cost_usd': 0.0, 'glm_precision': [],
        'kimi_calls': 0, 'kimi_cost_usd': 0.0, 'kimi_precision': [],
        'single_shot_attempts': None, 'sandbox': None, 'model_tier': None,
        'models': {}, 'effort': {}, 'seats': {}, 'phases': [],
        'versions': {}, 'harness': None, 'repair': None, 'selection': None,
    }
    manifest = os.path.join(cell_dir, 'run-manifest.json')
    if os.path.isfile(manifest):
        try:
            data = read_json(manifest)
            out['sandbox'] = (data.get('sandbox') or {}).get('codex')
            models = data.get('models') or {}
            effort = data.get('effort') or {}
            out['model_tier'] = data.get('model_tier')
            out['models'] = {'claude': models.get('claude'), 'codex': models.get('codex'),
                             'glm': models.get('glm'), 'kimi': models.get('kimi'),
                             'single_shot': data.get('model')}
            if data.get('agent') in SEAT_DEFAULT_MODEL and data.get('model'):
                out['models'][data['agent']] = data['model']
            out['effort'] = {'claude': effort.get('claude'), 'codex': effort.get('codex')}
            out['seats'] = data.get('seats') or {}
            out['phases'] = data.get('phases') or []
            out['versions'] = {k: v for k, v in (data.get('versions') or {}).items() if v}
            out['harness'] = data.get('harness')
            out['schema'] = data.get('schema')
        except ValueError:
            pass
    outcome = os.path.join(cell_dir, 'outcome.json')
    if os.path.isfile(outcome):
        try:
            out['single_shot_attempts'] = read_json(outcome).get('attempts')
        except ValueError:
            pass
    repair = os.path.join(cell_dir, 'repair.json')
    if os.path.isfile(repair):
        try:
            record = read_json(repair)
            out['repair'] = {'inert': bool(record.get('repair_inert')),
                             'phases': record.get('repair_phases') or []}
        except ValueError:
            pass
    selection = os.path.join(cell_dir, 'selection.json')
    if os.path.isfile(selection):
        try:
            record = read_json(selection)
            out['selection'] = {'chosen': record.get('chosen'), 'rule': record.get('rule'),
                                'candidates': len(record.get('candidates') or [])}
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
            elif name.startswith('codex-') and name.endswith('.stderr.log'):
                # Each Codex phase writes a transcript and a stderr log; the
                # pair is one phase. The stderr log is the anchor because the
                # transcript may be JSONL events or prose depending on flags.
                out['codex_phases'] += 1
                transcript = path[:-len('.stderr.log')] + '.log'
                phase = pricing_mod.price_codex_phase(
                    pricing, out['models'].get('codex'), transcript, path)
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
        artifacts = glob.glob(os.path.join(logs, '%s-response-*.md' % seat))
        artifacts += [p for p in glob.glob(os.path.join(cell_dir, 'reviews', 'reviewer-*.md'))
                      if _review_seat(cell_dir, p) == seat]
        for artifact in artifacts:
            out[seat + '_calls'] += 1
            model = out['models'].get(seat) or SEAT_DEFAULT_MODEL[seat]
            priced = pricing_mod.price_sidecar(pricing, model, artifact + '.usage.json')
            if priced:
                out[seat + '_cost_usd'] += priced['cost_usd']
                out[seat + '_precision'].append('exact')
            else:
                out[seat + '_precision'].append('unpriced')
    out['codex_cli_versions'] = sorted(out['codex_cli_versions'])
    out['wall_seconds'] = out['claude_wall_seconds'] + out['codex_wall_seconds']
    out['cost_usd'] = (out['claude_cost_usd'] + out['codex_cost_usd']
                       + out['glm_cost_usd'] + out['kimi_cost_usd'])
    out['tokens'] = (out['claude_input_tokens'] + out['claude_cached_tokens']
                     + out['claude_output_tokens'] + out['codex_tokens'])
    return out


SUMMED_TELEMETRY = (
    'claude_dispatches', 'claude_cost_usd', 'claude_input_tokens',
    'claude_cached_tokens', 'claude_output_tokens', 'claude_wall_seconds',
    'codex_phases', 'codex_wall_seconds', 'codex_tokens', 'codex_input_tokens',
    'codex_cached_tokens', 'codex_output_tokens', 'codex_cost_usd',
    'codex_cost_low_usd', 'codex_cost_high_usd', 'glm_calls', 'glm_cost_usd',
    'kimi_calls', 'kimi_cost_usd',
)


def empty_telemetry():
    out = {key: 0 for key in SUMMED_TELEMETRY}
    for key in ('claude_cost_usd', 'codex_cost_usd', 'codex_cost_low_usd',
                'codex_cost_high_usd', 'glm_cost_usd', 'kimi_cost_usd'):
        out[key] = 0.0
    out.update({'cells_linked': 0, 'repair_cells': 0, 'repair_inert_count': 0,
                'selection_cells': 0, 'selection_apply_only': 0,
                'patch_not_applied': 0, 'codex_cli_versions': [],
                'sandbox_modes': [], 'single_shot_attempts': []})
    return out


def percentile(values, q):
    if not values:
        return None
    ordered = sorted(values)
    index = int(round((len(ordered) - 1) * q))
    return ordered[index]


# --- configuration naming ---------------------------------------------------

def seat_model(seat, models):
    if seat == 'fable':
        return models.get('claude') or 'claude'
    if seat == 'codex':
        return models.get('codex') or 'codex'
    if seat in ('glm', 'kimi'):
        return models.get(seat) or SEAT_DEFAULT_MODEL[seat]
    if seat == 'select':
        return 'repo tests'
    return seat


def configuration_name(condition, models):
    """implementer -> reviewer(s), with the models that actually ran."""
    phases = condition.get('phases') or []
    if condition['tier'] == 'single-shot':
        seat = next((k for k, v in condition['dispatches'].items() if v), None)
        model = seat_model(seat, models)
        return '%s (single-shot)' % model, model, []
    implementer = seat_model(phases[0].split('-')[0], models) if phases else None
    reviewers = []
    for phase in phases[1:]:
        seat = seat_model(phase.split('-')[0], models)
        if seat not in reviewers:
            reviewers.append(seat)
    if reviewers:
        name = '%s → %s' % (implementer, ' + '.join(reviewers))
    else:
        name = '%s solo' % implementer
    return name, implementer, reviewers


def resolve_pipeline(condition, models):
    text = condition.get('pipeline') or condition.get('description') or ''
    return (text.replace('{claude}', models.get('claude') or 'claude')
                .replace('{codex}', models.get('codex') or 'codex'))


def reproduce_command(suite_id, run_label, condition, tier, sandbox_modes, seeds, task_count):
    """A copy-paste command that would regenerate and score this row."""
    env = ['CODE_BENCH_SUITE=%s' % suite_id]
    if sandbox_modes and sandbox_modes != ['workspace-write']:
        env.append('CODE_BENCH_CODEX_SANDBOX=%s' % sandbox_modes[0])
    claude = condition['dispatches']['claude'] * task_count * len(seeds)
    lines = [
        '%s bash benchmarks/code/code-bench.sh run-canary --run-id %s --models %s \\'
        % (' '.join(env), run_label, tier or 'frontier'),
        '  --conditions %s --task-limit %d%s --max-claude-dispatches %d'
        % (condition['id'], task_count,
           (' --repeat %d' % len(seeds)) if len(seeds) > 1 else '', claude),
    ]
    for seed in seeds:
        cell = condition['id'] if seed == 1 else '%s.r%d' % (condition['id'], seed)
        lines.append('bash benchmarks/code/code-bench.sh evaluate '
                     'benchmarks/results/code/predictions/%s/%s.jsonl --label %s'
                     % (run_label, cell, run_label))
    lines.append('bash benchmarks/site/aggregate.sh --suite %s --run-label %s'
                 % (suite_id, run_label))
    return '\n'.join(lines)


# --- rows ---------------------------------------------------------------------

def build_row(root, eval_dir, condition, run, seeds, latest, cells, attempts_index,
              instances, repos, difficulties, pricing, suite_id):
    cond_id = condition['id']
    label = run['label']
    row = {
        'id': '%s@%s' % (cond_id, label),
        'condition': cond_id,
        'label': condition['label'],
        'tier': condition['tier'],
        'mixed_tier': bool(condition.get('mixed_tier')),
        'run_label': label,
        'model_tier': run.get('model_tier'),
        'description': condition['description'],
        'declared_dispatches': condition['dispatches'],
        'phases': condition.get('phases') or [],
        'seeds': seeds,
        'measured': False,
        'attempted': False,
        'reports': [],
        'per_task': [],
        'telemetry': empty_telemetry(),
    }
    precision_parts = []
    models = {}
    efforts = {}
    tiers = set()
    versions = {}
    harness_records = []
    walls, costs = [], []
    for seed in seeds:
        entry = latest.get((cond_id, seed))
        verdicts, patches = {}, {}
        if entry is not None:
            run_id, report_path = entry
            report = read_json(report_path)
            model_name = 'co-evolution-condition-%s%s' % (cond_id, '' if seed == 1 else '.r%d' % seed)
            verdicts = per_instance_reports(eval_dir, run_id, model_name)
            patches = scored_patches(eval_dir, run_id, model_name)
            row['measured'] = True
            row['attempted'] = True
            row['reports'].append({'seed': seed, 'evaluator_run_id': run_id,
                                   'report_file': rel(root, report_path),
                                   'submitted': report.get('submitted_instances') or 0,
                                   'resolved': report.get('resolved_instances') or 0,
                                   'dataset_total_instances': report.get('total_instances')})
        for instance in instances:
            verdict = verdicts.get(instance)
            base = {'instance_id': instance, 'repo': repos[instance],
                    'difficulty': difficulties.get(instance), 'seed': seed}
            if verdict is None:
                attempt = attempts_index.get((cond_id, seed, instance))
                task = dict(base)
                task.update({
                    'status': 'no-patch' if attempt else ('not-submitted' if entry else 'not-run'),
                    'attempt_outcome': attempt['outcome'] if attempt else None,
                    'attempts': attempt['attempts'] if attempt else None,
                    'evidence': (rel(root, os.path.join(attempt['cell_dir'], 'outcome.json'))
                                 if attempt else None),
                })
                if attempt:
                    row['attempted'] = True
                    telemetry = cell_telemetry(attempt['cell_dir'], pricing)
                    _absorb(row, telemetry, precision_parts, models, efforts, tiers,
                            versions, harness_records, walls, costs, task)
                row['per_task'].append(task)
                continue
            cell = cells.get((cond_id, seed, instance, (patches.get(instance) or '').strip()))
            task = dict(base)
            task.update({
                'status': 'resolved' if verdict['resolved'] else 'unresolved',
                'patch_applied': verdict['patch_applied'],
                'fail_to_pass_passed': verdict['fail_to_pass_passed'],
                'fail_to_pass_failed': verdict['fail_to_pass_failed'],
                'pass_to_pass_failed': verdict['pass_to_pass_failed'],
                'evidence': rel(root, verdict['report_file']),
                'cell_dir': rel(root, cell) if cell else None,
            })
            if not verdict['patch_applied']:
                row['telemetry']['patch_not_applied'] += 1
            if cell:
                telemetry = cell_telemetry(cell, pricing)
                _absorb(row, telemetry, precision_parts, models, efforts, tiers,
                        versions, harness_records, walls, costs, task)
            row['per_task'].append(task)

    telemetry = row['telemetry']
    for key in ('claude_cost_usd', 'codex_cost_usd', 'codex_cost_low_usd',
                'codex_cost_high_usd', 'glm_cost_usd', 'kimi_cost_usd'):
        telemetry[key] = round(telemetry[key], 4)
    telemetry['sandbox_modes'] = sorted(telemetry['sandbox_modes'])
    telemetry['codex_cli_versions'] = sorted(telemetry['codex_cli_versions'])
    ran = [t for t in row['per_task'] if t['status'] in ('resolved', 'unresolved', 'no-patch')]
    row['attempted_count'] = len(ran)
    row['cells_expected'] = len(instances) * len(seeds)
    row['complete'] = len(ran) == row['cells_expected']
    row['submitted'] = sum(r['submitted'] for r in row['reports'])
    row['resolved'] = sum(1 for t in ran if t['status'] == 'resolved')

    # Effort. Every seat that ran is priced at list rate from its own token
    # log; a seat that ran without a priceable figure leaves the arm's cost
    # flagged incomplete rather than silently short.
    telemetry['total_wall_seconds'] = telemetry['claude_wall_seconds'] + telemetry['codex_wall_seconds']
    telemetry['cost_precision'] = pricing_mod.combine_precision(precision_parts)
    telemetry['cost_is_complete'] = (telemetry['cells_linked'] > 0
                                     and telemetry['cost_precision'] != 'unpriced')
    telemetry['cost_usd'] = round(telemetry['claude_cost_usd'] + telemetry['codex_cost_usd']
                                  + telemetry['glm_cost_usd'] + telemetry['kimi_cost_usd'], 4)
    telemetry['cost_low_usd'] = round(telemetry['cost_usd'] - telemetry['codex_cost_usd']
                                      + telemetry['codex_cost_low_usd'], 4)
    telemetry['cost_high_usd'] = round(telemetry['cost_usd'] - telemetry['codex_cost_usd']
                                       + telemetry['codex_cost_high_usd'], 4)
    linked = telemetry['cells_linked']
    resolved = row['resolved']
    complete_cost = telemetry['cost_is_complete']
    telemetry['cost_per_task'] = round(telemetry['cost_usd'] / linked, 4) if linked and complete_cost else None
    telemetry['cost_per_resolved'] = (round(telemetry['cost_usd'] / resolved, 4)
                                      if resolved and complete_cost else None)
    telemetry['tokens'] = (telemetry['claude_input_tokens'] + telemetry['claude_cached_tokens']
                           + telemetry['claude_output_tokens'] + telemetry['codex_tokens'])
    telemetry['tokens_per_task'] = round(telemetry['tokens'] / linked) if linked else None
    telemetry['wall_per_task'] = round(telemetry['total_wall_seconds'] / linked) if linked else None
    telemetry['wall_p50'] = percentile(walls, 0.5)
    telemetry['wall_p90'] = percentile(walls, 0.9)
    telemetry['seconds_per_resolved'] = (round(telemetry['total_wall_seconds'] / resolved)
                                         if resolved else None)

    row['models'] = {k: sorted(v)[0] if len(v) == 1 else sorted(v) for k, v in models.items() if v}
    flat_models = {k: (v if isinstance(v, str) else v[0]) for k, v in row['models'].items()}
    row['effort'] = {k: sorted(v) for k, v in efforts.items() if v}
    row['seats'] = condition.get('seats') or {}
    name, implementer, reviewers = configuration_name(condition, flat_models)
    row['configuration'] = name
    row['implementer'] = implementer
    row['reviewers'] = reviewers
    row['pipeline'] = resolve_pipeline(condition, flat_models)
    if tiers and row['model_tier'] is None:
        row['model_tier'] = sorted(tiers)[0]
    row['provenance'] = {
        'ran_by': run.get('ran_by') or 'unknown',
        'publishable': run.get('publishable'),
        'run_note': run.get('note'),
        'registered': run.get('registered', True),
        'evaluator_run_ids': [r['evaluator_run_id'] for r in row['reports']],
        'report_files': [r['report_file'] for r in row['reports']],
        'harness_commit': _consensus([h.get('commit') for h in harness_records if h]),
        'harness_dirty': _consensus([h.get('dirty') for h in harness_records if h]),
        'harness_recorded': any(h for h in harness_records),
        'cli_versions': {k: sorted(v) for k, v in versions.items() if v},
        'sandbox_modes': telemetry['sandbox_modes'],
    }
    row['reproduce'] = reproduce_command(suite_id, label, condition, run.get('model_tier'),
                                         telemetry['sandbox_modes'], seeds, len(instances))
    return row


def _consensus(values):
    values = [v for v in values if v is not None]
    if not values:
        return None
    distinct = sorted({str(v) for v in values})
    return values[0] if len(distinct) == 1 else 'mixed: ' + ', '.join(distinct)


def _absorb(row, telemetry, precision_parts, models, efforts, tiers, versions,
            harness_records, walls, costs, task):
    """Fold one cell's telemetry into the row and annotate its task entry."""
    t = row['telemetry']
    t['cells_linked'] += 1
    for key in SUMMED_TELEMETRY:
        t[key] += telemetry[key]
    t['codex_cli_versions'] = sorted(set(t['codex_cli_versions']) | set(telemetry['codex_cli_versions']))
    precision_parts.extend(telemetry['codex_precision'] + telemetry['glm_precision']
                           + telemetry['kimi_precision'])
    if telemetry['sandbox']:
        t['sandbox_modes'] = sorted(set(t['sandbox_modes']) | {telemetry['sandbox']})
    if telemetry.get('model_tier'):
        tiers.add(telemetry['model_tier'])
    for key, value in (telemetry.get('models') or {}).items():
        if value:
            models.setdefault(key, set()).add(value)
    for key, value in (telemetry.get('effort') or {}).items():
        if value:
            efforts.setdefault(key, set()).add(value)
    for key, value in (telemetry.get('versions') or {}).items():
        versions.setdefault(key, set()).add(value)
    for version in telemetry['codex_cli_versions']:
        versions.setdefault('codex', set()).add(version)
    harness_records.append(telemetry.get('harness'))
    if telemetry['single_shot_attempts'] is not None:
        t['single_shot_attempts'].append(telemetry['single_shot_attempts'])
    if telemetry.get('repair') is not None:
        t['repair_cells'] += 1
        task['repair_inert'] = telemetry['repair']['inert']
        if telemetry['repair']['inert']:
            t['repair_inert_count'] += 1
    if telemetry.get('selection') is not None:
        t['selection_cells'] += 1
        task['selection'] = telemetry['selection']
        if telemetry['selection'].get('rule') == 'apply-only':
            t['selection_apply_only'] += 1
    task['wall_seconds'] = telemetry['wall_seconds']
    task['cost_usd'] = round(telemetry['cost_usd'], 4)
    walls.append(telemetry['wall_seconds'])
    costs.append(telemetry['cost_usd'])


# --- statistics across rows ---------------------------------------------------

def outcome_cells(row):
    """Scored tasks of one row as bootstrap cells: {task, repo, seed, resolved}."""
    return [{'task': t['instance_id'], 'repo': t['repo'], 'seed': t['seed'],
             'resolved': t['status'] == 'resolved'}
            for t in row['per_task'] if t['status'] in ('resolved', 'unresolved', 'no-patch')]


def attach_statistics(rows, task_count):
    """Wilson and bootstrap intervals and Rank(UB) per row; contrasts per pair.

    Every figure the page shows with a +- comes from here, computed from the
    per-task verdicts already in the row, so the JSON stays the single source
    the renderer reads.
    """
    scored = [r for r in rows if r['measured'] or r.get('attempted')]
    for row in scored:
        cells = outcome_cells(row)
        n = row['cells_expected'] if row['complete'] else len(cells)
        k = sum(1 for c in cells if c['resolved'])
        low, high = stats.wilson(k, n)
        row['score'] = {'resolved': k, 'n': n, 'rate': (k / n) if n else None,
                        'wilson_low': low, 'wilson_high': high, 'seeds': len(row['seeds'])}
        row['bootstrap'] = (stats.hierarchical_bootstrap(cells, n_boot=BOOTSTRAP_DRAWS,
                                                         seed=BOOTSTRAP_SEED) if cells else None)
        row['seed_summary'] = stats.seed_summary(cells) if len(row['seeds']) > 1 and cells else None
    # Rank(UB) among complete rows of the same test tier, across batches: an
    # unfinished arm has no comparable interval, and a single-shot arm is a
    # different test. Rows flagged unpublishable are ranked but the page says so.
    for tier in sorted({r['tier'] for r in scored}):
        entries = [(r['id'], r['score']['wilson_low'], r['score']['wilson_high'])
                   for r in scored if r['tier'] == tier and r['complete']]
        ranks = stats.rank_by_upper_bound(entries)
        for r in scored:
            if r['tier'] == tier:
                r['rank_ub'] = ranks.get(r['id'])
    contrasts = []
    for i, first in enumerate(scored):
        for second in scored[i + 1:]:
            if first['tier'] != second['tier']:
                continue
            a = {t['instance_id']: t['status'] == 'resolved' for t in first['per_task']
                 if t['status'] in ('resolved', 'unresolved', 'no-patch') and t['seed'] == 1}
            b = {t['instance_id']: t['status'] == 'resolved' for t in second['per_task']
                 if t['status'] in ('resolved', 'unresolved', 'no-patch') and t['seed'] == 1}
            table = stats.discordance(a, b)
            if table['n'] == 0:
                continue
            p_value = stats.mcnemar_exact(table['only_a'], table['only_b'])
            delta = stats.hierarchical_bootstrap(outcome_cells(second), n_boot=BOOTSTRAP_DRAWS,
                                                 seed=BOOTSTRAP_SEED,
                                                 deltas_against=outcome_cells(first))
            ta, tb = first['telemetry'], second['telemetry']
            cost_a = ta['cost_per_task'] if ta['cost_is_complete'] else None
            cost_b = tb['cost_per_task'] if tb['cost_is_complete'] else None
            cost_delta = ((cost_b - cost_a) * table['n']) if (cost_a is not None and cost_b is not None) else None
            net = table['net_b_minus_a']
            contrasts.append({
                'a': first['id'], 'b': second['id'],
                'a_condition': first['condition'], 'b_condition': second['condition'],
                'n': table['n'], 'both': table['both'], 'only_a': table['only_a'],
                'only_b': table['only_b'], 'neither': table['neither'],
                'excluded': table['excluded'],
                'rescued_by_b': table['rescued_by_b'], 'broken_by_b': table['broken_by_b'],
                'net_b_minus_a': net,
                'mcnemar_exact_p': p_value,
                'delta_b_minus_a': delta,
                'cost_delta_usd': round(cost_delta, 4) if cost_delta is not None else None,
                'cost_per_net_flip_usd': (round(cost_delta / net, 4)
                                          if cost_delta is not None and net > 0 else None),
                'cost_is_complete': cost_delta is not None,
            })
    return contrasts


def pareto_sets(rows):
    """Row ids on the Pareto frontier for each x axis (lower x, higher rate)."""
    axes = {'cost': 'cost_per_task', 'wall': 'wall_per_task', 'tokens': 'tokens_per_task'}
    result = {}
    for axis, key in axes.items():
        points = [(r['id'], r['telemetry'].get(key), r['score']['rate'])
                  for r in rows if r.get('score') and r['complete']
                  and r['telemetry'].get(key) is not None and r['score']['rate'] is not None]
        frontier = []
        for ident, x, y in points:
            dominated = any((ox <= x and oy >= y) and (ox < x or oy > y)
                            for oid, ox, oy in points if oid != ident)
            if not dominated:
                frontier.append(ident)
        result[axis] = sorted(frontier)
    return result


def task_matrix(rows, instances, repos, difficulties):
    """Per-task view across configurations, grouped by difficulty then repo."""
    scored = [r for r in rows if r.get('score')]
    tasks = {}
    for instance in instances:
        entry = {'instance_id': instance, 'repo': repos[instance],
                 'difficulty': difficulties.get(instance), 'cells': {}}
        solo_resolved = review_resolved = False
        for row in scored:
            seeds = [t for t in row['per_task'] if t['instance_id'] == instance]
            statuses = [t['status'] for t in seeds]
            resolved = sum(1 for s in statuses if s == 'resolved')
            ran = sum(1 for s in statuses if s in ('resolved', 'unresolved', 'no-patch'))
            entry['cells'][row['id']] = {
                'resolved': resolved, 'ran': ran, 'seeds': len(seeds),
                'status': (statuses[0] if len(statuses) == 1 else
                           ('resolved' if resolved == ran and ran else
                            'mixed' if resolved else ('unresolved' if ran else 'not-run'))),
                'repair_inert': any(t.get('repair_inert') for t in seeds),
                'patch_applied': all(t.get('patch_applied', True) for t in seeds),
            }
            if resolved:
                if row['condition'] in SOLO_CONDITIONS:
                    solo_resolved = True
                else:
                    review_resolved = True
        entry['solo_resolved'] = solo_resolved
        entry['review_resolved'] = review_resolved
        entry['rescued_by_review'] = review_resolved and not solo_resolved
        entry['resolved_by'] = sorted(k for k, v in entry['cells'].items() if v['resolved'])
        tasks[instance] = entry
    order = sorted(instances, key=lambda i: (
        DIFFICULTY_ORDER.index(difficulties[i]) if difficulties.get(i) in DIFFICULTY_ORDER else 99,
        repos[i], i))
    return {'order': order, 'tasks': tasks, 'difficulty_order': DIFFICULTY_ORDER}


def methodology(prereg, suite_block, rows, contrasts):
    power = prereg['analysis']['power_assumptions']
    table = []
    for d in power['discordance_rates']:
        for e in power['effects']:
            table.append({'discordance_rate': d, 'effect': e,
                          'paired_observations': stats.power_paired(d, e, power['alpha'], power['power'])})
    phases = []
    by_condition = {}
    for row in rows:
        by_condition.setdefault(row['condition'], []).append(row)
    for phase in prereg['phases']:
        primary = dict(phase['primary_contrast'])
        observed = None
        for c in contrasts:
            if {c['a_condition'], c['b_condition']} == {primary['a'], primary['b']}:
                observed = c
                break
        phases.append({**phase, 'primary_contrast': primary,
                       'observed': ({'contrast': observed['a'] + ' vs ' + observed['b'],
                                     'only_a': observed['only_a'], 'only_b': observed['only_b'],
                                     'mcnemar_exact_p': observed['mcnemar_exact_p'],
                                     'delta': observed['delta_b_minus_a']}
                                    if observed else None),
                       'arms_measured': sorted(a for a in phase['arms'] if a in by_condition)})
    return {'preregistration': {k: v for k, v in prereg.items() if k != 'phases'},
            'phases': phases, 'power_table': table,
            'sampling': suite_block.get('sampling'),
            'difficulty': suite_block.get('difficulty_annotation')}


# --- main ---------------------------------------------------------------------

def main():
    global RESULTS_ROOT
    ap = argparse.ArgumentParser()
    ap.add_argument('--repo-root', required=True)
    ap.add_argument('--results-root', required=True)
    ap.add_argument('--suite', default='swebench-verified-canary')
    ap.add_argument('--output', required=True)
    ap.add_argument('--generated-at', required=True, help='UTC timestamp supplied by the caller')
    ap.add_argument('--run-label', action='append', default=[],
                    help='batch label(s) to read; default: every registered run of the suite')
    ap.add_argument('--run-id', default=None, help='ignored; kept for old callers')
    args = ap.parse_args()

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
    difficulties = {row['instance_id']: row.get('difficulty') for row in subset['instances']}
    lock = read_json(os.path.join(code_dir, 'external-sources.lock.json'))
    pricing_path = os.path.join(code_dir, 'pricing.json')
    pricing = pricing_mod.load_pricing(pricing_path)
    registry = read_json(os.path.join(code_dir, 'runs.json'))['runs']
    prereg = read_json(os.path.join(code_dir, 'preregistration.json'))

    registered = {r['label']: r for r in registry}
    labels = args.run_label or [r['label'] for r in registry if r['suite'] == suite['id']]
    runs, rows, superseded_all = [], [], []
    for label in labels:
        run = dict(registered.get(label) or {'label': label, 'suite': suite['id'],
                                             'model_tier': None, 'publishable': None,
                                             'ran_by': 'unknown', 'registered': False,
                                             'note': 'run label not in benchmarks/code/runs.json'})
        run.setdefault('registered', True)
        latest, superseded = newest_reports(eval_dir, run.get('evaluator_label') or label)
        cells = index_cells(runs_root, label)
        attempts_index = index_attempts(runs_root, label)
        superseded_all += [(label,) + s for s in superseded]
        measured_conditions = []
        for condition in conditions:
            cond_id = condition['id']
            seeds = sorted({seed for (cond, seed) in latest if cond == cond_id}
                           | {seed for (cond, seed, _) in attempts_index if cond == cond_id})
            if not seeds:
                continue
            row = build_row(root, eval_dir, condition, run, seeds, latest, cells,
                            attempts_index, instances, repos, difficulties, pricing, suite['id'])
            rows.append(row)
            measured_conditions.append(cond_id)
        run_rows = [r for r in rows if r['run_label'] == label]
        run_models = {}
        for row in run_rows:
            for key, value in row['models'].items():
                run_models.setdefault(key, set()).update([value] if isinstance(value, str) else value)
        run['models'] = {k: sorted(v) for k, v in run_models.items()}
        run['conditions_measured'] = measured_conditions
        run['conditions_not_run'] = [c['id'] for c in conditions if c['id'] not in measured_conditions]
        run['harness_commit'] = _consensus([r['provenance']['harness_commit'] for r in run_rows])
        run['harness_dirty'] = _consensus([r['provenance']['harness_dirty'] for r in run_rows])
        run['harness_recorded'] = any(r['provenance']['harness_recorded'] for r in run_rows)
        runs.append(run)

    contrasts = attach_statistics(rows, len(instances))
    suite_block = {
        'id': suite['id'], 'dataset': suite['dataset'], 'split': suite['split'],
        'task_count': suite['task_count'], 'subset_file': rel(root, subset_path),
        'sampling': subset.get('sampling'),
        'difficulty_annotation': (subset.get('annotations') or {}).get('difficulty'),
        'instances': [{'instance_id': i, 'repo': repos[i], 'difficulty': difficulties.get(i)}
                      for i in instances],
    }
    payload = {
        'schema': SCHEMA,
        'title': TITLE,
        'generated_at': args.generated_at,
        'harness': {
            'build_commit': harness_commit(root),
            'build_tree_dirty': harness_dirty(root),
            'swebench_commit': lock.get('swebench', {}).get('commit'),
            'dataset': suite.get('dataset'),
            'dataset_revision': lock.get('dataset', {}).get('revision'),
            'lock_file': rel(root, os.path.join(code_dir, 'external-sources.lock.json')),
            'conditions_file': rel(root, os.path.join(code_dir, 'conditions.json')),
            'runs_file': rel(root, os.path.join(code_dir, 'runs.json')),
        },
        'pricing': {
            'file': rel(root, pricing_path),
            'recorded_on': pricing.get('recorded_on'),
            'models': pricing.get('models'),
            'codex_total_only_split': pricing['codex_total_only']['assumed_split'],
        },
        'statistics': {
            'interval': 'Wilson score, 95%',
            'paired_test': 'exact two-sided McNemar on discordant tasks',
            'bootstrap': {'levels': ['repo', 'task', 'seed'], 'draws': BOOTSTRAP_DRAWS,
                          'rng_seed': BOOTSTRAP_SEED, 'interval': 'percentile 2.5-97.5'},
            'rank': 'Rank(UB): 1 + number of arms whose interval lower bound exceeds this upper bound',
            'module': 'benchmarks/site/stats.py',
        },
        'suite': suite_block,
        'gold_canary': gold_canary(eval_dir),
        'runs': runs,
        'rows': rows,
        'contrasts': contrasts,
        'pareto': pareto_sets(rows),
        'task_matrix': task_matrix(rows, instances, repos, difficulties),
        'methodology': methodology(prereg, suite_block, rows, contrasts),
        'superseded_reports': [
            {'run_label': label, 'condition': cond, 'seed': seed, 'evaluator_run_id': run_id,
             'report_file': rel(root, path)}
            for label, cond, seed, run_id, path in sorted(superseded_all)
        ],
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
