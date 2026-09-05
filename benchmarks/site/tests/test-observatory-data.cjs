const assert = require('node:assert/strict');
const {test} = require('node:test');
const fs = require('node:fs');
const path = require('node:path');
const {eligible, observed, repoStats, phaseProgress, wallValue} = require('../observatory-data.js');
// The frozen original export is our known-answer fixture; current results may evolve.
const data = JSON.parse(fs.readFileSync(path.join(__dirname, '../public/leaderboard.json'), 'utf8'));

test('completed public scores exclude every flagged frontier result', () => {
  const rows = data.rows.filter(eligible);
  assert.deepEqual(rows.map(r => [r.id, r.score.resolved, r.score.n]), [
    ['A@base50-light',39,50], ['B@base50-light',42,50], ['E@base50-light',33,50]
  ]);
  assert.equal(eligible({...rows[0], complete:false}), false);
  assert.equal(eligible({...rows[0], provenance:{}}), false);
});

test('zero scores are observations; null, missing and unrun scores are not', () => {
  assert.equal(observed({score:{rate:0},attempted:true}), true);
  assert.equal(!!observed({score:{rate:null},attempted:true}), false);
  assert.equal(!!observed({score:{rate:0},attempted:false,measured:false}), false);
  assert.equal(!!observed({measured:true}), false);
});

test('API-only timing placeholders are not presented as zero-second measurements', () => {
  assert.equal(wallValue(data.rows.find(r=>r.id==='G@base50')), null);
  assert.equal(wallValue(data.rows.find(r=>r.id==='B@base50-light')), 600);
  assert.equal(wallValue({telemetry:{claude_dispatches:1,wall_per_task:0}}), 0);
});

test('repository denominators count no-patch failures but exclude unattempted tasks', () => {
  const row = {per_task:['resolved','no-patch','unresolved','not-submitted','not-run']
    .map(status => ({repo:'org/repo',status}))};
  const stats = repoStats([row], [{repo:'org/repo'},{repo:'org/empty'}]);
  assert.deepEqual(stats.find(s=>s.repo==='org/repo').values[0], {n:3,resolved:1,rate:1/3});
  assert.deepEqual(stats.find(s=>s.repo==='org/empty').values[0], {n:0,resolved:0,rate:null});
});

test('repository totals reproduce official scores, including single-shot no-patch attempts', () => {
  for (const row of data.rows.filter(observed)) {
    const stats = repoStats([row], data.suite.instances);
    assert.equal(stats.reduce((sum,s)=>sum+s.values[0].resolved,0), row.score.resolved, row.id);
    assert.equal(stats.reduce((sum,s)=>sum+s.values[0].n,0), row.score.n, row.id);
  }
});

test('a roadmap phase cannot inherit scores from another suite or model tier', () => {
  const phase = data.methodology.phases[0];
  assert.deepEqual(phaseProgress(phase, data), {count:3,total:12});
  assert.equal(phaseProgress({...phase, suite:'future-suite'},data).count, 0);
  assert.equal(phaseProgress({...phase, model_tier:'mixed'},data).count, 0);
  const duplicate = {...data,rows:[...data.rows,...data.rows]};
  assert.equal(phaseProgress(phase,duplicate).count, 3);
});
