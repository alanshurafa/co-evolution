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

def assess(summary,contrasts,resources,total):
    dc,db=contrasts['D-C'],contrasts['D-B']
    complete=total==200
    times={arm:resources[arm]['median_observed_workflow_seconds'] for arm in resources}
    ratio=times['D']/times['B'] if times['D'] is not None and times['B'] else None
    threshold=complete and dc['delta_pp']>=10 and db['delta_pp']>0 and ratio is not None and ratio<=2
    ceiling=summary['A']['score'] is not None and summary['A']['score']>=90
    floor=complete and all(s['score']<=10 for s in summary.values())
    upper_d=summary['D'].get('score_bounds',[0,100])[1]
    score_threshold_ruled_out=upper_d-summary['C'].get('score_bounds',[0,100])[0]<10 or upper_d-summary['B'].get('score_bounds',[0,100])[0]<=0
    if total==0:
        finding='No scored benchmark plan was evaluated. There is no new measurement of co-evolution effectiveness.'
        decision='Readiness failed; benchmark scores are unavailable, not zero.'
    else:
        counts=', '.join(f'{a}: {s["valid"]}/{s["evaluated"]} valid' for a,s in summary.items())
        change=lambda p:'unavailable' if p['delta_pp'] is None else f'{p["delta_pp"]:+.2f}'
        finding=f'{counts}. Cross-model minus self-review: {change(dc)} percentage points across {dc["n"]} paired tasks; cross-model minus plain revision: {change(db)} points across {db["n"]} paired tasks.'
        if not complete:
            decision='Partial measurement: paired observed outcomes are descriptive, and missing tasks prevent a complete fixed-50 benchmark claim.'
            if score_threshold_ruled_out:decision+=' Even the most favorable missing outcomes cannot meet the predeclared score-improvement threshold.'
            else:decision+=' The practical-threshold decision remains unresolved.'
            if ceiling:decision+=' The completed original-draft arm is also ceiling-limited under the predeclared rule.'
        elif ceiling or floor:decision='The screen is '+('ceiling' if ceiling else 'floor')+'-limited under the predeclared rule. It cannot reliably distinguish small workflow benefits; do not expand the same matrix automatically.'
        elif threshold:decision='The predeclared operational threshold is met: at least five net extra solves over self-review, a gain over plain revision, and at most twice plain-revision observed workflow time. Treat this as benchmark-specific evidence, with the reported paired interval and exact test limiting statistical claims.'
        else:decision='The predeclared practical threshold is not met. This screen does not justify the additional cross-model step as a default over the simpler workflow.'
    return dict(question='Does Fable critique improve Astra valid-plan rate beyond self-review and plain revision?',finding=finding,
      test_quality='The official 110-task corpus, fixed 50-task manifest, upstream PDDL extractor and VAL were pinned. Offline valid/invalid/malformed fixtures and duplicate-free resume passed. Candidates were frozen before scoring. All arms share the same original per task; no validator feedback reached participants.',
      limitation='This is a continued, one-generation-per-arm 50-task subset, not the complete leaderboard. Two documented continuations preserved earlier successes and charged attempts; known request-specific refusals could receive one identical retry within the original reserve. Observed workflow latency includes queueing and recovery suspension, so it does not isolate intrinsic review latency. Static public tasks may have training exposure. Symbolic validity does not measure human rework or software delivery. Astra token caps are prompt targets, not an enforced CLI limit; provider effort labels do not establish equal compute.',
      decision=decision,
      next_action='Publish the fixed subset result and preserve the task-level repairs/regressions. If a practical gain is supported, replicate on fresh application-relevant tasks. If there is no gain or a ceiling/floor, favor the simpler workflow for this benchmark and do not automatically extend the matrix.',
      impact_quantified=total>0,practical_threshold_met=bool(threshold),score_threshold_ruled_out=bool(score_threshold_ruled_out),ceiling_limited=bool(ceiling),floor_limited=bool(floor),D_to_B_observed_time_ratio=ratio)

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
        charges.append(dict(id=call['id'],job=call['job'],seat=call['seat'],state=call['state'],started=call['started'],finished=call['finished'],seconds=saved.get('seconds',response.get('seconds')),usage=response.get('usage',{}),cost_usd=amount,cost_precision=precision))
    summary={}
    for arm,values in arrays.items():
        valid=values.count(True);invalid=values.count(False);missing=values.count(None)
        summary[arm]=dict(workflow=m['roles'][arm],valid=valid,invalid=invalid,missing=missing,evaluated=valid+invalid,planned=50,
          score=2*valid if not missing else None,score_bounds=[2*valid,2*(valid+missing)])
    total=sum(v['evaluated'] for v in summary.values())
    failures=[dict(job=j['id'],error=j['error']) for j in jobs.values() if j['state']=='failed']
    refusal=any('reasoning_extraction' in LOAD(root/'attempts'/f'{call["id"]:04d}.response.json').get('raw','') for call in calls if call['state']=='failed')
    contrasts={f'D-{arm}':paired(arrays['D'],arrays[arm]) for arm in ('C','B','A')}
    resources={}
    for arm in ('A','B','C','D'):
        per_task=[]
        for ident in m['tasks']:
            required=set();todo=[f'{ident}.{arm}']
            while todo:
                key=todo.pop()
                if key not in required:
                    required.add(key);todo.extend(json.loads(jobs[key]['definition'])['deps'])
            task_calls=[x for x in charges if x['job'] in required]
            completed=all(jobs[k]['state']=='succeeded' for k in required)
            priced=completed and all(x['cost_usd'] is not None for x in task_calls)
            first=min((datetime.fromisoformat(x['started']) for x in task_calls),default=None)
            final=max((datetime.fromisoformat(x['finished']) for x in task_calls if x['finished']),default=None)
            per_task.append(dict(task=ident,completed=completed,dispatches=len(task_calls),cost_usd=sum(x['cost_usd'] for x in task_calls) if priced else None,
              phase_seconds=sum(x['seconds'] for x in task_calls) if completed and all(x['seconds'] is not None for x in task_calls) else None,
              observed_workflow_seconds=(final-first).total_seconds() if completed and first and final else None))
        wall=[x['observed_workflow_seconds'] for x in per_task if x['observed_workflow_seconds'] is not None]
        phase=[x['phase_seconds'] for x in per_task if x['phase_seconds'] is not None]
        costs=[x['cost_usd'] for x in per_task if x['cost_usd'] is not None]
        resources[arm]=dict(per_task=per_task,priced_tasks=len(costs),mean_standalone_cost_usd=mean(costs) if len(costs)==50 else None,median_observed_workflow_seconds=median(wall) if wall else None,median_model_phase_seconds=median(phase) if phase else None)
    assessment=assess(summary,contrasts,resources,total);assessment['prior_provider_refusal']=refusal
    result=dict(schema='planbench-results/1.0',title='PlanBench Blocksworld Hard — fixed 50-task co-evolution subset',generated_at=now(),
      completion='readiness-failed' if total==0 else ('complete' if total==200 else 'partial'),benchmark=dict(name='PlanBench Blocksworld Hard',upstream=m['upstream_url'],commit=m['upstream_commit'],released_tasks=110,selected_tasks=m['tasks'],seed=m['seed'],evaluator='Bundled VAL 4 with upstream save_gpt3_response PDDL extractor',hashes=m['benchmark_hashes'],full_leaderboard_result=False),
      models=m['models'],effort=m['effort'],output_caps=m['output_caps'],scores=summary,per_task=rows,
      contrasts=contrasts,resources=resources,
      timing_note='Observed workflow time spans the first draft dispatch through the final arm response, including retry/queue delays in this shared concurrent run. Model phase time sums only recorded provider-call durations. Neither is human work time.',
      smoke=dict(excluded=True,tasks=m['smoke_tasks'],planned_jobs=12,succeeded_jobs=sum(j['state']=='succeeded' and json.loads(j['definition'])['smoke'] for j in jobs.values()),outcomes=smoke),
      spend=dict(calls=c.count(),cap=336,families={f:c.count(family=f) for f in ('codex','claude')},known_list_equivalent_usd=sum(x['cost_usd'] for x in charges if x['cost_usd'] is not None),unpriced_calls=[x['id'] for x in charges if x['cost_usd'] is None],
        pricing_note='Astra estimate uses frozen September 11 rates: input $10, cached $1, output $50 per million tokens. Fable uses CLI-reported list-equivalent cost. These are not cash subscription charges.',attempts=charges),
      timing=dict(execution_started_epoch=m['started_epoch'],deadline_epoch=m['deadline_epoch'],controller_receipt=json.loads((root/'controller.exit.json').read_text(encoding='utf-8-sig'))),
      continuation=LOAD(root/'CONTINUATION.json') if (root/'CONTINUATION.json').exists() else None,
      failures=failures,assessment=assessment,provenance=dict(manifest_sha256=sha(root/'manifest.json'),generation_freeze_sha256=sha(root/'generation-freeze.json'),source_hashes=m['source_hashes'],analysis_source_sha256=sha(__file__)))
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
