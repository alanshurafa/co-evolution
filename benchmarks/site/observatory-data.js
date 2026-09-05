/* Data rules shared by the browser and offline regression checks. */
const ObservatoryData = (() => {
  const observed = r => Number.isFinite(r.score?.rate) && (r.measured || r.attempted);
  const eligible = r => observed(r) && r.complete === true && r.provenance?.publishable === true;

  function wallValue(row, key = 'wall_per_task') {
    const t = row.telemetry || {};
    // Schema 2.0 sums Claude and Codex phase time only. API-only seats have
    // zero-filled timing fields, not measured zero-second execution.
    return (t.claude_dispatches > 0 || t.codex_phases > 0) && Number.isFinite(t[key]) ? t[key] : null;
  }

  function repoStats(rows, instances) {
    const repos = [...new Set(instances.map(t => t.repo))].sort();
    return repos.map(repo => ({repo, values: rows.map(r => {
      // The official export counts no-patch attempts as failures. Unreached
      // and not-submitted tasks are absent from the denominator, never zero.
      const tasks = (r.per_task || []).filter(t => t.repo === repo &&
        ['resolved', 'unresolved', 'no-patch'].includes(t.status));
      const resolved = tasks.filter(t => t.status === 'resolved').length;
      return {n: tasks.length, resolved, rate: tasks.length ? resolved / tasks.length : null};
    })}));
  }

  function phaseProgress(phase, data) {
    const arms = new Set(phase.arms || []);
    const completed = new Set(data.rows.filter(r => eligible(r) &&
      r.model_tier === phase.model_tier && phase.suite === data.suite.id &&
      arms.has(r.condition)).map(r => r.condition));
    return {count: completed.size, total: arms.size};
  }

  return {observed, eligible, repoStats, phaseProgress, wallValue};
})();
if (typeof module !== 'undefined' && module.exports) module.exports = ObservatoryData;
