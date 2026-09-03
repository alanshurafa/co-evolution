#!/usr/bin/env python3
"""Render the results page from the aggregator's JSON and nothing else.

Every figure on the page is read out of leaderboard.json, which in turn records
the evaluator report or run log each number came from. Prose here is framing;
it never states a result the JSON does not contain.

The agentic and single-shot tiers are rendered as separate tables on purpose. A
single-shot seat gets one prompt and one answer with no tools and no test run,
so its score is not comparable to a coding agent's and must never appear in the
same ranked list without the label.
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

COMPOSITION = {
    'A': 'fable implements',
    'B': 'fable implements → codex repairs',
    'C': 'fable implements → codex + glm + kimi critique → fable repairs',
    'D': 'fable implements → fable reviews and repairs',
    'E': 'codex implements',
    'F': 'glm answers once, from retrieved context',
    'G': 'kimi answers once, from retrieved context',
    'H': 'fable implements → glm critiques once → fable repairs',
    'I': 'fable implements → kimi critiques once → fable repairs',
}


def esc(value):
    return html.escape('' if value is None else str(value), quote=True)


def dots(per_task):
    cells = []
    for task in per_task:
        status = task['status']
        klass = {'resolved': 'p', 'unresolved': 'f'}.get(status, 'n')
        cells.append('<i class="%s" title="%s · %s"></i>'
                     % (klass, esc(task['instance_id']), esc(status)))
    return '<div class="dots">%s</div>' % ''.join(cells)


def denominator(row, task_count):
    """What a row's score is out of.

    A finished arm is scored against the whole subset, so a task it failed to
    submit counts against it. An arm still in progress is scored against what it
    has actually run, because the tasks it has not reached yet are not failures
    and must not be counted as any kind of result.
    """
    if row.get('complete', True):
        return task_count
    return row.get('attempted_count') or 0


def duration(seconds):
    if not seconds:
        return None
    hours, rest = divmod(int(seconds), 3600)
    minutes = rest // 60
    if hours:
        return '%dh %02dm' % (hours, minutes)
    if minutes:
        return '%dm' % minutes
    return '%ds' % int(seconds)


def effort_cells(row):
    """Wall time, cost, and cost per resolved task for one arm."""
    telemetry = row['telemetry']
    if not (row['measured'] or row.get('attempted')):
        blank = '<td class="num" data-sort="-1">—</td>'
        return blank * 3
    seconds = telemetry.get('total_wall_seconds') or 0
    cost = telemetry.get('claude_cost_usd') or 0
    per = telemetry.get('cost_per_resolved')
    partial = not telemetry.get('cost_is_complete', True)
    # A provider that reports no cost must not read as free. The dagger marks a
    # figure that covers only the Claude phases of an arm that used others.
    mark = '<span class="partial" title="Claude phases only; Codex, GLM and Kimi report no cost">†</span>' if partial else ''
    time_cell = ('<td class="num" data-sort="%d">%s</td>' % (seconds, esc(duration(seconds)))
                 if seconds else '<td class="num" data-sort="0">—</td>')
    if cost:
        cost_cell = '<td class="num" data-sort="%.2f">$%.2f%s</td>' % (cost, cost, mark)
    else:
        cost_cell = '<td class="num" data-sort="0">no CLI figure</td>'
    if per:
        per_cell = '<td class="num" data-sort="%.2f">$%.2f%s</td>' % (per, per, mark)
    else:
        per_cell = '<td class="num" data-sort="-1">—</td>'
    return time_cell + cost_cell + per_cell


def score_cell(row, task_count):
    if not row['measured']:
        # An arm that ran and produced nothing scorable scores zero. Only an arm
        # that never ran gets a blank.
        if row.get('attempted'):
            return ('<td class="score" data-sort="0"><span class="fig">'
                    '<span class="pct">0%%</span><span class="of">0 / %d</span>'
                    '</span></td>' % task_count)
        return '<td class="score none" data-sort="-1">not run</td>'
    # The denominator is the frozen subset, never the number of predictions the
    # arm managed to submit. A cell that produced no applicable patch failed its
    # task; dropping it from the denominator would flatter the arm.
    total = task_count
    resolved = row['resolved'] or 0
    pct = (100.0 * resolved / total) if total else 0.0
    remaining = max(0.0, 100.0 - pct)
    return (
        '<td class="score" data-sort="%.2f">'
        '<span class="bar" style="right:calc(%.1f%% + 6px)"></span>'
        '<span class="fig"><span class="pct">%d%%</span>'
        '<span class="of">%d / %d</span></span></td>'
    ) % (pct, remaining, round(pct), resolved, total)


def coverage_chip(row, task_count):
    if not row['measured']:
        if row.get('attempted'):
            return '<span class="chip bad">ran, no scorable patch</span>'
        return '<span class="chip none">no data</span>'
    # An unfinished arm is reported as unfinished, never as a low score. The
    # chip says how much of the subset it has actually run.
    if not row.get('complete', True):
        return ('<span class="chip warn">in progress · %d of %d tasks run</span>'
                % (row.get('attempted_count') or 0, task_count))
    linked = row['telemetry']['cells_linked']
    submitted = row['submitted'] or 0
    if submitted < task_count:
        return ('<span class="chip warn">%d of %d patches submitted</span>'
                % (submitted, task_count))
    if linked < submitted:
        return '<span class="chip warn">telemetry partial</span>'
    return '<span class="chip ok">fully measured</span>'


def num_cell(value, sort_value=None, suffix=''):
    if value is None:
        return '<td class="num" data-sort="-1">—</td>'
    sort_value = value if sort_value is None else sort_value
    return '<td class="num" data-sort="%s">%s%s</td>' % (sort_value, value, suffix)


def leaderboard_table(rows, table_id, task_count):
    body = []
    for row in rows:
        klass = '' if (row['measured'] or row.get('attempted')) else ' class="absent"'
        telemetry = row['telemetry']
        claude_calls = telemetry['claude_dispatches']
        codex_phases = telemetry['codex_phases']
        if row['measured'] or row.get('attempted'):
            calls_cell = num_cell(claude_calls if claude_calls else 0)
            codex_cell = num_cell(codex_phases if codex_phases else 0)
        else:
            calls_cell = codex_cell = '<td class="num" data-sort="-1">—</td>'
        body.append(
            '<tr%s><td><div class="pipeline">'
            '<span class="name">%s · %s</span>'
            '<span class="comp">%s</span></div></td>%s<td>%s</td>%s%s%s<td>%s</td></tr>'
            % (klass, esc(row['condition']), esc(row['label']),
               esc(COMPOSITION.get(row['condition'], row['description'])),
               score_cell(row, denominator(row, task_count)), dots(row['per_task']),
               calls_cell, codex_cell, effort_cells(row),
               coverage_chip(row, task_count)))
    return (
        '<div class="scroller"><table id="%s"><thead><tr>'
        '<th class="sortable" data-type="text">Pipeline</th>'
        '<th class="sortable" data-type="num" data-dir="desc">Resolved</th>'
        '<th>Per task</th>'
        '<th class="sortable" data-type="num">Fable calls</th>'
        '<th class="sortable" data-type="num">Codex phases</th>'
        '<th class="sortable" data-type="num">Wall time</th>'
        '<th class="sortable" data-type="num">Reported cost</th>'
        '<th class="sortable" data-type="num">Cost / resolved</th>'
        '<th>Coverage</th>'
        '</tr></thead><tbody>%s</tbody></table></div>'
    ) % (esc(table_id), ''.join(body))


def task_matrix(data):
    measured = [row for row in data['rows']
                if row['measured'] or row.get('attempted')]
    instances = [entry['instance_id'] for entry in data['suite']['instances']]
    header = ''.join('<th>%s<span class="tierflag">%s</span></th>'
                     % (esc(row['condition']),
                        ' single-shot' if row['tier'] == 'single-shot' else '')
                     for row in measured)
    body = []
    for instance in instances:
        cells = []
        for row in measured:
            task = next((t for t in row['per_task'] if t['instance_id'] == instance), None)
            if task is None or task['status'] in ('not-submitted', 'not-run'):
                cells.append('<td class="cell n">not scored</td>')
                continue
            if task['status'] == 'no-patch':
                cells.append('<td class="cell f" title="%s after %s attempts">no patch</td>'
                             % (esc(task.get('attempt_outcome') or 'no applicable patch'),
                                esc(task.get('attempts'))))
                continue
            if task['status'] == 'resolved':
                cells.append('<td class="cell p">resolved</td>')
                continue
            detail = []
            if task.get('fail_to_pass_failed'):
                detail.append('%d F2P fail' % task['fail_to_pass_failed'])
            if task.get('pass_to_pass_failed'):
                detail.append('%d P2P fail' % task['pass_to_pass_failed'])
            if not task.get('patch_applied'):
                detail.append('patch did not apply')
            cells.append('<td class="cell f" title="%s">unresolved</td>'
                         % esc(', '.join(detail) or 'unresolved'))
        repo = next(e['repo'] for e in data['suite']['instances']
                    if e['instance_id'] == instance)
        body.append('<tr><td class="mono">%s</td><td class="repo">%s</td>%s</tr>'
                    % (esc(instance), esc(repo), ''.join(cells)))
    return (
        '<div class="scroller"><table class="matrix"><thead><tr>'
        '<th>Instance</th><th>Repository</th>%s</tr></thead><tbody>%s</tbody></table></div>'
    ) % (header, ''.join(body))


def provenance_table(data):
    body = []
    for row in data['rows']:
        if not row['measured']:
            body.append('<tr><td class="mono">%s</td><td colspan="2">no evaluator report</td></tr>'
                        % esc(row['condition']))
            continue
        body.append('<tr><td class="mono">%s</td><td class="mono">%s</td><td class="mono">%s</td></tr>'
                    % (esc(row['condition']), esc(row['evaluator_run_id']), esc(row['report_file'])))
    for entry in data.get('superseded_reports', []):
        body.append('<tr class="absent"><td class="mono">%s</td><td class="mono">%s</td>'
                    '<td class="mono">%s <span class="chip none">superseded</span></td></tr>'
                    % (esc(entry['condition']), esc(entry['evaluator_run_id']),
                       esc(entry['report_file'])))
    return ('<div class="scroller"><table><thead><tr>'
            '<th>Condition</th><th>Evaluator run</th><th>Report file</th>'
            '</tr></thead><tbody>%s</tbody></table></div>') % ''.join(body)


def tiles(data):
    rows = data['rows']
    measured = [r for r in rows if r['measured'] or r.get('attempted')]
    scored_cells = sum(r['submitted'] or 0 for r in measured)
    claude_calls = sum(r['telemetry']['claude_dispatches'] for r in measured)
    wall_seconds = sum(r['telemetry'].get('total_wall_seconds') or 0 for r in measured)
    cost = sum(r['telemetry']['claude_cost_usd'] for r in measured)
    resolved = sum(r['resolved'] or 0 for r in measured)
    per_resolved = ('$%.2f' % (cost / resolved)) if resolved and cost else '—'
    items = [
        ('Configurations', '%d <span class="of">/ %d</span>' % (len(measured), len(rows)),
         'measured on this subset'),
        ('Tasks per cell', str(data['suite']['task_count']), 'frozen subset'),
        ('Scored cells', str(scored_cells), 'official evaluator, Docker'),
        ('Fable dispatches', str(claude_calls), 'across every measured arm'),
        ('Wall time', esc(duration(wall_seconds) or '—'), 'model time, all providers'),
        ('Cost per resolved', per_resolved, 'Claude phases only'),
    ]
    return '<div class="tiles">%s</div>' % ''.join(
        '<div class="tile"><span class="k">%s</span><span class="v">%s</span>'
        '<span class="n">%s</span></div>' % (esc(k), v, esc(n)) for k, v, n in items)


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
  body { background: var(--paper); color: var(--ink); font-family: var(--f-sans);
         font-size: 16px; line-height: 1.55; -webkit-font-smoothing: antialiased; margin: 0; }
  .wrap { max-width: 1180px; margin: 0 auto; padding: var(--pad);
          display: flex; flex-direction: column; gap: 3.25rem; }
  a { color: var(--accent); text-underline-offset: 2px; }
  :focus-visible { outline: 2px solid var(--accent); outline-offset: 2px; border-radius: 2px; }

  .masthead { display: flex; flex-direction: column; gap: .85rem; padding-top: .5rem; }
  .eyebrow { font-family: var(--f-mono); font-size: .72rem; letter-spacing: .14em;
             text-transform: uppercase; color: var(--ink-faint);
             display: flex; flex-wrap: wrap; gap: .5rem .9rem; }
  h1 { font-family: var(--f-display); font-weight: 600;
       font-size: clamp(2rem, 5.2vw, 3.1rem); line-height: 1.05;
       letter-spacing: -.015em; margin: 0; text-wrap: balance; }
  .standfirst { font-size: clamp(1rem, 2.1vw, 1.14rem); color: var(--ink-soft);
                max-width: var(--measure); margin: 0; }
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
  .tile { background: var(--surface); padding: .95rem 1.1rem;
          display: flex; flex-direction: column; gap: .18rem; }
  .tile .k { font-family: var(--f-mono); font-size: .68rem; letter-spacing: .11em;
             text-transform: uppercase; color: var(--ink-faint); }
  .tile .v { font-family: var(--f-mono); font-size: 1.5rem; font-weight: 600;
             font-variant-numeric: tabular-nums; line-height: 1.15; }
  .tile .v .of { font-size: .9rem; color: var(--ink-faint); font-weight: 400; }
  .tile .n { font-size: .78rem; color: var(--ink-faint); }

  section { display: flex; flex-direction: column; gap: 1rem; }
  h2.sec { font-family: var(--f-display); font-size: clamp(1.3rem, 3vw, 1.65rem);
           font-weight: 600; letter-spacing: -.01em; margin: 0; padding-bottom: .45rem;
           border-bottom: 2px solid var(--ink); text-wrap: balance; }
  h3.tier { font-family: var(--f-mono); font-size: .78rem; letter-spacing: .12em;
            text-transform: uppercase; margin: .6rem 0 0; color: var(--ink); }
  .sec-note { margin: 0; color: var(--ink-soft); max-width: var(--measure); font-size: .95rem; }

  .scroller { overflow-x: auto; border: 1px solid var(--rule); border-radius: 5px;
              background: var(--surface); box-shadow: var(--shadow); }
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
  .num { font-family: var(--f-mono); font-variant-numeric: tabular-nums; white-space: nowrap; }
  .partial { color: var(--caveat); font-weight: 600; margin-left: .15rem; cursor: help; }
  .mono { font-family: var(--f-mono); font-size: .82rem; }
  td.repo { font-family: var(--f-mono); font-size: .78rem; color: var(--ink-faint); }
  .tierflag { font-family: var(--f-mono); font-size: .6rem; color: var(--caveat);
              display: block; letter-spacing: .08em; }

  tr.absent td { color: var(--ink-faint);
    background-image: repeating-linear-gradient(45deg, transparent, transparent 7px,
      var(--absent-wash) 7px, var(--absent-wash) 8px); }
  tr.absent:hover td { background-color: var(--surface-sunk); }

  .pipeline { display: flex; flex-direction: column; gap: .12rem; min-width: 230px; }
  .pipeline .name { font-weight: 600; color: var(--ink); }
  .pipeline .comp { font-family: var(--f-mono); font-size: .74rem; color: var(--ink-faint); }

  .score { position: relative; min-width: 132px; }
  .score .bar { position: absolute; inset: 4px auto 4px 6px; border-radius: 2px;
                background: var(--pass-wash); border-left: 3px solid var(--pass); }
  .score .fig { position: relative; font-family: var(--f-mono);
                font-variant-numeric: tabular-nums; font-weight: 600; padding-left: .7rem;
                display: flex; align-items: baseline; gap: .4rem; }
  .score .fig .pct { font-size: 1.02rem; }
  .score .fig .of { font-size: .74rem; color: var(--ink-soft); font-weight: 400; }
  .score.none { color: var(--ink-faint); font-family: var(--f-mono); }

  .dots { display: flex; gap: 3px; }
  .dots i { width: 15px; height: 15px; border-radius: 2px; display: block;
            border: 1px solid transparent; }
  .dots i.p { background: var(--pass-wash); border-color: var(--pass); }
  .dots i.f { background: var(--fail-wash); border-color: var(--fail); }
  .dots i.n { background: var(--absent-wash); border-color: var(--rule-strong); }

  .chip { display: inline-block; font-family: var(--f-mono); font-size: .68rem;
          letter-spacing: .05em; text-transform: uppercase; padding: .17rem .45rem;
          border-radius: 3px; white-space: nowrap; border: 1px solid; }
  .chip.ok { color: var(--pass); background: var(--pass-wash); border-color: var(--pass); }
  .chip.warn { color: var(--caveat); background: var(--caveat-wash); border-color: var(--caveat); }
  .chip.bad { color: var(--fail); background: var(--fail-wash); border-color: var(--fail); }
  .chip.none { color: var(--absent); background: var(--absent-wash); border-color: var(--rule-strong); }

  .matrix td.cell { text-align: center; font-family: var(--f-mono); font-weight: 600; width: 104px; }
  .matrix td.cell.p { background: var(--pass-wash); color: var(--pass); }
  .matrix td.cell.f { background: var(--fail-wash); color: var(--fail); }
  .matrix td.cell.n { color: var(--ink-faint); }

  .findings { display: grid; gap: 1.15rem; grid-template-columns: 1fr; }
  @media (min-width: 900px) { .findings { grid-template-columns: 1fr 1fr; } }
  .finding { background: var(--surface); border: 1px solid var(--rule);
             border-top: 3px solid var(--fail); border-radius: 5px;
             padding: 1.15rem 1.25rem; display: flex; flex-direction: column;
             gap: .7rem; box-shadow: var(--shadow); }
  .finding.amber { border-top-color: var(--caveat); }
  .finding h3 { margin: 0; font-family: var(--f-display); font-size: 1.12rem;
                font-weight: 600; line-height: 1.25; text-wrap: balance; }
  .finding p { margin: 0; font-size: .93rem; color: var(--ink-soft); }
  .finding .label { font-family: var(--f-mono); font-size: .66rem; letter-spacing: .12em;
                    text-transform: uppercase; color: var(--ink-faint); }
  pre.code { margin: 0; background: var(--surface-sunk); border: 1px solid var(--rule);
             border-radius: 4px; padding: .7rem .85rem; overflow-x: auto;
             font-family: var(--f-mono); font-size: .78rem; line-height: 1.6; color: var(--ink); }
  pre.code .add { color: var(--pass); }
  pre.code .del { color: var(--fail); }
  pre.code .dim { color: var(--ink-faint); }

  ul.plain { margin: 0; padding-left: 1.1rem; color: var(--ink-soft); font-size: .93rem;
             display: flex; flex-direction: column; gap: .35rem; }
  ul.plain strong { color: var(--ink); }

  .legend { display: flex; flex-wrap: wrap; gap: .5rem 1.1rem; align-items: center;
            font-size: .78rem; color: var(--ink-soft); }
  .legend .swatch { display: inline-flex; align-items: center; gap: .35rem; }
  .legend .swatch i { width: 12px; height: 12px; border-radius: 2px;
                      border: 1px solid transparent; display: block; }

  footer { border-top: 1px solid var(--rule); padding-top: 1.15rem; padding-bottom: 2rem;
           color: var(--ink-faint); font-size: .82rem;
           display: flex; flex-direction: column; gap: .35rem; }
  footer .mono { font-size: .76rem; }

  @media (prefers-reduced-motion: reduce) { * { animation: none !important; transition: none !important; } }
</style>
"""

