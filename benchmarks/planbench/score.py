"""Settle frozen PlanBench attempts and evaluate the evidence, including readiness failure."""
import argparse, hashlib, json, math, random
from datetime import datetime
from pathlib import Path
from statistics import mean, median
from campaign import Campaign
from run import GRANT,STAGE,LOAD,LOAD_result,verify
from support import sha,write_once,now
from evaluator import evaluate

def paired(left,right):
    pairs=[(a,b) for a,b in zip(left,right) if a is not None and b is not None]
    if not pairs:return dict(n=0,delta_pp=None,interval95=None,repairs=0,regressions=0,mcnemar_exact_p=None)
    diffs=[int(a)-int(b) for a,b in pairs];win=diffs.count(1);loss=diffs.count(-1);n=win+loss
    rng=random.Random(20260913);samples=sorted(100*mean(rng.choices(diffs,k=len(diffs))) for _ in range(10000))
    return dict(n=len(pairs),delta_pp=100*mean(diffs),interval95=[samples[249],samples[9749]],repairs=win,regressions=loss,
      mcnemar_exact_p=min(1,2*sum(math.comb(n,k) for k in range(min(win,loss)+1))/2**n) if n else 1)

def cost(response,seat):
    if response.get('cost_usd') is not None:return response['cost_usd'],'CLI-reported-list-equivalent'
    usage=response.get('usage') or {}
    if seat=='astra' and all(k in usage for k in ('input_tokens','output_tokens')):
        cached=usage.get('cached_input_tokens',0)
        if not 0<=cached<=usage['input_tokens']:return None,'unpriced'
        return ((usage['input_tokens']-cached)*10+cached+usage['output_tokens']*50)/1e6,'historical-rate-estimate'
    return None,'unpriced'

