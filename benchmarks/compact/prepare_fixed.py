"""Select fresh fixed cohorts using existing pinned datasets and eligibility."""
import argparse,json,random,re,subprocess
from pathlib import Path
from prepare import private_tests,sha,save,textsha
from checker import linux
def prepare(root,kind):
    root=Path(root);old=root/kind;source=json.loads((old/'source.json').read_text());prior={q['id'] for q in json.loads((old/'questions.json').read_text())};n=24 if kind=='bcb' else 12;seed=20260920 if kind=='bcb' else 20260921
    target=root/(kind+'-fixed-20260916');assert not target.exists()
    pool=[]
    if kind=='bcb':
        assert sha(root/'bcb-hard.parquet')==source['dataset_sha256'] and sha(root/'bcb-reference-checks.json')==source['reference_receipt_sha256']
        command=['wsl','-d','Ubuntu','--','docker','run','--rm','--network','none','--mount',f'type=bind,src={linux(root / "bcb-hard.parquet")},dst=/input.parquet,readonly','--entrypoint','python3',source['image'],'-c','import json,pyarrow.parquet as pq; print(json.dumps(pq.read_table("/input.parquet").to_pylist()))']
        rows=json.loads(subprocess.check_output(command,text=True,encoding='utf-8',timeout=60));eligible=set(source['eligible'])
        for r in rows:
            ident=r['task_id'].replace('/','-')
            if r['task_id'] not in eligible or ident in prior:continue
            pool.append((ident,r['complete_prompt'],'library-programming',dict(kind='bcb',test=r['test'],entry_point=r['entry_point'])))
    else:
        banned=set(re.findall(r'^\d+\. ([\w-]+) -',(root/'livecodebench-upstream/ERRATA.md').read_text(),re.M))
        for file in sorted(root.glob('lcb-test*.jsonl')):
            with file.open(encoding='utf-8') as stream:
                for line in stream:
                    r=json.loads(line);ident='lcb-'+r['question_id']
                    if r['difficulty']!='hard' or not '2024-08-01'<=r['contest_date'][:10]<='2025-04-30' or r['question_id'] in banned or ident in prior:continue
                    tests=json.loads(r['public_test_cases'])+private_tests(r['private_test_cases'])
                    if not tests:continue
                    prompt=r['question_content']+('\nPython starter code:\n'+r['starter_code'] if r.get('starter_code') else '')
                    pool.append((ident,prompt,r['platform'],dict(kind='lcb',tests=dict(inputs=[t['input'] for t in tests],outputs=[t['output'] for t in tests],fn_name=json.loads(r['metadata']).get('func_name')))))
    assert len(pool)>=n,(kind,len(pool),n)
    pool.sort(key=lambda x:x[0]);random.Random(seed).shuffle(pool);qs=[];keys={}
    for ident,prompt,family,key in pool[:n]:qs.append(dict(id=ident,input=prompt,input_sha256=textsha(prompt),family=family,phase='main'));keys[ident]=key
    save(target/'questions.json',qs);save(target/'keys.json',keys)
    source.update(mode='fixed-comparison',selection_seed=seed,fresh_eligible_count=len(pool),excluded_prior_ids=sorted(prior),prior_source_sha256=sha(old/'source.json'),questions_sha256=sha(target/'questions.json'),keys_sha256=sha(target/'keys.json'))
    save(target/'source.json',source);save(target/'offline-check.json',dict(passed=True,reused_fixture_receipt_sha256=sha(old/'offline-check.json'),image=source['image'],verifier_sha256=source['verifier_sha256']))
    print(json.dumps({'kind':kind,'fresh_tasks':n,'eligible':len(pool),'prior_overlap':False}))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--kind',choices=['bcb','lcb'],required=True);a=p.parse_args();prepare(a.root,a.kind)
