"""Publish only terminal, assessed campaign reports; no provider calls."""
import argparse,hashlib,importlib.util,json
from pathlib import Path
SITE=Path(__file__).resolve().parent
def module(name,file):
    spec=importlib.util.spec_from_file_location(name,SITE/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def publish(root):
    root=Path(root);gate=module('gate','validate-publication.py');validator=module('compact','compact-page.py');public=SITE/'public';registry=json.loads((public/'test-evaluations.json').read_text(encoding='utf-8'))
    entries=[]
    for kind in ('lcb','bcb','gym'):
        path=root/kind/'report.json'
        if not path.exists():raise ValueError('Missing terminal report: '+kind)
        data=json.loads(path.read_text(encoding='utf-8'));validator.validate(data);data['provenance']['source_report_sha256']=hashlib.sha256(path.read_bytes()).hexdigest();name='compact-'+kind
        decision=data.get('gate')
        if decision and not decision['passed']:
            data['assessment']['limitation']=data['assessment']['limitation'].replace('This is a selected 24-task main experiment following eight excluded calibration tasks, or a stopped readiness/calibration screen, not a full leaderboard submission.','This is an eight-task suitability screen with 24 unused reserved tasks, not a full leaderboard submission.')
            reasons=[]
            if not decision['complete']:reasons.append('the 24-answer calibration was incomplete or had unusable outcomes')
            high=[a for a,n in decision['correct'].items() if n>6]
            if high:reasons.append('baseline '+', '.join(high)+' exceeded the six-of-eight ceiling')
            if decision['complete'] and any(n<2 for n in decision['correct'].values()):reasons.append('a baseline was below the two-of-eight floor')
            if decision['estimated_main_seconds'] is None or decision['estimated_main_seconds']>decision['remaining_seconds']:reasons.append('the conservative main-run forecast did not fit the remaining window')
            errors=[r['error'] for r in data['phases']['calibration']['outcomes'] if r.get('error') and r['state']=='failed']
            if errors:data['assessment']['finding']+=f' {len(errors)} calibration dispatches failed; see the per-task error receipts. Undispatched dependent work remains missing.'
            data['assessment']['decision']='Stop at the predeclared gate because '+ '; '.join(reasons)+'. No Co-Evolution gain or loss has been measured on this benchmark.'
        target=public/(name+'-results.json');target.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
        cal=data['phases']['calibration']['outcomes'];main=data['phases']['main']['outcomes'];coverage=f'{sum(r["correct"] is not None for r in cal)}/24 calibration; {sum(r["correct"] is not None for r in main)}/120 main outputs scored'
        entries.append(dict(id=name,data=target.name,page=name+'.html',title=data['title'],status=data['completion'],coverage=coverage,data_sha256=gate.digest(target),**data['assessment']))
    ids={e['id'] for e in entries};registry['studies']=entries+[e for e in registry['studies'] if e['id'] not in ids]
    (public/'test-evaluations.json').write_text(json.dumps(registry,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);publish(p.parse_args().root)
