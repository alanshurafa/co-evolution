#!/usr/bin/env python3
"""Write a synthetic results tree the site builder can aggregate.

The builder reads evaluator reports, per-instance verdicts, scored patches, and
cell directories. This lays all of those out under a temporary results root
from a compact JSON spec, so the site tests exercise the real builder against
known inputs without a model call or a Docker run.

Spec (JSON on stdin or --spec FILE):

  {
    "run_label": "fx",
    "conditions": {
      "A": {"seed": 1, "tier": "light", "cells": {
          "sympy__sympy-20916": {"resolved": true, "claude_cost": 1.0,
                                 "codex": "exact" | "total" | null,
                                 "repair_inert": false, "glm": "sidecar"|"bare"|null,
                                 "kimi": ..., "applied": true,
                                 "no_patch": false}
      }}
    }
  }

Every cell gets a prediction.json whose patch is unique to (condition,
instance, seed), and the evaluator's patch.diff carries the same text so the
builder links the cell the way it does for a real run.
"""
import argparse
import json
import os
import sys


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'w', encoding='utf-8', newline='\n') as handle:
        handle.write(text)


def write_json(path, payload):
    write(path, json.dumps(payload, indent=2) + '\n')


def patch_text(cond, instance, seed):
    return ('diff --git a/%s.py b/%s.py\n--- a/%s.py\n+++ b/%s.py\n'
            '@@ -1 +1 @@\n-old\n+new %s %s seed%d\n'
            % (instance, instance, instance, instance, cond, instance, seed))


