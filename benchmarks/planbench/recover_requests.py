"""Restore eligible tasks after a misclassified per-request refusal; no live calls."""
import argparse,hashlib,json,shutil,sqlite3,time
from pathlib import Path
from support import sha,write_once,now
from run import GRANT,STAGE,prompt

def prepare(source,root):
    source=Path(source).resolve();root=Path(root).resolve();load=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
    assert not root.exists()
    status=load(source/'status.json');m=load(source/'manifest.json')
    assert status['controller']=='finished' and (source/'generation-freeze.json').is_file()
    assert time.time()<m['dispatch_cutoff'],'Original cutoff expired'
    before_db_sha=sha(source/'campaign.sqlite');root.mkdir(parents=True)
    shutil.copyfile(source/'campaign.sqlite',root/'campaign.sqlite');shutil.copyfile(source/'readiness.json',root/'readiness.json')
    shutil.copytree(source/'attempts',root/'attempts')
    shutil.copytree(source/'upstream',root/'upstream')
    (root/'runtime').mkdir()
    code=Path(__file__).resolve().parent
    old_code_hashes=dict(m['source_hashes'])
    for name,digest in old_code_hashes.items():
        assert sha(source/'runtime'/name)==digest
        shutil.copyfile(code/name,root/'runtime'/name)
    archive=root/'previous-evidence';archive.mkdir()
    for name in ('manifest.json','status.json','generation-freeze.json','controller.exit.json','CONTINUATION.json'):
        shutil.copyfile(source/name,archive/name)
    db=sqlite3.connect(root/'campaign.sqlite');db.row_factory=sqlite3.Row
    calls=[dict(x) for x in db.execute('SELECT * FROM calls ORDER BY id')]
    successes=[dict(x) for x in db.execute("SELECT * FROM jobs WHERE state='succeeded' ORDER BY id")]
    failures=list(db.execute("SELECT * FROM jobs WHERE state='failed'"));retry_jobs=[]
    jobs={j['id']:j for j in db.execute('SELECT * FROM jobs')}
    for j in failures:
        attempts=[x for x in calls if x['job']==j['id']]
        raw=load(root/'attempts'/f'{attempts[-1]["id"]:04d}.response.json').get('raw','')
        assert 'safeguards flagged this message' in raw and 'reasoning_extraction' in raw,'Unexpected failure category'
        if len(attempts)<2:
            text=prompt(root,json.loads(j['definition']),jobs)
            assert hashlib.sha256(text.encode()).hexdigest()==attempts[0]['prompt_sha']
            retry_jobs.append(j['id'])
    restored=[j['id'] for j in jobs.values() if j['state']=='blocked']+retry_jobs
    astra=sum(json.loads(jobs[k]['definition'])['seat']=='astra' for k in restored)
    fable=len(restored)-astra
    used={family:sum(x['family']==family for x in calls) for family in ('codex','claude')}
    assert used['codex']+astra<=m['family_caps']['codex'] and used['claude']+fable<=m['family_caps']['claude']
    amendment=dict(at=now(),authorization='Alan requested continuation of the full bounded test. Correct per-request error classification while preserving the existing protocol, account routes, limits and original evidence.',
      change='Classify the known reasoning_extraction provider content refusal as per-request, not account/model unavailability. Permit at most one identical retry within the existing family retry reserve. Do not stop unrelated tasks for this category; exhausted requests remain missing.',
      no_treatment_change='No prompt, model, effort, output cap, safety setting, selected task, validator or score-based selection changes. Only runner error classification/recovery changes.',
      source_run=source.name,source_db_sha256=before_db_sha,source_manifest_sha256=sha(source/'manifest.json'),prior_source_hashes=old_code_hashes,
      prior_calls=len(calls),preserved_successes=len(successes),retry_jobs=retry_jobs,restored_jobs=restored,minimum_remaining_calls={'astra':astra,'fable':fable},used=used,
      original_deadline=m['deadline_epoch'],dispatch_cutoff=m['dispatch_cutoff'],cap=336,family_caps=m['family_caps'],
      methodology='Scored generation from the previous segment froze but has not been graded. Continue all eligible missing jobs independently of scores. Disclose both continuations and retained failures in the final assessment.')
    write_once(root/'CONTINUATION.json',amendment)
    m['source_hashes']={name:sha(root/'runtime'/name) for name in old_code_hashes}
    m['continuation']=dict(amendment_sha256=sha(root/'CONTINUATION.json'),prior_calls=len(calls),prior_manifest_sha256=sha(source/'manifest.json'))
    write_once(root/'manifest.json',m)
    with db:
        for ident in restored:db.execute("UPDATE jobs SET state='pending',error=NULL,not_before=0 WHERE stage=? AND id=?",(STAGE,ident))
        db.execute('UPDATE stages SET manifest_sha=? WHERE id=? AND grant_id=?',(sha(root/'manifest.json'),STAGE,GRANT))
    assert calls==[dict(x) for x in db.execute('SELECT * FROM calls ORDER BY id')]
    assert successes==[dict(x) for x in db.execute("SELECT * FROM jobs WHERE state='succeeded' ORDER BY id")]
    assert sha(source/'campaign.sqlite')==before_db_sha
    db.close()
    (root/'STATUS.md').write_text('Continuation 2 prepared: request-specific refusal handling corrected. All prior calls/successes retained; same336-call ceiling and original deadline. Scored candidates have not been graded. Launch once.\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in amendment.items() if k not in ('prior_source_hashes','restored_jobs')},indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--root',type=Path,required=True);a=p.parse_args();prepare(a.source,a.root)
