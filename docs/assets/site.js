/* Co-Evolution benchmark results site.
 *
 * Renders data/<batch>.json, written by benchmarks/export-site-data.sh, and
 * nothing else. No number is computed here beyond formatting and the chart's
 * pixel arithmetic: the aggregation lives in the export so the site and
 * benchmarks/report.sh cannot drift apart.
 *
 * No framework and no charting library. The scatter is inline SVG built from
 * the same data the leaderboard table renders, so the table is the chart's
 * accessible equivalent rather than a separate claim.
 */
(function () {
  "use strict";

  var COND_VARS = ["--c1", "--c2", "--c3", "--c4", "--c5", "--c6"];
  var ALL_JUDGES = "__all__";

  var state = {
    index: null,
    batch: null,     // parsed data/<batch>.json
    judge: null,     // a judge id, or ALL_JUDGES
    sort: { key: "score", dir: "desc" },
    task: null
  };

  // --- small helpers -------------------------------------------------------

  function $(id) { return document.getElementById(id); }

  function el(tag, attrs, kids) {
    var node = document.createElement(tag);
    if (attrs) {
      Object.keys(attrs).forEach(function (k) {
        if (k === "class") { node.className = attrs[k]; }
        else if (k === "text") { node.textContent = attrs[k]; }
        else if (k === "html") { node.innerHTML = attrs[k]; }
        else if (attrs[k] !== null && attrs[k] !== undefined) { node.setAttribute(k, attrs[k]); }
      });
    }
    (kids || []).forEach(function (kid) {
      node.appendChild(typeof kid === "string" ? document.createTextNode(kid) : kid);
    });
    return node;
  }

  function clear(node) { while (node.firstChild) { node.removeChild(node.firstChild); } }

  function condColor(id) {
    var conds = state.batch ? state.batch.completeness.condition_ids : [];
    var i = conds.indexOf(id);
    return "var(" + COND_VARS[(i < 0 ? 0 : i) % COND_VARS.length] + ")";
  }

  function fmtNum(v, digits) {
    if (v === null || v === undefined) { return "—"; }
    return Number(v).toFixed(digits === undefined ? 2 : digits);
  }

  function fmtScore(v) { return v === null || v === undefined ? "—" : fmtNum(v, 1) + "%"; }
  function fmtUsd(v)   { return v === null || v === undefined ? "—" : "$" + fmtNum(v, 2); }

  function fmtDate(iso) {
    if (!iso) { return ""; }
    var d = new Date(iso);
    return isNaN(d.getTime()) ? iso : d.toISOString().replace("T", " ").slice(0, 16) + "Z";
  }

  function judgesShown() {
    var all = state.batch.completeness.judges_with_verdicts;
    return state.judge === ALL_JUDGES ? all : [state.judge];
  }

  // The judge whose numbers a single-value column shows. With every judge on
  // screen at once there is no single answer, so the primary judge stands in
  // and every such column says so in its header.
  function focusJudge() {
    return state.judge === ALL_JUDGES ? state.batch.suite.primary_judge : state.judge;
  }

  function scoreOf(cond, judge) {
    var pj = cond.per_judge && cond.per_judge[judge];
    return pj && pj.score !== undefined ? pj.score : null;
  }

  // --- theme ---------------------------------------------------------------

  function initTheme() {
    var saved = null;
    try { saved = window.localStorage.getItem("coev-theme"); } catch (e) { /* private mode */ }
    if (saved === "light" || saved === "dark") {
      document.documentElement.setAttribute("data-theme", saved);
    }
    var btn = $("theme-toggle");
    function label() {
      var t = document.documentElement.getAttribute("data-theme");
      btn.textContent = t === "dark" ? "Dark" : t === "light" ? "Light" : "Auto theme";
    }
    btn.addEventListener("click", function () {
      var order = ["auto", "light", "dark"];
      var cur = document.documentElement.getAttribute("data-theme") || "auto";
      var next = order[(order.indexOf(cur) + 1) % order.length];
      document.documentElement.setAttribute("data-theme", next);
      try { window.localStorage.setItem("coev-theme", next); } catch (e) { /* ignore */ }
      label();
      renderChart();
    });
    label();
  }

  // --- header --------------------------------------------------------------

  function renderHeader() {
    var b = state.batch;
    var eyebrow = $("eyebrow");
    clear(eyebrow);
    [
      "Batch " + b.batch,
      b.completeness.tasks + " tasks × " + b.completeness.conditions + " conditions",
      b.completeness.judges_with_verdicts.length + " judges, reported separately",
      "Exported " + fmtDate(b.generated_at)
    ].forEach(function (t) { eyebrow.appendChild(el("span", { text: t })); });

    $("suite-title").textContent = b.suite.title;
    $("suite-summary").textContent = b.suite.summary || "";

    var meta = $("runmeta");
    clear(meta);
    b.suite.judges.forEach(function (j) {
      var bits = j.id + " judge: " + (j.model || "unknown");
      if (j.effort) { bits += " @ " + j.effort; }
      if (j.model_assert && j.model_assert !== "verified") { bits += " (" + j.model_assert + ")"; }
      meta.appendChild(el("span", { text: bits }));
    });
    meta.appendChild(el("span", { text: "primary judge: " + b.suite.primary_judge }));

    $("foot-provenance").textContent =
      "Batch " + b.batch + ", exported " + fmtDate(b.generated_at) +
      ". Pre-registration: " + b.suite.preregistration + ". Full report: " + b.suite.report + ".";
  }

  // --- coverage ------------------------------------------------------------

  function renderCoverage() {
    var c = state.batch.completeness;
    var host = $("coverage-body");
    clear(host);

    var problems = [];
    if (!c.generation_cells_complete) {
      problems.push(c.incomplete_cells.length + " generation cell(s) did not complete: " +
        c.incomplete_cells.map(function (x) { return x.cell + " (" + x.status + ")"; }).join(", "));
    }
    if (c.degraded_cells.length) {
      problems.push(c.degraded_cells.length + " degraded cell(s) excluded from all pairing: " +
        c.degraded_cells.join(", "));
    }
    var unjudged = c.per_judge.reduce(function (n, p) { return n + Math.max(0, p.unjudged); }, 0);
    if (unjudged > 0) {
      problems.push(unjudged + " pair(s) across all judges have no verdict on disk.");
    }
    var missingJudges = c.judges_requested.filter(function (j) {
      return c.judges_with_verdicts.indexOf(j) === -1;
    });
    if (missingJudges.length) {
      problems.push("No verdicts on disk for judge(s): " + missingJudges.join(", ") + ".");
    }

    // A pair can have a verdict file and still be unscorable: sanitization
    // leaks and fabricated evidence are recorded as verdicts, then excluded
    // from every rate. Counting only "unjudged" would call that full coverage.
    function notScorable(judge) {
      var row = state.batch.integrity.filter(function (r) { return r.judge === judge; })[0];
      return row ? (row.sanitize_leak || 0) + (row.invalid_evidence || 0) : 0;
    }
    var unscorable = c.per_judge.reduce(function (n, p) { return n + notScorable(p.judge); }, 0);

    if (problems.length) {
      var warn = el("div", { class: "callout warn" }, [
        el("p", { html: "<strong>This batch is not fully covered.</strong> Every rate below is computed over what exists, not over what was planned." })
      ]);
      var ul = el("ul");
      problems.forEach(function (p) { ul.appendChild(el("li", { text: p })); });
      warn.appendChild(ul);
      host.appendChild(warn);
    } else if (unscorable > 0) {
      host.appendChild(el("div", { class: "callout" }, [
        el("p", { html: "<strong>Every cell ran and every expected pair has a verdict on disk</strong> — " +
                        "all " + c.tasks + "×" + c.conditions + " generation cells completed and no cell was degraded." }),
        el("p", { text: "But " + unscorable + " verdict(s) across all judges could not be scored, because a " +
                        "document leaked sanitization or a judge's evidence did not check out. Those pairs " +
                        "leave both the numerator and the denominator, so the comparison counts below are " +
                        "smaller than the expected-pairs column would suggest." })
      ]));
    } else {
      host.appendChild(el("div", { class: "callout ok" }, [
        el("p", { html: "<strong>Full coverage.</strong> All " + c.tasks + "×" + c.conditions +
                        " generation cells completed, no cell was degraded, and every requested judge " +
                        "returned a scorable verdict on every expected pair." })
      ]));
    }

    var wrap = el("div", { class: "scroll-x" });
    var table = el("table");
    table.appendChild(el("thead", {}, [el("tr", {}, [
      el("th", { class: "left", scope: "col", text: "Judge" }),
      el("th", { scope: "col", text: "Verdict files" }),
      el("th", { scope: "col", text: "Expected pairs" }),
      el("th", { scope: "col", text: "Unjudged" }),
      el("th", { scope: "col", text: "Not scorable" }),
      el("th", { scope: "col", text: "Pairs scored" })
    ])]));
    var tb = el("tbody");
    c.per_judge.forEach(function (p) {
      var ns = notScorable(p.judge);
      tb.appendChild(el("tr", {}, [
        el("td", { class: "left", text: p.judge }),
        el("td", { class: "num", text: String(p.verdict_files) }),
        el("td", { class: "num", text: String(p.expected_pairs) }),
        el("td", { class: "num", text: String(p.unjudged) }),
        el("td", { class: "num", text: String(ns) }),
        el("td", { class: "num", text: String(p.verdict_files - ns) })
      ]));
    });
    table.appendChild(tb);
    wrap.appendChild(table);
    host.appendChild(wrap);

    if (c.excluded_documents && c.excluded_documents.length) {
      host.appendChild(el("p", { class: "note", text:
        "Documents dropped before judging: " +
        c.excluded_documents.map(function (x) {
          return x.task + "/" + x.condition + " (" + x.why + ")";
        }).join(", ") +
        ". Every pair touching a dropped document leaves both the numerator and the denominator." }));
    }
    host.appendChild(el("p", { class: "note", text: c.note || "" }));
  }

  // --- pre-registered outcomes --------------------------------------------

  function renderPrereg() {
    var b = state.batch;
    $("prereg-lede").textContent =
      "Only these comparisons were frozen before generation, in " + b.suite.preregistration +
      ". Everything else on this page is secondary or exploratory and is labelled as such.";

    var host = $("prereg-body");
    clear(host);

    b.preregistered.forEach(function (cmp) {
      var card = el("div", { class: "card" });
      card.appendChild(el("h3", { text: cmp.primary ? "Primary comparison" : "Secondary confirmatory" }));
      card.appendChild(el("p", { class: "sub", text: cmp.label }));

      if (cmp.sign_test) {
        var st = cmp.sign_test;
        var words = {
          "helps": cmp.treatment + " helps",
          "directional": "Directionally positive, underpowered",
          "no-evidence": "No evidence"
        };
        card.appendChild(el("p", {
          class: "big " + (st.outcome === "helps" ? "ok" : "no"),
          text: words[st.outcome] || st.outcome
        }));
        card.appendChild(el("p", { class: "sub", text:
          st.wins + "/" + st.tasks + " decisive wins for the primary judge (" + st.judge +
          "). The frozen rule calls " + st.threshold_helps + "/" + st.prereg_n +
          " a result and " + st.threshold_directional + "–" + (st.threshold_helps - 1) +
          "/" + st.prereg_n + " directional." }));
        if (st.n_caveat) {
          card.appendChild(el("p", { class: "sub", text:
            "Caveat: the thresholds were frozen for N=" + st.prereg_n + " tasks and this batch has " +
            st.tasks + ". They are applied as absolute win counts, so read the verdict as indicative." }));
        }
        if (st.missing_caveat) {
          card.appendChild(el("p", { class: "sub", text:
            "Caveat: some tasks have no verdict for this pair. Missing verdicts count as neither win nor " +
            "loss, which makes the sign test conservative rather than neutral." }));
        }
      } else {
        card.appendChild(el("p", { class: "sub", text:
          "Reported per judge without a decision rule — the frozen sign test applies to the primary comparison only." }));
      }

      var t = el("table");
      t.appendChild(el("thead", {}, [el("tr", {}, [
        el("th", { class: "left", text: "Judge" }),
        el("th", { text: cmp.treatment + " wins" }),
        el("th", { text: cmp.baseline + " wins" }),
        el("th", { text: "Non-dec." }),
        el("th", { text: "Missing" })
      ])]));
      var tb = el("tbody");
      cmp.per_judge.forEach(function (p) {
        tb.appendChild(el("tr", {}, [
          el("td", { class: "left", text: p.judge + (p.judge === b.suite.primary_judge ? " ★" : "") }),
          el("td", { class: "num", text: String(p.treatment_wins) }),
          el("td", { class: "num", text: String(p.baseline_wins) }),
          el("td", { class: "num", text: String(p.non_decisive) }),
          el("td", { class: "num", text: String(p.missing) })
        ]));
      });
      t.appendChild(tb);
      card.appendChild(el("div", { class: "scroll-x" }, [t]));
      host.appendChild(card);
    });
  }

  // --- scatter -------------------------------------------------------------

  function niceCeil(v) {
    if (v <= 0) { return 1; }
    var mag = Math.pow(10, Math.floor(Math.log10(v)));
    var n = v / mag;
    var step = n <= 1 ? 1 : n <= 2 ? 2 : n <= 5 ? 5 : 10;
    return step * mag;
  }

  function svgEl(tag, attrs) {
    var node = document.createElementNS("http://www.w3.org/2000/svg", tag);
    Object.keys(attrs || {}).forEach(function (k) {
      if (k === "text") { node.textContent = attrs[k]; }
      else { node.setAttribute(k, attrs[k]); }
    });
    return node;
  }

  function renderChart() {
    var b = state.batch;
    var host = $("scatter");
    clear(host);

    var shown = judgesShown();
    $("chart-lede").textContent =
      b.metric.axis_label + " against " + b.cost.axis_label +
      ". One point per condition, for " +
      (shown.length === 1 ? "judge " + shown[0] : "each of the " + shown.length + " judges") +
      ". Up and to the left is better value: more wins for less spend.";

    // Layout in a fixed user-space box; the SVG scales to the container.
    var W = 900, H = 460;
    var m = { t: 18, r: 20, b: 56, l: 62 };
    var iw = W - m.l - m.r, ih = H - m.t - m.b;

    var points = [];
    b.conditions.forEach(function (c) {
      shown.forEach(function (j) {
        var s = scoreOf(c, j);
        if (s === null) { return; }
        points.push({ cond: c.id, label: c.label, judge: j, x: c.captured_cost_usd, y: s });
      });
    });

    var maxCost = niceCeil(Math.max.apply(null, points.map(function (p) { return p.x; }).concat([0.01])) * 1.08);
    var yMin = b.metric.min, yMax = b.metric.max;

    function px(v) { return m.l + (v / maxCost) * iw; }
    function py(v) { return m.t + ih - ((v - yMin) / (yMax - yMin)) * ih; }

    var svg = svgEl("svg", {
      viewBox: "0 0 " + W + " " + H,
      preserveAspectRatio: "xMidYMid meet",
      role: "presentation"
    });

    // Grid and y axis.
    var ySteps = 5;
    for (var i = 0; i <= ySteps; i++) {
      var yv = yMin + (yMax - yMin) * (i / ySteps);
      var y = py(yv);
      svg.appendChild(svgEl("line", {
        x1: m.l, x2: m.l + iw, y1: y, y2: y,
        stroke: "var(--rule)", "stroke-width": 1
      }));
      svg.appendChild(svgEl("text", {
        x: m.l - 10, y: y + 4, "text-anchor": "end",
        fill: "var(--ink-faint)", "font-size": 12, text: Math.round(yv) + "%"
      }));
    }

    // Parity line: the value at which a condition is level with the field.
    if (b.metric.parity !== null && b.metric.parity !== undefined) {
      var py0 = py(b.metric.parity);
      svg.appendChild(svgEl("line", {
        x1: m.l, x2: m.l + iw, y1: py0, y2: py0,
        stroke: "var(--ink-faint)", "stroke-width": 1.5, "stroke-dasharray": "6 5"
      }));
      svg.appendChild(svgEl("text", {
        x: m.l + iw - 4, y: py0 - 7, "text-anchor": "end",
        fill: "var(--ink-faint)", "font-size": 11,
        text: "parity (" + b.metric.parity + "%)"
      }));
    }

    // X axis.
    var xSteps = 4;
    for (var k = 0; k <= xSteps; k++) {
      var xv = maxCost * (k / xSteps);
      var x = px(xv);
      svg.appendChild(svgEl("line", {
        x1: x, x2: x, y1: m.t, y2: m.t + ih,
        stroke: "var(--rule)", "stroke-width": 1
      }));
      svg.appendChild(svgEl("text", {
        x: x, y: m.t + ih + 20, "text-anchor": "middle",
        fill: "var(--ink-faint)", "font-size": 12, text: "$" + xv.toFixed(xv < 10 ? 1 : 0)
      }));
    }

    svg.appendChild(svgEl("text", {
      x: m.l + iw / 2, y: H - 12, "text-anchor": "middle",
      fill: "var(--ink-soft)", "font-size": 13, text: b.cost.axis_label
    }));
    svg.appendChild(svgEl("text", {
      x: 16, y: m.t + ih / 2, "text-anchor": "middle",
      transform: "rotate(-90 16 " + (m.t + ih / 2) + ")",
      fill: "var(--ink-soft)", "font-size": 13, text: b.metric.axis_label
    }));

    // Points. One marker shape per judge so an overlay stays readable without
    // colour alone carrying the distinction.
    var judgeOrder = b.completeness.judges_with_verdicts;
    points.forEach(function (p) {
      var cx = px(p.x), cy = py(p.y);
      var colour = condColor(p.cond);
      var ji = judgeOrder.indexOf(p.judge);
      var g = svgEl("g", {});
      if (ji === 1) {
        g.appendChild(svgEl("rect", { x: cx - 6, y: cy - 6, width: 12, height: 12,
          fill: colour, stroke: "var(--bg-raised)", "stroke-width": 1.5, rx: 2 }));
      } else if (ji === 2) {
        g.appendChild(svgEl("polygon", {
          points: [cx, cy - 8, cx + 7, cy + 5, cx - 7, cy + 5].join(" "),
          fill: colour, stroke: "var(--bg-raised)", "stroke-width": 1.5 }));
      } else {
        g.appendChild(svgEl("circle", { cx: cx, cy: cy, r: 7,
          fill: colour, stroke: "var(--bg-raised)", "stroke-width": 1.5 }));
      }
      g.appendChild(svgEl("title", { text:
        p.cond + " (" + p.label + ") — judge " + p.judge + ": " +
        fmtScore(p.y) + " win rate at " + fmtUsd(p.x) + " captured cost" }));
      if (shown.length === 1) {
        g.appendChild(svgEl("text", {
          x: cx + 12, y: cy + 4, fill: "var(--ink)", "font-size": 13,
          "font-weight": 600, text: p.cond
        }));
      }
      svg.appendChild(g);
    });

    host.appendChild(svg);

    var legend = $("chart-legend");
    clear(legend);
    b.conditions.forEach(function (c) {
      legend.appendChild(el("span", { class: "key" }, [
        el("span", { class: "swatch", style: "background:" + condColor(c.id) }),
        el("span", { text: c.id + " · " + c.label })
      ]));
    });
    if (shown.length > 1) {
      var shapes = ["circle", "square", "triangle"];
      legend.appendChild(el("span", { class: "key", text:
        "Marker = judge: " + judgeOrder.map(function (j, i) {
          return j + " " + (shapes[i] || "dot");
        }).join(", ") }));
    }
  }

  // --- leaderboard ---------------------------------------------------------

  var COLUMNS = [
    { key: "id",      label: "Cond",        align: "left", get: function (c) { return c.id; } },
    { key: "label",   label: "Treatment",   align: "left", get: function (c) { return c.label; } },
    { key: "models",  label: "Models",      align: "left", sortable: false,
      get: function (c) { return (c.models || []).join(" + "); } },
    { key: "score",   label: "Win rate",    get: function (c) { return scoreOf(c, focusJudge()); },
      fmt: fmtScore },
    { key: "bt",      label: "Bradley-Terry",
      get: function (c) { var p = c.per_judge[focusJudge()]; return p ? p.bt_strength : null; },
      fmt: function (v) { return v === null ? "—" : fmtNum(v, 4); } },
    { key: "wins",    label: "Wins",
      get: function (c) { var p = c.per_judge[focusJudge()]; return p ? p.wins : null; },
      fmt: function (v) { return v === null ? "—" : fmtNum(v, 1); } },
    { key: "comps",   label: "Comparisons",
      get: function (c) { var p = c.per_judge[focusJudge()]; return p ? p.comparisons : null; },
      fmt: function (v) { return v === null ? "—" : String(v); } },
    { key: "ties",    label: "Ties",
      get: function (c) { var p = c.per_judge[focusJudge()]; return p ? p.ties : null; },
      fmt: function (v) { return v === null ? "—" : String(v); } },
    { key: "posbias", label: "Pos-biased",
      get: function (c) { var p = c.per_judge[focusJudge()]; return p ? p.position_biased : null; },
      fmt: function (v) { return v === null ? "—" : String(v); } },
    { key: "dropped", label: "Excluded",
      get: function (c) { var p = c.per_judge[focusJudge()]; return p ? p.excluded : null; },
      fmt: function (v) { return v === null ? "—" : String(v); } },
    { key: "missing", label: "Missing",
      get: function (c) { var p = c.per_judge[focusJudge()]; return p ? p.missing : null; },
      fmt: function (v) { return v === null ? "—" : String(v); } },
    { key: "wall",    label: "Mean wall s", get: function (c) { return c.mean_wall_secs; },
      fmt: function (v) { return String(v) + "s"; } },
    { key: "cost",    label: "Captured cost", get: function (c) { return c.captured_cost_usd; },
      fmt: fmtUsd }
  ];

  function renderBoard() {
    var b = state.batch;
    var jf = focusJudge();

    $("leaderboard-lede").textContent =
      (state.judge === ALL_JUDGES
        ? "Per-judge columns show the primary judge (" + jf + "), because with every judge on screen there is no single value to show. Switch the judge selector to read another judge's numbers."
        : "Per-judge columns show judge " + jf + ".") +
      " Cost and wall time are judge-independent.";

    $("metric-rubric").textContent = b.metric.label + " — " + b.metric.rubric + " " + b.metric.note +
      "  " + b.cost.label + " — " + b.cost.note;

    var head = $("board-head");
    clear(head);
    COLUMNS.forEach(function (col) {
      var th = el("th", { class: col.align === "left" ? "left" : "num", scope: "col" });
      if (col.sortable === false) {
        th.appendChild(document.createTextNode(col.label));
      } else {
        th.setAttribute("aria-sort",
          state.sort.key === col.key ? (state.sort.dir === "asc" ? "ascending" : "descending") : "none");
        var btn = el("button", { type: "button", text: col.label });
        btn.addEventListener("click", function () {
          if (state.sort.key === col.key) {
            state.sort.dir = state.sort.dir === "asc" ? "desc" : "asc";
          } else {
            state.sort.key = col.key;
            state.sort.dir = col.align === "left" ? "asc" : "desc";
          }
          renderBoard();
        });
        th.appendChild(btn);
      }
      head.appendChild(th);
    });

    var col = COLUMNS.filter(function (c) { return c.key === state.sort.key; })[0] || COLUMNS[3];
    var rows = b.conditions.slice().sort(function (a, z) {
      var av = col.get(a), zv = col.get(z);
      if (av === null || av === undefined) { return 1; }
      if (zv === null || zv === undefined) { return -1; }
      var cmp = typeof av === "string" ? av.localeCompare(zv) : (av - zv);
      return state.sort.dir === "asc" ? cmp : -cmp;
    });

    var body = $("board-body");
    clear(body);
    rows.forEach(function (c) {
      var tr = el("tr");
      COLUMNS.forEach(function (cl) {
        var v = cl.get(c);
        var text = cl.fmt ? cl.fmt(v) : String(v);
        if (cl.key === "id") {
          var td = el("td", { class: "left" });
          td.appendChild(el("span", { class: "chip", style: "background:" + condColor(c.id), text: c.id }));
          td.setAttribute("title", c.description || "");
          tr.appendChild(td);
        } else if (cl.key === "models") {
          tr.appendChild(el("td", { class: "left models", text: text }));
        } else if (cl.align === "left") {
          tr.appendChild(el("td", { class: "left", text: text, title: c.description || "" }));
        } else {
          tr.appendChild(el("td", { class: "num", text: text }));
        }
      });
      body.appendChild(tr);
    });
  }

  // --- judge integrity -----------------------------------------------------

  function renderJudges() {
    var b = state.batch;
    var head = $("integrity-head");
    clear(head);
    ["Judge", "Model", "Pairs", "Decisive", "Ties", "Pos-biased", "Invalid evidence",
     "Sanitize-leak", "Longer doc won"].forEach(function (h, i) {
      head.appendChild(el("th", { class: i < 2 ? "left" : "num", scope: "col", text: h }));
    });

    var body = $("integrity-body");
    clear(body);
    b.integrity.forEach(function (row) {
      var lb = b.length_bias.filter(function (l) { return l.judge === row.judge; })[0];
      var meta = b.suite.judges.filter(function (j) { return j.id === row.judge; })[0] || {};
      var rate = lb && lb.comparable_decisive
        ? Math.round(100 * lb.longer_won / lb.comparable_decisive) + "%"
        : "—";
      body.appendChild(el("tr", {}, [
        el("td", { class: "left", text: row.judge + (row.judge === b.suite.primary_judge ? " ★" : "") }),
        el("td", { class: "left models", text: meta.model || "—" }),
        el("td", { class: "num", text: String(row.pairs) }),
        el("td", { class: "num", text: String(row.decisive) }),
        el("td", { class: "num", text: String(row.ties) }),
        el("td", { class: "num", text: String(row.position_biased) }),
        el("td", { class: "num", text: String(row.invalid_evidence) }),
        el("td", { class: "num", text: String(row.sanitize_leak) }),
        el("td", { class: "num", text: rate + (lb ? " (" + lb.longer_won + "/" + lb.comparable_decisive + ")" : "") })
      ]));
    });

    var host = $("agreement-body");
    clear(host);
    var ag = b.agreement;
    var pct = function (n) { return ag.comparable_pairs ? Math.round(100 * n / ag.comparable_pairs) + "%" : "—"; };

    host.appendChild(el("div", { class: "card" }, [
      el("h3", { text: "Cross-judge agreement" }),
      el("p", { class: "big", text: pct(ag.unanimous) }),
      el("p", { class: "sub", text: ag.unanimous + " of " + ag.comparable_pairs +
        " pairs scored by every judge got the same verdict from all of them." })
    ]));
    host.appendChild(el("div", { class: "card" }, [
      el("h3", { text: "Unanimous and decisive" }),
      el("p", { class: "big", text: pct(ag.unanimous_decisive) }),
      el("p", { class: "sub", text: ag.unanimous_decisive + " pairs where every judge picked the same " +
        "winner rather than agreeing it was a tie. Unanimous decisive agreement across vendors is the " +
        "strongest signal this batch can produce." })
    ]));
    host.appendChild(el("div", { class: "card" }, [
      el("h3", { text: "Length bias" }),
      el("p", { class: "sub", text: "A judge that picks the longer document about half the time is " +
        "judging on quality; a rate well above 50% means length is doing the work. Pairs whose two " +
        "documents have the same word count are out of the denominator." })
    ]));
  }

  // --- task drill-down -----------------------------------------------------

  function renderTaskPicker() {
    var sel = $("task-select");
    clear(sel);
    state.batch.tasks.forEach(function (t) {
      sel.appendChild(el("option", { value: t.id, text: t.id + " · " + t.difficulty }));
    });
    if (!state.task || !state.batch.tasks.some(function (t) { return t.id === state.task; })) {
      state.task = state.batch.tasks.length ? state.batch.tasks[0].id : null;
    }
    sel.value = state.task;
  }

  function verdictCell(v, pair) {
    if (!v || v.outcome === "missing") {
      return el("span", { class: "verdict drop", text: "missing" });
    }
    if (v.outcome === "decisive") {
      return el("span", {
        class: "verdict win",
        style: "background:" + condColor(v.winner),
        text: v.winner + " wins"
      });
    }
    if (v.outcome === "tie") { return el("span", { class: "verdict tie", text: "tie ½–½" }); }
    if (v.outcome === "position_biased") {
      return el("span", { class: "verdict tie", title:
        "The two position-swapped trials disagreed, so the pair makes no quality claim and scores half a win each.",
        text: "position-biased" });
    }
    return el("span", { class: "verdict drop", title:
      "Excluded from win counts entirely.", text: v.outcome });
  }

  function renderTask() {
    var b = state.batch;
    $("tasks-lede").textContent =
      "Every pair of conditions on one task, as each judge scored it. Task ids and difficulty are " +
      "published; the task prompts and the generated plans are not.";

    var t = b.tasks.filter(function (x) { return x.id === state.task; })[0];
    var host = $("task-body");
    clear(host);
    if (!t) { return; }

    // Per-cell process stats for this task.
    var cellWrap = el("div", { class: "scroll-x" });
    var ct = el("table");
    ct.appendChild(el("thead", {}, [el("tr", {}, [
      el("th", { class: "left", scope: "col", text: "Condition" }),
      el("th", { scope: "col", text: "Status" }),
      el("th", { scope: "col", text: "Words" }),
      el("th", { scope: "col", text: "Wall s" }),
      el("th", { scope: "col", text: "Convergence" }),
      el("th", { scope: "col", text: "Captured cost" })
    ])]));
    var ctb = el("tbody");
    b.completeness.condition_ids.forEach(function (cid) {
      var cell = t.cells[cid];
      ctb.appendChild(el("tr", {}, [
        el("td", { class: "left" }, [el("span", { class: "chip", style: "background:" + condColor(cid), text: cid })]),
        el("td", { class: "num", text: cell ? cell.status + (cell.degraded ? " (degraded)" : "") : "—" }),
        el("td", { class: "num", text: cell ? String(cell.words) : "—" }),
        el("td", { class: "num", text: cell ? String(cell.wall_secs) + "s" : "—" }),
        el("td", { class: "num", text: cell && cell.convergence_status ? cell.convergence_status : "—" }),
        el("td", { class: "num", text: cell ? fmtUsd(cell.cost_usd) : "—" })
      ]));
    });
    ct.appendChild(ctb);
    cellWrap.appendChild(ct);
    host.appendChild(el("h3", { text: "Cells" }));
    host.appendChild(cellWrap);

    // Pair verdicts, one column per judge.
    var judges = b.completeness.judges_with_verdicts;
    var pw = el("div", { class: "scroll-x" });
    var pt = el("table");
    var hr = el("tr", {}, [el("th", { class: "left", scope: "col", text: "Pair" })]);
    judges.forEach(function (j) {
      hr.appendChild(el("th", { class: "left", scope: "col",
        text: j + (j === b.suite.primary_judge ? " ★" : "") }));
    });
    hr.appendChild(el("th", { scope: "col", text: "Words" }));
    pt.appendChild(el("thead", {}, [hr]));

    var ptb = el("tbody");
    t.pairs.forEach(function (p) {
      var tr = el("tr", {}, [el("td", { class: "left", text: p.x + " vs " + p.y })]);
      judges.forEach(function (j) {
        var td = el("td", { class: "left" });
        td.appendChild(verdictCell(p.judges[j], p));
        tr.appendChild(td);
      });
      var any = judges.map(function (j) { return p.judges[j]; })
                      .filter(function (v) { return v && v.words_x !== undefined; })[0];
      tr.appendChild(el("td", { class: "num",
        text: any ? any.words_x + " / " + any.words_y : "—" }));
      ptb.appendChild(tr);
    });
    pt.appendChild(ptb);
    pw.appendChild(pt);
    host.appendChild(el("h3", { text: "Pair verdicts" }));
    host.appendChild(pw);
    host.appendChild(el("p", { class: "note", text:
      "★ marks the primary judge. A tie or a position-biased pair scores half a win to each side; " +
      "an invalid-evidence or sanitize-leak pair is excluded from win counts entirely." }));
  }

  // --- method --------------------------------------------------------------

  function renderMethod() {
    var b = state.batch;
    var host = $("method-body");
    clear(host);
    var points = [
      ["The metric", b.metric.rubric],
      ["The cost axis", b.cost.note],
      ["Judges are never merged", b.metric.note + " No judge on this batch is neutral on style: two of " +
        "the three share a vendor with a condition under test, in opposite directions. Divergence between " +
        "them is reported as divergence, not averaged away."],
      ["What is pre-registered", "Only the comparisons in the pre-registered section were frozen before " +
        "generation. The leaderboard, the Bradley-Terry column, the length-bias check and the per-task " +
        "drill-down are secondary or exploratory, and none of them carries a confidence interval — " +
        "with " + b.completeness.tasks + " tasks none would be meaningful."],
      ["What this evidence is", "Selected tasks scored by automated judges produce exploratory " +
        "directional evidence. It is not proof, and a general claim about cross-AI bouncing needs a " +
        "larger held-out replication."],
      ["What is published", "Scores, costs, model and condition names, judge tallies, and task ids and " +
        "difficulty. Task prompts, generated plans, judge reasoning and transcripts are not published."]
    ];
    var dl = el("div", { class: "cards" });
    points.forEach(function (pair) {
      dl.appendChild(el("div", { class: "card" }, [
        el("h3", { text: pair[0] }),
        el("p", { class: "sub", text: pair[1] })
      ]));
    });
    host.appendChild(dl);
  }

  // --- wiring --------------------------------------------------------------

  function renderAll() {
    renderHeader();
    renderCoverage();
    renderPrereg();
    renderChart();
    renderBoard();
    renderJudges();
    renderTaskPicker();
    renderTask();
    renderMethod();
  }

  function fillJudgeSelect() {
    var sel = $("judge-select");
    clear(sel);
    var js = state.batch.completeness.judges_with_verdicts;
    js.forEach(function (j) {
      sel.appendChild(el("option", { value: j,
        text: j + (j === state.batch.suite.primary_judge ? " (primary)" : "") }));
    });
    if (js.length > 1) {
      sel.appendChild(el("option", { value: ALL_JUDGES, text: "All judges, side by side" }));
    }
    if (!state.judge || js.indexOf(state.judge) === -1) {
      if (state.judge !== ALL_JUDGES) { state.judge = state.batch.suite.primary_judge; }
    }
    sel.value = state.judge;
  }

  function loadBatch(id) {
    var entry = state.index.batches.filter(function (b) { return b.batch === id; })[0];
    if (!entry) { return Promise.reject(new Error("unknown batch " + id)); }
    return fetch(entry.file, { cache: "no-cache" })
      .then(function (r) {
        if (!r.ok) { throw new Error(entry.file + ": HTTP " + r.status); }
        return r.json();
      })
      .then(function (data) {
        state.batch = data;
        state.task = null;
        fillJudgeSelect();
        renderAll();
        try { history.replaceState(null, "", "#" + id); } catch (e) { /* file:// */ }
      });
  }

  function fatal(msg) {
    var main = $("main");
    clear(main);
    main.appendChild(el("div", { class: "callout warn" }, [
      el("p", { html: "<strong>Could not load the results data.</strong>" }),
      el("p", { text: msg }),
      el("p", { text: "The page fetches data/index.json, so it needs to be served over HTTP. " +
        "Opening index.html straight from the filesystem will not work: run a static server from " +
        "the docs/ folder instead." })
    ]));
  }

  function init() {
    initTheme();

    $("batch-select").addEventListener("change", function (e) {
      loadBatch(e.target.value).catch(function (err) { fatal(String(err.message || err)); });
    });
    $("judge-select").addEventListener("change", function (e) {
      state.judge = e.target.value;
      renderChart();
      renderBoard();
    });
    $("task-select").addEventListener("change", function (e) {
      state.task = e.target.value;
      renderTask();
    });

    fetch("data/index.json", { cache: "no-cache" })
      .then(function (r) {
        if (!r.ok) { throw new Error("data/index.json: HTTP " + r.status); }
        return r.json();
      })
      .then(function (index) {
        state.index = index;
        if (!index.batches || !index.batches.length) { throw new Error("the index lists no batches"); }
        var sel = $("batch-select");
        clear(sel);
        index.batches.forEach(function (b) {
          sel.appendChild(el("option", { value: b.batch,
            text: b.batch + " · " + b.tasks + " tasks · " + fmtDate(b.generated_at) }));
        });
        var wanted = (location.hash || "").replace(/^#/, "");
        var pick = index.batches.some(function (b) { return b.batch === wanted; })
          ? wanted
          : (index.default_batch || index.batches[0].batch);
        sel.value = pick;
        return loadBatch(pick);
      })
      .catch(function (err) { fatal(String(err.message || err)); });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
