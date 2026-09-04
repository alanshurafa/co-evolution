#!/usr/bin/env python3
"""Render the results site from the aggregator's JSON and nothing else.

Every figure on the page is read out of leaderboard.json (schema
code-bench-site/2.0), which in turn records the evaluator report or run log
each number came from. Prose here is framing; it never states a result the
JSON does not contain. Two pages come out of the same JSON: the leaderboard
and a methodology page.

Inline SVG only, no chart library. The agentic and single-shot tiers are
rendered as separate tables on purpose: a single-shot seat gets one prompt and
one answer with no tools and no test run, so its score is not comparable to a
coding agent's and must never appear in the same ranked list without the label.
"""
import argparse
import html
import json
import os

TIER_COPY = {
    'agentic': ('Agentic tier',
                'A coding agent works in the repository: reads files, edits them, '
                'runs tests, and iterates before the patch is taken.'),
    'single-shot': ('Single-shot tier',
                    'One prompt, one answer. The model sees the issue and a fixed '
                    'set of retrieved files, returns a diff, and never runs a test '
                    'or looks again. Not comparable to an agentic score.'),
}
AXES = (('cost', 'Cost per task (USD, list price)', 'cost_per_task'),
        ('wall', 'Wall time per task (seconds)', 'wall_per_task'),
        ('tokens', 'Tokens per task', 'tokens_per_task'))


def esc(value):
    return html.escape('' if value is None else str(value), quote=True)


def pct(value, digits=0):
    if value is None:
        return '—'
    return ('%.' + str(digits) + 'f%%') % (100.0 * value)


def money(value, digits=2):
    if value is None:
        return '—'
    return ('$%.' + str(digits) + 'f') % value


def duration(seconds):
    if seconds is None:
        return '—'
    seconds = int(seconds)
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    if hours:
        return '%dh %02dm' % (hours, minutes)
    if minutes:
        return '%dm %02ds' % (minutes, secs)
    return '%ds' % secs


def compact(value):
    if value is None:
        return '—'
    value = float(value)
    for unit, size in (('B', 1e9), ('M', 1e6), ('k', 1e3)):
        if value >= size:
            return '%.1f%s' % (value / size, unit)
    return '%d' % value


def scored_rows(data):
    return [r for r in data['rows'] if r.get('score')]


def row_by_id(data, ident):
    return next((r for r in data['rows'] if r['id'] == ident), None)


# --- masthead, caveat, tiles ---------------------------------------------------

NAV = {'page': 'leaderboard.html', 'methodology': 'methodology.html', 'json': 'leaderboard.json'}


def nav_links(data, also, current):
    items = []
    for label, href in (('Leaderboard', NAV['page']), ('Methodology', NAV['methodology']),
                        (NAV['json'], NAV['json'])):
        cls = ' class="here"' if label.lower().startswith(current) else ''
        items.append('<a%s href="%s">%s</a>' % (cls, esc(href), esc(label)))
    for label, href in also:
        items.append('<a href="%s">%s</a>' % (esc(href), esc(label)))
    return '<nav class="sitenav">%s</nav>' % ''.join(items)


def run_chips(data):
    chips = []
    for run in data['runs']:
        models = run.get('models') or {}
        seats = []
        for key in ('claude', 'codex'):
            if models.get(key):
                seats.append(', '.join(models[key]))
        chip = '%s tier · %s' % (run.get('model_tier') or 'unknown', ' / '.join(seats) or 'no seats')
        if run.get('publishable') is False:
            chip += ' · flagged'
        chips.append('<span title="%s">%s</span>' % (esc(run.get('note')), esc(chip)))
    return ''.join(chips)


def masthead(data, also, current):
    suite = data['suite']
    gold = data.get('gold_canary') or {}
    harness = data['harness']
    return (
        '<header class="masthead">'
        '<div class="eyebrow"><span>SWE-bench Verified · %d-task frozen subset</span>'
        '<span>Official pinned evaluator, Docker</span><span>Built %s</span></div>'
        '<h1>%s</h1>'
        '<p class="standfirst">Does a second model reviewing the first one\'s patch produce more '
        'resolved issues than either model alone, and at what cost? Every configuration is an '
        'implementer and a reviewer drawn from different vendors, run on the same frozen tasks, '
        'scored by the official evaluator, and shown with its uncertainty.</p>'
        '%s'
        '<div class="runmeta">%s<span>gold canary %s/%s</span><span>harness build %s%s</span></div>'
        '</header>'
        % (suite['task_count'], esc(data['generated_at']), esc(data.get('title')),
           nav_links(data, also, current), run_chips(data),
           esc(gold.get('resolved')), esc(gold.get('submitted')),
           esc((harness.get('build_commit') or '')[:7]),
           ' (dirty tree)' if harness.get('build_tree_dirty') else ''))


def caveat(data):
    suite = data['suite']
    rows = scored_rows(data)
    paragraphs = []
    n = suite['task_count']
    paragraphs.append(
        '%d tasks is a probe, not a ranking. One task is %d points, and the intervals on every '
        'row say how far two rows have to be apart before the difference is more than noise. '
        'Rank(UB) ties every row whose interval overlaps the leader\'s.'
        % (n, round(100.0 / n)))
    flagged = [r for r in data['runs'] if r.get('publishable') is False]
    if flagged:
        paragraphs.append(
            'Rows from %s are shown with a flag rather than hidden: %s'
            % (', '.join('run %s' % r['label'] for r in flagged),
               ' '.join(r.get('note') or '' for r in flagged)))
    incomplete = [r for r in rows if not r['complete']]
    if incomplete:
        paragraphs.append(
            'Unfinished rows (%s) are scored against the tasks they actually ran, because a task '
            'an arm has not reached is not a failure; they carry no Rank(UB).'
            % ', '.join(r['configuration'] for r in incomplete))
    if any(r['telemetry'].get('cost_precision') == 'estimated' for r in rows):
        paragraphs.append(
            'Cost marked "est." prices a Codex phase from a total-only token figure with the '
            'split recorded in the pricing file; the range under it prices the whole total at '
            'the cached-input and output rates. A phase captured with --json is priced exactly.')
    paragraphs.append(
        'These numbers are not comparable to published full-500 SWE-bench Verified scores. '
        'The two tiers are listed separately because they are not the same test.')
    return ('<div class="callout"><h2>Read this before the table</h2>%s</div>'
            % ''.join('<p>%s</p>' % esc(p) for p in paragraphs))


def tiles(data):
    rows = scored_rows(data)
    complete_cost = [r for r in rows if r['telemetry']['cost_is_complete']]
    cells = sum(r['attempted_count'] for r in rows)
    cost = sum(r['telemetry']['cost_usd'] for r in complete_cost)
    items = [
        ('Configurations', str(len(rows)), 'measured on this subset'),
        ('Runs', str(len(data['runs'])), ', '.join(r['label'] for r in data['runs'])),
        ('Tasks', str(data['suite']['task_count']), 'frozen, uniform random draw'),
        ('Scored cells', str(cells), 'official evaluator, Docker'),
        ('Priced spend', money(cost), '%d of %d rows fully priced' % (len(complete_cost), len(rows))),
        ('Pairwise contrasts', str(len(data.get('contrasts') or [])), 'paired on shared tasks'),
    ]
    return '<div class="tiles">%s</div>' % ''.join(
        '<div class="tile"><span class="k">%s</span><span class="v">%s</span>'
        '<span class="n">%s</span></div>' % (esc(k), esc(v), esc(n)) for k, v, n in items)


def filters(data):
    rows = scored_rows(data)
    tiers = sorted({r.get('model_tier') or 'unknown' for r in rows})
    seeds = sorted({len(r['seeds']) for r in rows})
    tier_opts = ''.join('<option value="%s">%s</option>' % (esc(t), esc(t)) for t in tiers)
    run_opts = ''.join('<option value="%s">%s</option>' % (esc(r['label']), esc(r['label']))
                       for r in data['runs'])
    seed_opts = ''.join('<option value="%d">%d seed%s</option>' % (s, s, '' if s == 1 else 's')
                        for s in seeds)
    return (
        '<div class="filters" id="filters">'
        '<label>Model tier <select data-filter="tier"><option value="">all</option>%s</select></label>'
        '<label>Run <select data-filter="run"><option value="">all</option>%s</select></label>'
        '<label>Seeds <select data-filter="seeds"><option value="">any</option>%s</select></label>'
        '<span class="hint">Filters apply to the tables, the scatter and the heatmap.</span>'
        '</div>' % (tier_opts, run_opts, seed_opts))


# --- leaderboard --------------------------------------------------------------

