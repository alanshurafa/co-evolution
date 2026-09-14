"""Prepare a user-directed, evidence-preserving continuation; no provider calls."""
import argparse, hashlib, json, shutil, sqlite3, time
from pathlib import Path
from support import sha,write_once,now
from run import GRANT,STAGE,prompt

def prepare(source,root):
    source=Path(source).resolve();root=Path(root).resolve()
    assert not root.exists(),'Continuation already exists; do not prepare twice'
    load=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
    old=load(source/'manifest.json');status=load(source/'status.json')
    assert status['controller']=='finished' and status['calls']==11 and status['candidate_plans']==0
    assert time.time()<old['dispatch_cutoff'],'Original dispatch deadline expired'
    original_db_sha=sha(source/'campaign.sqlite')
    original_manifest_sha=sha(source/'manifest.json')
    root.mkdir(parents=True)
    for name in ('campaign.sqlite','readiness.json'):shutil.copyfile(source/name,root/name)
    shutil.copytree(source/'attempts',root/'attempts')
    for name,digest in old['benchmark_hashes'].items():
        src=source/'upstream'/name;assert sha(src)==digest
        dst=root/'upstream'/name;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(src,dst)
    (root/'runtime').mkdir()
    for name,digest in old['source_hashes'].items():
        assert sha(source/'runtime'/name)==digest
        shutil.copyfile(source/'runtime'/name,root/'runtime'/name)
    archive=root/'original-evidence';archive.mkdir()
    for name in ('manifest.json','status.json','generation-freeze.json','report.json','REPORT.md','controller.exit.json'):
        shutil.copyfile(source/name,archive/name)
    db=sqlite3.connect(root/'campaign.sqlite');db.row_factory=sqlite3.Row
    before=[dict(x) for x in db.execute('SELECT * FROM calls ORDER BY id')]
    success=[dict(x) for x in db.execute("SELECT * FROM jobs WHERE state='succeeded' ORDER BY id")]
    failures=list(db.execute("SELECT * FROM jobs WHERE state='failed'"))
    assert len(before)==11 and len(success)==10 and len(failures)==1
    failed=failures[0];assert failed['id']=='instance-97.cross-critique'
    assert failed['error']=='provider_stop:provider_error: CLI exit 1'
    jobs={j['id']:j for j in db.execute('SELECT * FROM jobs')}
    definition=json.loads(failed['definition']);frozen_prompt=prompt(root,definition,jobs)
    prompt_sha=hashlib.sha256(frozen_prompt.encode()).hexdigest()
    assert prompt_sha==before[7]['prompt_sha']
    assert frozen_prompt==load(source/'attempts/0008.request.json')['prompt']
    amendment=dict(at=now(),authorization='Alan said Continue after being told the specific Fable refusal blocked this goal. This directs one bounded continuation within the existing grant and deadline.',
      change='Permit one identical retry of the refused excluded smoke critique. Restore only its blocked dependencies and never-started scored jobs. If refusal repeats, stop again; no further retry of that job.',
      rationale='The inspected request asks for critique of a visible PDDL action sequence, not private reasoning. No wording, model, safety setting, transport, output cap or grading criterion changes.',
      original_db_sha256=original_db_sha,original_manifest_sha256=original_manifest_sha,original_run=source.name,
      charged_calls_preserved=11,successful_jobs_preserved=10,retry_job=failed['id'],retry_prompt_sha256=prompt_sha,
      total_cap=336,family_caps=old['family_caps'],deadline_epoch=old['deadline_epoch'],dispatch_cutoff=old['dispatch_cutoff'],
      methodological_note='Scored tasks have not begun. Seven excluded smoke plans were validated after the initial stop; those scores did not affect task selection, prompts or recovery selection. Report this as a continued stage, preserving the first attempt.')
    write_once(root/'CONTINUATION.json',amendment)
    m=dict(old);m['continuation']=dict(amendment_sha256=sha(root/'CONTINUATION.json'),original_manifest_sha256=original_manifest_sha,prior_calls=11)
    write_once(root/'manifest.json',m)
    with db:
        db.execute("UPDATE jobs SET state='pending',error=NULL,not_before=0 WHERE stage=? AND (id=? OR state='blocked')",(STAGE,failed['id']))
        db.execute('UPDATE stages SET manifest_sha=? WHERE id=? AND grant_id=?',(sha(root/'manifest.json'),STAGE,GRANT))
    assert before==[dict(x) for x in db.execute('SELECT * FROM calls ORDER BY id')]
    assert success==[dict(x) for x in db.execute("SELECT * FROM jobs WHERE state='succeeded' ORDER BY id")]
    assert len(list(db.execute("SELECT * FROM jobs WHERE state='pending'")))==302
    assert db.execute('SELECT cap FROM grants WHERE id=?',(GRANT,)).fetchone()[0]==336
    assert sha(source/'campaign.sqlite')==original_db_sha and sha(source/'manifest.json')==original_manifest_sha
    db.close()
    (root/'STATUS.md').write_text('User-directed continuation prepared. Original evidence unchanged. 11 calls retained, 302 eligible jobs, one identical smoke retry permitted, unchanged grant/deadline. Launch once; do not re-prepare.\n',encoding='utf-8')
    print(json.dumps(amendment,indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--root',type=Path,required=True);a=p.parse_args();prepare(a.source,a.root)
