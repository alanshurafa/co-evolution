"""Render the frozen planning-study export without model calls or scoring."""
import html
import json
from pathlib import Path

SITE = Path(__file__).resolve().parent
PUBLIC = SITE / 'public'
NAMES = {'sonnet': 'Sonnet', 'codex': 'Terra', 'glm': 'GLM'}


def label(row):
    author = NAMES[row['author']]
    variant = row['variant']
    if variant.endswith('.draft'):
        return author + ' · original draft'
    if variant.endswith('.plain'):
        return author + ' · plain revision'
    if '.self-panel.' in variant:
        return author + ' · ' + variant.rsplit('.', 1)[1] + ' independent self-reviews'
    return author + ' · review by ' + ' + '.join(NAMES[x] for x in variant.split('.panel.', 1)[1].split('+'))


def number(value, signed=False):
    return '—' if value is None else format(value, '+.2f' if signed else '.2f')


def render(data):
    esc = html.escape
    explanation = (SITE / 'planning-explanation.html').read_text(encoding='utf-8')
    rows, details = [], []
    for row in data['rows']:
        name = label(row)
        cells = [f'<th scope="row"><a href="#{esc(row["variant"])}">{esc(name)}</a></th>']
        for judge in ('astra', 'fable'):
            j = row['judges'][judge]
            cells.append(f'<td>{number(j["mean_score"])}<small>{j["n"]}/6 judged · {j["critical_violation_tasks"]} flagged</small></td>')
            cells.append(f'<td>{number(j["delta_vs_self"]["mean"], True)}<small>{j["delta_vs_self"]["n"]} paired briefs</small></td>')
        cost = row['cost_per_task']
        cells.append(f'<td>{"Incomplete" if cost is None else "$" + format(cost, ".4f")}<small>{esc(row["cost_precision"].replace("-", " "))}</small></td>')
        rows.append(f'<tr data-author="{row["author"]}">' + ''.join(cells) + '</tr>')
        tasks = []
        for task in row['per_task']:
            scores = [number(task[j]['score']) if task[j] else 'Missing' for j in ('astra', 'fable')]
            tasks.append(f'<tr><th scope="row">{esc(task["task"])}</th><td>{esc(task["plan_status"])}</td><td>{scores[0]}</td><td>{scores[1]}</td></tr>')
        comparisons = []
        for judge in ('astra', 'fable'):
            for key, baseline in [('delta_vs_original', 'original'), ('delta_vs_plain', 'plain revision'), ('delta_vs_self', 'matched self-review')]:
                delta = row['judges'][judge][key]
                comparisons.append(f'<tr><th scope="row">{judge.title()} vs {baseline}</th><td>{number(delta["mean"], True)}</td><td>{number(delta["low"], True)} to {number(delta["high"], True)}</td><td>{delta["n"]}</td></tr>')
        details.append(f'<details id="{esc(row["variant"])}"><summary>{esc(name)}</summary><div class="detail-body"><p>Matched self-review control: {esc(row["matched_self_control"])}</p><div class="table-scroll"><table><caption>Paired score differences; descriptive bootstrap intervals</caption><thead><tr><th>Comparison</th><th>Mean Δ</th><th>95% interval</th><th>Paired briefs</th></tr></thead><tbody>{"".join(comparisons)}</tbody></table></div><div class="table-scroll"><table><caption>Individual brief coverage and scores /100</caption><thead><tr><th>Brief</th><th>Plan</th><th>Astra</th><th>Fable</th></tr></thead><tbody>{"".join(tasks)}</tbody></table></div></div></details>')
    primary = []
    for judge in ('astra', 'fable'):
        p = data['primary']['judges'][judge]
        primary.append(f'<div class="primary-result"><span>{judge.title()} · {p["n"]} paired briefs</span><b>{number(p["mean"], True)}<small> points /100</small></b><p>Descriptive 95% interval: {number(p["low"], True)} to {number(p["high"], True)}</p></div>')
    template = (SITE / 'observatory.html').read_text(encoding='utf-8')
    head = template.split('<body>')[0].replace('Co-Evolution · AI evaluation observatory', 'Co-Evolution · Planning study results')
    head = head.replace('Does cross-vendor AI code review improve results? Explore Co-Evolution\'s SWE-bench Verified scores, uncertainty, cost, and task-level evidence.', 'A custom planning study: 33 workflows, six synthetic briefs, independent Astra and Fable judgments, paired comparisons and missing results.')
    css = (SITE / 'observatory.css').read_text(encoding='utf-8')
    css += '\n.primary-result{padding:18px 0;border-bottom:1px solid var(--line)}.primary-result b{display:block;font:500 40px var(--mono);color:var(--blue);margin:8px 0}.primary-result small{font:12px var(--sans)}.primary-result p,.method-copy{color:var(--muted);font-size:13px}.planning-table{min-width:1000px}td small{display:block;color:var(--muted);font-size:10px;font-weight:400}td{font-variant-numeric:tabular-nums}th,td{text-align:left;padding:14px;border-bottom:1px solid var(--line)}table{border-collapse:collapse;width:100%}caption{text-align:left;color:var(--muted);padding:12px 0}details{background:white;border:1px solid var(--line);border-radius:6px;margin:10px 0}summary{padding:16px;font-weight:650}.detail-body{padding:0 18px 18px}.method-copy p{margin:14px 0}.table-scroll a{color:var(--blue)}.planning-footer{margin:55px 0 25px;color:var(--muted)}.planning-note{margin:18px 0;color:var(--muted)}@media(max-width:700px){.hero h1{font-size:42px}.dataset-strip{flex-wrap:wrap}.header-inner{gap:12px}.brand-label{display:none}nav{gap:12px}}'
    css += '\n#explanation{max-width:860px;font-size:15px;line-height:1.8;color:var(--ink)}#explanation h3{margin-top:30px;font-size:20px}#explanation li{margin:6px 0}'
    head = head.replace('__STYLE__', css)
    return head + f'''<body>
<a class="skip" href="#results">Skip to results</a>
<header class="site-header"><div class="header-inner"><a class="brand" href="index.html">co-evolution<span class="brand-dot">.</span><span class="brand-label">EVALS</span></a><nav aria-label="Main navigation"><a href="index.html">Coding</a><a href="#results" class="active">Planning</a><a href="#explanation">Explanation</a><a href="#methodology">Methodology</a></nav></div></header>
<main id="top" class="shell"><section class="hero"><div class="hero-copy"><p class="eyebrow">CUSTOM PLANNING STUDY · 12 SEPTEMBER 2026</p><h1>Better plans?<br><span>Judges disagree.</span></h1><p class="hero-description">Sonnet writes a plan. Terra reviews it. Sonnet revises.<br>Compared with Sonnet self-review, Astra sees a gain; Fable sees no clear gain.</p><a class="primary-link" href="#results">Explore all 33 workflows <span>↗</span></a><p class="hero-footnote">Recovered / combined exploratory results · Terminal partial</p></div><div class="hero-scores"><div class="hero-chart-heading"><h2>Terra review minus Sonnet self-review</h2></div>{''.join(primary)}<p class="hero-chart-note">Same original draft and final writer. Five paired briefs; one missing. Judges are independent and scores are not pooled.</p></div></section>
<div class="dataset-strip"><div><strong>33 workflows · 6 synthetic briefs</strong><span>194/198 plans · Astra 194/198 · Fable 187/198 judgments</span></div><div class="dataset-meta"><a href="planning-results.json" download>Download evidence ↓</a></div></div>
{explanation}
<section id="results" class="section"><div class="section-heading"><div><p class="eyebrow">01 / THE RESULTS</p><h2>Every configured combination.</h2><p>Rubric scores /100. Δ is the paired difference from matched self-review; missing scores are never zero.</p></div></div><div class="filter-bar"><label>Plan author<select id="author"><option value="all">All authors</option><option value="sonnet">Sonnet</option><option value="codex">Terra</option><option value="glm">GLM</option></select></label><span id="count" role="status" aria-live="polite">33 workflows</span></div><div class="table-scroll" tabindex="0" role="region" aria-label="Workflow scores; scroll horizontally"><table class="planning-table"><caption>All workflows in configured order; means may cover different brief subsets</caption><thead><tr><th scope="col">Workflow</th><th scope="col">Astra score</th><th scope="col">Astra Δ self</th><th scope="col">Fable score</th><th scope="col">Fable Δ self</th><th scope="col">Generation cost / plan</th></tr></thead><tbody>{''.join(rows)}</tbody></table></div><p class="planning-note">“Flagged” counts judgments with at least one critical violation: Astra 110/194; Fable 4/187. These are judge assessments, not verified real-world failures. Their sharp disagreement limits any general conclusion. Generation costs exclude study judging and use frozen list-equivalent rates.</p></section>
<section id="details" class="section"><div class="section-heading"><div><p class="eyebrow">02 / LOOK CLOSER</p><h2>Paired comparisons and brief coverage.</h2><p>Open a workflow for original-draft, plain-revision and matched self-review comparisons.</p></div></div>{''.join(details)}</section>
<section id="methodology" class="section method-copy"><div class="section-heading"><div><p class="eyebrow">03 / HOW TO READ THIS</p><h2>A bounded, exploratory planning screen.</h2></div></div>
<p><strong>Design.</strong> Sonnet (claude-sonnet-5, medium), Terra (gpt-5.6-terra, medium) and GLM (glm-5.3-flash, high) each authored six synthetic briefs. Each author has an original draft, plain revision, all seven nonempty reviewer subsets, and two- and three-critic same-model controls: 11 workflows each, 33 total. Critics independently read the same frozen draft; the original author integrates anonymous critiques. Kimi was excluded after a billing suspension.</p>
<p><strong>Judges.</strong> Astra (gpt-6-astra, high) and Fable (claude-fable-5-1, high) judged plans independently, isolated from authorship, previous scores, session history and tools. Six rubric dimensions cover requirements, correctness and feasibility, safeguards, sequencing, verification, and clarity. Citation validation is required. A failed judgment is missing, not a low score.</p>
<p><strong>Coverage.</strong> All 33 workflows are represented; four have only five plans. One exhausted Terra critique on the scheduling brief blocked four Sonnet revisions and eight judgments. Seven Fable judgments exhausted output/citation validation. All 18 drafts, 18 plain revisions, 89 critiques and 158 reviewed revisions succeeded. No pending work remains within the frozen attempt policy.</p>
<p><strong>Interpretation.</strong> Intervals are unadjusted, descriptive paired bootstrap intervals over at most six briefs. They do not establish confirmatory significance or improved intelligence. Compare paired differences and their sample sizes, rather than subtracting unpaired row means. Multi-reviewer panels use same-model controls matched by critic count.</p>
<p><strong>Recovery.</strong> The original screen stopped after a transport error was misclassified. Two excluded recovery attempts exposed CLI metadata/isolation issues; a catalog repair enabled the final recovery. Original artifacts remain unchanged. Generation resumed after partial grading and after the original deadline; this combined cohort is not the original uninterrupted protocol. No score-based selection or treatment-prompt tuning was performed.</p>
<p><strong>Resources.</strong> 730/790 authorized stage calls charged, including failed and interrupted attempts; the separate pilot remains 166/200. Known total list-equivalent cost is $66.4590, with four attempts unpriced and 18/33 workflow cost rows incomplete. This is not inferred cash subscription billing. Original run: 2h 19m 12s. Final recovery: 2h 39m 57s. All recovery controllers: 2h 40m 42s. Combined elapsed span: 21h 21m 35s, including the overnight gap.</p>
<p><strong>Evidence.</strong> <a href="planning-results.json" download>Download the frozen public export</a> for individual scores, cited evidence, paired intervals, costs, pricing and source SHA-256 hashes. The original plans and raw provider attempts remain in the local study archive.</p></section>
<footer class="planning-footer"><a href="index.html">← Coding observatory</a> · <a href="https://github.com/alanshurafa/co-evolution">Source on GitHub ↗</a></footer></main>
<script>document.getElementById('author').addEventListener('change',e=>{{let n=0;document.querySelectorAll('tr[data-author]').forEach(row=>{{row.hidden=e.target.value!=='all'&&row.dataset.author!==e.target.value;if(!row.hidden)n++;}});document.getElementById('count').textContent=n+' workflows';}});document.querySelectorAll('a[href^="#"]').forEach(a=>a.addEventListener('click',()=>{{const target=document.getElementById(a.getAttribute('href').slice(1));if(target?.tagName==='DETAILS')target.open=true;}}));</script></body></html>'''


if __name__ == '__main__':
    data = json.loads((PUBLIC / 'planning-results.json').read_text(encoding='utf-8'))
    (PUBLIC / 'planning.html').write_text(render(data), encoding='utf-8', newline='\n')
    print('Rendered planning.html from frozen public export; no model calls.')
