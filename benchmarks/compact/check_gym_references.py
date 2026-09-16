"""Check generated witnesses before participant inference; never alter samples."""
import argparse,json
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from checker import invoke
from run import load,write_once
def main(root):
    root=Path(root);keys=load(root/'gym/keys.json');image=load(root/'gym/source.json')['image']
    def check(pair):
        ident,key=pair;entry=key['entry'];answer=json.dumps(entry['metadata']['possible_answer']) if key['family']=='graph_color' else entry['answer']
        return ident,invoke({**key,'answer':answer},image,root)
    with ThreadPoolExecutor(max_workers=4) as pool:results=dict(pool.map(check,keys.items()))
    write_once(root/'gym/reference-checks.json',results)
    assert all(r['correct'] is True for r in results.values()),'Generated witness failed; do not send these tasks to models'
    print(json.dumps({'reference_checks':len(results),'passed':True}))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);main(p.parse_args().root)
