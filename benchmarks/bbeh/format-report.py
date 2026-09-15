"""Report the terminal BBEH format/runtime screen without provider calls."""
import argparse, hashlib, json
from datetime import datetime
from pathlib import Path
import runner

def scores(rows):
    result={}
    for arm in ('A','B','E'):
        values=[r for r in rows if r['arm']==arm]; correct=sum(r['correct'] is True for r in values); incorrect=sum(r['correct'] is False for r in values); missing=12-correct-incorrect
        result[arm]=dict(workflow=runner.ROLES[arm],correct=correct,incorrect=incorrect,missing=missing,evaluated=correct+incorrect,planned=12,score=100*correct/12 if not missing else None,score_bounds=[100*correct/12,100*(correct+missing)/12])
    return result

def cost(response,seat):
    if response.get('cost_usd') is not None:return response['cost_usd']
    usage=response.get('usage') or {}
    if seat=='codex' and 'input_tokens' in usage and 'output_tokens' in usage:
        cached=usage.get('cached_input_tokens',0)
        return ((usage['input_tokens']-cached)*2+cached*.2+usage['output_tokens']*12)/1e6

def build(root):
    root=Path(root);manifest=runner.verify(root);status=runner.load(root/'status.json');assert status['controller']=='finished'
    calibration=runner.load(root/'calibration-scores.json');questions={q['id']:q for q in runner.load(root/'questions.json')}
    for row in calibration:row.update(input=questions[row['question']]['input'],input_sha256=questions[row['question']]['input_sha256'])
    campaign=runner.Campaign(root,runner.GRANT);jobs={j['id']:j for j in campaign.jobs(runner.STAGE)};charges=[]
    for call in campaign.db.execute('SELECT * FROM calls WHERE grant_id=? ORDER BY id',(runner.GRANT,)):
        path=root/'attempts'/f'{call["id"]:04d}.response.json';saved=runner.load(path) if path.exists() else {};response=saved.get('response',{})
        seconds=(datetime.fromisoformat(call['finished'])-datetime.fromisoformat(call['started'])).total_seconds() if call['finished'] else None
        charges.append(dict(id=call['id'],job=call['job'],seat=call['seat'],state=call['state'],seconds=response.get('seconds',seconds),usage=response.get('usage',{}),cost_usd=cost(response,call['seat'])))
    timeout_count=sum('timeout:' in (jobs[r['question']+'.'+r['arm']]['error'] or '') for r in calibration)
    campaign.close(); summary=scores(calibration)
    report=dict(schema='bbeh-results/1.0',title='BBEH format and runtime calibration',generated_at=runner.now(),completion='gate-rejected',
      benchmark=dict(name='BIG-Bench Extra Hard Mini subset',commit=manifest['upstream_commit'],families=list(runner.FAMILIES),full_benchmark_score=False,official_scorer_canonical_sha256=runner.hash_text((root/'upstream/bbeh/evaluate.py').read_text(encoding='utf-8'))),
      models=manifest['models'],effort='medium',gate=runner.load(root/'gate.json'),calibration=dict(scores=summary,outcomes=calibration),main=dict(scores={},outcomes=[],contrasts={},resources={}),
      spend=dict(calls=len(charges),cap=40,families={'claude':sum(x['seat']=='sonnet' for x in charges),'codex':sum(x['seat']=='codex' for x in charges)},family_caps=runner.CAPS,known_list_equivalent_usd=sum(x['cost_usd'] for x in charges if x['cost_usd'] is not None),unpriced_calls=[x['id'] for x in charges if x['cost_usd'] is None],attempts=charges,pricing_note='Claude CLI-reported list-equivalent costs; Terra estimate uses recorded rates. Not cash subscription charges.'),
      diagnostics=dict(format_only_mismatches=sum(r['format_only_mismatch'] for r in calibration),timeouts=timeout_count,lost_controller=True),
      assessment=dict(question='Does a stricter final-answer instruction and a 180-second call limit make this BBEH subset usable for a later Co-Evolution comparison?',finding=f'Two Sonnet originals timed out at 180 seconds, one in Multistep Arithmetic and one in Hyperbaton. The controller session ended with four active calls unresolved and they were reconciled as missing. Terra completed 12 answers; the full A/B/E calibration is incomplete, so no benchmark score or review comparison exists.',test_quality='Twelve questions not previously sent to either model were frozen before calls. The prompt required one exact final-answer line, and outputs were frozen before official deterministic scoring. The report verifies source, input and response hashes and replays the pinned official scorer. The interrupted controller and every charged call remain in the local ledger.',limitation='This is an incomplete throughput and format screen, not an accuracy measurement. The controller interruption creates four additional missing outputs. With no complete Sonnet baseline, its score bounds are wide and cannot be compared to Terra. Exact-answer formatting was improved, but this screen cannot separately measure its effect from different questions and runtime conditions.',decision='Reject this BBEH configuration for the planned Co-Evolution experiment. Restoring the established output allowance removed the immediate truncation defect, but two independent Sonnet timeouts at 180 seconds still prevent a complete matched baseline. Do not run the review arms or infer an intelligence or collaboration effect.',next_action='Close this BBEH line of testing. If measurement continues, choose a compact exact-numeric benchmark such as a pre-frozen AIME set, then run a small transport-only smoke before committing calibration questions. Keep runtime completion and exact-score-format checks as hard gates.'),
      provenance=dict(manifest_sha256=runner.sha(root/'manifest.json'),questions_sha256=manifest['question_sha256'],reference_sha256=manifest['answers_sha256'],source_hashes=manifest['source_hashes'],controller_receipt=runner.load(root/'controller.exit.json')))
    runner.write_once(root/'report.json',report)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);a=p.parse_args();build(a.root)
