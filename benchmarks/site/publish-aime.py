"""Recover a completed calibration and attach an assessed publication snapshot."""
import argparse,importlib.util,json
from pathlib import Path
SITE=Path(__file__).resolve().parent
def module(name,file):
    spec=importlib.util.spec_from_file_location(name,SITE/file);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
aime=module('aime','aime-evidence.py');gate=module('publication','validate-publication.py')
def publish(root):
    root=Path(root);read=lambda name:json.loads((root/name).read_text(encoding='utf-8'))
    manifest=read('manifest.json');questions=read('questions.json');keys=read('answers.json');result=read('results.json')
    for name,value in [('questions',questions),('answers',keys)]:
        assert aime.sha(json.dumps(value,sort_keys=True))==manifest[name+'_sha256']
    source_text=(root/'source-rows.json').read_text(encoding='utf-8');assert aime.sha(source_text)==manifest['source_sha256']
    source={r['row_idx']:r['row'] for r in json.loads(source_text)['rows']}
    for q in questions:
        raw=source[q['source_row']];problem=raw['prompt'][0]['content'].split('\n\n',1)[1].removesuffix('\n\nRemember to put your final answer within \\boxed{}.')
        assert problem==q['problem'] and str(raw['label']).zfill(3)==keys[q['id']]
        q['reference']=keys[q['id']]
    assessment=dict(
      question='Does this six-question AIME 2024 screen leave enough headroom to compare Co-Evolution with plain revision and Terra alone?',
      finding='All 18 calibration answers completed in the expected format. Sonnet originals scored 5/6 (83.3%); plain Sonnet revision and Terra alone each scored 6/6 (100%). Plain revision repaired one answer with no regressions, gaining 16.7 percentage points. Cross-model review was not run, so its effect is unmeasured.',
      test_quality='Publication verified the saved source snapshot, selected question and reference hashes, all 18 response hashes, exact integer scores and the paired repair/regression count. The complete observed outputs satisfy the format and tool-free checks. The saved gate rejects either cheap baseline at 6/6, which occurred in both B and E.',
      limitation='Only six public, static questions were tested, selected by hash order. This is smaller than the earlier proposed 10-question calibration and has no frozen 20-question comparison. These results do not establish saturation of all AIME problems or general reasoning ability. Runtime source hashes and per-attempt usage/prices were not saved. The manifest says 180 seconds, but the retained script does not apply that timeout and imports a 600-second transport default; exact historical timeout enforcement cannot be verified. All completed calls were under 50 seconds.',
      decision='Close this completed six-question calibration at its rejection gate. Plain revision improved the original by one answer here, but there is no measured Co-Evolution gain or loss. Both cheaper alternatives reached the maximum observed score. Further review calls on this slice are not justified.',
      next_action='Publish the recovered result and stop this run. A further experiment needs a separately specified source and calibration that leave headroom, a durable controller with captured errors, explicit runtime settings, and complete cost receipts. Do not extend this scored subset or automatically cycle through benchmarks until one produces an improvement.')
    data=dict(schema='aime-publication/1.0',completion=result['completion'],gate=result['gate'],questions=questions,outcomes=result['outcomes'],
      scores={a:dict(correct=n,total=6,score=100*n/6) for a,n in result['gate']['correct'].items()},plain_revision=dict(n=6,repairs=1,regressions=0,delta_pp=100/6),
      assessment=assessment,manifest=manifest,finished_at=result['finished_at'],provenance={name:aime.sha((root/name).read_text(encoding='utf-8')) for name in ('manifest.json','questions.json','answers.json','results.json','source-rows.json')},
      spend=dict(calibration_calls=18,excluded_setup_calls=4,recorded_calls=22,cost_usd=None),
      setup=[json.loads((root.parent/name/'summary.json').read_text(encoding='utf-8')) for name in ('aime-transport-smoke-20260914','aime-transport-smoke-v2-20260914')])
    aime.validate(data);public=SITE/'public';target=public/'aime-calibration-results.json'
    target.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
    path=public/'test-evaluations.json';registry=json.loads(path.read_text(encoding='utf-8'))
    entry=dict(id='aime-calibration',data=target.name,page='aime-calibration.html',title='AIME 2024: plain revision reaches the ceiling',status='gate-rejected',coverage='18/18 calibration answers; six questions; no review arms',data_sha256=gate.digest(target),**assessment)
    registry['studies']=[entry]+[e for e in registry['studies'] if e['id']!=entry['id']]
    path.write_text(json.dumps(registry,indent=2,ensure_ascii=False)+'\n',encoding='utf-8',newline='\n')
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);publish(p.parse_args().root)