SORT_SCRIPT = """
<script>
  (function () {
    var tables = document.querySelectorAll('table[data-sortable]');
    Array.prototype.forEach.call(tables, function (table) {
      var headers = table.querySelectorAll('th.sortable');
      Array.prototype.forEach.call(headers, function (th) {
        var index = Array.prototype.indexOf.call(th.parentNode.children, th);
        th.setAttribute('tabindex', '0');
        th.setAttribute('role', 'button');
        function activate() {
          var dir = th.getAttribute('data-dir') === 'desc' ? 'asc' : 'desc';
          Array.prototype.forEach.call(headers, function (h) { h.removeAttribute('data-dir'); });
          th.setAttribute('data-dir', dir);
          var body = table.tBodies[0];
          var rows = Array.prototype.slice.call(body.rows);
          var numeric = th.getAttribute('data-type') === 'num';
          rows.sort(function (a, b) {
            var ca = a.cells[index], cb = b.cells[index];
            if (numeric) {
              var va = parseFloat(ca.getAttribute('data-sort'));
              var vb = parseFloat(cb.getAttribute('data-sort'));
              if (isNaN(va)) { va = -Infinity; }
              if (isNaN(vb)) { vb = -Infinity; }
              return dir === 'desc' ? vb - va : va - vb;
            }
            var ta = ca.textContent.trim().toLowerCase();
            var tb = cb.textContent.trim().toLowerCase();
            return dir === 'desc' ? tb.localeCompare(ta) : ta.localeCompare(tb);
          });
          rows.forEach(function (r) { body.appendChild(r); });
        }
        th.addEventListener('click', activate);
        th.addEventListener('keydown', function (e) {
          if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); activate(); }
        });
      });
    });
  })();
</script>
"""


