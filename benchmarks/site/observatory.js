(() => {
  'use strict';
  const catalog = JSON.parse(document.getElementById('observatory-data').textContent);
  const $ = id => document.getElementById(id);
  const esc = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const pct = (n, decimals = 0) => Number.isFinite(n) ? `${(n * 100).toFixed(decimals)}%` : '—';
  const usd = n => Number.isFinite(n) ? `$${n.toFixed(2)}` : '—';
  const mins = n => Number.isFinite(n) ? `${(n / 60).toFixed(1)}m` : '—';
  const pp = n => Number.isFinite(n) ? `${n > 0 ? '+' : ''}${(n * 100).toFixed(1)} pp` : '—';
  const colors = ['#2d50e8', '#bb644a', '#16847b', '#806ca9', '#64798e', '#a88019', '#ae5376'];
  const fixedColors = {B:colors[0], A:colors[1], E:colors[2]};
  const color = r => fixedColors[r.condition] || colors[(r.condition.charCodeAt(0) - 65) % colors.length];
  const model = name => String(name || 'Unrecorded model').replace(/^sonnet$/, 'Claude Sonnet').replace(/^fable$/, 'Claude Fable').replace(/^gpt-(.+)-(sol|terra|luna)$/, (_, version, tier) => `GPT-${version} ${tier[0].toUpperCase()}${tier.slice(1)}`);
  const title = r => ({A:'Claude solo', B:'Cross-vendor review', C:'Multi-model review',
    D:'Claude self-review', E:'Codex solo', F:'GLM single-shot', G:'Kimi single-shot',
    H:'GLM review', I:'Kimi review', J:'Reverse cross-vendor review', K:'Codex self-review',
    L:'Best of two', M:'Light author, frontier review', N:'Frontier author, light review',
    O:'Frontier reverse review', P:'Two-round review'})[r.condition] || String(r.label || r.condition).replaceAll('-', ' ').replace(/^./, c => c.toUpperCase());
  const pipeline = r => [model(r.implementer), ...(r.reviewers || []).map(model)].join(' → ');
  const short = r => `${title(r)} · ${r.condition}`;
  const {eligible, observed, phaseProgress, wallValue} = ObservatoryData;
  const symbol = r => (r.reviewers || []).length ? '⇄' : r.implementer?.startsWith('gpt') ? '⌘' : '✳';
  let suite, data, run, tier = 'agentic', selected = new Set(), sort = 'score', direction = -1;
  let toastTimer;

  function allRows() { return data.rows.filter(r => r.run_label === run && r.tier === tier); }
  function measuredRows() { return allRows().filter(observed); }
  function comparableRows() { return allRows().filter(eligible).sort((a,b) => b.score.rate - a.score.rate); }
  function comparisonRows() { return comparableRows().filter(r => selected.has(r.id)); }
  function notify(message) {
    $('toast').textContent = message;
    $('toast').classList.add('visible');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => $('toast').classList.remove('visible'), 2500);
  }

  function setSuite(id) {
    suite = catalog.suites.find(s => s.id === id) || catalog.suites[0];
    data = suite.results;
    run = suite.default_run;
    $('suite-select').value = suite.id;
    $('run-select').innerHTML = data.runs.map(r => `<option value="${esc(r.label)}">${esc(r.label)}${r.publishable === false ? ' · flagged' : ''}</option>`).join('');
    $('run-select').value = run;
    $('dataset-name').textContent = suite.name;
    $('dataset-scope').textContent = `${suite.subtitle} · ${suite.category} · Official evaluator`;
    const date = new Date(data.generated_at);
    $('updated').textContent = `Data snapshot · ${Number.isNaN(+date) ? data.generated_at : date.toLocaleDateString('en-US', {month:'short', day:'numeric', year:'numeric', timeZone:'UTC'})} UTC`;
    $('method-link').href = suite.methodology;
    $('json-link').href = suite.data;
    const population = data.suite.sampling?.drawn_from?.population;
    $('method-sample').textContent = `${data.suite.task_count} frozen tasks${population ? ` drawn from ${population}` : ''}, scored by the pinned official evaluator. These subset results are not directly comparable to a full-benchmark leaderboard. Coding agents and single-shot models are shown separately.`;
    const canary = data.gold_canary;
    $('method-provenance').textContent = `Every configuration links to its recorded model, evaluator reports, and reproduction command.${canary?.submitted != null ? ` Gold-patch validation: ${canary.resolved}/${canary.submitted} resolved.` : ''} Missing harness metadata and flagged runs remain labeled in the evidence record. This site displays a dated snapshot; it does not poll running experiments.`;
    renderRoadmap();
    resetScope();
  }

  function resetScope() {
    selected = new Set(comparableRows().map(r => r.id));
    $('search').value = '';
    sort = 'score'; direction = -1;
    const repos = [...new Set((data.suite.instances || []).map(t => t.repo))].sort();
    $('repo-select').innerHTML = '<option value="all">All repositories</option>' + repos.map(r => `<option value="${esc(r)}">${esc(r)}</option>`).join('');
    renderHero(); renderRows(); renderComparison();
  }

  function renderHero() {
    const rows = comparableRows();
    $('hero-scores').innerHTML = `<div class="hero-chart-heading"><h2>Observed resolve rate</h2><span>${esc(run)} · ${esc(tier)}</span></div>` +
      (rows.length ? rows.map(r => `<div class="hero-score-row" style="--series:${color(r)}"><div class="hero-score-label"><strong>${esc(title(r))}</strong><b>${(r.score.rate * 100).toFixed(0)}<small>%</small></b></div><div class="hero-track"><div class="hero-fill" style="width:${r.score.rate * 100}%"></div><div class="hero-range" style="left:${r.score.wilson_low * 100}%;width:${(r.score.wilson_high - r.score.wilson_low) * 100}%"></div></div><div class="hero-bottom"><span>${r.score.resolved} / ${r.score.n} resolved</span><span>95% CI ${pct(r.score.wilson_low)}–${pct(r.score.wilson_high)}</span></div></div>`).join('') : '<p class="empty">No completed, publishable results for this selection yet. Inspect available results in the table below.</p>') +
      '<p class="hero-chart-note"><span class="info-icon" aria-hidden="true">i</span>Observed scores, with uncertainty. A higher score alone does not establish a better workflow.</p>';
  }

  function sortedRows() {
    const query = $('search').value.toLowerCase().trim();
    const value = r => sort === 'score' ? r.score?.rate : sort === 'cost' ? (r.telemetry?.cost_is_complete ? r.telemetry.cost_per_task : null) : wallValue(r);
    return measuredRows().filter(r => `${r.configuration} ${pipeline(r)} ${title(r)} ${r.condition}`.toLowerCase().includes(query)).sort((a,b) => {
      const va = value(a), vb = value(b);
      if (va == null) return vb == null ? a.id.localeCompare(b.id) : 1;
      if (vb == null) return -1;
      return direction * (va - vb) || a.id.localeCompare(b.id);
    });
  }

  function renderRows() {
    const rows = sortedRows();
    const info = data.runs.find(r => r.label === run);
    $('run-context').innerHTML = `${info?.publishable === false ? '<span class="flag">Flagged run</span>' : ''}<strong>${esc(info?.model_tier || 'Unrecorded')} tier</strong> · ${esc(info?.note || '')}${tier === 'single-shot' ? ' One response, no tools or test iteration; separate from coding-agent scores.' : ''}`;
    $('result-count').textContent = `${rows.length} of ${measuredRows().length} measured configurations`;
    document.querySelectorAll('[data-sort]').forEach(button => {
      const active = button.dataset.sort === sort;
      button.parentElement.setAttribute('aria-sort', active ? (direction === -1 ? 'descending' : 'ascending') : 'none');
      button.querySelector('span').textContent = active ? (direction === -1 ? '↓' : '↑') : '↕';
    });
    $('result-rows').innerHTML = rows.length ? rows.map(r => {
      const s = r.score, t = r.telemetry || {};
      const estimated = t.cost_precision === 'estimated';
      const cost = t.cost_is_complete ? usd(t.cost_per_task) : 'Incomplete';
      return `<tr data-row="${esc(r.id)}" style="--series:${color(r)}"><td><div class="config-cell"><span class="config-symbol" aria-hidden="true">${symbol(r)}</span><div><span class="config-name">${esc(title(r))}</span><span class="config-pipeline">${esc(pipeline(r))}</span></div></div></td><td class="number"><span class="score-value">${(s.rate * 100).toFixed(0)}<small>%</small></span><span class="subvalue">${s.resolved} / ${s.n} resolved</span></td><td><div class="interval"><div class="interval-track"><span class="interval-line" style="left:${s.wilson_low * 100}%;width:${(s.wilson_high-s.wilson_low)*100}%"></span><span class="interval-dot" style="left:${s.rate*100}%"></span></div><span class="interval-text">${pct(s.wilson_low)} – ${pct(s.wilson_high)}</span></div></td><td class="number mono">${cost}<span class="subvalue">${estimated ? 'Est. · token split' : t.cost_is_complete ? 'Recorded usage' : 'Unpriced usage'}</span></td><td class="number mono">${mins(wallValue(r))}<span class="subvalue">p90 ${mins(wallValue(r, 'wall_p90'))}</span></td><td class="number mono">${s.n}<span class="subvalue">${r.complete ? `${s.seeds || r.seeds?.length || 1} seed(s)` : 'Partial run'}</span></td><td>${!r.complete ? '<span class="flag">Partial</span><br>' : ''}${r.provenance?.publishable !== true ? '<span class="flag">Flagged</span><br>' : ''}<button class="evidence-btn" data-evidence="${esc(r.id)}" aria-label="View evidence for ${esc(title(r))}">View record ↗</button></td></tr>`;
    }).join('') : `<tr><td colspan="7" class="empty">${$('search').value ? 'No configurations match your search. Try a model or workflow name.' : 'No evaluated configurations in this selection yet. Planned tests appear in the research agenda below.'}</td></tr>`;
  }

  function repoStats(rows) {
    return ObservatoryData.repoStats(rows, data.suite.instances || []);
  }

  function renderComparison() {
    const available = comparableRows(), rows = comparisonRows();
    $('compare-chips').innerHTML = available.length ? available.map(r => `<button class="compare-chip" style="--series:${color(r)}" data-compare="${esc(r.id)}" aria-pressed="${selected.has(r.id)}" aria-label="Compare ${esc(title(r))}"><i class="swatch" aria-hidden="true"></i>${esc(title(r))}<span class="chip-action" aria-hidden="true">${selected.has(r.id) ? '×' : '+'}</span></button>`).join('') : '<p class="small-note">Comparisons require completed, publishable configurations from the selected run and execution type.</p>';
    $('select-all').disabled = !available.length;
    const stats = repoStats(rows);
    renderRadar(rows, stats); renderCosts(rows); renderRepoTable(rows, stats); renderPairs(rows); renderTasks(rows);
    $('compare-legend').innerHTML = rows.map(r => `<span style="--series:${color(r)}"><i class="swatch" aria-hidden="true"></i>${esc(title(r))} · ${esc(pipeline(r))}</span>`).join('');
  }

  function renderRadar(rows, stats) {
    if (!rows.length || stats.length < 3) {
      $('radar-chart').innerHTML = `<p class="empty">${!rows.length ? 'Select a configuration to explore repository performance.' : 'At least three repositories are needed for a radar chart. Exact results are in the breakdown below.'}</p>`;
      return;
    }
    const cx=255, cy=161, radius=119;
    const point = (i, ratio) => { const a = (i/stats.length) * Math.PI*2 - Math.PI/2; return [cx+Math.cos(a)*radius*ratio, cy+Math.sin(a)*radius*ratio]; };
    const points = ratio => stats.map((_,i) => point(i, ratio).join(',')).join(' ');
    let svg = '<svg class="radar-svg" viewBox="0 0 510 330" role="img" aria-label="Resolved-task percentage by repository. Exact counts are in the repository breakdown.">';
    for (const ratio of [.25,.5,.75,1]) {
      svg += `<polygon points="${points(ratio)}" fill="${ratio === 1 ? '#f9fafc' : 'none'}" stroke="#e2e7ef"/>`;
    }
    // Rings follow the outer fill so all four guides remain visible.
    for (const ratio of [.25,.5,.75]) svg += `<polygon points="${points(ratio)}" fill="none" stroke="#e2e7ef"/>`;
    stats.forEach((s,i) => {
      const [x,y] = point(i,1), [lx,ly] = point(i,1.17);
      const anchor = Math.abs(lx-cx)<5 ? 'middle' : lx>cx ? 'start' : 'end';
      const repoName = s.repo.split('/').pop();
      svg += `<line x1="${cx}" y1="${cy}" x2="${x}" y2="${y}" stroke="#e7ebf2"/><text x="${lx}" y="${ly+4}" text-anchor="${anchor}" font-size="14">${esc(repoName)}</text>`;
    });
    rows.forEach((r, index) => {
      // Missing repository observations must not become a zero on the radar.
      if (stats.some(s => s.values[index].rate == null)) return;
      const outline = stats.map((s,i) => point(i,s.values[index].rate).join(',')).join(' ');
      svg += `<g class="chart-line"><title>${esc(title(r))}: ${stats.map(s => `${esc(s.repo)} ${pct(s.values[index].rate)}`).join('; ')}</title><polygon points="${outline}" fill="${color(r)}" fill-opacity=".065" stroke="${color(r)}" stroke-width="2" stroke-linejoin="round"/>`;
      stats.forEach((s,i) => { const [x,y]=point(i,s.values[index].rate); svg+=`<circle cx="${x}" cy="${y}" r="3" fill="${color(r)}"/>`; });
      svg += '</g>';
    });
    for (const ratio of [.25,.5,.75,1]) svg += `<text x="${cx+5}" y="${cy-radius*ratio+12}" font-size="11" style="font-family:var(--mono)">${ratio*100}</text>`;
    svg += '</svg><p class="cost-note">Each axis is a repository, not a separate benchmark. Small samples can produce large swings; expand the breakdown for denominators.</p>';
    $('radar-chart').innerHTML = svg;
  }

  function renderCosts(rows) {
    const priced = rows.filter(r => r.telemetry?.cost_is_complete && Number.isFinite(r.telemetry.cost_per_resolved));
    if (!priced.length) {
      $('cost-chart').innerHTML = `<p class="empty">${rows.length ? 'No complete cost-per-resolved-task data for this selection. Missing cost is never treated as zero.' : 'Select a configuration to compare cost.'}</p>`;
      return;
    }
    const max = Math.max(.1,...priced.map(r => r.telemetry.cost_per_resolved))*1.22;
    const left=55, top=28, bottom=255, right=482, plotWidth=right-left;
    let svg = '<svg class="cost-svg" viewBox="0 0 510 330" role="img" aria-label="Cost per resolved task in US dollars. Bar labels contain the exact figures; estimated costs are marked.">';
    for (let i=0;i<=4;i++) {
      const y=bottom-(bottom-top)*i/4;
      svg+=`<line x1="${left}" x2="${right}" y1="${y}" y2="${y}" stroke="#e5e9f0" ${i ? 'stroke-dasharray="3 4"' : ''}/><text x="${left-11}" y="${y+3}" text-anchor="end" font-size="12">${usd(max*i/4)}</text>`;
    }
    priced.forEach((r,i) => {
      const t=r.telemetry, slot=plotWidth/priced.length, width=Math.min(72,slot*.55), x=left+slot*i+(slot-width)/2;
      const height=t.cost_per_resolved/max*(bottom-top), y=bottom-height;
      svg+=`<g class="chart-line"><title>${esc(title(r))}: ${usd(t.cost_per_resolved)} per resolved task${t.cost_precision==='estimated'?' (estimated)':''}</title><rect x="${x}" y="${y}" width="${width}" height="${height}" rx="3" fill="${color(r)}" fill-opacity=".86"/><text x="${x+width/2}" y="${y-10}" text-anchor="middle" font-size="17" style="fill:var(--ink);font-family:var(--mono)">${usd(t.cost_per_resolved)}${t.cost_precision==='estimated'?'*':''}</text><text x="${x+width/2}" y="279" text-anchor="middle" font-size="13">${esc(priced.length>4?r.condition:title(r))}</text><text x="${x+width/2}" y="295" text-anchor="middle" font-size="12">${r.score.resolved} resolved</text></g>`;
    });
    svg+='</svg>';
    svg+=`<p class="cost-note">${priced.some(r=>r.telemetry.cost_precision==='estimated') ? '* Estimated from recorded token totals. ' : ''}Total configuration cost ÷ resolved tasks.${priced.length<rows.length?' Configurations with incomplete cost or no resolved tasks are omitted.':''} See each evidence record for precision and bounds.</p>`;
    $('cost-chart').innerHTML=svg;
  }

  function renderRepoTable(rows, stats) {
    $('repo-table').innerHTML = `<thead><tr><th scope="col">Repository</th>${rows.map(r=>`<th scope="col">${esc(short(r))}</th>`).join('')}</tr></thead><tbody>${stats.map(s=>`<tr><th scope="row">${esc(s.repo)}</th>${s.values.map(v=>`<td class="repo-cell" style="background:${v.rate==null?'#f4f5f7':`rgba(22,132,123,${.025+v.rate*.095})`}">${pct(v.rate,1)}<small>${v.resolved} / ${v.n} evaluated</small></td>`).join('')}</tr>`).join('')}</tbody>`;
  }

  function renderPairs(rows) {
    const ids = new Set(rows.map(r=>r.id));
    const previous = $('pair-select').value;
    const pairs = (data.contrasts || []).map((c,i)=>({c,i})).filter(({c})=>ids.has(c.a)&&ids.has(c.b));
    $('pair-select').innerHTML = pairs.length ? pairs.map(({c,i})=>`<option value="${i}">${esc(title(data.rows.find(r=>r.id===c.a)))} → ${esc(title(data.rows.find(r=>r.id===c.b)))}</option>`).join('') : '<option value="">Select two comparable configurations</option>';
    if (pairs.some(p=>String(p.i)===previous)) $('pair-select').value=previous;
    $('pair-select').disabled = !pairs.length;
    renderPair();
  }

  function renderPair() {
    if ($('pair-select').value==='') {
      $('paired-result').innerHTML='<p class="empty">Select at least two completed configurations to view a paired comparison.</p>';
      return;
    }
    const c=data.contrasts[Number($('pair-select').value)];
    const a=data.rows.find(r=>r.id===c.a), b=data.rows.find(r=>r.id===c.b), delta=c.delta_b_minus_a || {};
    const conclusive = Number.isFinite(c.mcnemar_exact_p) && c.mcnemar_exact_p < .05;
    $('paired-result').innerHTML=`<div class="paired-stats"><div class="paired-stat gain"><strong>${c.only_b}</strong><span>gained by ${esc(title(b))}</span></div><div class="paired-stat loss"><strong>${c.only_a}</strong><span>lost vs ${esc(title(a))}</span></div><div class="paired-stat"><strong>${c.net_b_minus_a>0?'+':''}${c.net_b_minus_a}</strong><span>net tasks resolved</span></div></div><p class="paired-conclusion">${pp(delta.point)} observed change. ${conclusive?'Evidence of a difference on these tasks.':'The difference is not conclusive.'}</p><p class="paired-explanation">${c.n} shared tasks · Exact McNemar p = ${Number.isFinite(c.mcnemar_exact_p)?c.mcnemar_exact_p.toFixed(3):'not available'} · Exploratory, unadjusted.<br>95% bootstrap interval: ${pp(delta.low)} to ${pp(delta.high)}.${c.excluded?` ${c.excluded} tasks excluded from pairing.`:''}<br>${c.both} resolved by both; ${c.neither} resolved by neither.</p><details class="paired-task-list"><summary>See gained and lost issues</summary><p>Gained by ${esc(title(b))}</p><ul>${(c.rescued_by_b||[]).map(t=>`<li>${esc(t)}</li>`).join('')||'<li>None</li>'}</ul><p>Lost compared with ${esc(title(a))}</p><ul>${(c.broken_by_b||[]).map(t=>`<li>${esc(t)}</li>`).join('')||'<li>None</li>'}</ul></details>`;
  }

  function renderTasks(rows=comparisonRows()) {
    const matrix=data.task_matrix || {tasks:{},order:[]};
    const tasks=(matrix.order || []).map(id=>matrix.tasks[id]).filter(Boolean).filter(t=>$('repo-select').value==='all'||t.repo===$('repo-select').value);
    $('task-table').innerHTML=`<thead><tr><th scope="col">Repository / issue</th>${rows.map(r=>`<th scope="col" class="number">${esc(short(r))}</th>`).join('')}</tr></thead><tbody>${rows.length ? tasks.map(t=>`<tr><td class="task-name"><strong>${esc(t.instance_id)}</strong><span>${esc(t.difficulty || 'Difficulty not recorded')}</span></td>${rows.map(r=>{
      const cell=t.cells?.[r.id];
      const hasResult=cell && cell.ran>0 && (cell.status==='resolved'||cell.status==='unresolved'||Number.isFinite(cell.resolved));
      const status=!hasResult?'missing':cell.resolved===cell.ran?'resolved':'failed';
      const content=!hasResult?'—':`${status==='resolved'?'✓':'×'} ${cell.resolved}/${cell.ran}`;
      return `<td class="task-result"><button class="${status}-key" data-task="${esc(t.instance_id)}" data-task-row="${esc(r.id)}" aria-label="${esc(t.instance_id)}, ${esc(title(r))}: ${hasResult?`${cell.resolved} of ${cell.ran} resolved`:'not evaluated'}">${content}</button></td>`;
    }).join('')}</tr>`).join(''):'<tr><td class="empty">Select a configuration above to inspect its task outcomes.</td></tr>'}</tbody>`;
  }

  function renderRoadmap() {
    const phases=data.methodology?.phases || [];
    $('roadmap').innerHTML=phases.length ? phases.map(p=>{
      // Do not reuse legacy arms_measured/observed: those can cross phase cohorts.
      const {count, total}=phaseProgress(p, data);
      return `<article><div class="phase-head"><span>PHASE ${esc(p.id)}</span><span class="phase-status">${count===0?'Planned':count===total?'Evaluated':'Partially evaluated'}</span></div><h3>${esc(p.name)}</h3><p>${esc(p.primary_contrast?.question || p.exit)}</p><div class="phase-progress"><span style="width:${total?100*count/total:0}%"></span></div><div class="phase-count">${total?`${count} / ${total} configurations complete`:'New task set and repeated seeds planned'}</div></article>`;
    }).join(''):'<p class="small-note">No future phases have been registered for this benchmark yet.</p>';
  }

  function showEvidence(id, taskId) {
    const r=data.rows.find(row=>row.id===id);
    if (!r) return;
    const t=r.telemetry||{}, p=r.provenance||{};
    $('evidence-title').textContent = taskId || `${title(r)} · ${pipeline(r)}`;
    if (taskId) {
      const tasks=(r.per_task||[]).filter(t=>t.instance_id===taskId);
      $('evidence-body').innerHTML=`<p>${esc(pipeline(r))} · ${esc(run)}</p>${tasks.length?tasks.map(t=>`<div class="evidence-grid"><div><dt>Outcome · seed ${esc(t.seed)}</dt><dd>${esc(t.status)}</dd></div><div><dt>Patch applied</dt><dd>${t.patch_applied==null?'Not recorded':t.patch_applied?'Yes':'No'}</dd></div><div><dt>Fail-to-pass tests</dt><dd>${esc(t.fail_to_pass_passed ?? '—')} passed / ${esc(t.fail_to_pass_failed ?? '—')} failed</dd></div><div><dt>Pass-to-pass regressions</dt><dd>${esc(t.pass_to_pass_failed ?? 'Not recorded')}</dd></div></div><div class="evidence-block"><h3>Local evaluator record</h3><pre>${esc(t.evidence||'Not recorded')}</pre></div>`).join(''):'<p class="empty">This task has no evaluator record in this configuration.</p>'}<p class="small-note">Paths identify artifacts in the benchmark checkout. They are not public download links.</p>`;
    } else {
      $('evidence-body').innerHTML=`<p>${esc(r.pipeline || pipeline(r))}</p>${!eligible(r)?`<p class="warning-note">${esc(p.run_note||'This run is incomplete or has a provenance flag. It is excluded from headline comparisons.')}</p>`:''}<dl class="evidence-grid"><div><dt>Observed score · 95% Wilson interval</dt><dd>${pct(r.score?.rate)} (${r.score?.resolved??'—'}/${r.score?.n??'—'}) · ${pct(r.score?.wilson_low)}–${pct(r.score?.wilson_high)}</dd></div><div><dt>Run and completion</dt><dd>${esc(r.run_label)} · ${r.complete?'Complete':'Partial'} · ${esc(r.tier)}</dd></div><div><dt>Cost precision</dt><dd>${esc(t.cost_precision || 'Unrecorded')} · ${t.cost_is_complete?'All seats priced':'Unpriced usage remains'}</dd></div><div><dt>Total cost and accounting bounds</dt><dd>${t.cost_is_complete ? `${usd(t.cost_usd)} · ${usd(t.cost_low_usd)}–${usd(t.cost_high_usd)}` : 'Incomplete; total unavailable'}</dd></div><div><dt>Cost per resolved task</dt><dd>${t.cost_is_complete?usd(t.cost_per_resolved):'Unavailable: incomplete costs'}</dd></div><div><dt>Average / p50 / p90 time</dt><dd>${mins(wallValue(r))} / ${mins(wallValue(r, 'wall_p50'))} / ${mins(wallValue(r, 'wall_p90'))}</dd></div><div><dt>Run harness commit</dt><dd>${esc(p.harness_commit || 'Not recorded')}</dd></div><div><dt>Run harness state</dt><dd>${p.harness_dirty===true?'Dirty tree':p.harness_dirty===false?'Clean tree':'Not recorded'}</dd></div><div><dt>Unapplied patches</dt><dd>${esc(t.patch_not_applied ?? 'Not recorded')}</dd></div><div><dt>Repair activity</dt><dd>${t.repair_cells?`${t.repair_inert_count} inert / ${t.repair_cells} recorded`:'Not recorded'}</dd></div><div><dt>Recorded effort</dt><dd>${esc(JSON.stringify(r.effort||{}))}</dd></div><div><dt>Interval-overlap rank (Rank UB)</dt><dd>${eligible(r)?esc(r.rank_ub??'Not available'):'Not ranked'} · overlapping intervals may tie</dd></div></dl><div class="evidence-block"><h3>Evaluator report files · local artifacts</h3><pre>${esc((p.report_files||[]).join('\n')||'Not recorded')}</pre></div><div class="evidence-block"><h3>Reproduce this evaluation</h3><p>This command runs evaluation work; copying it does not execute it.</p><pre id="reproduce-command">${esc(r.reproduce || 'No reproduction command recorded.')}</pre>${r.reproduce?'<button class="button secondary" id="copy-command">Copy command</button>':''}</div><div class="evidence-block"><h3>Data snapshot provenance</h3><p>Site build ${esc(data.harness?.build_commit || 'not recorded')} · ${data.harness?.build_tree_dirty?'dirty build tree':'build tree not flagged'}. Site-build metadata is distinct from run-harness metadata.</p></div>`;
    }
    // dl provides native name/value semantics in the task evidence too.
    $('evidence-body').querySelectorAll('div.evidence-grid').forEach(grid=>{
      const dl=document.createElement('dl');dl.className=grid.className;dl.innerHTML=grid.innerHTML;grid.replaceWith(dl);
    });
    $('evidence-dialog').showModal();
    const copy=$('copy-command');
    if (copy) copy.addEventListener('click', async()=>{
      try { await navigator.clipboard.writeText(r.reproduce); notify('Reproduction command copied'); }
      catch { notify('Copy unavailable. Select the command text to copy it.'); }
    });
  }

  function exportCsv() {
    const headers=['benchmark','run','condition','configuration','execution','complete','publishable','resolved','evaluated','resolve_rate','wilson_low','wilson_high','cost_per_task_usd','cost_precision','cost_is_complete','wall_seconds_per_task'];
    const cells=value=>`"${String(value??'').replaceAll('"','""').replace(/^[=+@\-]/,"'$&")}"`;
    const lines=[headers,...sortedRows().map(r=>[suite.id,r.run_label,r.condition,r.configuration,r.tier,r.complete,r.provenance?.publishable,r.score.resolved,r.score.n,r.score.rate,r.score.wilson_low,r.score.wilson_high,r.telemetry.cost_is_complete?r.telemetry.cost_per_task:null,r.telemetry.cost_precision,r.telemetry.cost_is_complete,wallValue(r)])];
    const blob=new Blob(['\uFEFF'+lines.map(row=>row.map(cells).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'});
    const url=URL.createObjectURL(blob), link=document.createElement('a');
    link.href=url;link.download=`co-evolution-${suite.id}-${run}-${tier}.csv`;link.click();
    setTimeout(()=>URL.revokeObjectURL(url),1000);notify(`${sortedRows().length} configurations exported`);
  }

  $('suite-select').innerHTML=catalog.suites.map(s=>`<option value="${esc(s.id)}">${esc(s.name)} · ${esc(s.subtitle)}</option>`).join('');
  $('archive-links').innerHTML=(catalog.archives||[]).map(a=>`<a class="archive-link" href="${esc(a.href)}"><h3>${esc(a.name)}</h3><p>${esc(a.description)}</p><span>${esc(a.label)}</span><b aria-hidden="true">↗</b></a>`).join('');
  $('suite-select').addEventListener('change',e=>setSuite(e.target.value));
  $('run-select').addEventListener('change',e=>{run=e.target.value;resetScope();});
  $('tier-select').addEventListener('change',e=>{tier=e.target.value;resetScope();});
  $('search').addEventListener('input',renderRows);
  $('repo-select').addEventListener('change',()=>renderTasks());
  $('pair-select').addEventListener('change',renderPair);
  $('select-all').addEventListener('click',()=>{selected=new Set(comparableRows().map(r=>r.id));renderComparison();});
  $('export').addEventListener('click',exportCsv);
  document.addEventListener('click',e=>{
    const chip=e.target.closest('[data-compare]');
    if(chip){const id=chip.dataset.compare;selected.has(id)?selected.delete(id):selected.add(id);renderComparison();document.querySelector(`[data-compare="${CSS.escape(id)}"]`)?.focus({preventScroll:true});}
    const sortButton=e.target.closest('[data-sort]');
    if(sortButton){const next=sortButton.dataset.sort;direction=sort===next?-direction:next==='score'?-1:1;sort=next;renderRows();}
    const evidence=e.target.closest('[data-evidence]');if(evidence)showEvidence(evidence.dataset.evidence);
    const task=e.target.closest('[data-task]');if(task)showEvidence(task.dataset.taskRow,task.dataset.task);
  });
  $('evidence-dialog').addEventListener('click',e=>{if(e.target===$('evidence-dialog')){const rect=e.target.getBoundingClientRect();if(e.clientX<rect.left||e.clientX>rect.right||e.clientY<rect.top||e.clientY>rect.bottom)e.target.close();}});
  let scrollQueued=false;
  window.addEventListener('scroll',()=>{
    if(scrollQueued)return;scrollQueued=true;
    requestAnimationFrame(()=>{const max=document.documentElement.scrollHeight-innerHeight;document.querySelector('.reading-progress').style.transform=`scaleX(${max>0?scrollY/max:0})`;scrollQueued=false;});
  },{passive:true});
  if ('IntersectionObserver' in window) {
    const observer=new IntersectionObserver(entries=>{entries.forEach(entry=>{if(entry.isIntersecting){document.querySelectorAll('nav a').forEach(a=>a.classList.toggle('active',a.hash===`#${entry.target.id}`));}});},{rootMargin:'-15% 0px -65% 0px'});
    ['results','compare','methodology','archive'].forEach(id=>observer.observe($(id)));
  }
  setSuite(catalog.default_suite);
})();
