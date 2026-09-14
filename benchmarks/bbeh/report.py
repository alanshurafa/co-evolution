"""Report frozen BBEH gate/main outcomes; no provider calls."""
import argparse,hashlib,json,math,random,sqlite3,sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from statistics import mean,median
import runner

def cost(response,seat):
    if response.get('cost_usd') is not None:return response['cost_usd']
    u=response.get('usage') or {}
    if seat=='codex' and 'input_tokens' in u and 'output_tokens' in u:
        cache=u.get('cached_input_tokens',0)
        if 0<=cache<=u['input_tokens']:return ((u['input_tokens']-cache)*2+cache*.2+u['output_tokens']*12)/1e6
    return None

def summarize(rows,arms,n):
    out={}
    for arm in arms:
        values=[r for r in rows if r['arm']==arm];good=sum(r['correct'] is True for r in values);bad=sum(r['correct'] is False for r in values);missing=n-good-bad
        out[arm]=dict(workflow=runner.ROLES[arm],correct=good,incorrect=bad,missing=missing,evaluated=good+bad,planned=n,score=100*good/n if missing==0 else None,score_bounds=[100*good/n,100*(good+missing)/n])
    return out

def contrast(rows,other):
    by_id=defaultdict(dict)
    for r in rows:by_id[r['question']][r['arm']]=r
    strata=defaultdict(list)
    for arms in by_id.values():
        if 'D' in arms and other in arms and arms['D']['correct'] is not None and arms[other]['correct'] is not None:
            strata[arms['D']['family']].append(int(arms['D']['correct'])-int(arms[other]['correct']))
    values=[v for s in strata.values() for v in s]
    if not values:return dict(n=0,delta_pp=None,interval95=None,repairs=0,regressions=0,p_exact=None)
    rng=random.Random(20260914);draws=sorted(100*mean(v for s in strata.values() for v in rng.choices(s,k=len(s))) for _ in range(10000))
    wins=values.count(1);losses=values.count(-1);discordant=wins+losses
    p=min(1,2*sum(math.comb(discordant,k) for k in range(min(wins,losses)+1))/2**discordant) if discordant else 1
    return dict(n=len(values),delta_pp=100*mean(values),interval95=[draws[249],draws[9749]],repairs=wins,regressions=losses,p_exact=p)