def badges(row):
    prov = row['provenance']
    out = ['<span class="badge ok" title="Scored by the pinned official SWE-bench evaluator in Docker">official evaluator</span>']
    if prov.get('ran_by') == 'we ran it':
        out.append('<span class="badge ok" title="Generated and scored by this project, not submitted by a third party">we ran it</span>')
    else:
        out.append('<span class="badge none">%s</span>' % esc(prov.get('ran_by')))
    if prov.get('harness_recorded'):
        if prov.get('harness_dirty') in (False, 'False'):
            out.append('<span class="badge ok" title="Cell manifests record a clean harness tree at commit %s">clean tree %s</span>'
                       % (esc(prov.get('harness_commit')), esc(str(prov.get('harness_commit') or '')[:7])))
        else:
            out.append('<span class="badge warn" title="Cell manifests record uncommitted harness changes">dirty tree</span>')
    else:
        out.append('<span class="badge none" title="This run predates manifests that record the harness commit">harness unrecorded</span>')
    if prov.get('publishable') is False:
        out.append('<span class="badge bad" title="%s">flagged</span>' % esc(prov.get('run_note')))
    if row['telemetry'].get('repair_inert_count'):
        out.append('<span class="badge warn" title="Cells whose repair stage left the implementation unchanged">%d inert</span>'
                   % row['telemetry']['repair_inert_count'])
    return '<div class="badges">%s</div>' % ''.join(out)


def interval_svg(row):
    score = row['score']
    low, high, rate = score['wilson_low'], score['wilson_high'], score['rate']
    if rate is None:
        return ''
    return ('<svg class="ci" viewBox="0 0 100 10" preserveAspectRatio="none" role="img" '
            'aria-label="Wilson interval %s to %s">'
            '<line x1="%.1f" y1="5" x2="%.1f" y2="5" class="ci-band"/>'
            '<line x1="%.1f" y1="1" x2="%.1f" y2="9" class="ci-mark"/></svg>'
            % (pct(low), pct(high), 100 * low, 100 * high, 100 * rate, 100 * rate))


def score_cell(row):
    score = row['score']
    if score['rate'] is None:
        return '<td class="score none" data-sort="-1">no result</td>'
    half = 100.0 * (score['wilson_high'] - score['wilson_low']) / 2.0
    seeds = score.get('seeds') or 1
    seed_note = ' · %d seeds' % seeds if seeds > 1 else ''
    return ('<td class="score" data-sort="%.4f"><span class="fig"><span class="pct">%s</span>'
            '<span class="pm">± %.0f</span></span><span class="of">%d / %d%s · CI %s–%s</span>%s</td>'
            % (score['rate'], pct(score['rate']), half, score['resolved'], score['n'], seed_note,
               pct(score['wilson_low']), pct(score['wilson_high']), interval_svg(row)))


def cost_cell(row):
    t = row['telemetry']
    if not t['cost_is_complete']:
        seats = []
        for seat in ('glm', 'kimi'):
            if t.get(seat + '_calls') and not t.get(seat + '_cost_usd'):
                seats.append(seat)
        if t.get('codex_phases') and t.get('cost_precision') == 'unpriced':
            seats.append('codex')
        return ('<td class="num cost-incomplete" data-sort="-1"><span class="flag" title="%s seat has no priced token figure">'
                'incomplete</span><span class="sub">Claude %s only</span></td>'
                % (esc(', '.join(seats) or 'a'), money(t['claude_cost_usd'] / t['cells_linked'] if t['cells_linked'] else None)))
    per = t['cost_per_task']
    mark = ''
    sub = ''
    if t['cost_precision'] == 'estimated' and t['cells_linked']:
        low = t['cost_low_usd'] / t['cells_linked']
        high = t['cost_high_usd'] / t['cells_linked']
        mark = '<span class="est" title="Codex priced from a total-only token figure; range prices the total at cached-input and output rates">est.</span>'
        sub = '<span class="sub">%s–%s</span>' % (money(low), money(high))
    return '<td class="num" data-sort="%.4f">%s%s%s</td>' % (per, money(per), mark, sub)


def wall_cell(row):
    t = row['telemetry']
    if t.get('wall_p50') is None:
        return '<td class="num" data-sort="-1">—</td>'
    return ('<td class="num" data-sort="%d">%s<span class="sub">p90 %s</span></td>'
            % (t['wall_p50'], duration(t['wall_p50']), duration(t['wall_p90'])))


def tokens_cell(row):
    t = row['telemetry']
    if not t.get('tokens_per_task'):
        return '<td class="num" data-sort="-1">—</td>'
    return '<td class="num" data-sort="%d">%s</td>' % (t['tokens_per_task'], compact(t['tokens_per_task']))


def rank_cell(row):
    rank = row.get('rank_ub')
    if rank is None:
        return '<td class="num rank" data-sort="999">—</td>'
    return '<td class="num rank" data-sort="%d">%d</td>' % (rank, rank)


def config_cell(row):
    chips = ['<span class="chip tier">%s</span>' % esc(row.get('model_tier') or 'unknown'),
             '<span class="chip run">%s</span>' % esc(row['run_label']),
             '<span class="chip id">%s</span>' % esc(row['condition'])]
    if row.get('mixed_tier'):
        chips.append('<span class="chip warn">mixed tier</span>')
    return ('<td><div class="pipeline"><span class="name">%s</span>'
            '<span class="comp">%s</span><span class="chips">%s</span></div></td>'
            % (esc(row['configuration']), esc(row['pipeline']), ''.join(chips)))


def coverage_chip(row):
    if not row['complete']:
        return ('<span class="chip warn">in progress · %d of %d cells</span>'
                % (row['attempted_count'], row['cells_expected']))
    t = row['telemetry']
    if t['cells_linked'] < row['attempted_count']:
        return '<span class="chip warn">telemetry partial</span>'
    return '<span class="chip ok">complete</span>'


def detail_row(row, colspan):
    t = row['telemetry']
    prov = row['provenance']
    facts = [
        ('Harness commit', (prov.get('harness_commit') or 'not recorded in this run\'s manifests')),
        ('Dataset revision', row.get('dataset_revision') or ''),
        ('Evaluator run', ', '.join(prov.get('evaluator_run_ids') or []) or 'none'),
        ('Report file', ', '.join(prov.get('report_files') or []) or 'none'),
        ('Sandbox', ', '.join(prov.get('sandbox_modes') or []) or 'n/a'),
        ('Models', ', '.join('%s=%s' % (k, v if isinstance(v, str) else ','.join(v))
                             for k, v in sorted(row['models'].items()))),
        ('Effort', ', '.join('%s=%s' % (k, ','.join(v)) for k, v in sorted(row['effort'].items())) or 'model default'),
        ('CLI versions', ', '.join('%s %s' % (k, ','.join(v)) for k, v in sorted((prov.get('cli_versions') or {}).items())) or 'not recorded'),
        ('Claude tokens', 'in %s · cached %s · out %s' % (compact(t['claude_input_tokens']), compact(t['claude_cached_tokens']), compact(t['claude_output_tokens']))),
        ('Codex tokens', ('total %s' % compact(t['codex_tokens'])) + (
            ' (in %s · cached %s · out %s)' % (compact(t['codex_input_tokens']), compact(t['codex_cached_tokens']), compact(t['codex_output_tokens']))
            if t['codex_input_tokens'] else ' (no split in log)') if t['codex_phases'] else 'no Codex phase'),
        ('Cost by seat', 'claude %s · codex %s%s · glm %s · kimi %s' % (
            money(t['claude_cost_usd']), money(t['codex_cost_usd']),
            (' [%s–%s]' % (money(t['codex_cost_low_usd']), money(t['codex_cost_high_usd']))) if t['cost_precision'] == 'estimated' else '',
            money(t['glm_cost_usd']), money(t['kimi_cost_usd']))),
        ('Cost precision', t['cost_precision']),
        ('Wall p50 / p90', '%s / %s' % (duration(t.get('wall_p50')), duration(t.get('wall_p90')))),
        ('Patch did not apply', str(t.get('patch_not_applied', 0))),
        ('Inert repairs', '%d of %d repair cells' % (t.get('repair_inert_count', 0), t.get('repair_cells', 0)) if t.get('repair_cells') else 'n/a'),
        ('Best-of-k selection', ('%d cells, %d apply-only' % (t['selection_cells'], t['selection_apply_only'])) if t.get('selection_cells') else 'n/a'),
        ('Bootstrap CI', ('%s–%s (%d draws over repo, task, seed)' % (pct(row['bootstrap']['low']), pct(row['bootstrap']['high']), row['bootstrap']['n_boot'])) if row.get('bootstrap') and row['bootstrap'].get('low') is not None else 'n/a'),
    ]
    if row.get('seed_summary'):
        ss = row['seed_summary']
        facts.append(('Seeds', 'pass@%d %s · pass^%d %s · flip rate %s · unstable: %s' % (
            ss['k'], pct(ss['pass_at_k']), ss['k'], pct(ss['pass_pow_k']), pct(ss['flip_rate']),
            ', '.join(ss['unstable_tasks']) or 'none')))
    dl = ''.join('<div><dt>%s</dt><dd>%s</dd></div>' % (esc(k), esc(v)) for k, v in facts)
    return ('<tr class="detail" id="detail-%s" hidden><td colspan="%d"><dl class="facts">%s</dl>'
            '<div class="repro"><span class="label">Reproduce</span><pre class="code">%s</pre></div></td></tr>'
            % (esc(row['id']), colspan, dl, esc(row['reproduce'])))