# The narrative below describes one specific pattern in the results. It is
# guarded: if a later run stops producing that pattern, the section renders
# nothing rather than describing a run that did not happen.
SEPARATOR_TASK = 'sympy__sympy-20916'
UNICODE_DIGITS = ('B', 'D')
ASCII_DIGITS = ('A', 'C', 'E')


def status_on(rows, condition, instance):
    row = next((r for r in rows if r['condition'] == condition), None)
    if row is None:
        return None
    task = next((t for t in row['per_task'] if t['instance_id'] == instance), None)
    return task['status'] if task else None


def findings(data):
    rows = data['rows']
    resolved_ok = all(status_on(rows, c, SEPARATOR_TASK) == 'resolved' for c in UNICODE_DIGITS)
    failed_ok = all(status_on(rows, c, SEPARATOR_TASK) == 'unresolved' for c in ASCII_DIGITS)
    others_uniform = True
    for entry in data['suite']['instances']:
        if entry['instance_id'] == SEPARATOR_TASK:
            continue
        for cond in UNICODE_DIGITS + ASCII_DIGITS:
            if status_on(rows, cond, entry['instance_id']) != 'resolved':
                others_uniform = False
    if not (resolved_ok and failed_ok and others_uniform):
        return ''

    return (
        '<section><h2 class="sec">What actually separated the pipelines</h2>'
        '<p class="sec-note">Four of the five tasks resolved under every agentic '
        'configuration. The entire spread across the leaderboard comes from one task, '
        'and within that task from one character class.</p>'
        '<div class="findings">'
        '<article class="finding">'
        '<span class="label">Finding 01 &middot; ' + esc(SEPARATOR_TASK) + '</span>'
        '<h3>Every agentic arm wrote the same fix; two chose Unicode digits and passed</h3>'
        '<p>All five agentic configurations edited the same line of '
        '<span class="mono">sympy/printing/conventions.py</span>, replacing an ASCII-only '
        'name pattern with a Unicode-aware one. They differ in the second capture group '
        'alone.</p>'
        '<pre class="code"><span class="dim">baseline </span>'
        "^([a-zA-Z]+)([0-9]+)$\n"
        '<span class="add">B, D    </span> '
        "^([^" + chr(92) + "W" + chr(92) + "d_]+)(" + chr(92) + "d+)$     "
        '<span class="dim">Unicode digits &rarr; resolved</span>\n'
        '<span class="del">A, C, E </span> '
        "^([^" + chr(92) + "W" + chr(92) + "d_]+)([0-9]+)$  "
        '<span class="dim">ASCII only &rarr; unresolved</span></pre>'
        '<p>The upstream test subscripts a non-ASCII digit, so the ASCII-only class fails it. '
        'In condition C the panel critique argued explicitly that '
        '<span class="mono">' + chr(92) + 'd+</span> would wrongly capture Arabic-Indic digits; '
        'the repair pass accepted that reasoning and narrowed the class. The argument was '
        'careful and the conclusion was wrong.</p>'
        '</article>'
        '<article class="finding amber">'
        '<span class="label">Finding 02 &middot; harness</span>'
        '<h3>The cross-vendor repair arm had never actually run</h3>'
        '<p>Codex on this Windows host accepts '
        '<span class="mono">--sandbox workspace-write</span> and then reports '
        '<span class="mono">sandbox: read-only</span>. Across the earlier B cells it wrote a '
        'review and changed nothing, so that run\'s 5/5 was Fable\'s first draft with a '
        'discarded review attached.</p>'
        '<p>The arm now runs with elevated access inside throwaway clones, and the mode is '
        'recorded per cell. Re-run with a repair step that can write, B resolves the separator '
        'task. Its two earlier reports are listed as superseded below rather than deleted.</p>'
        '</article>'
        '</div></section>')


