"""Create fresh visible/held-out test cohorts before inference."""
import argparse,ast,json,random,subprocess
from pathlib import Path
from prepare import private_tests,save,sha,textsha
from checker import invoke,linux

def split_tests(source,seed):
    tree=ast.parse(source);cls=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='TestCases')
    names=sorted(n.name for n in cls.body if isinstance(n,ast.FunctionDef) and n.name.startswith('test'))
    if len(names)<4:raise ValueError('fewer than four methods')
    random.Random(seed).shuffle(names);visible=set(names[:max(1,len(names)//3)]);hidden=set(names)-visible
    def filtered(selected):
        t=ast.parse(source);c=next(n for n in t.body if isinstance(n,ast.ClassDef) and n.name=='TestCases')
        c.body=[n for n in c.body if not (isinstance(n,ast.FunctionDef) and n.name.startswith('test') and n.name not in selected)]
        return ast.unparse(t)
    return filtered(visible),filtered(hidden),sorted(visible),sorted(hidden)

def prepare(root,kind):
    root=Path(root);source=json.loads((root/kind/'source.json').read_text(encoding='utf-8'));prior=set()
    for folder in (root/kind,root/(kind+'-fixed-20260916')):prior.update(q['id'] for q in json.loads((folder/'questions.json').read_text(encoding='utf-8')))
    target=root/(kind+'-feedback-20260917');assert not target.exists();n=12 if kind=='bcb' else 8;seed=20260922 if kind=='bcb' else 20260923
    pool=[];excluded=[];receipts={}
    if kind=='bcb':
        assert sha(root/'bcb-hard.parquet')==source['dataset_sha256']
        command=['wsl','-d','Ubuntu','--','docker','run','--rm','--network','none','--mount',f'type=bind,src={linux(root / "bcb-hard.parquet")},dst=/input.parquet,readonly','--entrypoint','python3',source['image'],'-c','import json,pyarrow.parquet as pq; print(json.dumps(pq.read_table("/input.parquet").to_pylist()))']
        rows=json.loads(subprocess.check_output(command,text=True,encoding='utf-8',timeout=60));eligible=set(source['eligible'])
        for row in rows:
            ident=row['task_id'].replace('/','-')
            if row['task_id'] not in eligible or ident in prior:continue
            try:vis,hid,vnames,hnames=split_tests(row['test'],seed+int(row['task_id'].split('/')[-1]))
            except (ValueError,StopIteration):excluded.append({'id':ident,'reason':'insufficient separable tests'});continue
            pool.append(dict(id=ident,input=row['complete_prompt'],family='library-programming',visible={'kind':'bcb','test':vis,'entry_point':row['entry_point']},hidden={'kind':'bcb','test':hid,'entry_point':row['entry_point']},split={'visible_methods':vnames,'heldout_methods':hnames},reference=row['complete_prompt']+'\n'+row['canonical_solution']))
    else:
        import re
        banned=set(re.findall(r'^\d+\. ([\w-]+) -',(root/'livecodebench-upstream/ERRATA.md').read_text(),re.M))
        for file in sorted(root.glob('lcb-test*.jsonl')):
            with file.open(encoding='utf-8') as stream:
                for line in stream:
                    r=json.loads(line);ident='lcb-'+r['question_id']
                    if ident in prior or r['difficulty']!='hard' or r['question_id'] in banned or not '2024-08-01'<=r['contest_date'][:10]<='2025-04-30':continue
                    visible=json.loads(r['public_test_cases']);hidden=private_tests(r['private_test_cases'])
                    if not visible or not hidden:continue
                    def payload(tests):return dict(kind='lcb',tests=dict(inputs=[t['input'] for t in tests],outputs=[t['output'] for t in tests],fn_name=json.loads(r['metadata']).get('func_name')))
                    pool.append(dict(id=ident,input=r['question_content']+('\nPython starter code:\n'+r['starter_code'] if r.get('starter_code') else ''),family=r['platform'],visible=payload(visible),hidden=payload(hidden),split={'visible_tests':len(visible),'heldout_tests':len(hidden)}))
    pool.sort(key=lambda x:x['id']);random.Random(seed).shuffle(pool);selected=[]
    for row in pool:
        if kind=='bcb':
            checks={part:invoke({**row[part],'code':row['reference']},source['image'],root) for part in ('visible','hidden')};receipts[row['id']]=checks
            if not all(c['correct'] is True for c in checks.values()):excluded.append({'id':row['id'],'reason':'split reference failed'});continue
        selected.append(row)
        if len(selected)==n:break
    assert len(selected)==n
    questions=[dict(id=r['id'],input=r['input'],input_sha256=textsha(r['input']),family=r['family'],phase='main') for r in selected]
    save(target/'questions.json',questions);save(target/'keys.json',{r['id']:r['hidden'] for r in selected});save(target/'visible-keys.json',{r['id']:r['visible'] for r in selected})
    save(target/'reference-checks.json',receipts)
    source.update(protocol='visible-test-feedback',primary_score='all held-out tests passed',selection_seed=seed,candidates=len(pool),excluded_prior_ids=sorted(prior),split_exclusions=excluded,test_splits={r['id']:r['split'] for r in selected},questions_sha256=sha(target/'questions.json'),keys_sha256=sha(target/'keys.json'),visible_keys_sha256=sha(target/'visible-keys.json'),reference_check_sha256=sha(target/'reference-checks.json'))
    save(target/'source.json',source);save(target/'offline-check.json',dict(passed=True,reused_checker_fixture_sha256=sha(root/kind/'offline-check.json'),reference_checks=len(receipts),split_disjoint=True))
    print(json.dumps({'kind':kind,'tasks':n,'candidates':len(pool),'excluded':len(excluded)}))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--kind',choices=['bcb','lcb'],required=True);a=p.parse_args();prepare(a.root,a.kind)
