import json,tempfile,time,unittest
from pathlib import Path
from unittest.mock import patch
import run
from prepare_feedback import split_tests
class FeedbackTests(unittest.TestCase):
    def test_counts_and_splits(self):
        qs=[dict(id=str(i),phase='smoke' if i<2 else 'main') for i in range(14)]
        ds=run.definitions(qs,True)
        self.assertEqual(sum(d['seat']!='local' for d in ds),100)
        self.assertEqual(sum(d['seat']=='local' for d in ds),24)
        source='import unittest\nclass TestCases(unittest.TestCase):\n def setUp(self): pass\n'+''.join(f' def test_{i}(self): self.assertTrue(True)\n' for i in range(6))
        vis,hid,vnames,hnames=split_tests(source,1)
        self.assertFalse(set(vnames)&set(hnames));self.assertEqual(len(vnames)+len(hnames),6);self.assertIn('setUp',vis);self.assertIn('setUp',hid)
    def test_visible_feedback_never_reads_holdout_keys(self):
        prompts=[]
        class Adapter:
            def invoke(self,seat,text,*args):
                prompts.append(text);return dict(text='```python\nprint(1)\n```',requested_model=run.MODELS[seat],reported_model=run.MODELS[seat],tool_calls=0,seconds=.01)
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp);qs=[dict(id='q',input='problem',phase='main',hidden='HOLDOUT_SENTINEL')]
            run.write_once(root/'all-questions.json',qs);run.write_once(root/'all-keys.json',{'q':'HOLDOUT_SENTINEL'});run.write_once(root/'visible-keys.json',{'q':{'kind':'lcb','visible':'VISIBLE_SENTINEL'}})
            m=dict(kind='lcb',grant='fixture',protocol='visible-test-feedback',mode='fixed-comparison',dispatch_cutoff=time.time()+60,retries={'claude':6,'codex':2},source={'image':'fixture'})
            c=run.Campaign(root,'fixture');c.authorize(204,run.CAPS,'fixture');c.allocate('lcb',204,run.CAPS,'fixture',run.definitions(qs,True),m['dispatch_cutoff'])
            def checker(payload,*args):
                self.assertEqual(payload['visible'],'VISIBLE_SENTINEL');self.assertNotIn('HOLDOUT_SENTINEL',json.dumps(payload));return {'correct':False,'message':'VISIBLE_DIAGNOSTIC'}
            with patch.object(run,'invoke',checker):run.run_phase(root,c,m,'main',Adapter())
            self.assertEqual(c.count(),8);self.assertEqual(len(prompts),8);self.assertFalse(any('HOLDOUT_SENTINEL' in p for p in prompts));self.assertEqual(sum('VISIBLE_DIAGNOSTIC' in p for p in prompts),6)
            self.assertTrue(all(j['state']=='succeeded' for j in c.jobs('lcb')));c.close()
if __name__=='__main__':unittest.main()
