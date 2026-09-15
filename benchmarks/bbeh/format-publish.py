"""Publish the reviewed terminal format/runtime screen without altering prior studies."""
import argparse, hashlib, importlib.util, json
from pathlib import Path

SITE=Path(__file__).resolve().parents[1]/'site'

def publish(root):
    root=Path(root);source=root/'report.json';data=json.loads(source.read_text(encoding='utf-8'))
    assert data['completion']=='gate-rejected' and data['diagnostics']['timeouts']==2
    data['provenance']['source_report_sha256']=hashlib.sha256(source.read_bytes()).hexdigest()
    public=SITE/'public';target=public/'bbeh-format-calibration-results.json'
    target.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    spec=importlib.util.spec_from_file_location('gate',SITE/'validate-publication.py');gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
    registry=json.loads((public/'test-evaluations.json').read_text(encoding='utf-8'))
    entry=dict(id='bbeh-format-calibration',data=target.name,page='bbeh-format-calibration.html',title='BBEH: exact-answer and runtime suitability screen',status='gate-rejected',coverage='22/36 calibration answers received; main comparison absent',data_sha256=gate.digest(target),**data['assessment'])
    registry['studies']=[entry]+[e for e in registry['studies'] if e['id']!=entry['id']]
    (public/'test-evaluations.json').write_text(json.dumps(registry,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);a=p.parse_args();publish(a.root)
