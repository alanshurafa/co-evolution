"""Render evidence evaluations and the bounded PlanBench outcome from frozen data."""
import html,importlib.util,json
from pathlib import Path
SITE=Path(__file__).resolve().parent;PUBLIC=SITE/'public'
spec=importlib.util.spec_from_file_location('publication',SITE/'validate-publication.py');gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
esc=html.escape

def shell(title,content):
    template=(SITE/'observatory.html').read_text(encoding='utf-8').split('<body>')[0]
    template=template.replace('Co-Evolution · AI evaluation observatory',esc(title))
    template=template.replace("Does cross-vendor AI code review improve results? Explore Co-Evolution's SWE-bench Verified scores, uncertainty, cost, and task-level evidence.",'Assessments of benchmark evidence, coverage, limitations, practical impact and next decisions.')
    css=(SITE/'observatory.css').read_text(encoding='utf-8')+'\n.evidence{max-width:900px;margin:0 auto;padding:48px 0}.evidence h1{font-size:46px;line-height:1.15;letter-spacing:-2px}.evidence h2{font-size:27px;margin:25px 0 15px}.evidence h3{font-size:17px;margin:22px 0 8px}.evidence p{font-size:15px;line-height:1.8;margin:12px 0}.evidence a{color:var(--blue)}.evidence article{padding:30px 0;border-top:1px solid var(--line);scroll-margin-top:110px}.evidence table{width:100%;border-collapse:collapse;min-width:550px}.evidence th,.evidence td{text-align:left;padding:14px;border-bottom:1px solid var(--line)}.evidence .notice{background:var(--blue-soft);border-left:3px solid var(--blue);padding:18px;margin:24px 0}.evidence .label{font:11px var(--mono);color:var(--muted);text-transform:uppercase;letter-spacing:1px}@media(max-width:700px){.evidence h1{font-size:36px}.evidence{padding:30px 0}.header-inner nav{gap:12px}}'
    return template.replace('__STYLE__',css)+f'<body><header class="site-header"><div class="header-inner"><a class="brand" href="index.html">co-evolution<span class="brand-dot">.</span></a><nav aria-label="Main navigation"><a href="index.html">Coding</a><a href="planning.html">Planning</a><a href="planbench.html">PlanBench</a><a href="evaluations.html">Assessments</a></nav></div></header><main class="shell"><div class="evidence">{content}</div></main></body></html>'

def build():
    entries=gate.validate(check_pages=False)
    content='<p class="eyebrow">EVALUATING THE TESTS</p><h1>What the evidence supports.</h1><p>Every current result publication needs an assessment of what was tested, what the results establish, their limitations, and the next decision. Scores alone do not establish practical benefit.</p><div class="notice"><strong>Publication requirement:</strong> the deployment check verifies that each current result export has a complete assessment tied to that exact data snapshot. Changed data requires a refreshed assessment. This enforces evidence coverage and freshness; it does not automatically prove the reasoning correct.</div>'
    for e in entries:
        content+=f'<article id="{esc(e["id"])}"><p class="label">{esc(e["status"])} · {esc(e["coverage"])}</p><h2>{esc(e["title"])}</h2>'
        for key,label in [('question','Question'),('finding','What we found'),('test_quality','How the test was checked'),('limitation','What it cannot establish'),('decision','Assessment'),('next_action','Next action')]:content+=f'<h3>{label}</h3><p>{esc(e[key])}</p>'
        content+=f'<p><a href="{esc(e["page"])}">Explore this test →</a> · <a href="{esc(e["data"])}" download>Download evidence ↓</a></p></article>'
    (PUBLIC/'evaluations.html').write_text(shell('Co-Evolution · Test assessments',content),encoding='utf-8',newline='\n')
    result=json.loads((PUBLIC/'planbench-results.json').read_text(encoding='utf-8'))
    content='<p class="eyebrow">PLANBENCH BLOCKSWORLD HARD · 50-TASK SUBSET</p><h1>Readiness failed.<br>No benchmark score.</h1><p>The official validator worked, but one Fable critique in the excluded smoke test received a provider safeguard refusal. The frozen readiness gate stopped the run before the 50 scored tasks began.</p><div class="notice"><strong>0 of 200 benchmark plans evaluated.</strong> This is missing measurement, not a score of zero and not evidence that co-evolution helped or hurt.</div><h2>The planned comparison</h2><div class="table-scroll" tabindex="0" role="region" aria-label="PlanBench arm coverage"><table><thead><tr><th>Arm</th><th>Workflow</th><th>Evaluated</th><th>Score /100</th></tr></thead><tbody>'
    for arm,s in result['scores'].items():content+=f'<tr><th scope="row">{arm}</th><td>{esc(s["workflow"])}</td><td>{s["evaluated"]}/50</td><td>Unavailable</td></tr>'
    content+='</tbody></table></div><p>Every arm shares the same original draft. The primary comparison was Fable review versus independent Astra self-review, with Astra performing the final revision in both. Planned scoring uses legal actions reaching the goal, not AI judgments.</p><h2>What actually ran</h2>'
    smoke=result['smoke'];valid=sum(x['outcome']['valid'] is True for x in smoke['outcomes']);evaluated=sum(x['outcome']['valid'] is not None for x in smoke['outcomes'])
    content+=f'<p>Two excluded smoke tasks were attempted: {smoke["succeeded_jobs"]}/12 generation jobs succeeded; one critique failed and its dependent revision was blocked. The {evaluated} available smoke plans passed VAL ({valid}/{evaluated}). These are setup checks, excluded from the benchmark score.</p>'
    content+=f'<p>Spent <strong>{result["spend"]["calls"]}/336 calls</strong>: nine Astra and two Fable. Known list-equivalent cost: <strong>${result["spend"]["known_list_equivalent_usd"]:.4f}</strong>. {esc(result["spend"]["pricing_note"])}</p>'
    content+='<p>The controller ran from 22:32:24 to 22:33:25 UTC on September 13, 2026, then exited with a partial-result receipt. No scored task was generated, no result was retried because of its score, and no model fallback or extra allowance was used.</p><article id="assessment"><h2>Evaluation of this test</h2>'
    for key,label in [('test_quality','Checks that passed'),('limitation','Limits of the evidence'),('decision','Conclusion'),('next_action','Next step')]:content+=f'<h3>{label}</h3><p>{esc(result["assessment"][key])}</p>'
    content+=f'</article><h2>Benchmark and provenance</h2><p>The fixed seed selected 50 tasks from the official 110-task hard set. This is a subset workflow experiment, not a full leaderboard submission. Benchmark commit: <code>{esc(result["benchmark"]["commit"])}</code>. Source, input, parser, validator and candidate hashes are retained.</p><p><a href="https://github.com/karthikv792/LLMs-Planning">Official PlanBench repository ↗</a> · <a href="planbench-results.json" download>Download the full outcome ↓</a> · <a href="evaluations.html#planbench">All test assessments →</a></p>'
    (PUBLIC/'planbench.html').write_text(shell('Co-Evolution · PlanBench readiness outcome',content),encoding='utf-8',newline='\n')
    print('Rendered test assessments and PlanBench outcome.')

if __name__=='__main__':build()
