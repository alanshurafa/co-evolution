"""Publish a reviewed assessment of the immutable calibration report; no model calls."""
import argparse, hashlib, importlib.util, json
from pathlib import Path

SITE=Path(__file__).resolve().parents[1]/'site'

def publish(root):
    source=Path(root)/'report.json'
    data=json.loads(source.read_text(encoding='utf-8'))
    assert data['completion']=='gate-rejected' and data['spend']['calls']==29
    assessment=dict(
        question='Does this compact BBEH subset provide usable headroom for a low-compute comparison of Co-Evolution with cheaper workflows?',
        finding='Terra completed 12/12 calibration answers and scored 3/12 (25%) under the official scorer. Sonnet completed five originals, with one correct; seven originals timed out at 120 seconds. Its five available plain revisions also had one correct, with seven dependent revisions blocked. The controller stopped after 29 calls; the conditional 168-call main comparison did not run.',
        test_quality='The 12 calibration and 24 disjoint main questions were frozen before generation. Participant prompts excluded answer keys. All 22 received answers could be extracted, and their unchanged text was graded with the pinned official deterministic scorer after generation froze. Publication replays that scorer and verifies input and response hashes. Missing answers remain unavailable, not incorrect.',
        limitation='This is a 12-question, three-family suitability screen, not a full BBEH score or a Co-Evolution effectiveness test. Sonnet full-set accuracy is unknown, with bounds of 8.3–66.7%. Eight officially incorrect responses (three A, three B, two E) match the normalized reference except for surrounding angle brackets. This diagnostic does not change the scores, but shows that formatting affects the apparent difficulty. Seven timed-out calls have no recorded price, so the cost total is incomplete.',
        decision='Reject this bundle under the configured limits and stop at the predeclared gate. The observed scores are below the earlier ceiling, but Sonnet timeouts and answer-format sensitivity prevent a clean reasoning comparison. No positive or negative Co-Evolution effect has been measured. The gate avoided launching 168 conditional main calls.',
        next_action='Publish this calibration and its assessment, then close the run. A separate plan should first address exact answer-format instructions and runtime suitability using fresh calibration questions. Web of Lies completed across all baselines here, but four questions and substantial formatting effects do not establish it as a suitably difficult replacement. Do not change settings or continue this run.')
    data['assessment']=assessment
    data['provenance']['source_report_sha256']=hashlib.sha256(source.read_bytes()).hexdigest()
    data['diagnostics']={'angle_bracket_only_mismatches':{'A':3,'B':3,'E':2},'changes_official_scores':False}
    public=SITE/'public'
    target=public/'bbeh-results.json'
    target.write_text(json.dumps(data,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')
    spec=importlib.util.spec_from_file_location('gate',SITE/'validate-publication.py')
    gate=importlib.util.module_from_spec(spec);spec.loader.exec_module(gate)
    registry=json.loads((public/'test-evaluations.json').read_text(encoding='utf-8'))
    entry=dict(id='bbeh-compact',data=target.name,page='bbeh.html',title='BBEH: harder questions, an unsuccessful suitability screen',status='gate-rejected',coverage='22/36 calibration answers received; main comparison not run',data_sha256=gate.digest(target),**assessment)
    registry['studies']=[entry]+[e for e in registry['studies'] if e['id']!=entry['id']]
    (public/'test-evaluations.json').write_text(json.dumps(registry,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--root',required=True);publish(parser.parse_args().root)