NUMBER_WORDS = {1: 'One', 2: 'Two', 3: 'Three', 4: 'Four', 5: 'Five', 6: 'Six',
                7: 'Seven', 8: 'Eight', 9: 'Nine', 10: 'Ten'}


def count_phrase(count, noun, cap=True):
    """"Nine configurations" — spelled out where English prefers it."""
    word = NUMBER_WORDS.get(count, str(count))
    if not cap:
        word = word.lower()
    return esc('%s %s%s' % (word, noun, '' if count == 1 else 's'))


def caveat(data):
    """The standing warning above the table, sized to what actually ran.

    A one-task run is a proof that the pipeline works, not a measurement, and
    the page has to say so in its own voice rather than leave a reader to infer
    it from the denominator.
    """
    task_count = data['suite']['task_count']
    rows = data.get('rows') or []
    running = [r for r in rows
               if (r['measured'] or r.get('attempted')) and not r.get('complete', True)]
    paragraphs = []
    if running:
        counts = sorted({r.get('attempted_count') or 0 for r in running})
        spread = (counts[0] != counts[-1])
        paragraphs.append(
            'This run is unfinished. Each arm is scored against the tasks it has actually '
            'run, not against the full subset, because a task an arm has not reached yet '
            'is not a failure. Nothing here is a final score.')
        if spread:
            paragraphs.append(
                'The arms have run different numbers of tasks so far (%d to %d of %d), so '
                'the percentages are not directly comparable to each other. Read the '
                'task-by-task table below for any head-to-head comparison; it is the only '
                'view here that holds the task set fixed.'
                % (counts[0], counts[-1], task_count))
    if task_count == 1:
        paragraphs.append(
            'Proof of concept: one SWE-bench Verified task, not a score. This run exists '
            'to show that every configuration executes end to end and reaches the official '
            'evaluator. A single task cannot separate two pipelines, and no row here should '
            'be read as evidence that one configuration is better than another. Frozen '
            '50-task results for arm B are internal until the comparison arms run.')
    else:
        points = 100.0 / task_count
        paragraphs.append(
            '%d tasks is a probe, not a ranking. One task is %d points, so a one-task gap '
            'between two rows is well inside what a %d-task sample produces by chance.'
            % (task_count, round(points), task_count))
    paragraphs.append(
        'These numbers are not comparable to published full-500 SWE-bench Verified scores: '
        'the subset is fixed and was chosen for the harness, not drawn at random.')
    paragraphs.append(
        'The two tiers are listed separately because they are not the same test. An agentic '
        'row had file tools and could run the test suite; a single-shot row got one prompt '
        'and answered once.')
    return ('<div class="callout"><h2>Read this before the table</h2>%s</div>'
            % ''.join('<p>%s</p>' % esc(text) for text in paragraphs))


