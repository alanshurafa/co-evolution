"""Stage a terminal, assessed report for website review; never pushes or calls models."""
import argparse,hashlib,importlib.util,json,shutil
from pathlib import Path
from statistics import mean,median
from datetime import datetime,timezone

def stage(root,site):
    root=Path(root);site=Path(site);public=site/'public'
    result=json.loads((root/'report.json').read_text(encoding='utf-8'))
    assert result['completion'] in ('complete','partial','readiness-failed')
    assert result['spend']['calls']<=336 and result['spend']['families']['codex']<=280 and result['spend']['families']['claude']<=56
    spec=importlib.util.spec_from_file_location('gate',site/'validate-publication.py');gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
    archive=public/'archive/2026-09-13-planbench-readiness';archive.mkdir(parents=True,exist_ok=True)
    manifest=json.loads((site/'archive-manifest.json').read_text(encoding='utf-8'))
    for name in ('planbench-results.json','test-evaluations.json'):
        dest=archive/name
        if not dest.exists():
            original=json.loads((public/name).read_text(encoding='utf-8'))
            if name=='planbench-results.json':assert original['completion']=='readiness-failed'
            shutil.copyfile(public/name,dest)
        key=dest.relative_to(public).as_posix();digest=hashlib.sha256(dest.read_bytes()).hexdigest()
        assert key not in manifest['files'] or manifest['files'][key]==digest
        manifest['files'][key]=digest
    (site/'archive-manifest.json').write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8',newline='\n')
    # Keep host diagnostics local, but publish exact extracted action sequences for reproducibility.
    for row in result['per_task']+result['smoke']['outcomes']:
        row['outcome'].pop('output',None)
        path=root/'evaluation'/f'{row["task"]}.{row["arm"]}'/'plan.pddl'
        row['extracted_plan']=path.read_bytes().decode('utf-8') if path.is_file() else None
    result['provenance']['source_report_sha256']=hashlib.sha256((root/'report.json').read_bytes()).hexdigest()
    result['provenance']['publication_analysis_source_sha256']=hashlib.sha256(Path(__file__).read_bytes()).hexdigest()
    receipts=[result['timing']['controller_receipt']]
    previous=root/'previous-evidence/controller.exit.json'
    if previous.is_file():receipts.append(json.loads(previous.read_text(encoding='utf-8-sig')))
    source_name=(result.get('continuation') or {}).get('source_run')
    if source_name and Path(source_name).name==source_name:
        initial=root.parent/source_name/'original-evidence/controller.exit.json'
        if initial.is_file():receipts.append(json.loads(initial.read_text(encoding='utf-8-sig')))
    result['timing']['all_controller_seconds']=sum((datetime.fromisoformat(x['finished'])-datetime.fromisoformat(x['started'])).total_seconds() for x in receipts)
    result['timing']['controller_segments']=receipts
    result['timing']['execution_window_seconds']=(datetime.fromisoformat(receipts[0]['finished'])-datetime.fromtimestamp(result['timing']['execution_started_epoch'],timezone.utc)).total_seconds()
    if result.get('resources'):
        common=set.intersection(*[{t['task'] for t in r['per_task'] if t['completed']} for r in result['resources'].values()])
        result['matched_complete_resources']={}
        if common:
            for arm,r in result['resources'].items():
                values=[t for t in r['per_task'] if t['task'] in common]
                result['matched_complete_resources'][arm]=dict(n=len(values),mean_cost_usd=mean(t['cost_usd'] for t in values) if all(t['cost_usd'] is not None for t in values) else None,
                  median_phase_seconds=median(t['phase_seconds'] for t in values) if all(t['phase_seconds'] is not None for t in values) else None)
    if all(result['scores'][a]['score']==100 for a in 'ABC') and result['scores']['D']['invalid']==0:
        d=result['scores']['D']
        result['assessment']['finding']=f'Original Astra, plain revision and self-review each produced 50/50 valid plans (100%). Fable review delivered {d["evaluated"]}/50 plans: {d["valid"]} valid, {d["invalid"]} invalid and {d["missing"]} missing. Cross-model review gained zero points on the jointly evaluated tasks. With the missing outcomes unresolved, its full-cohort score can only be {d["score_bounds"][0]}–{d["score_bounds"][1]}.'
        result['assessment']['decision']+=' For this benchmark, prefer the original Astra workflow: it already reached every goal. Additional review produced no measured validity gain and introduced delivery failures and extra compute.'
        result['assessment']['next_action']='Do not repeat the same matrix on this saturated subset. Keep the simpler workflow for tasks at this level. Any further study should use a separately specified benchmark with more headroom, preserve a fresh scored cohort, and measure application outcomes before claiming productivity benefits.'
    if result['contrasts']['D-C']['n'] and result['contrasts']['D-C']['repairs']==result['contrasts']['D-C']['regressions']==0:
        result['assessment']['limitation']+=' The [0,0] empirical bootstrap interval resamples only ties; it does not prove population-level equivalence. VAL validity also does not assess shortest-plan optimality.'
    result['publication_note']='Initial readiness snapshot is archived. This current export reflects the bounded continued stage; missing outcomes remain distinct from incorrect plans.'
    (public/'planbench-results.json').write_text(json.dumps(result,indent=2,ensure_ascii=False,allow_nan=False)+'\n',encoding='utf-8',newline='\n')
    registry=json.loads((public/'test-evaluations.json').read_text(encoding='utf-8'))
    e=next(x for x in registry['studies'] if x['id']=='planbench')
    e.update(title='PlanBench Hard: scored workflows and practical impact',status=result['completion'],coverage=f'{sum(s["evaluated"] for s in result["scores"].values())}/200 scored plans; smoke tasks excluded',data_sha256=gate.digest(public/'planbench-results.json'))
    for key in gate.FIELDS:e[key]=result['assessment'][key]
    if any(s['evaluated'] for s in result['scores'].values()):
        planning=next(x for x in registry['studies'] if x['id']=='planning')
        planning['next_action']='Read the separately reported PlanBench follow-up for objective symbolic-plan validity. Keep those scores separate from judge-rated writing quality; neither study alone measures human productivity.'
    registry['assessed_on']=result['generated_at'][:10]
    (public/'test-evaluations.json').write_text(json.dumps(registry,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
    print('Staged outcome and assessment; review then render and run the publication gate.')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--site',type=Path,required=True);a=p.parse_args();stage(a.root,a.site)
