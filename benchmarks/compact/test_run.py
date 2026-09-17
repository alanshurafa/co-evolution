import json,tempfile,time,unittest
from pathlib import Path
import run
class Contracts(unittest.TestCase):
    def test_counts_and_prompt_key_isolation(self):
        qs=[dict(id=str(i),input='visible',reference='HIDDEN',phase='smoke' if i<2 else 'calibration' if i<10 else 'main') for i in range(34)]
        ds=run.definitions(qs);self.assertEqual(len(ds),196)
        self.assertEqual(sum(d['seat']=='sonnet' for d in ds),138)
        for d in ds:
            result={dep:{'text':'candidate or critique'} for dep in d['deps']}
            self.assertNotIn('HIDDEN',run.prompt(qs[int(d['question'])],d,result,'lcb'))
    def test_gate_and_format(self):
        rows=[dict(arm=a,correct=i<4,format_ok=True) for a in 'ABE' for i in range(8)]
        self.assertTrue(run.gate(rows,100,50)['passed'])
        for row in rows:
            if row['arm']=='E':row['correct']=True
        self.assertFalse(run.gate(rows,100,50)['passed'])
        self.assertIsNone(run.extract('no code here!','lcb'))
        self.assertEqual(run.extract('```python\nprint(5)\n```','lcb'),'print(5)\n')
    def test_irreversible_failure_stops_new_dispatches(self):
        class Failed:
            def invoke(self,*args):raise run.ProviderFailure('timeout','simulated timeout')
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);qs=[dict(id=str(i),input='visible',phase='calibration') for i in range(8)]
            run.write_once(root/'all-questions.json',qs)
            m=dict(kind='fixture',grant='fixture',dispatch_cutoff=time.time()+60,retries={'claude':6,'codex':2})
            c=run.Campaign(root,'fixture');c.authorize(204,run.CAPS,'offline test');c.allocate('fixture',204,run.CAPS,'fixture',run.definitions(qs),m['dispatch_cutoff'])
            run.run_phase(root,c,m,'calibration',Failed())
            self.assertLessEqual(c.count(),4)
            self.assertFalse(any(j['state'] in ('pending','running') for j in c.jobs('fixture')));c.close()
if __name__=='__main__':unittest.main()
