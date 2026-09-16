"""Render and validate bounded multi-benchmark results."""
import hashlib,html

def validate(data):
    for phase,block in data['phases'].items():
        seen=set()
        for row in block['outcomes']:
            key=(row['question'],row['arm'])
            if key in seen:raise ValueError('Duplicate compact outcome')
            seen.add(key)
            if hashlib.sha256(row['input'].encode()).hexdigest()!=row['input_sha256']:raise ValueError('Compact input hash mismatch')
            if row['response'] is not None and hashlib.sha256(row['response'].encode()).hexdigest()!=row['response_sha256']:raise ValueError('Compact response hash mismatch')
            if row['correct'] is not None and (row.get('grade',{}).get('correct')!=row['correct'] or row['response'] is None):raise ValueError('Compact grader receipt mismatch')
        for arm,score in block['scores'].items():
            rows=[r for r in block['outcomes'] if r['arm']==arm];correct=sum(r['correct'] is True for r in rows);incorrect=sum(r['correct'] is False for r in rows);missing=score['n']-correct-incorrect
            expected=100*correct/score['n'] if missing==0 else None
            if (score['correct'],score['incorrect'],score['missing'],score['score'])!=(correct,incorrect,missing,expected):raise ValueError('Compact aggregate mismatch')
    if data['spend']['calls']!=len(data['spend']['attempts']) or data['spend']['calls']>204:raise ValueError('Compact call ledger mismatch')

def render(data,shell):
    e=html.escape
    content=f'<p class="eyebrow">BOUNDED SONNET / TERRA TEST · {e(data["completion"].upper())}</p><h1>{e(data["title"])}</h1><p>{e(data["assessment"]["finding"])}</p>'
    content+='<div class="notice">'+('The main review comparison ran. Compare cross-model review with plain revision, self-review and Terra alone.' if data['phases']['main']['ran'] else '<strong>The main comparison did not run.</strong> Co-Evolution’s effect is unmeasured for this test.')+'</div>'
    for phase,label in [('calibration','Calibration: eight excluded tasks'),('main','Main comparison: 24 fresh tasks'),('smoke','Excluded setup checks')]:
        block=data['phases'][phase];content+=f'<h2>{label}</h2>'
        if not block['ran']:content+='<p>Not run: the preceding gate did not authorize this phase.</p>';continue
        content+='<div class="table-scroll" tabindex="0" role="region" aria-label="'+label+'"><table><thead><tr><th>Workflow</th><th>Correct / planned</th><th>Missing</th><th>Score</th></tr></thead><tbody>'
        for arm,s in block['scores'].items():
            score=f'{s["score"]:.1f}%' if s['score'] is not None else f'Unavailable ({s["bounds"][0]:.1f}–{s["bounds"][1]:.1f}% bounds)'
            content+=f'<tr><th scope="row">{e(s["label"])}</th><td>{s["correct"]}/{s["n"]}</td><td>{s["missing"]}</td><td>{score}</td></tr>'
        content+='</tbody></table></div>'
    content+='<p>Scores use the full planned denominator only when every outcome is known. Missing responses or judge failures remain unavailable. Bounds show all missing outcomes failing or passing; they are not confidence intervals. Calibration required all 24 baseline answers and 2–6 correct per baseline, plus sufficient remaining runtime.</p>'
    if data['phases']['main']['ran']:
        content+='<h2>What cross-model review changed</h2><div class="table-scroll"><table><thead><tr><th>Comparison</th><th>Paired tasks</th><th>Change, points</th><th>Repairs</th><th>Regressions</th></tr></thead><tbody>'
        for name,c in data['contrasts'].items():
            delta='Unavailable' if c['delta_pp'] is None else f'{c["delta_pp"]:.1f}'
            content+=f'<tr><th>{e(name)}</th><td>{c["n"]}</td><td>{delta}</td><td>{c["repairs"]}</td><td>{c["regressions"]}</td></tr>'
        content+='</tbody></table></div><p>D−B compares cross-model review with plain revision; D−C with self-review; D−E with Terra alone; D−A with the original. Paired intervals, exact tests and corrected p-values are in the evidence download.</p>'
    spend=data['spend'];content+=f'<h2>Compute and method</h2><p>{spend["calls"]}/204 calls used, including setup and retries. Known list-equivalent estimate: ${spend["known_list_equivalent_usd"]:.4f}; {len(spend["unpriced_calls"])} calls unpriced. This is not a cash subscription bill. Terra estimates use historical token rates; usage records and pricing basis are retained in the download.</p><p>Models: {e(data["models"]["sonnet"])} and {e(data["models"]["codex"])}; medium effort, 300 seconds per call, maximum two active calls per provider. Responses froze before stage scoring. The planned review protocol supplies critics with the original problem and candidate, without hidden tests or answer keys.</p><article id="assessment"><h2>Evaluation of this test</h2>'
    for key,label in [('test_quality','Checks'),('limitation','Limits'),('decision','Conclusion'),('next_action','Next step')]:content+=f'<h3>{label}</h3><p>{e(data["assessment"][key])}</p>'
    upstream={'lcb':'https://github.com/LiveCodeBench/LiveCodeBench','bcb':'https://github.com/bigcode-project/bigcodebench','gym':'https://github.com/open-thought/reasoning-gym'}[data['benchmark']]
    name='compact-'+data['benchmark'];content+=f'</article><p>Pinned benchmark commit: <code>{e(data["source"]["commit"])}</code>. Questions and checkers are credited to the <a href="{upstream}">upstream benchmark project ↗</a>.</p><p><a href="{name}-results.json" download>Download outcomes and receipts ↓</a> · <a href="evaluations.html#{name}">All assessments →</a></p>'
    return shell('Co-Evolution · '+data['title'],content)
