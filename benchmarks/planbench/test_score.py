"""Known-answer checks for paired repair/regression accounting."""
import unittest
from score import paired,assess

class PairedOutcomes(unittest.TestCase):
    def test_five_repairs_are_ten_points_not_five_percent(self):
        p=paired([True]*5+[False]*45,[False]*50)
        self.assertEqual((p['n'],p['delta_pp'],p['repairs'],p['regressions']),(50,10,5,0))
        self.assertEqual(p['mcnemar_exact_p'],0.0625)

    def test_missing_is_excluded_not_incorrect(self):
        p=paired([True,None,False],[False,False,True])
        self.assertEqual((p['n'],p['delta_pp'],p['repairs'],p['regressions']),(2,0,1,1))
        self.assertEqual(p['mcnemar_exact_p'],1)

    def test_incomplete_cannot_meet_practical_threshold(self):
        s={a:{'valid':0,'evaluated':0,'score':None} for a in 'ABCD'}
        c={k:paired([],[]) for k in ('D-C','D-B')}
        r={a:{'median_observed_workflow_seconds':None} for a in 'ABCD'}
        self.assertFalse(assess(s,c,r,0)['practical_threshold_met'])

    def test_missing_cannot_hide_gain_above_perfect_control(self):
        s={a:{'valid':50,'evaluated':50,'score':100,'score_bounds':[100,100]} for a in 'ABC'}
        s['D']={'valid':49,'evaluated':49,'score':None,'score_bounds':[98,100]}
        c={k:paired([True]*49,[True]*49) for k in ('D-C','D-B')}
        r={a:{'median_observed_workflow_seconds':30} for a in 'ABCD'}
        result=assess(s,c,r,199)
        self.assertTrue(result['score_threshold_ruled_out'])
        self.assertTrue(result['ceiling_limited'])
        self.assertFalse(result['practical_threshold_met'])

if __name__=='__main__':unittest.main()
