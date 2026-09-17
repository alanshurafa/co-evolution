"""Publish scored feedback experiments and reviewed assessments."""
import argparse,hashlib,importlib.util,json
from pathlib import Path
SITE=Path(__file__).resolve().parent
def module(name,file):
    spec=importlib.util.spec_from_file_location(name,SITE/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def publish(root):
    root=Path(root);public=SITE/'public';gate=module('gate','validate-publication.py');validator=module('page','compact-page.py');registry=json.loads((public/'test-evaluations.json').read_text(encoding='utf-8'));entries=[]
    for kind in ('bcb','lcb'):
        path=root/(kind+'-feedback-20260917')/'report.json';data=json.loads(path.read_text(encoding='utf-8'));assert data['protocol']=='visible-test-feedback'
        data['phases']['calibration']['scores']={};data['page_id']='feedback-'+kind;data['provenance']['source_report_sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
        for s in data['phases']['main']['scores'].values():
            s['evaluated']=s['correct']+s['incorrect'];s['completed_answer_accuracy']=100*s['correct']/s['evaluated'] if s['evaluated'] else None;s['delivered_correct_percent']=100*s['correct']/s['n']
        validator.validate(data);c=data['contrasts']['D-B'];f=data['contrasts']['D-F']
        data['assessment']['decision']=f'Cross-model critique versus direct Sonnet feedback revision: {c["delta_pp"]} percentage points on {c["n"]} paired tasks, with {c["repairs"]} repairs and {c["regressions"]} regressions. Versus Terra feedback revision: {f["delta_pp"]} points on {f["n"]} pairs. These are small, single-run comparisons; inspect missingness, uncertainty and resources before claiming superiority.'
        data['assessment']['limitation']+=' Comparing a feedback revision with its original does not isolate the value of feedback from the extra revision call. The direct, self-review and cross-review comparisons control the feedback provided.'
        target=public/(data['page_id']+'-results.json');target.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
        rows=data['phases']['main']['outcomes'];entries.append(dict(id=data['page_id'],data=target.name,page=data['page_id']+'.html',title=data['title'],status=data['completion'],coverage=f'{sum(r["correct"] is not None for r in rows)}/{6*data["main_questions"]} held-out outcomes scored on {data["main_questions"]} tasks',data_sha256=gate.digest(target),**data['assessment']))
    ids={e['id'] for e in entries};registry['studies']=entries+[e for e in registry['studies'] if e['id'] not in ids];registry['assessed_on']='2026-09-17'
    (public/'test-evaluations.json').write_text(json.dumps(registry,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);publish(p.parse_args().root)