def leaderboard_table(rows, table_id):
    head = ('<th class="sortable" data-type="num" title="1 + number of rows whose interval lower bound is above this row\'s upper bound">Rank(UB)</th>'
            '<th class="sortable" data-type="text">Configuration</th>'
            '<th class="sortable" data-type="num" data-dir="desc">Resolved ± 95% CI</th>'
            '<th class="sortable" data-type="num">Cost / task</th>'
            '<th class="sortable" data-type="num">Wall p50</th>'
            '<th class="sortable" data-type="num">Tokens / task</th>'
            '<th>Provenance</th><th>Coverage</th><th></th>')
    body = []
    for row in rows:
        attrs = ('data-row="%s" data-tier="%s" data-run="%s" data-seeds="%d" data-flagged="%s"'
                 % (esc(row['id']), esc(row.get('model_tier') or 'unknown'), esc(row['run_label']),
                    len(row['seeds']), 'yes' if row['provenance'].get('publishable') is False else 'no'))
        body.append(
            '<tr %s>%s%s%s%s%s%s<td>%s</td><td>%s</td>'
            '<td><button class="expand" type="button" aria-expanded="false" aria-controls="detail-%s">details</button></td></tr>'
            % (attrs, rank_cell(row), config_cell(row), score_cell(row), cost_cell(row),
               wall_cell(row), tokens_cell(row), badges(row), coverage_chip(row), esc(row['id'])))
        body.append(detail_row(row, 9))
    return ('<div class="scroller"><table data-sortable id="%s"><thead><tr>%s</tr></thead>'
            '<tbody>%s</tbody></table></div>' % (esc(table_id), head, ''.join(body)))


# --- pareto scatter ------------------------------------------------------------

def pareto_svg(data, axis, label, key):
    rows = [r for r in scored_rows(data) if r['complete'] and r['tier'] == 'agentic'
            and r['telemetry'].get(key) is not None and r['score']['rate'] is not None]
    frontier = set((data.get('pareto') or {}).get(axis) or [])
    width, height = 720, 400
    left, right, top, bottom = 64, 24, 24, 56
    if not rows:
        return '<p class="sec-note">No fully priced, complete row to plot on this axis yet.</p>'
    xs = [r['telemetry'][key] for r in rows]
    xmax = max(xs) * 1.15 or 1.0
    xmin = 0.0

    def sx(x):
        return left + (x - xmin) / (xmax - xmin) * (width - left - right)

    def sy(y):
        return top + (1.0 - y) * (height - top - bottom)

    parts = ['<svg class="scatter" viewBox="0 0 %d %d" role="img" aria-label="Pass rate against %s">' % (width, height, esc(label))]
    for i in range(0, 11, 2):
        y = i / 10.0
        parts.append('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" class="grid"/>' % (left, sy(y), width - right, sy(y)))
        parts.append('<text x="%d" y="%.1f" class="tick" text-anchor="end">%d%%</text>' % (left - 8, sy(y) + 4, i * 10))
    ticks = 5
    for i in range(ticks + 1):
        x = xmin + (xmax - xmin) * i / ticks
        parts.append('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" class="grid"/>' % (sx(x), top, sx(x), height - bottom))
        if axis == 'cost':
            text = money(x)
        elif axis == 'wall':
            text = duration(x)
        else:
            text = compact(x)
        parts.append('<text x="%.1f" y="%d" class="tick" text-anchor="middle">%s</text>' % (sx(x), height - bottom + 18, esc(text)))
    parts.append('<text x="%d" y="%d" class="axis" text-anchor="middle">%s</text>' % ((left + width - right) / 2, height - 8, esc(label)))
    parts.append('<text transform="translate(14 %d) rotate(-90)" class="axis" text-anchor="middle">Resolved (Wilson 95%% CI)</text>' % ((top + height - bottom) / 2))
    front = sorted([r for r in rows if r['id'] in frontier], key=lambda r: r['telemetry'][key])
    if len(front) > 1:
        points = ' '.join('%.1f,%.1f' % (sx(r['telemetry'][key]), sy(r['score']['rate'])) for r in front)
        parts.append('<polyline points="%s" class="frontier"/>' % points)
    for r in rows:
        x, y = sx(r['telemetry'][key]), sy(r['score']['rate'])
        lo, hi = sy(r['score']['wilson_low']), sy(r['score']['wilson_high'])
        cls = 'pt front' if r['id'] in frontier else 'pt'
        flagged = r['provenance'].get('publishable') is False
        parts.append('<g class="%s%s" data-row="%s" data-tier="%s" data-run="%s" data-seeds="%d">'
                     % (cls, ' flagged' if flagged else '', esc(r['id']), esc(r.get('model_tier') or 'unknown'),
                        esc(r['run_label']), len(r['seeds'])))
        parts.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" class="whisker"/>' % (x, hi, x, lo))
        parts.append('<circle cx="%.1f" cy="%.1f" r="5"><title>%s · %s · %s</title></circle>'
                     % (x, y, esc(r['configuration']), esc(pct(r['score']['rate'])),
                        esc({'cost': money(r['telemetry'][key]), 'wall': duration(r['telemetry'][key]),
                             'tokens': compact(r['telemetry'][key])}[axis])))
        parts.append('<text x="%.1f" y="%.1f" class="ptlabel">%s</text>' % (x + 8, y - 8, esc(r['configuration'])))
        parts.append('</g>')
    parts.append('</svg>')
    return ''.join(parts)


def pareto_section(data):
    buttons = ''.join('<button type="button" class="axis-btn%s" data-axis="%s">%s</button>'
                      % (' active' if i == 0 else '', axis, esc(label.split(' (')[0]))
                      for i, (axis, label, _) in enumerate(AXES))
    panes = ''.join('<div class="pane" data-axis="%s"%s>%s</div>'
                    % (axis, '' if i == 0 else ' hidden', pareto_svg(data, axis, label, key))
                    for i, (axis, label, key) in enumerate(AXES))
    frontier = (data.get('pareto') or {}).get('cost') or []
    return (
        '<section id="pareto"><h2 class="sec">Pass rate against cost</h2>'
        '<p class="sec-note">Agentic rows with a complete run and a fully priced cost. The line joins the '
        'Pareto frontier: no row above and to the left. Whiskers are the Wilson interval. On the cost axis '
        'the frontier is %s.</p>'
        '<div class="axis-toggle" role="group" aria-label="x axis">%s</div>%s</section>'
        % (esc(', '.join(row_by_id(data, i)['configuration'] for i in frontier if row_by_id(data, i)) or 'empty'),
           buttons, panes))


# --- contrasts --------------------------------------------------------------------

def contrast_section(data):
    contrasts = data.get('contrasts') or []
    rows = [r for r in scored_rows(data) if r['tier'] == 'agentic']
    if len(rows) < 2 or not contrasts:
        return ''
    options = ''.join('<option value="%s">%s (%s)</option>' % (esc(r['id']), esc(r['configuration']), esc(r['run_label']))
                      for r in rows)
    default = None
    for phase in (data.get('methodology') or {}).get('phases') or []:
        if phase.get('observed'):
            default = phase['observed']['contrast'].split(' vs ')
            break
    if default is None:
        default = [contrasts[0]['a'], contrasts[0]['b']]
    payload = json.dumps(contrasts, separators=(',', ':')).replace('</', '<\\/')
    return (
        '<section id="contrast"><h2 class="sec">Paired contrast</h2>'
        '<p class="sec-note">Same tasks, same seed, compared task by task. The discordant tasks are the '
        'only ones that carry information about which arm is better; the exact McNemar test asks whether '
        'their split could be a coin flip. Cost per net flip is what the second arm paid for each task it '
        'gained on balance.</p>'
        '<div class="contrast-pick"><label>A <select id="contrast-a">%s</select></label>'
        '<label>B <select id="contrast-b">%s</select></label></div>'
        '<div id="contrast-out" data-default-a="%s" data-default-b="%s"></div>'
        '<script type="application/json" id="contrast-data">%s</script></section>'
        % (options, options, esc(default[0]), esc(default[1]), payload))


# --- heatmap ------------------------------------------------------------------------

