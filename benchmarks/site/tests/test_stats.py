#!/usr/bin/env python3
"""Known-value checks for benchmarks/site/stats.py.

The reference figures are the ones the expansion plan quotes for the light
tier on random50: A vs B is 2 / 5 discordant with exact McNemar p = 0.45, and
the Wilson interval for 42/50 is 71-92.
"""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
import stats  # noqa: E402


class WilsonTest(unittest.TestCase):
    def test_42_of_50_is_71_to_92(self):
        low, high = stats.wilson(42, 50)
        self.assertEqual((round(low * 100), round(high * 100)), (71, 92))

    def test_39_of_50_is_65_to_87(self):
        low, high = stats.wilson(39, 50)
        self.assertEqual((round(low * 100), round(high * 100)), (65, 87))

    def test_33_of_50_is_52_to_78(self):
        low, high = stats.wilson(33, 50)
        self.assertEqual((round(low * 100), round(high * 100)), (52, 78))

    def test_edges(self):
        self.assertEqual(stats.wilson(0, 0), (0.0, 0.0))
        low, high = stats.wilson(50, 50)
        self.assertEqual(high, 1.0)
        self.assertGreater(low, 0.9)


class McNemarTest(unittest.TestCase):
    def test_a_vs_b_random50(self):
        # A-only 2, B-only 5 -> 2 * P(Bin(7, .5) <= 2) = 2 * 29/128 = 0.453
        self.assertAlmostEqual(stats.mcnemar_exact(2, 5), 0.453125, places=6)
        self.assertEqual(round(stats.mcnemar_exact(2, 5), 2), 0.45)

    def test_a_vs_e_random50(self):
        self.assertEqual(round(stats.mcnemar_exact(9, 3), 2), 0.15)

    def test_b_vs_e_random50(self):
        # 9 / 0 -> 2 * (1/512) = 0.0039
        self.assertEqual(round(stats.mcnemar_exact(9, 0), 3), 0.004)

    def test_no_discordance(self):
        self.assertEqual(stats.mcnemar_exact(0, 0), 1.0)


class DiscordanceTest(unittest.TestCase):
    def test_table_and_lists(self):
        a = {'t1': True, 't2': True, 't3': False, 't4': False, 't5': True}
        b = {'t1': True, 't2': False, 't3': True, 't4': False, 't5': True, 't6': True}
        table = stats.discordance(a, b)
        self.assertEqual((table['both'], table['only_a'], table['only_b'], table['neither']),
                         (2, 1, 1, 1))
        self.assertEqual(table['rescued_by_b'], ['t3'])
        self.assertEqual(table['broken_by_b'], ['t2'])
        self.assertEqual(table['excluded'], 1)
        self.assertEqual(table['n'], 5)


class RankTest(unittest.TestCase):
    def test_overlapping_intervals_share_rank(self):
        entries = [('A', 0.65, 0.87), ('B', 0.71, 0.92), ('E', 0.52, 0.78)]
        ranks = stats.rank_by_upper_bound(entries)
        # No lower bound clears any upper bound, so every arm is rank 1.
        self.assertEqual(ranks, {'A': 1, 'B': 1, 'E': 1})

    def test_separated_interval_ranks_below(self):
        entries = [('A', 0.80, 0.95), ('B', 0.10, 0.30), ('C', 0.40, 0.85)]
        ranks = stats.rank_by_upper_bound(entries)
        self.assertEqual(ranks, {'A': 1, 'B': 3, 'C': 1})


class BootstrapTest(unittest.TestCase):
    def cells(self, pattern, seeds=1):
        out = []
        for i, resolved in enumerate(pattern):
            for s in range(seeds):
                out.append({'task': 't%d' % i, 'repo': 'r%d' % (i % 3),
                            'seed': s + 1, 'resolved': resolved})
        return out

    def test_point_is_task_mean_and_interval_brackets_it(self):
        cells = self.cells([True] * 42 + [False] * 8)
        result = stats.hierarchical_bootstrap(cells, n_boot=400)
        self.assertAlmostEqual(result['point'], 0.84)
        self.assertLessEqual(result['low'], 0.84)
        self.assertGreaterEqual(result['high'], 0.84)
        self.assertEqual(result['levels'], ['repo', 'task', 'seed'])

    def test_reproducible_for_a_seed(self):
        cells = self.cells([True, False, True, True, False, True])
        one = stats.hierarchical_bootstrap(cells, n_boot=200, seed=7)
        two = stats.hierarchical_bootstrap(cells, n_boot=200, seed=7)
        self.assertEqual((one['low'], one['high']), (two['low'], two['high']))

    def test_paired_delta_point(self):
        a = self.cells([True, True, False, False, True])
        b = self.cells([True, False, True, True, True])
        result = stats.hierarchical_bootstrap(b, n_boot=200, deltas_against=a)
        self.assertAlmostEqual(result['point'], 0.2)

    def test_seed_summary(self):
        cells = self.cells([True, False], seeds=3)
        cells[1]['resolved'] = False  # t0 seeds: F,T,T -> unstable
        summary = stats.seed_summary(cells)
        self.assertEqual(summary['k'], 3)
        self.assertEqual(summary['pass_at_k'], 0.5)
        self.assertEqual(summary['pass_pow_k'], 0.0)
        self.assertEqual(summary['unstable_tasks'], ['t0'])


class PowerTest(unittest.TestCase):
    def test_plan_figures(self):
        # Six-point paired difference at 14% discordance: about 300 pairs.
        n = stats.power_paired(0.14, 0.06)
        self.assertTrue(250 <= n <= 350, n)
        n20 = stats.power_paired(0.20, 0.06)
        self.assertTrue(380 <= n20 <= 480, n20)


if __name__ == '__main__':
    unittest.main()