def build(root, spec):
    label = spec['run_label']
    eval_dir = os.path.join(root, 'evaluation')
    runs = os.path.join(root, 'runs', label)
    for cond, block in spec['conditions'].items():
        seed = int(block.get('seed') or 1)
        tier = block.get('tier', 'light')
        suffix = '' if seed == 1 else '.r%d' % seed
        model_name = 'co-evolution-condition-%s%s' % (cond, suffix)
        eval_run = '%s-2026090%dT000000Z' % (label, seed)
        resolved_ids, unresolved_ids, submitted = [], [], []
        for instance, cell_spec in block['cells'].items():
            cell = os.path.join(runs, instance, cond + suffix)
            write_json(os.path.join(cell, 'input.json'),
                       {'instance_id': instance, 'condition': cond, 'seed': seed})
            manifest = {
                'schema': 'code-bench-run/1.0', 'instance': instance,
                'condition': cond, 'seed': seed, 'model_tier': tier,
                'models': {'claude': 'sonnet' if tier == 'light' else 'fable',
                           'codex': 'gpt-5.6-terra' if tier == 'light' else 'gpt-5.6-sol',
                           'glm': 'glm-5.3-flash', 'kimi': 'kimi-k3'},
                'effort': {'claude': '', 'codex': 'medium'},
                'sandbox': {'codex': 'danger-full-access'},
                'critics': block.get('critics', []),
                'phase_timeout_seconds': 900,
                'declared_claude_dispatches': 1,
                'harness': {'commit': 'fixturecommit', 'dirty': False},
            }
            write_json(os.path.join(cell, 'run-manifest.json'), manifest)
            logs = os.path.join(cell, 'logs')
            if cell_spec.get('claude_cost') is not None:
                write_json(os.path.join(logs, 'fable-implement.json'), {
                    'type': 'result', 'is_error': False, 'result': 'done',
                    'duration_ms': 60000, 'total_cost_usd': cell_spec['claude_cost'],
                    'usage': {'input_tokens': 100, 'cache_creation_input_tokens': 900,
                              'cache_read_input_tokens': 50000, 'output_tokens': 2000}})
            codex = cell_spec.get('codex')
            if codex:
                stderr = ('OpenAI Codex v0.144.5\n--------\n'
                          '2026-09-04T00:00:00Z start\n2026-09-04T00:02:00Z end\n'
                          'tokens used\n100,000\n')
                write(os.path.join(logs, 'codex-repair.stderr.log'), stderr)
                if codex == 'exact':
                    events = [
                        {'type': 'turn.started'},
                        {'type': 'turn.completed', 'usage': {
                            'input_tokens': 80000, 'cached_input_tokens': 60000,
                            'output_tokens': 20000}},
                    ]
                    write(os.path.join(logs, 'codex-repair.log'),
                          ''.join(json.dumps(e) + '\n' for e in events))
                else:
                    write(os.path.join(logs, 'codex-repair.log'), 'prose transcript\n')
            for seat in ('glm', 'kimi'):
                mode = cell_spec.get(seat)
                if not mode:
                    continue
                critics = block.get('critics', [])
                if seat in critics:
                    artifact = os.path.join(cell, 'reviews',
                                            'reviewer-%d.md' % (critics.index(seat) + 1))
                else:
                    artifact = os.path.join(logs, '%s-response-1.md' % seat)
                write(artifact, 'review text\n')
                if mode == 'sidecar':
                    write_json(artifact + '.usage.json', {
                        'input_tokens': 10000, 'output_tokens': 1000,
                        'cache_read_input_tokens': 0, 'cache_creation_input_tokens': None,
                        'total_cost_usd': None, 'source': 'fixture'})
            if cell_spec.get('repair') is not None:
                write_json(os.path.join(cell, 'repair.json'), {
                    'schema': 'code-bench-repair/1.0',
                    'before_sha256': 'aaa', 'after_sha256': 'aaa' if cell_spec['repair'] == 'inert' else 'bbb',
                    'repair_inert': cell_spec['repair'] == 'inert',
                    'repair_phase': 'codex-repair'})
            if cell_spec.get('selection') is not None:
                write_json(os.path.join(cell, 'selection.json'), cell_spec['selection'])
            if cell_spec.get('no_patch'):
                write_json(os.path.join(cell, 'outcome.json'), {
                    'schema': 'code-bench-outcome/1.0', 'instance': instance,
                    'condition': cond, 'seed': seed, 'outcome': 'empty-patch',
                    'attempts': 1})
                continue
            patch = patch_text(cond, instance, seed)
            write_json(os.path.join(cell, 'prediction.json'), {
                'instance_id': instance, 'model_name_or_path': model_name,
                'model_patch': patch})
            inst_dir = os.path.join(eval_dir, 'logs', 'run_evaluation', eval_run,
                                    model_name, instance)
            write(os.path.join(inst_dir, 'patch.diff'), patch)
            applied = cell_spec.get('applied', True)
            resolved = bool(cell_spec.get('resolved')) and applied
            write_json(os.path.join(inst_dir, 'report.json'), {instance: {
                'patch_is_None': False, 'patch_exists': True,
                'patch_successfully_applied': applied, 'resolved': resolved,
                'tests_status': {
                    'FAIL_TO_PASS': {'success': ['t1'] if resolved else [],
                                     'failure': [] if resolved else ['t1']},
                    'PASS_TO_PASS': {'success': ['p1'], 'failure': []}}}})
            submitted.append(instance)
            (resolved_ids if resolved else unresolved_ids).append(instance)
        write_json(os.path.join(eval_dir, '%s.%s.json' % (model_name, eval_run)), {
            'total_instances': 500, 'submitted_instances': len(submitted),
            'completed_instances': len(submitted),
            'resolved_instances': len(resolved_ids),
            'unresolved_instances': len(unresolved_ids),
            'resolved_ids': resolved_ids, 'unresolved_ids': unresolved_ids,
            'submitted_ids': submitted, 'schema_version': 2})
    write_json(os.path.join(eval_dir, 'gold.gold-canary-20260831T130008Z.json'),
               {'submitted_instances': 1, 'resolved_instances': 1})


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', required=True)
    ap.add_argument('--spec', default=None)
    args = ap.parse_args()
    if args.spec:
        with open(args.spec, encoding='utf-8') as handle:
            spec = json.load(handle)
    else:
        spec = json.load(sys.stdin)
    build(os.path.abspath(args.root), spec)
    print(args.root)


if __name__ == '__main__':
    main()