def heatmap(data):
    matrix = data.get('task_matrix') or {}
    rows = [r for r in scored_rows(data)]
    if not rows or not matrix:
        return ''
    head = ''.join('<th data-row="%s" data-tier="%s" data-run="%s" data-seeds="%d"><span class="hm-head">%s</span>'
                   '<span class="tierflag">%s · %s</span></th>'
                   % (esc(r['id']), esc(r.get('model_tier') or 'unknown'), esc(r['run_label']), len(r['seeds']),
                      esc(r['condition']), esc(r.get('model_tier') or ''),
                      'single-shot' if r['tier'] == 'single-shot' else esc(r['run_label']))
                   for r in rows)
    body = []
    last_group = None
    order = matrix['order']
    for index, instance in enumerate(order):
        task = matrix['tasks'][instance]
        group = task.get('difficulty') or 'unlabeled'
        if group != last_group:
            body.append('<tr class="group"><td colspan="%d">%s</td></tr>' % (len(rows) + 3, esc(group)))
            last_group = group
        cells = []
        resolved_count = 0
        for r in rows:
            cell = task['cells'].get(r['id']) or {'status': 'not-run', 'resolved': 0, 'ran': 0, 'seeds': 1}
            status = cell['status']
            klass = {'resolved': 'p', 'unresolved': 'f', 'no-patch': 'f', 'mixed': 'm'}.get(status, 'n')
            shade = ''
            if cell['ran'] > 1:
                shade = ' style="--k:%.2f"' % (cell['resolved'] / cell['ran'])
            text = {'resolved': '✓', 'unresolved': '✗', 'no-patch': 'no patch', 'mixed': '%d/%d' % (cell['resolved'], cell['ran'])}.get(status, '·')
            title = '%s · %s' % (r['configuration'], status)
            if cell.get('repair_inert'):
                title += ' · repair inert'
            if status in ('unresolved',) and not cell.get('patch_applied', True):
                title += ' · patch did not apply'
            resolved_count += cell['resolved']
            cells.append('<td class="cell %s" data-row="%s" data-tier="%s" data-run="%s" data-seeds="%d" title="%s"%s>%s</td>'
                         % (klass, esc(r['id']), esc(r.get('model_tier') or 'unknown'), esc(r['run_label']),
                            len(r['seeds']), esc(title), shade, text))
        body.append('<tr class="task" data-order="%d" data-rescued="%d" data-resolved="%d" data-group="%s">'
                    '<td class="mono">%s</td><td class="repo">%s</td><td class="diff">%s</td>%s</tr>'
                    % (index, 1 if task.get('rescued_by_review') else 0, resolved_count, esc(group),
                       esc(instance), esc(task['repo']), esc(task.get('difficulty') or '—'), ''.join(cells)))
    rescued = [i for i in order if matrix['tasks'][i].get('rescued_by_review')]
    return (
        '<section id="heatmap"><h2 class="sec">Task by configuration</h2>'
        '<p class="sec-note">Grouped by the Verified difficulty label, then repository. A task is '
        '"rescued by review" when a review arm resolved it and no solo arm did: %s. With seeds, a cell '
        'shows resolved/ran and shades by pass^k.</p>'
        '<div class="axis-toggle" role="group" aria-label="row order">'
        '<button type="button" class="axis-btn active" data-sort="default">difficulty · repo</button>'
        '<button type="button" class="axis-btn" data-sort="rescued">rescued by review first</button>'
        '<button type="button" class="axis-btn" data-sort="resolved">most resolved first</button></div>'
        '<div class="scroller"><table class="matrix" id="matrix"><thead><tr><th>Task</th><th>Repository</th>'
        '<th>Difficulty</th>%s</tr></thead><tbody>%s</tbody></table></div></section>'
        % (esc(', '.join(rescued) or 'none yet'), head, ''.join(body)))


# --- provenance and integrity -----------------------------------------------------

def provenance_table(data):
    body = []
    for row in scored_rows(data):
        prov = row['provenance']
        body.append('<tr><td class="mono">%s</td><td class="mono">%s</td><td class="num">%d</td>'
                    '<td class="mono">%s</td><td class="mono">%s</td></tr>'
                    % (esc(row['id']), esc(row['run_label']), len(row['seeds']),
                       esc(', '.join(prov.get('evaluator_run_ids') or [])),
                       esc(', '.join(prov.get('report_files') or []))))
    for entry in data.get('superseded_reports') or []:
        body.append('<tr class="absent"><td class="mono">%s@%s</td><td class="mono">%s</td><td class="num">%s</td>'
                    '<td class="mono">%s</td><td class="mono">%s <span class="chip none">superseded</span></td></tr>'
                    % (esc(entry['condition']), esc(entry['run_label']), esc(entry['run_label']), esc(entry['seed']),
                       esc(entry['evaluator_run_id']), esc(entry['report_file'])))
    return ('<div class="scroller"><table><thead><tr><th>Row</th><th>Run</th><th>Seeds</th>'
            '<th>Evaluator run</th><th>Report file</th></tr></thead><tbody>%s</tbody></table></div>' % ''.join(body))


def integrity(data):
    harness = data['harness']
    gold = data.get('gold_canary') or {}
    pricing = data.get('pricing') or {}
    items = [
        '<li><strong>Evaluator.</strong> Official SWE-bench harness pinned at <span class="mono">%s</span>, '
        'dataset <span class="mono">%s</span> at revision <span class="mono">%s</span>, both from '
        '<span class="mono">%s</span>.</li>'
        % (esc((harness.get('swebench_commit') or '')[:12]), esc(harness.get('dataset')),
           esc((harness.get('dataset_revision') or '')[:12]), esc(harness.get('lock_file'))),
    ]
    if gold:
        items.append('<li><strong>Gold canary.</strong> A gold patch resolved %s/%s before any generated '
                     'prediction was scored. Report: <span class="mono">%s</span>.</li>'
                     % (esc(gold.get('resolved')), esc(gold.get('submitted')), esc(gold.get('report_file'))))
    items.append('<li><strong>Cost.</strong> Claude cost is the CLI\'s own figure. Codex, GLM and Kimi are priced '
                 'from the token counts in each cell\'s logs at the list prices in <span class="mono">%s</span> '
                 '(recorded %s). A row is "fully priced" only when every seat that ran has a priced figure; '
                 'otherwise the cost column says incomplete rather than showing a smaller number.</li>'
                 % (esc(pricing.get('file')), esc(pricing.get('recorded_on'))))
    items.append('<li><strong>Uncertainty.</strong> %s per row; %s per pair; a %d-draw bootstrap over %s for the '
                 'paired delta; %s. Code: <span class="mono">%s</span>.</li>'
                 % (esc(data['statistics']['interval']), esc(data['statistics']['paired_test']),
                    data['statistics']['bootstrap']['draws'], esc(', '.join(data['statistics']['bootstrap']['levels'])),
                    esc(data['statistics']['rank']), esc(data['statistics']['module'])))
    items.append('<li><strong>Provenance badges.</strong> "official evaluator" and the gold canary say how a row '
                 'was scored; "we ran it" says who generated the patches; "clean tree" or "dirty tree" is what the '
                 'cell manifests recorded about the harness, and "harness unrecorded" means the run predates that '
                 'record; "flagged" carries the run registry\'s note and keeps the row out of any headline.</li>')
    items.append('<li><strong>Every number on this page comes from a file.</strong> The page is generated from '
                 '<span class="mono">benchmarks/site/aggregate.sh</span> output; each row names the evaluator '
                 'reports it was read from and each task cell is backed by that run\'s per-instance '
                 '<span class="mono">report.json</span>. The full JSON is linked in the header.</li>')
    return '<ul class="plain">%s</ul>' % ''.join(items)


# --- methodology page -----------------------------------------------------------------

