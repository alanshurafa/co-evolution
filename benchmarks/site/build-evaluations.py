"""Render evidence evaluations and the bounded PlanBench outcome from frozen data."""
import html,importlib.util,json
from pathlib import Path
SITE=Path(__file__).resolve().parent;PUBLIC=SITE/'public'
spec=importlib.util.spec_from_file_location('publication',SITE/'validate-publication.py');gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
esc=html.escape

def number(value,digits=2):
    return 'Unavailable' if value is None else f'{value:.{digits}f}'

def render_planbench(result,data_name='planbench-results.json',assessment_id='planbench'):
    labels=result.get('model_labels',{'author':'Astra','reviewer':'Fable'})
    author=esc(labels['author']);reviewer=esc(labels['reviewer'])
    author_family='claude' if result.get('author_seat','astra') in ('sonnet','fable') else 'codex'
    reviewer_family='claude' if author_family=='codex' else 'codex'
    count=sum(s['evaluated'] for s in result['scores'].values())
    headline='The benchmark is scored.' if count==200 else ('Partial benchmark results.' if count else 'Readiness failed. No benchmark score.')
    if result['scores']['A']['score']==100:headline='Original plans scored 100%.'
    elif count==200 and all(result['scores'][a]['score']==100 for a in ('B','C','D')):headline='Plain revision was enough.'
    intro=result['assessment']['finding']
    content=f'<p class="eyebrow">PLANBENCH BLOCKSWORLD HARD · 50-TASK SUBSET</p><h1>{headline}</h1><p>{esc(intro)}</p><div class="notice"><strong>{count} of 200 benchmark plans evaluated.</strong> Scores measure legal action sequences reaching the goal, not writing quality or human productivity. Missing outcomes stay unavailable.</div><h2>Four workflows, the same starting plans</h2><div class="table-scroll" tabindex="0" role="region" aria-label="PlanBench arm scores"><table><thead><tr><th>Arm</th><th>Workflow</th><th>Valid / evaluated</th><th>Missing</th><th>Score /100</th></tr></thead><tbody>'
    for arm,s in result['scores'].items():
        score=number(s['score']) if s['score'] is not None else 'Unavailable<br><small>Possible range '+str(s['score_bounds'][0])+'–'+str(s['score_bounds'][1])+'</small>'
        content+=f'<tr><th scope="row">{arm}</th><td>{esc(s["workflow"])}</td><td>{s["valid"]}/{s["evaluated"]}</td><td>{s["missing"]}/50</td><td>{score}</td></tr>'
    content+=f'</tbody></table></div><p>A is the original {author} plan. B adds plain revision. C adds independent {author} critique and {author} revision. D adds independent {reviewer} critique and {author} revision. Each arm uses the same original per task; no validator feedback reaches the models. Effort: {esc(result["effort"])}.</p><h2>What review changed</h2><div class="table-scroll" tabindex="0" role="region" aria-label="Paired workflow comparisons"><table><thead><tr><th>Comparison</th><th>Paired tasks</th><th>Change, points</th><th>95% paired interval</th><th>Repairs</th><th>Regressions</th></tr></thead><tbody>'
    for name,p in result['contrasts'].items():
        bounds='Unavailable' if p['interval95'] is None else ' to '.join(number(v) for v in p['interval95'])
        content+=f'<tr><th scope="row">{esc(name)}</th><td>{p["n"]}</td><td>{number(p["delta_pp"])}</td><td>{bounds}</td><td>{p["repairs"]}</td><td>{p["regressions"]}</td></tr>'
    primary=result['contrasts']['D-C']
    content+=f'</tbody></table></div><p>D−C is the primary comparison: cross-model versus self-review. D−B and D−A are secondary. A repair means D succeeds where its comparator fails; a regression is the reverse. Exact paired McNemar p-value for D−C: {number(primary["mcnemar_exact_p"],4)}. Bootstrap intervals are descriptive; there is one sampled response per arm and task.</p>'
    if result.get('resources'):
        content+='<h2>What the extra steps cost</h2><div class="table-scroll" tabindex="0" role="region" aria-label="Workflow resource costs"><table><thead><tr><th>Arm</th><th>Estimated cost / task</th><th>Priced tasks</th><th>Median workflow seconds</th><th>Median model-phase seconds</th></tr></thead><tbody>'
        for arm,r in result['resources'].items():
            charge='Incomplete' if r['mean_standalone_cost_usd'] is None else '$'+number(r['mean_standalone_cost_usd'],4)
            content+=f'<tr><th scope="row">{arm}</th><td>{charge}</td><td>{r["priced_tasks"]}/50</td><td>{number(r["median_observed_workflow_seconds"],1)}</td><td>{number(r["median_model_phase_seconds"],1)}</td></tr>'
        content+='</tbody></table></div><p>'+esc(result['timing_note'])+'</p>'
    paired_resources=result.get('matched_complete_resources',{})
    if paired_resources and all(paired_resources[a]['mean_cost_usd'] for a in ('A','D')):
        a,d=paired_resources['A'],paired_resources['D']
        content+=f'<p>On the same {d["n"]} completed tasks, original {author} cost an estimated ${a["mean_cost_usd"]:.4f} per task versus ${d["mean_cost_usd"]:.4f} with {reviewer} review ({d["mean_cost_usd"]/a["mean_cost_usd"]:.1f}×). Median model-phase time was {number(a["median_phase_seconds"],1)} versus {number(d["median_phase_seconds"],1)} seconds. These matched-completion estimates exclude undelivered workflows; the experiment total below includes their charged attempts.</p>'
    spend=result['spend']
    content+=f'<p>Whole experiment: <strong>{spend["calls"]}/{spend["cap"]} calls</strong>, including preserved prior attempts and excluded smoke work. {author}: {spend["families"][author_family]}; {reviewer}: {spend["families"][reviewer_family]}. Known list-equivalent cost: <strong>${spend["known_list_equivalent_usd"]:.4f}</strong>; unpriced calls: {len(spend["unpriced_calls"])}. Shared experiment spend is not the sum of standalone arm costs. {esc(spend["pricing_note"])}</p>'
    smoke=result['smoke'];valid=sum(x['outcome']['valid'] is True for x in smoke['outcomes']);evaluated=sum(x['outcome']['valid'] is not None for x in smoke['outcomes'])
    content+=f'<h2>Readiness and continuation</h2><p>Two excluded smoke tasks: {smoke["succeeded_jobs"]}/12 generation jobs completed; {valid}/{evaluated} available smoke plans passed VAL. These are setup checks, not part of the benchmark score.</p>'
    if result.get('continuation'):
        content+='<p>The initial attempt stopped after one Fable safeguard refusal. Its exact retry succeeded. A second continuation corrected the treatment of request-specific refusals as account-wide failures, allowing unrelated work to proceed and at most one identical retry within the existing reserve. All previous successful outputs and charged calls were retained. Models, prompts, selected tasks, scoring rules, original deadline and 336-call ceiling stayed unchanged. <a href="archive/2026-09-13-planbench-readiness/planbench-results.json">Initial readiness outcome ↓</a></p>'
    if result.get('profile_amendment'):
        content+='<p>Before any scored task, high-effort Sonnet smoke testing hit a timeout and exhausted a small combined response budget. The documented readiness amendment uses medium effort for Sonnet and Terra, with an 8,192-token combined Claude reasoning/response allowance. Visible targets remain 4,096 tokens for plans and 1,024 for critiques. All six earlier calls remain charged and excluded. This is not a model-only comparison with the earlier high-effort Astra/Fable trial.</p>'
    receipt=result['timing']['controller_receipt']
    if 'all_controller_seconds' in result['timing']:
        content+=f'<p>All controller segments together ran for {result["timing"]["all_controller_seconds"]/60:.1f} minutes. The original execution window through final generation was {result["timing"]["execution_window_seconds"]/3600:.2f} hours, including setup and the pause between attempts; it stayed within the original three-hour limit.</p>'
    content+=f'<p>Latest controller: {esc(receipt["started"])} to {esc(receipt["finished"])}. Candidate generation froze before benchmark scoring.</p><article id="assessment"><h2>Evaluation of this test</h2>'
    for key,label in [('test_quality','Checks that passed'),('limitation','Limits of the evidence'),('decision','Conclusion'),('next_action','Next step')]:content+=f'<h3>{label}</h3><p>{esc(result["assessment"][key])}</p>'
    content+='</article><h2>Task-level outcomes</h2><details><summary>Show the fixed 50-task comparison</summary><div class="table-scroll" tabindex="0" role="region" aria-label="Individual task outcomes"><table><thead><tr><th>Task</th><th>A</th><th>B</th><th>C</th><th>D</th></tr></thead><tbody>'
    outcomes={(r['task'],r['arm']):r['outcome']['valid'] for r in result['per_task']}
    for task in result['benchmark']['selected_tasks']:
        content+=f'<tr><th scope="row">{esc(task)}</th>'+''.join('<td>'+('Pass' if outcomes[(task,a)] is True else 'Fail' if outcomes[(task,a)] is False else 'Missing')+'</td>' for a in ('A','B','C','D'))+'</tr>'
    content+=f'</tbody></table></div></details><h2>Benchmark and provenance</h2><p>The fixed seed selected 50 tasks from the official 110-task hard set. This is a subset workflow experiment, not a full leaderboard submission. Benchmark commit: <code>{esc(result["benchmark"]["commit"])}</code>. Source, input, parser, validator and candidate hashes are retained.</p><p><a href="https://github.com/karthikv792/LLMs-Planning">Official PlanBench repository ↗</a> · <a href="{esc(data_name)}" download>Download the full outcome ↓</a> · <a href="evaluations.html#{esc(assessment_id)}">All test assessments →</a></p>'
    if assessment_id!='planbench':content+='<p><a href="planbench.html">Earlier Astra/Fable results →</a></p>'
    return shell('Co-Evolution · PlanBench results and assessment',content)

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
    for e in entries:
        result=json.loads((PUBLIC/e['data']).read_text(encoding='utf-8'))
        if result.get('schema')=='planbench-results/1.0':
            (PUBLIC/e['page']).write_text(render_planbench(result,e['data'],e['id']),encoding='utf-8',newline='\n')
        elif result.get('schema')=='bbeh-results/1.0':
            spec=importlib.util.spec_from_file_location('bbeh_page',SITE/'bbeh-page.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
            (PUBLIC/e['page']).write_text(module.render(result,shell),encoding='utf-8',newline='\n')
    print('Rendered test assessments and PlanBench outcome.')

if __name__=='__main__':build()
