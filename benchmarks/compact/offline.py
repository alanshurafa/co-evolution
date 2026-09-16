"""Minimal checker fixtures, with no participant calls."""
import argparse,json
from pathlib import Path
from checker import invoke
from run import load,write_once,now
def main(root,kind):
    root=Path(root);target=root/kind;image=load(root/'gym/source.json')['image'];checks=[]
    if kind in ('lcb','bcb'):
        payload=dict(kind='lcb',tests=dict(inputs=['2 3\n'],outputs=['5\n'],fn_name=None))
        for code,expected in [('a,b=map(int,input().split());print(a+b)',True),('print(99)',False),('this is invalid python!',False)]:
            result=invoke({**payload,'code':code},image,root);assert result['correct']==expected,result;checks.append(result)
        if kind=='bcb':
            own=load(target/'source.json')['image'];p=dict(kind='bcb',test='import unittest\nclass TestCases(unittest.TestCase):\n def test_value(self): self.assertEqual(task_func(2),3)',entry_point='task_func')
            for code,expected in [('def task_func(x): return x+1',True),('def task_func(x): return 0',False)]:
                result=invoke({**p,'code':code},own,root);assert result['correct']==expected,result;checks.append(result)
    else:
        graph=dict(kind='gym',family='graph_color',entry={'metadata':{'puzzle':{'vertices':[0,1],'edges':[[0,1]],'color_options':[1,2]}}})
        for answer,expected in [('{"0":1,"1":2}',True),('{"0":1}',False),('{"0":1,"1":1}',False),('{"0":1,"1":3}',False)]:
            result=invoke({**graph,'answer':answer},image,root);assert result['correct']==expected,result;checks.append(result)
        count=dict(kind='gym',family='countdown',entry={'metadata':{'numbers':[1,2,3],'target':6}})
        for answer,expected in [('1+2+3',True),('3+3',False),('1**2+3',False),('6',False)]:
            result=invoke({**count,'answer':answer},image,root);assert result['correct']==expected,result;checks.append(result)
    write_once(target/'offline-check.json',{'passed':True,'at':now(),'fixtures':checks});print(json.dumps({'kind':kind,'fixtures':len(checks),'passed':True}))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',required=True);p.add_argument('--kind',required=True);a=p.parse_args();main(a.root,a.kind)