def methodology_page(data, also):
    meth = data.get('methodology') or {}
    prereg = meth.get('preregistration') or {}
    suite = data['suite']
    sampling = meth.get('sampling') or {}
    diff = meth.get('difficulty') or {}
    parts = [HEAD, '<title>%s</title>' % esc('Methodology · ' + (data.get('title') or 'Co-Evolution')), STYLE,
             '<div class="wrap">', masthead(data, also, 'meth')]
    parts.append('<section><h2 class="sec">Suite draw</h2><ul class="plain">'
                 '<li><strong>Suite.</strong> <span class="mono">%s</span>: %d tasks from %s (%s split), file '
                 '<span class="mono">%s</span>.</li>'
                 '<li><strong>Sampling.</strong> %s with seed <span class="mono">%s</span> from %s instances at '
                 'dataset revision <span class="mono">%s</span>. %s</li></ul></section>'
                 % (esc(suite['id']), suite['task_count'], esc(suite['dataset']), esc(suite['split']),
                    esc(suite['subset_file']), esc(sampling.get('method') or 'hand-pinned'),
                    esc(sampling.get('seed')), esc((sampling.get('drawn_from') or {}).get('population')),
                    esc(((sampling.get('drawn_from') or {}).get('revision') or '')[:12]),
                    esc(sampling.get('note') or '')))
    if diff:
        counts = diff.get('counts') or {}
        rows = ''.join('<tr><td>%s</td><td class="num">%s</td></tr>' % (esc(b), esc(counts.get(b, 0)))
                       for b in diff.get('buckets') or [])
        parts.append('<section><h2 class="sec">Difficulty stratification</h2>'
                     '<p class="sec-note">%s Source: %s, fetched %s.</p>'
                     '<div class="scroller"><table><thead><tr><th>Bucket</th><th>Tasks</th></tr></thead>'
                     '<tbody>%s</tbody></table></div></section>'
                     % (esc(diff.get('note')), esc(diff.get('source')), esc(diff.get('fetched_on')), rows))
    phase_rows = []
    for phase in meth.get('phases') or []:
        primary = phase.get('primary_contrast') or {}
        observed = phase.get('observed')
        if observed:
            delta = observed.get('delta') or {}
            outcome = ('%s: %d / %d discordant, McNemar p = %.2f, delta %s (bootstrap %s to %s)'
                       % (observed['contrast'], observed['only_a'], observed['only_b'],
                          observed['mcnemar_exact_p'], pct(delta.get('point'), 1),
                          pct(delta.get('low'), 1), pct(delta.get('high'), 1)))
        else:
            outcome = 'pending: %s' % (', '.join(a for a in (phase.get('arms') or [])
                                                  if a not in (phase.get('arms_measured') or [])) or 'no arms declared')
        phase_rows.append('<tr><td class="num">%s</td><td>%s</td><td class="mono">%s vs %s</td><td>%s</td>'
                          '<td>%s</td><td class="mono">%s</td></tr>'
                          % (esc(phase.get('id')), esc(phase.get('name')), esc(primary.get('a')),
                             esc(primary.get('b')), esc(primary.get('question')), esc(outcome),
                             esc(', '.join(phase.get('arms_measured') or []) or 'none')))
    parts.append('<section><h2 class="sec">Pre-registered contrasts</h2>'
                 '<p class="sec-note">Registered %s from %s. One primary contrast per phase, declared before the '
                 'phase runs; the outcome column is filled from the evaluator reports, never by hand. %s</p>'
                 '<div class="scroller"><table><thead><tr><th>Phase</th><th>Name</th><th>Primary</th>'
                 '<th>Question</th><th>Outcome</th><th>Arms measured</th></tr></thead><tbody>%s</tbody></table></div></section>'
                 % (esc(prereg.get('registered_on')), esc(prereg.get('source')),
                    esc((prereg.get('analysis') or {}).get('secondary_correction') or ''), ''.join(phase_rows)))
    power_rows = ''.join('<tr><td class="num">%s</td><td class="num">%s</td><td class="num">%s</td></tr>'
                         % (pct(p['discordance_rate']), pct(p['effect']), esc(p['paired_observations']))
                         for p in meth.get('power_table') or [])
    parts.append('<section><h2 class="sec">Power</h2>'
                 '<p class="sec-note">Paired observations (task × seed) needed to detect a paired difference at '
                 '80%% power and α = 0.05, from the McNemar normal approximation, for the discordance rates seen '
                 'so far. The light tier\'s A vs B discordance is 14%%; repeats count as observations.</p>'
                 '<div class="scroller"><table><thead><tr><th>Discordance</th><th>Effect</th>'
                 '<th>Paired observations</th></tr></thead><tbody>%s</tbody></table></div></section>' % power_rows)
    pricing = data.get('pricing') or {}
    price_rows = ''.join('<tr><td class="mono">%s</td><td>%s</td><td class="num">%s</td><td class="num">%s</td>'
                         '<td class="num">%s</td><td>%s</td></tr>'
                         % (esc(m), esc(r.get('vendor')), money(r['input']), money(r['cached_input']),
                            money(r['output']), esc(r.get('note') or ''))
                         for m, r in sorted((pricing.get('models') or {}).items()))
    split = pricing.get('codex_total_only_split') or {}
    parts.append('<section><h2 class="sec">Cost basis</h2>'
                 '<p class="sec-note">List prices per million tokens from <span class="mono">%s</span>, recorded %s. '
                 'Claude is priced by its CLI\'s own envelope. A Codex phase whose log carries only a total is priced '
                 'with an assumed split of %s cached, %s uncached input, %s output, and flagged "est." with bounds.</p>'
                 '<div class="scroller"><table><thead><tr><th>Model</th><th>Vendor</th><th>Input</th>'
                 '<th>Cached input</th><th>Output</th><th>Note</th></tr></thead><tbody>%s</tbody></table></div></section>'
                 % (esc(pricing.get('file')), esc(pricing.get('recorded_on')), pct(split.get('cached_input')),
                    pct(split.get('input')), pct(split.get('output')), price_rows))
    parts.append('<section><h2 class="sec">Statistics and integrity</h2>%s</section>' % integrity(data))
    parts.append('<section><h2 class="sec">Downloads</h2><ul class="plain">'
                 '<li><a href="%s">%s</a> — the complete data this site renders (schema %s).</li>'
                 '<li><a href="code-bench-site-2.0.schema.json">code-bench-site-2.0.schema.json</a> — the JSON schema.</li>'
                 '<li>In the repository: <span class="mono">%s</span>, <span class="mono">%s</span>, '
                 '<span class="mono">%s</span>, <span class="mono">benchmarks/code/preregistration.json</span>.</li></ul></section>'
                 % (esc(NAV['json']), esc(NAV['json']), esc(data.get('schema')), esc(data['harness'].get('conditions_file')),
                    esc(pricing.get('file')), esc(data['harness'].get('runs_file'))))
    parts.append(footer(data))
    parts.append('</div>')
    return '\n'.join(parts)


def footer(data):
    harness = data['harness']
    return ('<footer><div>Generated from run artifacts in <span class="mono">benchmarks/results/code/</span> by '
            '<span class="mono">benchmarks/site/aggregate.sh</span>.</div>'
            '<div class="mono">site build %s%s · schema %s</div></footer>'
            % (esc(harness.get('build_commit')),
               ' · working tree had uncommitted changes at build time' if harness.get('build_tree_dirty') else '',
               esc(data.get('schema'))))


# --- leaderboard page ------------------------------------------------------------------

def build(data, also=()):
    rows = scored_rows(data)
    agentic = [r for r in rows if r['tier'] == 'agentic']
    single = [r for r in rows if r['tier'] == 'single-shot']
    parts = [HEAD, '<title>%s</title>' % esc(data.get('title') or 'Co-Evolution'), STYLE,
             '<div class="wrap">', masthead(data, also, 'leader'), caveat(data), tiles(data), filters(data)]
    parts.append('<section id="leaderboard"><h2 class="sec">Leaderboard</h2>')
    for tier, group in (('agentic', agentic), ('single-shot', single)):
        if not group:
            continue
        title, note = TIER_COPY[tier]
        parts.append('<h3 class="tier">%s</h3><p class="sec-note">%s</p>' % (esc(title), esc(note)))
        parts.append(leaderboard_table(group, 'board-%s' % tier))
    parts.append('</section>')
    parts.append(pareto_section(data))
    parts.append(contrast_section(data))
    parts.append(heatmap(data))
    parts.append('<section><h2 class="sec">Methodology and integrity</h2>%s'
                 '<p class="sec-note">The <a href="%s">methodology page</a> carries the suite draw, '
                 'stratification, pre-registered contrasts, the power table and the cost basis, generated from the '
                 'same JSON.</p>%s</section>' % (integrity(data), esc(NAV['methodology']), provenance_table(data)))
    parts.append(footer(data))
    parts.append('</div>')
    parts.append(SCRIPT)
    return '\n'.join(parts)


# The pages are served raw by GitHub Pages, so they declare their own charset
# and viewport; without them a phone lays the page out at 980px and a server
# without a charset header shows the middle dots as mojibake.
HEAD = ('<!doctype html><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">')

