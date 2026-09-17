"""Build auditable terminal reports from frozen outputs and grader receipts."""
import argparse,hashlib,json,math,random,sqlite3
from collections import defaultdict,Counter
from pathlib import Path
from statistics import mean

LABELS={'A':'Sonnet original','B':'Sonnet plain revision','C':'Sonnet self-review','D':'Terra critique + Sonnet revision','E':'Terra alone'}
NAMES={'lcb':'LiveCodeBench hard','bcb':'BigCodeBench-Hard','gym':'Reasoning Gym constraint tasks'}
load=lambda p:json.loads(Path(p).read_text(encoding='utf-8-sig'))
def digest(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def summarize(rows,n,arms):
    scores={}
    for a in arms:
        selected=[r for r in rows if r['arm']==a];good=sum(r['correct'] is True for r in selected);bad=sum(r['correct'] is False for r in selected);missing=n-good-bad
        scores[a]=dict(label=LABELS[a],correct=good,incorrect=bad,missing=missing,n=n,score=100*good/n if not missing else None,bounds=[100*good/n,100*(good+missing)/n])
    return scores
def compare(rows,other):
    by=defaultdict(dict)
    for r in rows:by[r['question']][r['arm']]=r
    strata=defaultdict(list)
    for arms in by.values():
        if arms.get('D',{}).get('correct') is not None and arms.get(other,{}).get('correct') is not None:strata[arms['D']['family']].append(int(arms['D']['correct'])-int(arms[other]['correct']))
    values=[v for s in strata.values() for v in s];n=len(values)
    if not n:return dict(n=0,delta_pp=None,interval95=None,repairs=0,regressions=0,p_exact=None)
    rng=random.Random(20260916);samples=sorted(100*mean(x for s in strata.values() for x in rng.choices(s,k=len(s))) for _ in range(10000));wins=values.count(1);losses=values.count(-1);dis=wins+losses
    p=min(1,2*sum(math.comb(dis,i) for i in range(min(wins,losses)+1))/2**dis) if dis else 1
    return dict(n=n,delta_pp=100*mean(values),interval95=[samples[249],samples[9749]],repairs=wins,regressions=losses,p_exact=p)
def build(root):
    root=Path(root);m=load(root/'manifest.json');terminal=load(root/'outcome.json');assert load(root/'status.json')['phase']=='finished'
    main_n=m.get('main_questions',24);fixed=m.get('mode')=='fixed-comparison'
    for name,expected in m['source_hashes'].items():assert digest(root/'runtime'/name)==expected
    assert digest(root/'all-questions.json')==m['questions_hash'] and digest(root/'all-keys.json')==m['keys_hash']
    phases={}
    for phase in ('smoke','calibration','main'):
        path=root/(phase+'-scores.json');rows=load(path) if path.exists() else []
        if rows:
            freeze=load(root/(phase+'-freeze.json'))
            for row in rows:
                if row['response'] is not None:assert hashlib.sha256(row['response'].encode()).hexdigest()==freeze['outputs'][row['question']+'.'+row['arm']]==row['response_sha256']
        phases[phase]=dict(ran=path.exists(),outcomes=rows,scores=summarize(rows,2 if phase=='smoke' else 8 if phase=='calibration' else main_n,('A','E') if phase=='smoke' else ('A','B','E') if phase=='calibration' else LABELS))
        if fixed and phase=='main':
            for score in phases[phase]['scores'].values():score['delivered_correct_percent']=100*score['correct']/main_n
    c=sqlite3.connect(root/'campaign.sqlite');c.row_factory=sqlite3.Row;charges=[];jobs={j['id']:dict(j) for j in c.execute('SELECT * FROM jobs')}
    for call in c.execute('SELECT * FROM calls WHERE grant_id=? ORDER BY id',(m['grant'],)):
        saved=load(root/'attempts'/f'{call["id"]:04d}.response.json');r=saved.get('response',{});usage=r.get('usage',{});price=r.get('cost_usd');basis='CLI reported list-equivalent'
        if price is None and call['seat']=='codex' and 'input_tokens' in usage and 'output_tokens' in usage:
            cached=usage.get('cached_input_tokens',0);price=((usage['input_tokens']-cached)*2+cached*.2+usage['output_tokens']*12)/1e6;basis='historical rate estimate: input $2, cached $0.20, output $12 per million'
        charges.append(dict(id=call['id'],job=call['job'],seat=call['seat'],state=call['state'],usage=usage,seconds=r.get('seconds'),cost_usd=price,cost_basis=basis if price is not None else 'unavailable'))
    c.close();contrasts={f'D-{a}':compare(phases['main']['outcomes'],a) for a in ('B','C','E','A')};adjusted=sorted((v['p_exact'],k) for k,v in contrasts.items() if k!='D-A' and v['p_exact'] is not None);previous=0
    for i,(p,k) in enumerate(adjusted):previous=max(previous,min(1,p*(len(adjusted)-i)));contrasts[k]['p_holm']=previous
    resources={}
    for arm in LABELS:
        costs=[];seconds=[]
        for q in load(root/'all-questions.json'):
            if q['phase']!='main':continue
            pending=[q['id']+'.'+arm];required=set()
            while pending:
                ident=pending.pop()
                if ident in required:continue
                required.add(ident);pending.extend(json.loads(jobs[ident]['definition'])['deps'])
            if any(jobs[i]['state']!='succeeded' for i in required):continue
            calls=[r for r in charges if r['job'] in required]
            if all(r['cost_usd'] is not None for r in calls):costs.append(sum(r['cost_usd'] for r in calls))
            if all(r['seconds'] is not None for r in calls):seconds.append(sum(r['seconds'] for r in calls))
        resources[arm]=dict(priced_tasks=len(costs),mean_cost_usd=mean(costs) if len(costs)==main_n else None,mean_model_seconds=mean(seconds) if len(seconds)==main_n else None)
    cal=phases['calibration']['scores'];main=phases['main'];gate=load(root/'gate.json') if (root/'gate.json').exists() else None
    finding='Calibration: '+', '.join(f'{LABELS[a]} {s["correct"]} correct, {s["missing"]} missing of 8' for a,s in cal.items())+'.'
    if fixed:finding='Fixed comparison; no accuracy-based calibration gate.'
    if main['ran']:finding+=' Main: '+', '.join(f'{LABELS[a]} {s["correct"]} correct, {s["missing"]} missing of {main_n}' for a,s in main['scores'].items())+'.'
    else:finding+=' The main review comparison did not run, so no Co-Evolution gain or loss was measured.'
    if terminal['completion']=='readiness-failed':finding='Readiness failed before calibration. No benchmark comparison was run.'
    decision='Stop at the frozen gate. This configuration did not establish a usable difficulty and throughput window for the full comparison.'
    if main['ran']:
        primary=contrasts['D-B'];decision=f'Cross-model review changed accuracy by {primary["delta_pp"]} percentage points versus plain revision on {primary["n"]} completed pairs. Assess this alongside self-review, Terra alone, uncertainty and cost; a gain over the original alone is insufficient.'
    limitation='This is a selected 24-task main experiment following eight excluded calibration tasks, or a stopped readiness/calibration screen, not a full leaderboard submission. One generation per arm limits precision. Missing responses and evaluator errors remain unavailable. A bootstrap interval of zero width on all ties does not prove equivalence. Subscription list-equivalent estimates are not bills; unavailable token records prevent a complete cost total.'
    if fixed:limitation=f'This is a fixed {main_n}-task subset with one generation per arm, not a full leaderboard result. High accuracy is retained as an outcome. Missing responses and evaluator errors remain unavailable; delivered-correct/planned measures operational yield, not the latent accuracy of missing answers. Paired effects exclude missing pairs. A zero-width bootstrap interval on ties does not prove general equivalence. List-equivalent cost estimates are not subscription bills.'
    if m['kind']=='gym':limitation+=' Generated tasks are a custom public-framework subset. Countdown success additionally requires an exact rational expression using only allowed operators and each number once; this stricter check is disclosed separately from upstream reward.'
    if m['kind']=='bcb':limitation+=' Selection is conditional on the reference solution passing in the pinned local container; excluded tasks are disclosed in the eligibility manifest.'
    assessment=dict(question='Does Terra critique followed by Sonnet revision improve on plain revision, matched Sonnet self-review and Terra alone?',finding=finding,test_quality='Pinned benchmark sources, container images, prompts, settings and task splits were recorded before calls. Offline valid/invalid fixtures and controller failure tests passed. All stage responses froze before grading; no hidden tests or answer keys reached participants. Response hashes and task-level grader receipts are preserved.',limitation=limitation,decision=decision,next_action='Publish this outcome and its limitations. Do not rerun failed or wrong answers or change settings after seeing scores. Consider a separate replication only if the predeclared practical gain and overhead thresholds are met.')
    result=dict(schema='compact-results/1.0',benchmark=m['kind'],mode=m.get('mode','calibrated'),main_questions=main_n,title=NAMES[m['kind']]+(' fixed comparison' if fixed else ''),completion=terminal['completion'],models=m['models'],effort=m['effort'],timeout_seconds=m['timeout_seconds'],source=m['source'],phases=phases,gate=gate,contrasts=contrasts,resources=resources,assessment=assessment,spend=dict(calls=len(charges),cap=m.get('cap',204),by_provider=dict(Counter(r['seat'] for r in charges)),known_list_equivalent_usd=sum(r['cost_usd'] for r in charges if r['cost_usd'] is not None),unpriced_calls=[r['id'] for r in charges if r['cost_usd'] is None],attempts=charges),provenance=dict(manifest_sha256=digest(root/'manifest.json'),runtime_hashes=m['source_hashes'],receipt=load(root/'controller.exit.json')),finished=terminal['finished'])
    path=root/'report.json'
    with path.open('x',encoding='utf-8') as f:json.dump(result,f,indent=2)
    print(json.dumps({'benchmark':m['kind'],'completion':terminal['completion'],'calls':len(charges),'calibration':{a:s['score'] for a,s in cal.items()}}))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);build(p.parse_args().root)
