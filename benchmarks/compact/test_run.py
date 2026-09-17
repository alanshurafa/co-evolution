import json,tempfile,time,unittest
from pathlib import Path
import run
class Contracts(unittest.TestCase):
    def test_fixed_scores_keep_missing_denominator(self):
        import report
        rows=[dict(arm='A',correct=i<4) for i in range(10)]
        score=report.summarize(rows,12,['A'])['A']
        self.assertEqual((score['correct'],score['incorrect'],score['missing']),(4,6,2))
        self.assertIsNone(score['score']);self.assertAlmostEqual(score['bounds'][0],100/3);self.assertEqual(score['bounds'][1],50)
    def test_paired_effect_excludes_missing_pairs(self):
        import report
        rows=[]
        for i in range(12):
            rows.extend([dict(question=str(i),arm='B',family='fixture',correct=i>=2),dict(question=str(i),arm='D',family='fixture',correct=None if i==11 else i!=2)])
        result=report.compare(rows,'B')
        self.assertEqual((result['n'],result['repairs'],result['regressions']),(11,2,1));self.assertAlmostEqual(result['delta_pp'],100/11)
        self.assertLess(result['interval95'][0],0);self.assertGreater(result['interval95'][1],0)
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
    def test_fixed_main_continues_after_individual_timeout(self):
        class Failed:
            def invoke(self,seat,*args):
                if seat=='sonnet':raise run.ProviderFailure('timeout','simulated timeout')
                return dict(requested_model=run.MODELS['codex'],tool_calls=0,text='print(5)',seconds=.01)
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);qs=[dict(id=str(i),input='visible',phase='main') for i in range(3)]
            run.write_once(root/'all-questions.json',qs)
            m=dict(kind='fixture',grant='fixture',mode='fixed-comparison',dispatch_cutoff=time.time()+60,retries={'claude':6,'codex':2})
            c=run.Campaign(root,'fixture');c.authorize(204,run.CAPS,'offline test');c.allocate('fixture',204,run.CAPS,'fixture',run.definitions(qs),m['dispatch_cutoff'])
            run.run_phase(root,c,m,'main',Failed())
            jobs={j['id']:j for j in c.jobs('fixture')}
            self.assertEqual(sum(jobs[str(i)+'.E']['state']=='succeeded' for i in range(3)),3)
            self.assertEqual(c.count(),6);c.close()
if __name__=='__main__':unittest.main()