STYLE = """
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Serif:ital,wght@0,500;0,600;1,400&display=swap">
<style>
  :root {
    --paper: #F7F8FA; --surface: #FFFFFF; --surface-sunk: #EFF2F6;
    --rule: #DCE2EA; --rule-strong: #C2CBD6;
    --ink: #11161C; --ink-soft: #444F5C; --ink-faint: #6B7785;
    --accent: #1F4E8C; --accent-soft: #E4EBF5;
    --pass: #2F7D5D; --pass-wash: #DCEDE4;
    --fail: #B23A34; --fail-wash: #F7DEDC;
    --caveat: #96660F; --caveat-wash: #FAEDD4;
    --absent: #8A94A1; --absent-wash: #E8EBEF;
    --shadow: 0 1px 2px rgba(17,22,28,.05), 0 8px 24px -18px rgba(17,22,28,.35);
    --f-display: "IBM Plex Serif", Georgia, "Times New Roman", serif;
    --f-sans: "IBM Plex Sans", system-ui, -apple-system, "Segoe UI", sans-serif;
    --f-mono: "IBM Plex Mono", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    --measure: 68ch;
    --pad: clamp(1.15rem, 4vw, 2.5rem);
  }
  @media (prefers-color-scheme: dark) {
    :root:not([data-theme="light"]) {
      --paper: #0D1218; --surface: #141B23; --surface-sunk: #1B242E;
      --rule: #26313D; --rule-strong: #3A4855;
      --ink: #E7ECF2; --ink-soft: #AEB9C6; --ink-faint: #7E8B99;
      --accent: #7FA9E0; --accent-soft: #1B2C42;
      --pass: #6FC79B; --pass-wash: #163326;
      --fail: #EA8079; --fail-wash: #3A1F1D;
      --caveat: #E0B25C; --caveat-wash: #362A14;
      --absent: #7E8B99; --absent-wash: #1E262F;
      --shadow: 0 1px 2px rgba(0,0,0,.5), 0 10px 30px -20px rgba(0,0,0,.9);
    }
  }
  :root[data-theme="dark"] {
    --paper: #0D1218; --surface: #141B23; --surface-sunk: #1B242E;
    --rule: #26313D; --rule-strong: #3A4855;
    --ink: #E7ECF2; --ink-soft: #AEB9C6; --ink-faint: #7E8B99;
    --accent: #7FA9E0; --accent-soft: #1B2C42;
    --pass: #6FC79B; --pass-wash: #163326;
    --fail: #EA8079; --fail-wash: #3A1F1D;
    --caveat: #E0B25C; --caveat-wash: #362A14;
    --absent: #7E8B99; --absent-wash: #1E262F;
    --shadow: 0 1px 2px rgba(0,0,0,.5), 0 10px 30px -20px rgba(0,0,0,.9);
  }
  * { box-sizing: border-box; }
  html, body { overflow-x: hidden; }
  body { background: var(--paper); color: var(--ink); font-family: var(--f-sans);
         font-size: 16px; line-height: 1.55; -webkit-font-smoothing: antialiased; margin: 0; }
  .wrap { max-width: 1240px; margin: 0 auto; padding: var(--pad);
          display: flex; flex-direction: column; gap: 3rem; }
  a { color: var(--accent); text-underline-offset: 2px; }
  :focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; border-radius: 2px; }

  .masthead { display: flex; flex-direction: column; gap: .85rem; padding-top: .5rem; }
  .eyebrow { font-family: var(--f-mono); font-size: .72rem; letter-spacing: .14em;
             text-transform: uppercase; color: var(--ink-faint);
             display: flex; flex-wrap: wrap; gap: .5rem .9rem; }
  h1 { font-family: var(--f-display); font-weight: 600;
       font-size: clamp(1.7rem, 4.6vw, 2.8rem); line-height: 1.08;
       letter-spacing: -.015em; margin: 0; text-wrap: balance; }
  .standfirst { font-size: clamp(1rem, 2.1vw, 1.12rem); color: var(--ink-soft);
                max-width: var(--measure); margin: 0; }
  .sitenav { display: flex; flex-wrap: wrap; gap: .4rem 1.1rem; font-family: var(--f-mono); font-size: .8rem; }
  .sitenav a.here { font-weight: 600; text-decoration: none; color: var(--ink); }
  .runmeta { display: flex; flex-wrap: wrap; gap: .4rem .5rem; margin-top: .35rem; }
  .runmeta span { font-family: var(--f-mono); font-size: .74rem; color: var(--ink-soft);
                  background: var(--surface-sunk); border: 1px solid var(--rule);
                  border-radius: 3px; padding: .22rem .5rem; white-space: nowrap; }

  .callout { background: var(--caveat-wash); border: 1px solid var(--caveat);
             border-left-width: 4px; border-radius: 4px; padding: 1.1rem 1.25rem;
             display: flex; flex-direction: column; gap: .55rem; }
  .callout h2 { font-family: var(--f-mono); font-size: .74rem; letter-spacing: .13em;
                text-transform: uppercase; margin: 0; color: var(--caveat); }
  .callout p { margin: 0; max-width: var(--measure); color: var(--ink); }

  .tiles { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
           gap: 1px; background: var(--rule); border: 1px solid var(--rule);
           border-radius: 5px; overflow: hidden; }
  .tile { background: var(--surface); padding: .95rem 1.1rem; display: flex; flex-direction: column; gap: .18rem; }
  .tile .k { font-family: var(--f-mono); font-size: .68rem; letter-spacing: .11em;
             text-transform: uppercase; color: var(--ink-faint); }
  .tile .v { font-family: var(--f-mono); font-size: 1.5rem; font-weight: 600;
             font-variant-numeric: tabular-nums; line-height: 1.15; }
  .tile .n { font-size: .78rem; color: var(--ink-faint); overflow-wrap: anywhere; }

  .filters { display: flex; flex-wrap: wrap; gap: .6rem 1.4rem; align-items: center;
             background: var(--surface); border: 1px solid var(--rule); border-radius: 5px; padding: .7rem 1rem; }
  .filters label { font-family: var(--f-mono); font-size: .76rem; letter-spacing: .06em; text-transform: uppercase;
                   color: var(--ink-soft); display: flex; gap: .5rem; align-items: center; }
  .filters select, .contrast-pick select { font: inherit; font-family: var(--f-sans); text-transform: none;
             background: var(--surface-sunk); color: var(--ink); border: 1px solid var(--rule-strong);
             border-radius: 3px; padding: .25rem .4rem; max-width: 60vw; }
  .filters .hint { font-size: .78rem; color: var(--ink-faint); }

  section { display: flex; flex-direction: column; gap: 1rem; }
  h2.sec { font-family: var(--f-display); font-size: clamp(1.3rem, 3vw, 1.65rem);
           font-weight: 600; letter-spacing: -.01em; margin: 0; padding-bottom: .45rem;
           border-bottom: 2px solid var(--ink); text-wrap: balance; }
  h3.tier { font-family: var(--f-mono); font-size: .78rem; letter-spacing: .12em;
            text-transform: uppercase; margin: .6rem 0 0; color: var(--ink); }
  .sec-note { margin: 0; color: var(--ink-soft); max-width: var(--measure); font-size: .95rem; }

  .scroller { overflow-x: auto; border: 1px solid var(--rule); border-radius: 5px;
              background: var(--surface); box-shadow: var(--shadow); max-width: 100%; }
  table { border-collapse: collapse; width: 100%; font-size: .875rem; }
  thead th { background: var(--surface-sunk); font-family: var(--f-mono); font-size: .68rem;
             letter-spacing: .1em; text-transform: uppercase; color: var(--ink-soft);
             text-align: left; padding: .6rem .8rem; border-bottom: 1px solid var(--rule-strong);
             white-space: nowrap; position: sticky; top: 0; z-index: 2; }
  th.sortable { cursor: pointer; user-select: none; }
  th.sortable:hover { color: var(--ink); }
  th.sortable::after { content: " \\2195"; opacity: .35; }
  th.sortable[data-dir="asc"]::after { content: " \\2191"; opacity: 1; color: var(--accent); }
  th.sortable[data-dir="desc"]::after { content: " \\2193"; opacity: 1; color: var(--accent); }
  td { padding: .62rem .8rem; border-bottom: 1px solid var(--rule); vertical-align: middle; }
  tbody tr:last-child td { border-bottom: none; }
  tbody tr:hover td { background: var(--surface-sunk); }
  tr[hidden] { display: none; }
  .num { font-family: var(--f-mono); font-variant-numeric: tabular-nums; white-space: nowrap; }
  .num .sub, .score .of { display: block; font-size: .72rem; color: var(--ink-faint); font-weight: 400; white-space: nowrap; }
  .rank { font-weight: 600; font-size: 1.05rem; }
  .mono { font-family: var(--f-mono); font-size: .82rem; overflow-wrap: anywhere; }
  td.repo, td.diff { font-family: var(--f-mono); font-size: .76rem; color: var(--ink-faint); white-space: nowrap; }
  .tierflag { font-family: var(--f-mono); font-size: .6rem; color: var(--caveat); display: block; letter-spacing: .08em; }
  .hm-head { font-weight: 600; }
  tr.absent td { color: var(--ink-faint);
    background-image: repeating-linear-gradient(45deg, transparent, transparent 7px, var(--absent-wash) 7px, var(--absent-wash) 8px); }

  .pipeline { display: flex; flex-direction: column; gap: .18rem; min-width: 240px; }
  .pipeline .name { font-weight: 600; color: var(--ink); }
  .pipeline .comp { font-family: var(--f-mono); font-size: .74rem; color: var(--ink-faint); }
  .chips { display: flex; flex-wrap: wrap; gap: .3rem; margin-top: .15rem; }
  .chip { display: inline-block; font-family: var(--f-mono); font-size: .66rem; letter-spacing: .05em;
          text-transform: uppercase; padding: .15rem .42rem; border-radius: 3px; white-space: nowrap; border: 1px solid; }
  .chip.ok { color: var(--pass); background: var(--pass-wash); border-color: var(--pass); }
  .chip.warn { color: var(--caveat); background: var(--caveat-wash); border-color: var(--caveat); }
  .chip.bad { color: var(--fail); background: var(--fail-wash); border-color: var(--fail); }
  .chip.none, .chip.run, .chip.id { color: var(--absent); background: var(--absent-wash); border-color: var(--rule-strong); }
  .chip.tier { color: var(--accent); background: var(--accent-soft); border-color: var(--accent); }
  .badges { display: flex; flex-wrap: wrap; gap: .3rem; max-width: 220px; }
  .badge { font-family: var(--f-mono); font-size: .62rem; letter-spacing: .04em; padding: .12rem .38rem;
           border-radius: 3px; border: 1px solid; cursor: help; white-space: nowrap; }
  .badge.ok { color: var(--pass); border-color: var(--pass); background: var(--pass-wash); }
  .badge.warn { color: var(--caveat); border-color: var(--caveat); background: var(--caveat-wash); }
  .badge.bad { color: var(--fail); border-color: var(--fail); background: var(--fail-wash); }
  .badge.none { color: var(--absent); border-color: var(--rule-strong); background: var(--absent-wash); }

  .score { min-width: 170px; }
  .score .fig { font-family: var(--f-mono); font-variant-numeric: tabular-nums; font-weight: 600;
                display: flex; align-items: baseline; gap: .35rem; }
  .score .fig .pct { font-size: 1.05rem; }
  .score .fig .pm { font-size: .78rem; color: var(--ink-soft); font-weight: 500; }
  .score.none { color: var(--ink-faint); font-family: var(--f-mono); }
  svg.ci { display: block; width: 100%; height: 8px; margin-top: .3rem; }
  .ci-band { stroke: var(--pass); stroke-width: 4; stroke-opacity: .35; }
  .ci-mark { stroke: var(--pass); stroke-width: 2; }
  .est { font-family: var(--f-mono); font-size: .62rem; color: var(--caveat); margin-left: .3rem; cursor: help; }
  .cost-incomplete .flag { font-family: var(--f-mono); font-size: .7rem; color: var(--fail); text-transform: uppercase;
                           letter-spacing: .05em; cursor: help; }
  button.expand, .axis-btn { font: inherit; font-family: var(--f-mono); font-size: .72rem; letter-spacing: .05em;
                  text-transform: uppercase; background: var(--surface-sunk); color: var(--ink-soft);
                  border: 1px solid var(--rule-strong); border-radius: 3px; padding: .25rem .55rem; cursor: pointer; }
  button.expand:hover, .axis-btn:hover { color: var(--ink); border-color: var(--accent); }
  .axis-btn.active { color: var(--accent); border-color: var(--accent); background: var(--accent-soft); }
  .axis-toggle { display: flex; flex-wrap: wrap; gap: .4rem; }
  tr.detail td { background: var(--surface-sunk); }
  tr.detail:hover td { background: var(--surface-sunk); }
  dl.facts { display: grid; grid-template-columns: repeat(auto-fit, minmax(260px, 1fr)); gap: .5rem 1.5rem; margin: 0; }
  dl.facts div { display: flex; flex-direction: column; gap: .1rem; }
  dl.facts dt { font-family: var(--f-mono); font-size: .64rem; letter-spacing: .1em; text-transform: uppercase; color: var(--ink-faint); }
  dl.facts dd { margin: 0; font-size: .84rem; overflow-wrap: anywhere; }
  .repro { margin-top: .8rem; display: flex; flex-direction: column; gap: .3rem; }
  .repro .label { font-family: var(--f-mono); font-size: .64rem; letter-spacing: .1em; text-transform: uppercase; color: var(--ink-faint); }
  pre.code { margin: 0; background: var(--paper); border: 1px solid var(--rule); border-radius: 4px; padding: .7rem .85rem;
             overflow-x: auto; font-family: var(--f-mono); font-size: .76rem; line-height: 1.55; color: var(--ink); max-width: 100%; }

  svg.scatter { width: 100%; height: auto; max-width: 100%; background: var(--surface); border: 1px solid var(--rule);
                border-radius: 5px; box-shadow: var(--shadow); font-family: var(--f-mono); }
  svg.scatter .grid { stroke: var(--rule); stroke-width: 1; }
  svg.scatter .tick { font-size: 11px; fill: var(--ink-faint); }
  svg.scatter .axis { font-size: 11px; fill: var(--ink-soft); letter-spacing: .08em; text-transform: uppercase; }
  svg.scatter .frontier { fill: none; stroke: var(--accent); stroke-width: 1.5; stroke-dasharray: 4 3; }
  svg.scatter .whisker { stroke: var(--ink-faint); stroke-width: 1.5; }
  svg.scatter circle { fill: var(--surface); stroke: var(--ink-soft); stroke-width: 2; }
  svg.scatter .front circle { fill: var(--accent); stroke: var(--accent); }
  svg.scatter .flagged circle { stroke-dasharray: 2 2; }
  svg.scatter .ptlabel { font-size: 11px; fill: var(--ink); }
  svg.scatter g[hidden] { display: none; }

  .contrast-pick { display: flex; flex-wrap: wrap; gap: .6rem 1.4rem; }
  .contrast-pick label { font-family: var(--f-mono); font-size: .76rem; letter-spacing: .06em; text-transform: uppercase;
                         color: var(--ink-soft); display: flex; gap: .5rem; align-items: center; }
  .contrast-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(240px, 1fr)); gap: 1rem; }
  .card { background: var(--surface); border: 1px solid var(--rule); border-radius: 5px; padding: 1rem 1.1rem;
          box-shadow: var(--shadow); display: flex; flex-direction: column; gap: .5rem; }
  .card h3 { margin: 0; font-family: var(--f-mono); font-size: .68rem; letter-spacing: .12em; text-transform: uppercase; color: var(--ink-faint); }
  .card .big { font-family: var(--f-mono); font-size: 1.4rem; font-weight: 600; font-variant-numeric: tabular-nums; }
  .card p { margin: 0; font-size: .9rem; color: var(--ink-soft); }
  .card ul { margin: 0; padding-left: 1.1rem; font-family: var(--f-mono); font-size: .78rem; }
  table.two { width: auto; }
  table.two td, table.two th { padding: .35rem .7rem; }

  .matrix td.cell { text-align: center; font-family: var(--f-mono); font-weight: 600; min-width: 64px; }
  .matrix td.cell.p { background: var(--pass-wash); color: var(--pass); }
  .matrix td.cell.f { background: var(--fail-wash); color: var(--fail); }
  .matrix td.cell.m { background: color-mix(in srgb, var(--pass-wash) calc(var(--k, .5) * 100%), var(--fail-wash)); color: var(--ink); }
  .matrix td.cell.n { color: var(--ink-faint); }
  .matrix tr.group td { background: var(--surface-sunk); font-family: var(--f-mono); font-size: .7rem;
                        letter-spacing: .1em; text-transform: uppercase; color: var(--ink-soft); }
  td[hidden], th[hidden] { display: none; }

  ul.plain { margin: 0; padding-left: 1.1rem; color: var(--ink-soft); font-size: .93rem;
             display: flex; flex-direction: column; gap: .35rem; }
  ul.plain strong { color: var(--ink); }
  footer { border-top: 1px solid var(--rule); padding-top: 1.15rem; padding-bottom: 2rem;
           color: var(--ink-faint); font-size: .82rem; display: flex; flex-direction: column; gap: .35rem; }
  footer .mono { font-size: .76rem; }
  @media (prefers-reduced-motion: reduce) { * { animation: none !important; transition: none !important; } }
</style>
"""