def settle(root):
    root=Path(root);m=LOAD(root/'manifest.json');verify(root,m)
    freeze=LOAD(root/'generation-freeze.json');status=LOAD(root/'status.json')
    assert status['controller']=='finished'
    c=Campaign(root,GRANT);jobs={j['id']:j for j in c.jobs(STAGE)}
    assert not any(j['state'] in ('pending','running') for j in jobs.values())
    for ident,digest in freeze['outputs'].items():assert hashlib.sha256(LOAD_result(jobs[ident])['text'].encode()).hexdigest()==digest
    rows=[];smoke=[];arrays={arm:[] for arm in ('A','B','C','D')}
    for ident in m['tasks']+m['smoke_tasks']:
        for arm in ('A','B','C','D'):
            job=jobs[f'{ident}.{arm}'];response=LOAD_result(job) if job['state']=='succeeded' else None
            if response:
                problem=root/'upstream/llm_planning_analysis/instances/blocksworld_hard/generated'/(ident+'.pddl')
                outcome=evaluate(root/'upstream',problem,response['text'],root/'evaluation'/f'{ident}.{arm}')
            else:outcome=dict(valid=None,category='not_generated',reason=job['error'])
            row=dict(task=ident,arm=arm,job_state=job['state'],outcome=outcome)
            if ident in m['smoke_tasks']:smoke.append(row)
            else:rows.append(row);arrays[arm].append(outcome['valid'])
    calls=[dict(x) for x in c.db.execute('SELECT * FROM calls WHERE grant_id=? ORDER BY id',(GRANT,))]
    charges=[]
    for call in calls:
        saved=LOAD(root/'attempts'/f'{call["id"]:04d}.response.json')
        response=saved.get('response',{})
        if not response:
            for line in saved.get('raw','').splitlines():
                try:event=json.loads(line)
                except ValueError:continue
                if event.get('type')=='result':response={'usage':event.get('usage',{}),'cost_usd':event.get('total_cost_usd')}
                elif event.get('type')=='turn.completed':response={'usage':event.get('usage',{})}
        amount,precision=cost(response,call['seat'])
        charges.append(dict(id=call['id'],job=call['job'],seat=call['seat'],state=call['state'],seconds=saved.get('seconds',response.get('seconds')),usage=response.get('usage',{}),cost_usd=amount,cost_precision=precision))
    summary={}
    for arm,values in arrays.items():
        valid=values.count(True);invalid=values.count(False);missing=values.count(None)
        summary[arm]=dict(workflow=m['roles'][arm],valid=valid,invalid=invalid,missing=missing,evaluated=valid+invalid,planned=50,
          score=2*valid if not missing else None,score_bounds=[2*valid,2*(valid+missing)])
    total=sum(v['evaluated'] for v in summary.values())
    failures=[dict(job=j['id'],error=j['error']) for j in jobs.values() if j['state']=='failed']
    refusal=any('reasoning_extraction' in LOAD(root/'attempts'/f'{call["id"]:04d}.response.json').get('raw','') for call in calls if call['state']=='failed')
    assessment=dict(question='Does Fable critique improve Astra valid-plan rate beyond self-review and plain revision?',
      finding='The scored benchmark did not start. There is no new measurement of co-evolution effectiveness.' if total==0 else 'See paired valid-plan outcomes; missing tasks limit inference.',
      test_quality='Official task corpus, deterministic upstream PDDL extraction and VAL were pinned. Valid, invalid and malformed fixtures passed. An offline lifecycle check charged a transient retry and confirmed duplicate-free resume.',
      limitation='One of two excluded smoke workflows failed at Fable critique; its revision was blocked. The readiness gate stopped all 50 scored tasks. Smoke outputs are excluded from benchmark accuracy. No benchmark score, confidence interval, or efficacy conclusion can be inferred from zero evaluated study tasks.' if total==0 else 'Fixed 50-task subset, one draw per arm and public static tasks limit generalization.',
      decision='Readiness failed; do not claim improvement, regression, or a 0% score. The attempt is complete, but the intended 50-task measurement is incomplete.' if total==0 else 'Compare D versus C and B with the predeclared practical threshold.',
      next_action='Resolve the provider safeguard refusal with the provider before a separately documented continuation. Preserve the 11 charged calls, fixed task set and deadline; do not rephrase requests to evade the safeguard, silently switch models, reset jobs, or expand this run.' if refusal else 'Review missingness and the fixed decision thresholds before further execution.',
      impact_quantified=False if total==0 else None,
      provider_refusal=refusal)
    result=dict(schema='planbench-results/1.0',title='PlanBench Blocksworld Hard — fixed 50-task co-evolution subset',generated_at=now(),
      completion='readiness-failed' if total==0 else ('complete' if total==200 else 'partial'),benchmark=dict(name='PlanBench Blocksworld Hard',upstream=m['upstream_url'],commit=m['upstream_commit'],released_tasks=110,selected_tasks=m['tasks'],seed=m['seed'],evaluator='Bundled VAL 4 with upstream save_gpt3_response PDDL extractor',hashes=m['benchmark_hashes'],full_leaderboard_result=False),
      models=m['models'],effort=m['effort'],output_caps=m['output_caps'],scores=summary,per_task=rows,
      contrasts={f'D-{arm}':paired(arrays['D'],arrays[arm]) for arm in ('C','B','A')},
      smoke=dict(excluded=True,tasks=m['smoke_tasks'],planned_jobs=12,succeeded_jobs=sum(j['state']=='succeeded' and json.loads(j['definition'])['smoke'] for j in jobs.values()),outcomes=smoke),
      spend=dict(calls=c.count(),cap=336,families={f:c.count(family=f) for f in ('codex','claude')},known_list_equivalent_usd=sum(x['cost_usd'] for x in charges if x['cost_usd'] is not None),unpriced_calls=[x['id'] for x in charges if x['cost_usd'] is None],
        pricing_note='Astra estimate uses frozen September 11 rates: input $10, cached $1, output $50 per million tokens. Fable uses CLI-reported list-equivalent cost. These are not cash subscription charges.',attempts=charges),
      timing=dict(execution_started_epoch=m['started_epoch'],deadline_epoch=m['deadline_epoch'],controller_receipt=json.loads((root/'controller.exit.json').read_text(encoding='utf-8-sig'))),
      failures=failures,assessment=assessment,provenance=dict(manifest_sha256=sha(root/'manifest.json'),generation_freeze_sha256=sha(root/'generation-freeze.json'),source_hashes=m['source_hashes']))
    write_once(root/'report.json',result)
    lines=['# PlanBench execution assessment','',result['title'],'',assessment['finding'],'',
      '| Arm | Evaluated | Valid | Invalid | Missing | Benchmark score |','|---|---:|---:|---:|---:|---|']
    for arm,s in summary.items():lines.append(f'| {arm} | {s["evaluated"]}/50 | {s["valid"]} | {s["invalid"]} | {s["missing"]} | '+('Unavailable' if s['score'] is None else str(s['score']))+' |')
    for key in ('test_quality','limitation','decision','next_action'):lines+=['',assessment[key]]
    lines+=['',f'Calls: {c.count()}/336. Known list-equivalent cost: ${result["spend"]["known_list_equivalent_usd"]:.6f}.',result['spend']['pricing_note']]
    (root/'REPORT.md').write_text('\n'.join(lines)+'\n',encoding='utf-8');c.close()
    print(json.dumps({'completion':result['completion'],'evaluated':total,'spend':{k:v for k,v in result['spend'].items() if k!='attempts'},'smoke_valid':sum(x['outcome']['valid'] is True for x in smoke),'smoke_evaluated':sum(x['outcome']['valid'] is not None for x in smoke)},indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);a=p.parse_args();settle(a.root)
