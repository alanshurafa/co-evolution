"""Build a source-bound website inventory and protocol-separated composites."""
import hashlib,importlib.util,json
from pathlib import Path
SITE=Path(__file__).resolve().parent;PUBLIC=SITE/'public';BASE='https://alanshurafa.github.io/co-evolution/'
def digest(path):return hashlib.sha256(json.dumps(json.loads(Path(path).read_text(encoding='utf-8')),sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode()).hexdigest()
def build():
    registry=json.loads((PUBLIC/'test-evaluations.json').read_text(encoding='utf-8'));studies=[e for e in registry['studies'] if e['id']!='comparison-sheet'];websites=[]
    for e in studies:
        record=json.loads((PUBLIC/e['data']).read_text(encoding='utf-8'));summary=e['finding']
        if record.get('schema')=='compact-results/1.0':
            block=record['phases']['main'] if record['phases']['main']['ran'] else record['phases']['calibration']
            summary='; '.join(f'{a}: {s["correct"]}/{s["n"]} planned, {s["missing"]} missing' for a,s in block['scores'].items())
        elif record.get('schema')=='bbeh-results/1.0':
            summary='; '.join(f'{a}: {s["correct"]}/{s["planned"]} planned, {s["missing"]} missing' for a,s in record['calibration']['scores'].items())
        elif record.get('schema')=='aime-publication/1.0':summary='; '.join(f'{a}: {s["correct"]}/{s["total"]}' for a,s in record['scores'].items())
        elif record.get('schema')=='planbench-results/1.0':summary='; '.join(f'{a}: {s["valid"]}/{s["evaluated"]} evaluated, {s["missing"]} missing' for a,s in record['scores'].items())
        elif e['id']=='planning':summary='Exploratory rubric gains; material disagreement between judges. No executed-task accuracy or productivity measurement.'
        elif e['id']=='coding':
            rows={r['id']:r for r in record['rows']};summary='Completed light cohort: '+', '.join(f'{a}: {rows[a+"@base50-light"]["resolved"]}/{rows[a+"@base50-light"]["submitted"]}' for a in 'ABE')+'. Other cohorts and tools differ.'
        metric='Held-out tests all pass (%)' if e['id'].startswith('feedback-') else 'Mean rubric points, by AI judge' if e['id']=='planning' else 'SWE-bench issues resolved (%)' if e['id']=='coding' else 'Symbolic plans reaching goal (%)' if record.get('schema')=='planbench-results/1.0' else 'Official answer-match accuracy (%)' if record.get('schema')=='bbeh-results/1.0' else 'Exact integer-answer accuracy (%)' if record.get('schema')=='aime-publication/1.0' else 'All constraints satisfied (%)' if record.get('benchmark')=='gym' else 'All benchmark tests pass (%)'
        group='feedback' if e['id'].startswith('feedback-') else 'fixed' if e['id'].startswith('fixed-') else 'excluded'
        websites.append(dict(id=e['id'],type='Our result page',title=e['title'],url=BASE+e['page'],metric=metric,coverage=e['coverage'],status=e['status'],composite_group=group,summary=summary,full_finding=e['finding'],source=BASE+e['data'],features='Scored evidence, coverage, limitations and test assessment'))
    refs=json.loads((SITE/'comparison-references.json').read_text(encoding='utf-8'))
    for e in refs['sites']:websites.append(dict(id=e['id'],type='External reference',title=e['title'],url=e['url'],metric=e['metric'],coverage=e['scope'],status='reference only',composite_group='excluded',summary=e['use'],source=e['source'],features=e['features']))
    for ident,title,path in [('archive-coding','Earlier coding-site edition','archive/2026-09-04-code-battery/index.html'),('archive-frontier','Archived frontier coding results','frontier.html'),('archive-poc','One-task proof of concept','poc.html')]:
        websites.append(dict(id=ident,type='Archive',title=title,url=BASE+path,metric='Historical evidence; not a new replication',coverage='See preserved source',status='archived',composite_group='excluded',summary='Retained for history; excluded to avoid duplicate counting.',source=BASE+path,features='Preserved historical publication'))
    groups=[];observations=[];source_hashes={}
    for name,prefix,arms in [('feedback','feedback','ABCDEF'),('fixed','fixed','ABCDE')]:
        data={k:json.loads((PUBLIC/f'{prefix}-{k}-results.json').read_text(encoding='utf-8')) for k in ('bcb','lcb')};eligible={}
        for k,d in data.items():
            source_hashes[f'{prefix}-{k}-results.json']=digest(PUBLIC/f'{prefix}-{k}-results.json')
            fatal=('auth_blocked','billing_blocked','rate_limited','isolation_failure','local_error','local_unavailable','model_unavailable')
            eligible[k]=d['phases']['main']['ran'] and not any(r.get('grader_error') or any(x in (r.get('error') or '') for x in fatal) for r in d['phases']['main']['outcomes']) and not any(r.get('error') for r in d.get('diagnostics',{}).values())
            for a in arms:
                s=d['phases']['main']['scores'][a];observations.append(dict(protocol=name,benchmark=k,arm=a,label=s['label'],correct=s['correct'],planned=s['n'],missing=s['missing'],eligible=eligible[k],url=BASE+f'{prefix}-{k}.html'))
        rows=[]
        for a in arms:
            s={k:data[k]['phases']['main']['scores'][a] for k in data};valid=all(eligible.values())
            rows.append(dict(arm=a,label=s['bcb']['label'],bcb=100*s['bcb']['correct']/s['bcb']['n'] if eligible['bcb'] else None,lcb=100*s['lcb']['correct']/s['lcb']['n'] if eligible['lcb'] else None,score=50*sum(v['correct']/v['n'] for v in s.values()) if valid else None,coverage=50*sum((v['n']-v['missing'])/v['n'] for v in s.values()) if valid else None,upper_bound=50*sum((v['correct']+v['missing'])/v['n'] for v in s.values()) if valid else None))
        baseline=next(r['score'] for r in rows if r['arm']=='B')
        for r in rows:r['delta_vs_B']=r['score']-baseline if r['score'] is not None and baseline is not None else None
        groups.append(dict(id=name,title='Visible-feedback protocol' if name=='feedback' else 'Earlier tool-free protocol',rows=rows,eligible=eligible))
    result=dict(schema='website-comparison/1.0',checked_on=refs['checked_on'],websites=websites,groups=groups,observations=observations,source_hashes=source_hashes,inventory_hashes={e['data']:digest(PUBLIC/e['data']) for e in studies},weights={'bcb':.5,'lcb':.5},formula='100 × mean(correct / planned) across BigCodeBench and LiveCodeBench within one protocol',limitations='Operational yield, not latent accuracy or an intelligence score. Show coverage and possible upper bounds. Protocols are separate; calibration screens, AI-judge rubric scores, archives and external leaderboards are excluded. Weights are an explicit reporting convention. Cost is not blended because historical accounting is incomplete.')
    target=PUBLIC/'website-comparison.json';target.write_text(json.dumps(result,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
    spec=importlib.util.spec_from_file_location('gate',SITE/'validate-publication.py');gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
    current=groups[0];d=next(r for r in current['rows'] if r['arm']=='D');b=next(r for r in current['rows'] if r['arm']=='B')
    assessment=dict(question='How do matched workflows compare across our benchmark pages, and which external sites provide useful context?',finding=f'The feedback-protocol operational composite is {d["score"]} for cross-model review and {b["score"]} for direct Sonnet feedback revision. The comparison covers {len(studies)} current result pages, {len(refs["sites"])} external references and three archives.',test_quality='Every composite input is tied to a published result snapshot. Scores are recomputed from correct/planned counts with equal benchmark weights, separately by protocol. Coverage and missing-outcome upper bounds are shown; external leaderboard numbers are not pooled.',limitation=result['limitations'],decision='Use this sheet to compare matching workflows and find the supporting evidence. Do not treat a composite across these small selected cohorts as a universal model ranking or a measure of website design.',next_action='Inspect the primary D-B, D-C and D-F paired effects within the feedback studies before choosing a workflow. Publish changed source data only with refreshed assessments and recomputed composites.')
    entry=dict(id='comparison-sheet',data=target.name,page='comparison.html',title='Website inventory and workflow composite scores',status='mixed',coverage=f'{len(websites)} websites; two separate protocol composites',data_sha256=gate.digest(target),**assessment)
    registry['studies']=[entry]+studies
    (PUBLIC/'test-evaluations.json').write_text(json.dumps(registry,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
    print(json.dumps({'websites':len(websites),'groups':{g['id']:{r['arm']:r['score'] for r in g['rows']} for g in groups}}))
if __name__=='__main__':build()
