"""Publish both assessed fixed comparisons without replacing older screens."""
import argparse,hashlib,importlib.util,json
from pathlib import Path
SITE=Path(__file__).resolve().parent
def module(name,file):
    spec=importlib.util.spec_from_file_location(name,SITE/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def publish(root):
    root=Path(root);gate=module('gate','validate-publication.py');validator=module('compact','compact-page.py');public=SITE/'public';registry=json.loads((public/'test-evaluations.json').read_text(encoding='utf-8'));entries=[]
    for kind in ('bcb','lcb'):
        path=root/(kind+'-fixed-20260916')/'report.json';data=json.loads(path.read_text(encoding='utf-8'));assert data['mode']=='fixed-comparison'
        assert not data['phases']['calibration']['ran'] and not data['phases']['calibration']['outcomes']
        data['phases']['calibration']['scores']={}
        for score in data['phases']['main']['scores'].values():
            evaluated=score['correct']+score['incorrect'];score['evaluated']=evaluated
            score['completed_answer_accuracy']=100*score['correct']/evaluated if evaluated else None
            score['delivered_correct_percent']=100*score['correct']/score['n']
        validator.validate(data)
        data['provenance']['source_report_sha256']=hashlib.sha256(path.read_bytes()).hexdigest();name='fixed-'+kind
        c=data['contrasts']['D-B'];n=data['main_questions'];decision='No paired cross-review/plain-revision outcomes were available.'
        if c['delta_pp'] is not None:
            decision=f'Cross-model review versus plain revision: {c["delta_pp"]:+.1f} percentage points across {c["n"]}/{n} paired tasks, with {c["repairs"]} repairs and {c["regressions"]} regressions.'
            if c['interval95'] is not None:decision+=f' The paired 95% bootstrap interval is {c["interval95"][0]:.1f} to {c["interval95"][1]:.1f} points.'
            decision+=' Compare this with self-review and Terra alone before attributing benefit to model diversity. This small single-run subset does not establish general superiority or productivity gains.'
            b_cost=data['resources']['B']['mean_cost_usd'];d_cost=data['resources']['D']['mean_cost_usd']
            if b_cost and d_cost is not None:
                decision+=f' Standalone cross-review cost ${d_cost:.4f} per task versus ${b_cost:.4f} for plain revision ({100*(d_cost/b_cost-1):+.1f}%).'
            scores=data['phases']['main']['scores']
            if any(s['missing'] for s in scores.values()):
                decision+=f' Across the full planned cohort, cross-review delivered {scores["D"]["correct"]}/{n} correct answers and Terra alone delivered {scores["E"]["correct"]}/{n}. Paired comparisons exclude unavailable answers and therefore do not measure this delivery difference.'
            if all(s['missing']==0 for s in scores.values()) and scores['A']['correct']>scores['D']['correct'] and c['delta_pp']<=0:
                decision+=' Additional cross-model review is not justified by accuracy in this cohort: the original Sonnet answers scored higher, and cross-review did not beat plain revision.'
        data['assessment']['decision']=decision
        data['assessment']['test_quality']+=' All earlier selected tasks were excluded. Four setup calls were separate from the fixed cohort; no accuracy ceiling cancelled the main phase, and isolated task failures did not stop unrelated work.'
        data['assessment']['limitation']+=' Generation and review were tool-free. This does not measure an agent executing its own tests during implementation or saved human work time.'
        target=public/(name+'-results.json');target.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
        main=data['phases']['main']['outcomes'];entries.append(dict(id=name,data=target.name,page=name+'.html',title=data['title'],status=data['completion'],coverage=f'{sum(r["correct"] is not None for r in main)}/{n*5} main outputs scored on {n} fresh tasks',data_sha256=gate.digest(target),**data['assessment']))
    ids={e['id'] for e in entries};registry['studies']=entries+[e for e in registry['studies'] if e['id'] not in ids];registry['assessed_on']=max(json.loads((public/e['data']).read_text(encoding='utf-8'))['finished'][:10] for e in entries)
    (public/'test-evaluations.json').write_text(json.dumps(registry,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);publish(p.parse_args().root)