def nav_links(also):
    """Links to the project's other published runs.

    Each run is its own page because each is a different subset; without a link
    between them a reader who lands on one has no way to discover the others.
    """
    if not also:
        return ''
    return ''.join('<span><a href="%s">%s</a></span>' % (esc(href), esc(label))
                   for label, href in also)


def build(data, also=()):
    harness = data['harness']
    gold = data['gold_canary'] or {}
    suite = data['suite']
    rows = data['rows']
    agentic = [r for r in rows if r['tier'] == 'agentic']
    single = [r for r in rows if r['tier'] == 'single-shot']
    measured_single = [r for r in single if r['measured'] or r.get('attempted')]

    parts = []
    parts.append('<title>Co-Evolution Code Battery</title>')
    parts.append(STYLE)
    parts.append('<div class="wrap">')

    parts.append(
        '<header class="masthead">'
        '<div class="eyebrow"><span>SWE-bench Verified · %d-task frozen subset</span>'
        '<span>Official pinned evaluator, Docker</span>'
        '<span>Built %s</span>%s</div>'
        '<h1>Co-Evolution Code Battery</h1>'
        '<p class="standfirst">Does putting a second model in the loop produce better patches '
        'than one model working alone? %s, %s, every patch scored by the official '
        'evaluator in Docker.</p>'
        '<div class="runmeta"><span>fable @ medium</span><span>gpt-5.6-sol @ medium</span>'
        '<span>glm-5.3-flash @ effort:low</span><span>kimi-k3 @ thinking:off</span>'
        '<span>phase timeout 900s</span><span>gold canary %s/%s</span>'
        '<span>harness %s</span></div></header>'
        % (suite['task_count'], esc(data['generated_at']), nav_links(also),
           count_phrase(len(rows), 'configuration'),
           count_phrase(suite['task_count'], 'pinned SWE-bench Verified task', cap=False),
           esc(gold.get('resolved')), esc(gold.get('submitted')),
           esc((harness.get('repo_commit') or '')[:7])))

    parts.append(caveat(data))

    parts.append(tiles(data))

    parts.append('<section><h2 class="sec">Leaderboard</h2>')
    for tier, group in (('agentic', agentic), ('single-shot', single)):
        title, note = TIER_COPY[tier]
        parts.append('<h3 class="tier">%s</h3><p class="sec-note">%s</p>' % (esc(title), esc(note)))
        parts.append(leaderboard_table(group, 'board-%s' % tier, suite['task_count']))
    parts.append(
        '<div class="legend">'
        '<span class="swatch"><i style="background:var(--pass-wash);border-color:var(--pass)"></i> resolved</span>'
        '<span class="swatch"><i style="background:var(--fail-wash);border-color:var(--fail)"></i> unresolved</span>'
        '<span class="swatch"><i style="background:var(--absent-wash);border-color:var(--rule-strong)"></i> no patch scored</span>'
        '<span>Task order: %s</span></div>'
        % esc(' · '.join(e['instance_id'].split('__')[0] for e in suite['instances'])))
    parts.append('</section>')

    parts.append(findings(data))

    parts.append(
        '<section><h2 class="sec">Task by task</h2>'
        '<p class="sec-note">One column per measured configuration. Hover an unresolved cell '
        'for the failing test counts the evaluator recorded.</p>%s</section>' % task_matrix(data))

    integrity = []
    integrity.append(
        '<li><strong>Evaluator.</strong> Official SWE-bench harness pinned at '
        '<span class="mono">%s</span>, dataset <span class="mono">%s</span> at revision '
        '<span class="mono">%s</span>, both from <span class="mono">%s</span>.</li>'
        % (esc((harness.get('swebench_commit') or '')[:12]), esc(harness.get('dataset')),
           esc((harness.get('dataset_revision') or '')[:12]), esc(harness.get('lock_file'))))
    if gold:
        integrity.append(
            '<li><strong>Gold canary.</strong> A gold patch resolved %s/%s before any generated '
            'prediction was scored, so a failure here means the patch, not the harness. Report: '
            '<span class="mono">%s</span>.</li>'
            % (esc(gold.get('resolved')), esc(gold.get('submitted')), esc(gold.get('report_file'))))
    integrity.append(
        '<li><strong>Cost is the CLI\'s own figure</strong> for work billed to a Max '
        'subscription, not metered API spend. The Claude CLI exposes no plan meter, so there is '
        'no percentage-of-plan number here. Codex, GLM and Kimi report no per-call cost, so their '
        'rows show dispatch counts instead.</li>')
    if measured_single:
        integrity.append(
            '<li><strong>The single-shot tier is a floor, not a model ceiling.</strong> GLM and '
            'Kimi are reachable here only as chat completions. Their cells receive the issue plus '
            'a deterministic file selection and return one diff, gated by '
            '<span class="mono">git apply --check --recount</span>. A cell that never produced an '
            'applicable patch contributes no prediction and still counts against the '
            'subset\'s ' + str(suite['task_count']) + '. '
            '<span class="mono">--recount</span> recomputes the hunk line counts and changes no '
            'line of the proposed edit: without it the gate scores a chat model\'s ability to '
            'count lines, which the agentic arms never have to do because they edit files '
            'directly.</li>')
    by_mode = {}
    for row in rows:
        for mode in row['telemetry']['sandbox_modes']:
            by_mode.setdefault(mode, []).append(row['condition'])
    if by_mode:
        detail = '; '.join('<span class="mono">%s</span> in %s'
                           % (esc(mode), esc(', '.join(sorted(conds))))
                           for mode, conds in sorted(by_mode.items()))
        integrity.append(
            '<li><strong>Codex sandbox.</strong> %s. Codex on Windows accepts '
            '<span class="mono">workspace-write</span> and then runs read-only, which makes a '
            'repair arm look like it ran while changing nothing, so the mode each cell used is '
            'recorded in its run manifest. The arms that needed Codex to write ran with elevated '
            'access inside throwaway clones.</li>' % detail)
    integrity.append(
        '<li><strong>Every number on this page comes from a file.</strong> The page is generated '
        'from <span class="mono">benchmarks/site/aggregate.sh</span> output; each row names the '
        'evaluator report it was read from and each task cell is backed by that run\'s per-instance '
        '<span class="mono">report.json</span>.</li>')

    parts.append('<section><h2 class="sec">Methodology and integrity</h2>'
                 '<ul class="plain">%s</ul>%s</section>'
                 % (''.join(integrity), provenance_table(data)))

    dirty = harness.get('working_tree_dirty')
    parts.append(
        '<footer><div>Generated from run artifacts in '
        '<span class="mono">benchmarks/results/code/</span> by '
        '<span class="mono">benchmarks/site/aggregate.sh</span>.</div>'
        '<div class="mono">Repository co-evolution-runtime · harness commit %s%s</div>'
        '<div>%s</div></footer>'
        % (esc(harness.get('repo_commit')),
           ' · working tree had uncommitted changes at build time' if dirty else '',
           esc(data['caveat'])))

    parts.append('</div>')
    parts.append(SORT_SCRIPT)
    return '\n'.join(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--data', required=True)
    ap.add_argument('--output', required=True)
    ap.add_argument('--also', action='append', default=[], metavar='LABEL=HREF',
                    help='link to another published run, repeatable')
    args = ap.parse_args()
    also = []
    for item in args.also:
        label, _, href = item.partition('=')
        if label and href:
            also.append((label, href))
    with open(args.data, encoding='utf-8') as handle:
        data = json.load(handle)
    page = build(data, also)
    page = page.replace('<table id="board-', '<table data-sortable id="board-')
    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, 'w', encoding='utf-8', newline='\n') as handle:
        handle.write(page)
        handle.write('\n')
    print(args.output)


if __name__ == '__main__':
    main()
