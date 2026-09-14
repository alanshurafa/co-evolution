"""Amend an unstarted scored stage after readiness-only runtime failures."""
import argparse,json,shutil,sqlite3,time
from pathlib import Path
from support import sha,write_once,now
import run
from campaign import Campaign

def prepare(source,root):
    source=Path(source);root=Path(root);load=lambda p:json.loads(p.read_text(encoding='utf-8-sig'))
    old=load(source/'manifest.json');status=load(source/'status.json')
    assert status['controller']=='finished' and status['calls']==6 and status['candidate_plans']==0
    assert not root.exists() and time.time()<old['dispatch_cutoff']
    original_sha=sha(source/'campaign.sqlite');root.mkdir(parents=True)
    shutil.copyfile(source/'campaign.sqlite',root/'campaign.sqlite');shutil.copyfile(source/'readiness.json',root/'readiness.json')
    shutil.copytree(source/'attempts',root/'attempts')
    for name,digest in old['benchmark_hashes'].items():
        assert sha(source/'upstream'/name)==digest
        dest=root/'upstream'/name;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source/'upstream'/name,dest)
    (root/'runtime').mkdir()
    for file in Path(__file__).resolve().parent.glob('*.py'):shutil.copyfile(file,root/'runtime'/file.name)
    (root/'prior-readiness').mkdir()
    for name in ('manifest.json','status.json','generation-freeze.json','controller.exit.json'):
        shutil.copyfile(source/name,root/'prior-readiness'/name)
    db=sqlite3.connect(root/'campaign.sqlite');db.row_factory=sqlite3.Row
    calls=[dict(x) for x in db.execute('SELECT * FROM calls ORDER BY id')]
    jobs=[dict(x) for x in db.execute('SELECT * FROM jobs ORDER BY id')]
    assert len(calls)==6
    with db:
        db.execute('UPDATE stages SET cap=?,family_caps=? WHERE id=?',(6,json.dumps({'claude':5,'codex':1,'glm':0,'kimi':0}),old['stage']))
    assert calls==[dict(x) for x in db.execute('SELECT * FROM calls ORDER BY id')]
    assert jobs==[dict(x) for x in db.execute('SELECT * FROM jobs ORDER BY id')]
    db.close()
    amendment=dict(at=now(),reason='High-effort Sonnet smoke draft timed out and critique exhausted the small combined output allowance. No scored task began and no scores were used to select settings.',
      change='Both models use medium effort; Claude combined reasoning/response allowance8192, visible prompt targets unchanged4096/1024. Fresh smoke outputs are necessary because effort changed. Prior high-effort smoke is excluded and charged.',
      authorization='User requested the Sonnet/Terra test within the established bounded workflow; this is a readiness-only implementation adjustment, not a score-based change or a new budget.',
      prior_calls=6,original_db_sha256=original_sha,original_manifest_sha256=sha(source/'manifest.json'),source_run=source.name,
      old_allocation=6,new_allocation=330,new_family_allocation={'claude':275,'codex':55,'glm':0,'kimi':0},
      cap=336,family_caps=old['family_caps'],deadline=old['deadline_epoch'],comparability='Medium effort and combined response allowance differ from the earlier Astra/Fable high-effort experiment. Within the new trial, settings are fixed across all matching roles.')
    write_once(root/'PROFILE-AMENDMENT.json',amendment)
    m=dict(old);m.update(stage=old['stage']+'-medium',effort='medium',combined_output_limit=8192,retry_limits={'claude':15,'codex':3},stage_cap=330,
      profile_amendment_sha256=sha(root/'PROFILE-AMENDMENT.json'),source_hashes={p.name:sha(p) for p in (root/'runtime').glob('*.py')},
      output_caps={'sonnet':'8192-token combined reasoning/response allowance; visible targets4096 plans and1024 critiques.','codex':'4096/1024 visible instruction targets; Codex CLI cap not enforced.'})
    write_once(root/'manifest.json',m)
    run.configure(m);c=Campaign(root,m['grant'])
    c.allocate(m['stage'],330,amendment['new_family_allocation'],sha(root/'manifest.json'),run.definitions(m['smoke_tasks']+m['execution_order'],m['smoke_tasks']),m['dispatch_cutoff'])
    assert c.count()==6 and c.limits()[0]==336;c.close()
    assert sha(source/'campaign.sqlite')==original_sha
    (root/'STATUS.md').write_text('Medium-effort readiness amendment prepared. Six high-effort calls retained and charged; no study scores observed.336 total cap, unchanged deadline. Fresh smoke tests use medium and8192 combined response tokens. Launch once.\n',encoding='utf-8')
    print(json.dumps(amendment,indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--root',type=Path,required=True);a=p.parse_args();prepare(a.source,a.root)
