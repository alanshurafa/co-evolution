#!/usr/bin/env python3
"""Uncertainty for the results page: intervals, paired contrasts, ranking.

Pure Python on purpose. The site builder runs wherever the benchmark ran,
which may be a Windows host with no scientific stack, and every figure here
must be reproducible from the JSON alone.

Design, following the pre-registered analysis in the expansion plan:

  * A single arm's score gets a Wilson interval on resolved / n.
  * Two arms on the same tasks are compared paired: the discordant table,
    an exact two-sided McNemar test on the discordant counts, and the net
    tasks the second arm rescued or broke.
  * With seeds, the per-task score is the mean over seeds, and a
    hierarchical bootstrap resamples repositories, then tasks within a
    repository, then seeds within a task (Epoch's three-level scheme), so
    the interval reflects that tasks within one repository are not
    independent draws.
  * Rank(UB) ranks arms by interval overlap (the Scale / Arena rule): an
    arm's rank is one plus the number of arms whose lower bound sits above
    its upper bound, so no arm is #1 on the strength of one task.
"""
import math
import random

Z_95 = 1.959963984540054


def wilson(successes, n, z=Z_95):
    """Wilson score interval for a binomial proportion, as (low, high)."""
    if n <= 0:
        return (0.0, 0.0)
    p = successes / n
    z2 = z * z
    denom = 1.0 + z2 / n
    centre = (p + z2 / (2.0 * n)) / denom
    half = z * math.sqrt(p * (1.0 - p) / n + z2 / (4.0 * n * n)) / denom
    return (max(0.0, centre - half), min(1.0, centre + half))


def discordance(outcomes_a, outcomes_b):
    """Paired 2x2 table over the tasks both arms scored.

    outcomes_* map task id -> True/False (resolved). A task missing from
    either side is excluded and counted in `excluded`, because a paired
    comparison is only fair over the tasks both arms actually ran.
    """
    shared = sorted(set(outcomes_a) & set(outcomes_b))
    both = only_a = only_b = neither = 0
    rescued, broken = [], []
    for task in shared:
        a, b = bool(outcomes_a[task]), bool(outcomes_b[task])
        if a and b:
            both += 1
        elif a:
            only_a += 1
            broken.append(task)
        elif b:
            only_b += 1
            rescued.append(task)
        else:
            neither += 1
    return {
        'n': len(shared),
        'both': both, 'only_a': only_a, 'only_b': only_b, 'neither': neither,
        'rescued_by_b': rescued, 'broken_by_b': broken,
        'net_b_minus_a': only_b - only_a,
        'excluded': len(set(outcomes_a) ^ set(outcomes_b)),
    }


def mcnemar_exact(only_a, only_b):
    """Two-sided exact McNemar p-value on the discordant counts.

    Under the null the discordant tasks split 50/50, so the smaller count is
    Binomial(only_a + only_b, 1/2). p = 2 * P(X <= min), capped at 1. With no
    discordant tasks there is nothing to test and p is 1.
    """
    n = only_a + only_b
    if n == 0:
        return 1.0
    k = min(only_a, only_b)
    tail = sum(math.comb(n, i) for i in range(0, k + 1)) / (2.0 ** n)
    return min(1.0, 2.0 * tail)


def per_task_means(cells):
    """cells: iterable of {task, repo, seed, resolved} -> {task: (repo, mean, seeds)}."""
    by_task = {}
    for cell in cells:
        entry = by_task.setdefault(cell['task'], {'repo': cell['repo'], 'values': []})
        entry['values'].append(1.0 if cell['resolved'] else 0.0)
    return {task: (e['repo'], sum(e['values']) / len(e['values']), len(e['values']))
            for task, e in by_task.items()}


