"""Minimal BBEH contracts; no model calls."""
import unittest
import runner

class Contracts(unittest.TestCase):
    def test_counts_and_key_isolation(self):
        questions=[dict(id=str(i),input='problem',phase='calibration' if i<12 else 'main') for i in range(36)]
        defs=runner.definitions(questions)
        self.assertEqual(len(defs),204)
        self.assertEqual(sum(d['seat']=='sonnet' for d in defs),144)
        self.assertEqual(sum(d['seat']=='codex' for d in defs),60)
        question=dict(input='visible problem',reference='PRIVATE_ANSWER_KEY_SENTINEL')
        for step,deps in [('A',[]),('B',['q.A']),('C',['q.A','q.self-critique']),('D',['q.A','q.cross-critique']),('E',[]),('self-critique',['q.A']),('cross-critique',['q.A'])]:
            text=runner.build_prompt(question,dict(step=step,deps=deps),{'q.A':{'text':'candidate'},'q.self-critique':{'text':'critique'},'q.cross-critique':{'text':'critique'}})
            self.assertNotIn('PRIVATE_ANSWER_KEY_SENTINEL',text)

    def test_gate_checks_strongest_cheap_baseline(self):
        rows=[dict(arm=a,correct=i<6,scoreable=True) for a in ('A','B','E') for i in range(12)]
        self.assertTrue(runner.gate(rows,100,50)['passed'])
        for r in rows:
            if r['arm']=='E':r['correct']=True
        self.assertFalse(runner.gate(rows,100,50)['passed'])
        rows[0]['scoreable']=False
        self.assertFalse(runner.gate(rows,100,50)['passed'])

if __name__=='__main__':unittest.main()