SCRIPT = """
<script>
(function () {
  function all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }

  // Sortable headers. Detail rows travel with their parent.
  all('table[data-sortable]').forEach(function (table) {
    var headers = all('th.sortable', table);
    headers.forEach(function (th) {
      var index = Array.prototype.indexOf.call(th.parentNode.children, th);
      th.setAttribute('tabindex', '0'); th.setAttribute('role', 'button');
      function activate() {
        var dir = th.getAttribute('data-dir') === 'desc' ? 'asc' : 'desc';
        headers.forEach(function (h) { h.removeAttribute('data-dir'); });
        th.setAttribute('data-dir', dir);
        var body = table.tBodies[0];
        var rows = all('tr[data-row]', body);
        var numeric = th.getAttribute('data-type') === 'num';
        rows.sort(function (a, b) {
          var ca = a.cells[index], cb = b.cells[index];
          if (numeric) {
            var va = parseFloat(ca.getAttribute('data-sort')), vb = parseFloat(cb.getAttribute('data-sort'));
            if (isNaN(va)) { va = -Infinity; } if (isNaN(vb)) { vb = -Infinity; }
            return dir === 'desc' ? vb - va : va - vb;
          }
          var ta = ca.textContent.trim().toLowerCase(), tb = cb.textContent.trim().toLowerCase();
          return dir === 'desc' ? tb.localeCompare(ta) : ta.localeCompare(tb);
        });
        rows.forEach(function (r) {
          body.appendChild(r);
          var d = document.getElementById('detail-' + r.getAttribute('data-row'));
          if (d) { body.appendChild(d); }
        });
      }
      th.addEventListener('click', activate);
      th.addEventListener('keydown', function (e) { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); activate(); } });
    });
  });

  // Expandable rows.
  all('button.expand').forEach(function (btn) {
    btn.addEventListener('click', function () {
      var target = document.getElementById(btn.getAttribute('aria-controls'));
      if (!target) { return; }
      var open = target.hidden;
      target.hidden = !open;
      btn.setAttribute('aria-expanded', open ? 'true' : 'false');
      btn.textContent = open ? 'hide' : 'details';
    });
  });

  // Filters: tier, run, seeds, applied to every element carrying the data attributes.
  var filters = {};
  function applyFilters() {
    all('[data-row]').forEach(function (el) {
      var show = true;
      Object.keys(filters).forEach(function (key) {
        var want = filters[key];
        if (want && el.getAttribute('data-' + key) !== want) { show = false; }
      });
      if (el.tagName === 'TR') {
        el.hidden = !show;
        var d = document.getElementById('detail-' + el.getAttribute('data-row'));
        if (d && !show) { d.hidden = true; }
      } else if (el.tagName === 'TD' || el.tagName === 'TH') {
        el.hidden = !show;
      } else {
        if (show) { el.removeAttribute('hidden'); } else { el.setAttribute('hidden', ''); }
      }
    });
  }
  all('#filters select').forEach(function (sel) {
    sel.addEventListener('change', function () { filters[sel.getAttribute('data-filter')] = sel.value; applyFilters(); });
  });

  // Pareto axis toggle: three pre-rendered SVGs, one visible.
  all('#pareto .axis-btn').forEach(function (btn) {
    btn.addEventListener('click', function () {
      all('#pareto .axis-btn').forEach(function (b) { b.classList.remove('active'); });
      btn.classList.add('active');
      all('#pareto .pane').forEach(function (p) { p.hidden = p.getAttribute('data-axis') !== btn.getAttribute('data-axis'); });
    });
  });

  // Heatmap ordering.
  var matrix = document.getElementById('matrix');
  if (matrix) {
    var mbody = matrix.tBodies[0];
    var original = all('tr', mbody);
    all('#heatmap .axis-btn').forEach(function (btn) {
      btn.addEventListener('click', function () {
        all('#heatmap .axis-btn').forEach(function (b) { b.classList.remove('active'); });
        btn.classList.add('active');
        var mode = btn.getAttribute('data-sort');
        if (mode === 'default') {
          original.forEach(function (r) { r.hidden = false; mbody.appendChild(r); });
          return;
        }
        all('tr.group', mbody).forEach(function (r) { r.hidden = true; });
        var rows = all('tr.task', mbody);
        rows.sort(function (a, b) {
          var ka = parseInt(a.getAttribute('data-' + mode), 10), kb = parseInt(b.getAttribute('data-' + mode), 10);
          if (kb !== ka) { return kb - ka; }
          return parseInt(a.getAttribute('data-order'), 10) - parseInt(b.getAttribute('data-order'), 10);
        });
        rows.forEach(function (r) { mbody.appendChild(r); });
      });
    });
  }

  // Paired contrast panel: every pair is precomputed by the aggregator; the
  // page only selects which one to show. Swapping A and B flips the table.
  var dataEl = document.getElementById('contrast-data');
  var out = document.getElementById('contrast-out');
  if (dataEl && out) {
    var contrasts = JSON.parse(dataEl.textContent);
    var selA = document.getElementById('contrast-a'), selB = document.getElementById('contrast-b');
    function esc(s) { return String(s).replace(/[&<>"]/g, function (c) { return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]; }); }
    function pct(v, d) { return v == null ? '—' : (100 * v).toFixed(d || 0) + '%'; }
    function money(v) { return v == null ? '—' : '$' + v.toFixed(2); }
    function find(a, b) {
      for (var i = 0; i < contrasts.length; i++) {
        var c = contrasts[i];
        if (c.a === a && c.b === b) { return c; }
        if (c.a === b && c.b === a) {
          var d = c.delta_b_minus_a || {};
          return {a: b, b: a, n: c.n, both: c.both, only_a: c.only_b, only_b: c.only_a, neither: c.neither,
                  rescued_by_b: c.broken_by_b, broken_by_b: c.rescued_by_b, net_b_minus_a: -c.net_b_minus_a,
                  mcnemar_exact_p: c.mcnemar_exact_p,
                  delta_b_minus_a: {point: d.point == null ? null : -d.point, low: d.high == null ? null : -d.high, high: d.low == null ? null : -d.low, n_boot: d.n_boot},
                  cost_delta_usd: c.cost_delta_usd == null ? null : -c.cost_delta_usd,
                  cost_per_net_flip_usd: (c.cost_delta_usd != null && c.net_b_minus_a < 0) ? (-c.cost_delta_usd / -c.net_b_minus_a) : null,
                  cost_is_complete: c.cost_is_complete};
        }
      }
      return null;
    }
    function render() {
      var a = selA.value, b = selB.value;
      if (a === b) { out.innerHTML = '<p class="sec-note">Pick two different configurations.</p>'; return; }
      var c = find(a, b);
      if (!c) { out.innerHTML = '<p class="sec-note">These two rows are not in the same tier or share no scored task.</p>'; return; }
      var d = c.delta_b_minus_a || {};
      var la = selA.options[selA.selectedIndex].text, lb = selB.options[selB.selectedIndex].text;
      var html = '<div class="contrast-grid">';
      html += '<div class="card"><h3>Discordant table · ' + c.n + ' shared tasks</h3>' +
        '<table class="two"><thead><tr><th></th><th>B resolved</th><th>B failed</th></tr></thead><tbody>' +
        '<tr><th>A resolved</th><td class="num">' + c.both + '</td><td class="num">' + c.only_a + '</td></tr>' +
        '<tr><th>A failed</th><td class="num">' + c.only_b + '</td><td class="num">' + c.neither + '</td></tr></tbody></table>' +
        '<p>A = ' + esc(la) + '<br>B = ' + esc(lb) + '</p></div>';
      html += '<div class="card"><h3>Exact McNemar</h3><span class="big">p = ' + c.mcnemar_exact_p.toFixed(3) + '</span>' +
        '<p>' + c.only_b + ' tasks only B resolved against ' + c.only_a + ' only A. Net ' + (c.net_b_minus_a >= 0 ? '+' : '') + c.net_b_minus_a + ' for B.</p></div>';
      html += '<div class="card"><h3>Paired delta (B − A)</h3><span class="big">' + (d.point == null ? '—' : ((d.point >= 0 ? '+' : '') + pct(d.point, 1))) + '</span>' +
        '<p>Bootstrap 95% ' + pct(d.low, 1) + ' to ' + pct(d.high, 1) + ' over repo, task, seed (' + (d.n_boot || 0) + ' draws).</p></div>';
      html += '<div class="card"><h3>Cost</h3><span class="big">' + (c.cost_is_complete ? ((c.cost_delta_usd >= 0 ? '+' : '') + money(c.cost_delta_usd)) : 'incomplete') + '</span>' +
        '<p>' + (c.cost_is_complete ? ('B minus A over the shared tasks. Per net rescued task: ' + (c.cost_per_net_flip_usd == null ? 'n/a (no net gain)' : money(c.cost_per_net_flip_usd)) + '.') : 'One side has an unpriced seat, so no cost delta is shown.') + '</p></div>';
      html += '<div class="card"><h3>Rescued by B</h3><ul>' + (c.rescued_by_b.length ? c.rescued_by_b.map(function (t) { return '<li>' + esc(t) + '</li>'; }).join('') : '<li>none</li>') + '</ul></div>';
      html += '<div class="card"><h3>Broken by B</h3><ul>' + (c.broken_by_b.length ? c.broken_by_b.map(function (t) { return '<li>' + esc(t) + '</li>'; }).join('') : '<li>none</li>') + '</ul></div>';
      html += '</div>';
      out.innerHTML = html;
    }
    selA.value = out.getAttribute('data-default-a'); selB.value = out.getAttribute('data-default-b');
    selA.addEventListener('change', render); selB.addEventListener('change', render);
    render();
  }
})();
</script>
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True)
    ap.add_argument('--output', required=True)
    ap.add_argument('--methodology', default=None, help='also write the methodology page here')
    ap.add_argument('--also', action='append', default=[], metavar='LABEL=HREF',
                    help='link to another published suite page, repeatable')
    args = ap.parse_args()
    also = []
    for item in args.also:
        label, _, href = item.partition('=')
        if label and href:
            also.append((label, href))
    with open(args.data, encoding='utf-8') as handle:
        data = json.load(handle)
    # Links between the page, its methodology page and its JSON are by file
    # name, so a second suite's pages (poc.html, poc.json) link to their own.
    NAV['page'] = os.path.basename(args.output)
    NAV['json'] = os.path.basename(args.data)
    NAV['methodology'] = os.path.basename(args.methodology) if args.methodology else NAV['page']
    if data.get('schema') != 'code-bench-site/2.0':
        raise SystemExit('render-page.py renders code-bench-site/2.0; got %s' % data.get('schema'))
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, 'w', encoding='utf-8', newline='\n') as handle:
        handle.write(build(data, also))
        handle.write('\n')
    print(args.output)
    if args.methodology:
        with open(args.methodology, 'w', encoding='utf-8', newline='\n') as handle:
            handle.write(methodology_page(data, also))
            handle.write('\n')
        print(args.methodology)


if __name__ == '__main__':
    main()