def hierarchical_bootstrap(cells, n_boot=2000, seed=20260904, deltas_against=None):
    """Percentile interval on the task-mean score by a three-level bootstrap.

    cells: iterable of {task, repo, seed, resolved}. Repositories are drawn
    with replacement; within each drawn repository its tasks are drawn with
    replacement; within each drawn task its seed outcomes are drawn with
    replacement. The statistic is the mean over drawn tasks of the per-task
    mean over drawn seeds.

    deltas_against: an optional second cell set on the same tasks. When
    given, the statistic is the paired difference (first minus second) with
    the same draw applied to both, which is the CI for the headline contrast.
    """
    def group(cell_list):
        repos = {}
        for cell in cell_list:
            repos.setdefault(cell['repo'], {}).setdefault(cell['task'], []).append(
                1.0 if cell['resolved'] else 0.0)
        return repos

    first = group(cells)
    second = group(deltas_against) if deltas_against is not None else None
    if second is not None:
        # Pair over the tasks both arms ran; a task on one side only would
        # bias the difference toward whichever arm happened to run it.
        for repo in list(first):
            for task in list(first[repo]):
                if task not in (second.get(repo) or {}):
                    del first[repo][task]
            if not first[repo]:
                del first[repo]
    repo_ids = sorted(first)
    if not repo_ids:
        return {'point': None, 'low': None, 'high': None, 'n_boot': 0, 'seed': seed}

    def statistic(sample_repos, rng):
        total, count = 0.0, 0
        for repo in sample_repos:
            tasks = sorted(first[repo])
            drawn_tasks = [rng.choice(tasks) for _ in tasks]
            for task in drawn_tasks:
                values = first[repo][task]
                drawn = [rng.choice(values) for _ in values]
                score = sum(drawn) / len(drawn)
                if second is not None:
                    other = second[repo][task]
                    drawn_other = [rng.choice(other) for _ in other]
                    score -= sum(drawn_other) / len(drawn_other)
                total += score
                count += 1
        return total / count if count else 0.0

    # The point estimate is the plain task mean (or paired mean difference).
    point_total, point_count = 0.0, 0
    for repo in repo_ids:
        for task, values in first[repo].items():
            score = sum(values) / len(values)
            if second is not None:
                other = second[repo][task]
                score -= sum(other) / len(other)
            point_total += score
            point_count += 1
    point = point_total / point_count

    rng = random.Random(seed)
    draws = []
    for _ in range(n_boot):
        sample_repos = [rng.choice(repo_ids) for _ in repo_ids]
        draws.append(statistic(sample_repos, rng))
    draws.sort()
    low = draws[int(math.floor(0.025 * (n_boot - 1)))]
    high = draws[int(math.ceil(0.975 * (n_boot - 1)))]
    return {'point': point, 'low': low, 'high': high, 'n_boot': n_boot, 'seed': seed,
            'levels': ['repo', 'task', 'seed'], 'tasks': point_count, 'repos': len(repo_ids)}


def rank_by_upper_bound(entries):
    """entries: list of (id, low, high). Returns {id: rank}.

    Rank = 1 + number of entries whose low bound is strictly above this
    entry's high bound. Ties in rank are the point: two arms whose intervals
    overlap share a rank instead of being ordered by a coin flip.
    """
    ranks = {}
    for ident, low, high in entries:
        better = sum(1 for other, o_low, o_high in entries
                     if other != ident and o_low > high)
        ranks[ident] = 1 + better
    return ranks


def seed_summary(cells):
    """pass@k, pass^k and the flip rate over tasks that have seeds."""
    by_task = {}
    for cell in cells:
        by_task.setdefault(cell['task'], []).append(bool(cell['resolved']))
    if not by_task:
        return None
    k = max(len(v) for v in by_task.values())
    tasks = len(by_task)
    any_pass = sum(1 for v in by_task.values() if any(v))
    all_pass = sum(1 for v in by_task.values() if all(v))
    mixed = sum(1 for v in by_task.values() if any(v) and not all(v))
    return {
        'k': k,
        'tasks': tasks,
        'pass_at_k': any_pass / tasks,
        'pass_pow_k': all_pass / tasks,
        'flip_rate': mixed / tasks,
        'unstable_tasks': sorted(t for t, v in by_task.items() if any(v) and not all(v)),
    }


def power_paired(discordance_rate, effect, alpha=0.05, power=0.8):
    """Approximate paired-observation count to detect `effect` (proportion).

    From the McNemar normal approximation: n = (z_a * sqrt(d) + z_b *
    sqrt(d - effect^2))^2 / effect^2, where d is the discordance rate. This
    is the table the plan quotes (about 300 paired observations for a
    6-point difference at 14% discordance).
    """
    if effect <= 0 or discordance_rate <= 0 or discordance_rate <= effect * effect:
        return None
    z_a = Z_95
    z_b = 0.8416212335729143 if abs(power - 0.8) < 1e-9 else _z_from_power(power)
    n = ((z_a * math.sqrt(discordance_rate)
          + z_b * math.sqrt(discordance_rate - effect * effect)) ** 2) / (effect * effect)
    return int(math.ceil(n))


def _z_from_power(power):
    # Inverse normal by bisection; only exercised for a non-default power.
    lo, hi = -6.0, 6.0
    for _ in range(100):
        mid = (lo + hi) / 2.0
        if 0.5 * (1.0 + math.erf(mid / math.sqrt(2.0))) < power:
            lo = mid
        else:
            hi = mid
    return (lo + hi) / 2.0