def build(root):
    root=Path(root);m=runner.verify(root);status=runner.load(root/'status.json');assert status['controller']=='finished'
    c=runner.Campaign(root,runner.GRANT);jobs={j['id']:j for j in c.jobs(runner.STAGE)}
    assert not any(j['state'] in ('pending','running') for j in jobs.values())
    for phase in ('calibration','main'):
        freeze=runner.load(root/(phase+'-freeze.json'))
        for ident,sha in freeze['outputs'].items():assert runner.hash_text(json.loads(jobs[ident]['result'])['text'])==sha
    calibration=runner.load(root/'calibration-scores.json');gate=runner.load(root/'gate.json');main=runner.load(root/'main-scores.json') if gate['passed'] else []
    questions=runner.load(root/'questions.json');question_map={q['id']:q for q in questions}
    for row in calibration+main:row['input']=question_map[row['question']]['input'];row['input_sha256']=question_map[row['question']]['input_sha256']
    calls=[dict(x) for x in c.db.execute('SELECT * FROM calls WHERE grant_id=? ORDER BY id',(runner.GRANT,))];charges=[]
    for call in calls:
        saved=runner.load(root/'attempts'/f'{call["id"]:04d}.response.json');response=saved.get('response',{})
        if not response:
            for line in saved.get('raw','').splitlines():
                try:event=json.loads(line)
                except ValueError:continue
                if event.get('type')=='result':response={'usage':event.get('usage',{}),'cost_usd':event.get('total_cost_usd')}
                elif event.get('type')=='turn.completed':response={'usage':event.get('usage',{})}
        seconds=(datetime.fromisoformat(call['finished'])-datetime.fromisoformat(call['started'])).total_seconds() if call['finished'] else None
        charges.append(dict(id=call['id'],job=call['job'],seat=call['seat'],state=call['state'],seconds=response.get('seconds',seconds),usage=response.get('usage',{}),cost_usd=cost(response,call['seat'])))
    scores=summarize(main,runner.ROLES,24);cal_scores=summarize(calibration,('A','B','E'),12)
    comparisons={f'D-{arm}':contrast(main,arm) for arm in ('C','B','E','A')}
    family=[(k,v['p_exact']) for k,v in comparisons.items() if k!='D-A' and v['p_exact'] is not None];family.sort(key=lambda kv:kv[1]);previous=0
    for i,(key,p) in enumerate(family):previous=max(previous,min(1,(len(family)-i)*p));comparisons[key]['p_holm']=previous
    per_family={f:{'calibration':summarize([r for r in calibration if r['family']==f],('A','B','E'),4),'main':summarize([r for r in main if r['family']==f],runner.ROLES,8)} for f in runner.FAMILIES}
    costs_by_seat={s:[x['cost_usd'] for x in charges if x['seat']==s] for s in ('sonnet','codex')}
    cal_ids={q['id'] for q in questions if q['phase']=='calibration'}
    cal_costs={s:[x['cost_usd'] for x in charges if x['seat']==s and json.loads(jobs[x['job']]['definition'])['question'] in cal_ids] for s in costs_by_seat}
    forecast=1.3*(120*mean(cal_costs['sonnet'])+48*mean(cal_costs['codex'])) if all(v and all(x is not None for x in v) for v in cal_costs.values()) else None
    resources={}
    for arm in runner.ROLES:
        rows=[]
        for q in questions:
            if q['phase']!='main':continue
            required=set();todo=[q['id']+'.'+arm]
            while todo:
                ident=todo.pop()
                if ident not in required:required.add(ident);todo.extend(json.loads(jobs[ident]['definition'])['deps'])
            selected=[x for x in charges if x['job'] in required];complete=all(jobs[x]['state']=='succeeded' for x in required)
            rows.append(dict(question=q['id'],complete=complete,cost=sum(x['cost_usd'] for x in selected) if complete and all(x['cost_usd'] is not None for x in selected) else None,phase_seconds=sum(x['seconds'] for x in selected) if complete and all(x['seconds'] is not None for x in selected) else None))
        priced=[x['cost'] for x in rows if x['cost'] is not None];timed=[x['phase_seconds'] for x in rows if x['phase_seconds'] is not None]
        resources[arm]=dict(per_question=rows,priced=len(priced),mean_cost=mean(priced) if len(priced)==24 else None,median_model_phase_seconds=median(timed) if timed else None)
    if not gate['passed']:
        findings=', '.join(f'{runner.ROLES[a]} {v["correct"]}/{v["evaluated"]}' for a,v in cal_scores.items())
        reasons=[]
        if not gate['scoreable']:reasons.append('incomplete or format-incompatible responses')
        if any(v>9 for v in gate['correct'].values()):reasons.append('at least one cheap baseline above the 75% ceiling')
        if any(s['correct']+s['missing']<3 for s in cal_scores.values()):reasons.append('at least one baseline below the 25% floor even under favorable missing outcomes')
        if gate['estimated_main_seconds'] is None or gate['estimated_main_seconds']>gate['remaining_seconds']:reasons.append('insufficient projected runtime')
        assessment=dict(question='Does this compact BBEH mix leave enough headroom to test Co-Evolution against cheap baselines?',finding=f'Calibration: {findings}. The gate rejected the main comparison because of '+', '.join(reasons)+'.',
          test_quality='Twelve disjoint calibration questions and24 main questions were frozen before calls. Only inputs reached tool-free participant contexts. The official deterministic scorer and known-answer/format cases were checked. All calibration outputs froze before scoring.',
          limitation='This is a12-question suitability screen, not a full BBEH score or a Co-Evolution effectiveness test. No main critique workflows ran. Tiny category samples and a public static dataset limit generalization. Missing outputs are not wrong reasoning answers.',
          decision='Stop at the predeclared gate. These settings and this task bundle do not justify spending the conditional168 main calls. No collaboration benefit or harm has been established.',
          next_action='Preserve and publish the calibration outcome. Any harder or different bundle requires a separate plan and independent questions; do not silently change models, effort, families or questions in this run.')
    else:
        assessment=dict(question='Does Terra review improve Sonnet reasoning beyond self-review, plain revision and Terra alone?',finding='; '.join(f'{runner.ROLES[a]}: {s["correct"]}/{s["evaluated"]} correct' for a,s in scores.items())+'.',
          test_quality='The three cheap baselines passed a disjoint12-question difficulty screen. Main answers for24 frozen questions were generated before official deterministic scoring, with shared originals, isolated contexts and matched review instructions.',
          limitation='This is a24-question, three-family subset conditioned on a small suitability screen, not the full BBEH or BBEH Mini score. One generation per arm and public static questions limit inference. Paired uncertainty and multiplicity matter; reasoning accuracy is not a general intelligence or productivity score.',
          decision='Assess D-C as primary and D-B/D-E as the practical alternatives. Improvements over the original alone are insufficient. Report paired changes, corrected p-values and costs before deciding on replication.',
          next_action='If a large practical gain survives the controls, propose a fresh replication separately. Otherwise prefer the cheaper equally capable workflow; do not enlarge this experiment automatically.')
    source=(root/'upstream/bbeh/evaluate.py').read_text(encoding='utf-8')
    report=dict(schema='bbeh-results/1.0',title='BBEH compact reasoning screen',generated_at=runner.now(),completion='gate-rejected' if not gate['passed'] else 'complete' if all(s['missing']==0 for s in scores.values()) else 'partial',
      benchmark=dict(name='BIG-Bench Extra Hard Mini subset',commit=m['upstream_commit'],families=list(runner.FAMILIES),full_benchmark_score=False,official_scorer_canonical_sha256=runner.hash_text(source)),
      models=m['models'],effort='medium',gate=gate,calibration=dict(scores=cal_scores,outcomes=calibration),main=dict(scores=scores,outcomes=main,contrasts=comparisons,resources=resources),per_family=per_family,
      spend=dict(calls=c.count(),cap=220,families={f:c.count(family=f) for f in ('claude','codex')},family_caps=runner.CAPS,known_list_equivalent_usd=sum(x['cost_usd'] for x in charges if x['cost_usd'] is not None),unpriced_calls=[x['id'] for x in charges if x['cost_usd'] is None],forecast_main_list_equivalent_usd=forecast,attempts=charges,
       pricing_note='Claude CLI-reported list-equivalent costs; Terra estimate uses recorded rates of$2 input,$0.20 cached input,$12 output per million tokens. Not cash subscription charges.'),
      assessment=assessment,provenance=dict(manifest_sha256=runner.sha(root/'manifest.json'),questions_sha256=m['question_sha256'],reference_sha256=m['answers_sha256'],source_hashes=m['source_hashes'],reporter_sha256=runner.sha(__file__)),
      timing=dict(started_epoch=m['started_epoch'],deadline=m['deadline'],controller=runner.load(root/'controller.exit.json')))
    runner.write_once(root/'report.json',report);c.close()
    print(json.dumps({'completion':report['completion'],'gate':gate,'spend':{k:v for k,v in report['spend'].items() if k!='attempts'}},indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);a=p.parse_args();build(a.root)
