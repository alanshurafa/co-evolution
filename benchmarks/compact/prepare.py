"""Freeze sources, participant inputs and private grading payloads before calls."""
import argparse,base64,hashlib,io,json,pickle,random,re,subprocess,zlib
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from checker import invoke,linux

def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def textsha(s):return hashlib.sha256(s.encode()).hexdigest()
def save(path,obj):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('x',encoding='utf-8') as f:json.dump(obj,f,indent=2)
def image_id(tag):return subprocess.check_output(['wsl','-d','Ubuntu','--','docker','image','inspect',tag,'--format','{{.Id}}'],text=True).strip()
class StringsOnly(pickle.Unpickler):
    def find_class(self,*args):raise ValueError('Unexpected object in test-case pickle')
def private_tests(value):
    try:return json.loads(value)
    except ValueError:return json.loads(StringsOnly(io.BytesIO(zlib.decompress(base64.b64decode(value)))).load())
def lcb(root):
    pool=[];excluded=[];errata=(root/'livecodebench-upstream/ERRATA.md').read_text();banned=set(re.findall(r'^\d+\. ([\w-]+) -',errata,re.M))
    # Fix date eligibility independently of model outcomes, before selecting tasks.
    for path in sorted(root.glob('lcb-test*.jsonl')):
        with path.open(encoding='utf-8') as file:
            for line in file:
                row=json.loads(line)
                if row['difficulty']!='hard' or not '2024-08-01'<=row['contest_date'][:10]<='2025-04-30':continue
                if row['question_id'] in banned:excluded.append(dict(id=row['question_id'],reason='official errata'));continue
                tests=json.loads(row['public_test_cases'])+private_tests(row['private_test_cases'])
                if not tests:excluded.append(dict(id=row['question_id'],reason='no tests'));continue
                pool.append((row,tests))
    pool.sort(key=lambda x:x[0]['question_id']);assert len(pool)>=32 and len({r['question_id'] for r,t in pool})==len(pool)
    random.Random(20260916).shuffle(pool);questions=[];keys={}
    for i,(row,tests) in enumerate(pool[:32]):
        ident='lcb-'+row['question_id'];prompt=row['question_content']
        if row.get('starter_code'):prompt+='\nPython starter code:\n'+row['starter_code']
        questions.append(dict(id=ident,phase='calibration' if i<8 else 'main',family=row['platform'],input=prompt,input_sha256=textsha(prompt)))
        keys[ident]=dict(kind='lcb',tests=dict(inputs=[t['input'] for t in tests],outputs=[t['output'] for t in tests],fn_name=json.loads(row['metadata']).get('func_name')))
    return questions,keys,dict(eligible=len(pool),excluded=excluded,revision='0fe84c3912ea0c4d4a78037083943e8f0c4dd505',dates=['2024-08-01','2025-04-30'],difficulty='hard',source_hashes={p.name:sha(p) for p in root.glob('lcb-test*.jsonl')})
def gym(root,image):
    rows=invoke({'kind':'generate-gym'},image,root);questions=[];keys={};graph,count=0,0
    for row in rows:
        entry=row['entry'];questions.append(dict(id=row['id'],family=row['family'],phase=row['phase'],input=entry['question'],input_sha256=textsha(entry['question'])))
        keys[row['id']]=dict(kind='gym',family=row['family'],entry=entry)
    return questions,keys,dict(generator_parameters={'graph_color':{'min_num_vertices':20,'max_num_vertices':25,'num_colors':3,'edge_probability':.15},'countdown':{'min_numbers':6,'max_numbers':6,'min_target':100,'max_target':999}},seeds={'calibration':20260918,'main':20260919})
def bcb(root,image):
    command=['wsl','-d','Ubuntu','--','docker','run','--rm','--network','none','--mount',f'type=bind,src={linux(root / "bcb-hard.parquet")},dst=/input.parquet,readonly','--entrypoint','python3',image,'-c','import json,pyarrow.parquet as pq; print(json.dumps(pq.read_table("/input.parquet").to_pylist()))']
    rows=json.loads(subprocess.check_output(command,text=True,encoding='utf-8',timeout=60));assert len(rows)==148
    def check(row):
        payload=dict(kind='bcb',test=row['test'],entry_point=row['entry_point'],code=row['complete_prompt']+'\n'+row['canonical_solution'])
        try:result=invoke(payload,image,root)
        except Exception as e:result={'correct':None,'error':str(e)}
        print(json.dumps({'reference':row['task_id'],'result':result['correct']}),flush=True)
        return row,result
    receipt=root/'bcb-reference-checks.json'
    if receipt.exists():
        records=json.loads(receipt.read_text());checked=[(r,records[r['task_id']]) for r in rows]
    else:
        with ThreadPoolExecutor(max_workers=4) as pool:checked=list(pool.map(check,rows))
        save(receipt,{r['task_id']:v for r,v in checked})
    pool=[r for r,v in checked if v['correct'] is True];pool.sort(key=lambda x:x['task_id']);assert len(pool)>=32
    eligible=[r['task_id'] for r in pool];random.Random(20260917).shuffle(pool);questions=[];keys={}
    for i,row in enumerate(pool[:32]):
        ident=row['task_id'].replace('/','-');prompt=row['complete_prompt']
        questions.append(dict(id=ident,family='library-programming',phase='calibration' if i<8 else 'main',input=prompt,input_sha256=textsha(prompt)))
        keys[ident]=dict(kind='bcb',test=row['test'],entry_point=row['entry_point'])
    return questions,keys,dict(revision='298d2cc7b96612e15e47313c3603ee124cee0c1f',version='v0.1.4',eligible=eligible,excluded=[dict(id=r['task_id'],verdict=v) for r,v in checked if v['correct'] is not True],reference_receipt_sha256=sha(receipt),dataset_sha256=sha(root/'bcb-hard.parquet'))
def main(root,kind):
    root=Path(root);target=root/kind
    image=image_id('bigcodebench/bigcodebench-evaluate:latest' if kind=='bcb' else 'coevolution-compact-eval:20260916')
    questions,keys,info=lcb(root) if kind=='lcb' else bcb(root,image) if kind=='bcb' else gym(root,image)
    save(target/'questions.json',questions);save(target/'keys.json',keys)
    upstream={'lcb':'livecodebench','bcb':'bigcodebench','gym':'reasoning-gym'}[kind]+'-upstream'
    info.update(image=image,commit=subprocess.check_output(['git','-C',str(root/upstream),'rev-parse','HEAD'],text=True).strip(),questions_sha256=sha(target/'questions.json'),keys_sha256=sha(target/'keys.json'),verifier_sha256=sha(root/'verifier.py'))
    save(target/'source.json',info);print(json.dumps({'benchmark':kind,'questions':len(questions),'image':image}))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--kind',choices=['lcb','bcb','gym'],required=True);a=p.parse_args();main(a.root,a.kind)
