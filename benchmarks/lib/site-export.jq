# benchmarks/lib/site-export.jq — assemble one batch's site data file.
#
# Called only by benchmarks/export-site-data.sh, which feeds it eight TSV
# --rawfile inputs built from run artifacts. Split out of that script because a
# jq program this size embedded in a heredoc is unreadable and unlintable.
#
# Accounting is PREREGISTRATION.md section 4 throughout: a win is 1, a tie or a
# position-biased pair is 0.5 each side, and invalid-evidence / sanitize-leak
# pairs leave both the numerator and the denominator. Win/comparison totals and
# Bradley-Terry strengths arrive precomputed in matrix_tsv / bt_tsv from the
# same awk report.sh uses, so the two agree by construction, not by review.
#
# Lookup keys join their parts with "/" — condition ids are constrained to
# [A-Za-z0-9_-] by run-benchmark.sh and task ids are directory names, so no key
# part can contain the separator and no two keys can collide.

def tsv($s):
  $s | rtrimstr("\n")
     | if length == 0 then [] else split("\n") | map(select(length > 0) | split("\t")) end;
def num: (. // "") | tonumber? // 0;
def r2: (. * 100 | round) / 100;
def r4: (. * 10000 | round) / 10000;
def pairkey($p; $q): [$p, $q] | sort | join("/");

# Verdicts are stored once per unordered pair, so every read has to tolerate the
# stored orientation being the reverse of the one being asked about.
def rowat($ix; $j; $t; $p; $q): $ix[$j][$t + "/" + pairkey($p; $q)];

# oriented: name the winning condition, or pass the non-decisive verdict through
# unchanged ("tie", "position_biased", "invalid-evidence", "sanitize-leak").
def oriented($r):
  if   $r == null        then "missing"
  elif $r.verdict == "x" then $r.x
  elif $r.verdict == "y" then $r.y
  else $r.verdict end;

(tsv($tasks_tsv) | map({ id: .[0], difficulty: (.[1] // "unknown") }))            as $tasks
| ($tasks | map(.id))                                                             as $task_ids
| (tsv($conds_tsv) | map({
      id: .[0], label: (.[1] // .[0]), kind: (.[2] // ""),
      glm_calls_per_run: (.[3] | num),
      seats:  ((.[4] // "") | split("|") | map(select(length > 0))),
      models: ((.[5] // "") | split("|") | map(select(length > 0))),
      description: (.[6] // "") }))                                               as $conds
| ($conds | map(.id))                                                             as $cond_ids
| (tsv($judges_tsv) | map({
      id: .[0], model: (.[1] // ""), cli_version: (.[2] // ""),
      effort: (.[3] // ""), model_assert: (.[4] // "") }))                        as $judges
| ($judges | map(.id))                                                            as $judge_ids
| (tsv($rows_tsv) | map({
      judge: .[0], task: .[1], x: .[2], y: .[3], verdict: .[4],
      words_x: (.[5] | num), words_y: (.[6] | num),
      confidence_pair: (.[7] // ""),
      evidence_verified: ((.[8] // "false") == "true") }))                        as $rows
| (tsv($matrix_tsv) | map({ judge: .[0], a: .[1], b: .[2], wins: (.[3] | num), n: (.[4] | num) })) as $matrix
| (tsv($bt_tsv)     | map({ judge: .[0], cond: .[1], strength: (.[2] | num), total_wins: (.[3] | num) })) as $bt
| (tsv($cells_tsv) | map({
      task: .[0], cond: .[1], status: .[2], degraded: (.[3] == "true"),
      words: (.[4] | num), wall_secs: (.[5] | num), glm_calls: (.[6] | num),
      convergence_status: (if (.[7] // "") == "" then null else .[7] end),
      cost_usd: (.[8] | num) }))                                                  as $cells
| (tsv($excluded_tsv) | map({ task: .[0], condition: .[1], why: .[2] }))          as $excluded

# --- lookup indexes ----------------------------------------------------------

| ($rows | group_by(.judge)
        | map({ key: .[0].judge,
                value: (map({ key: (.task + "/" + pairkey(.x; .y)), value: . }) | from_entries) })
        | from_entries)                                                           as $row_ix
| ($matrix | map({ key: (.judge + "/" + .a + "/" + .b), value: . }) | from_entries) as $mat_ix
| ($bt     | map({ key: (.judge + "/" + .cond), value: . }) | from_entries)        as $bt_ix
| ($cells  | map({ key: (.task  + "/" + .cond), value: . }) | from_entries)        as $cell_ix

# --- per-judge condition scores ----------------------------------------------
# score = total wins / total scored comparisons, as a percentage. The
# denominator is the win matrix's N, which already drops leaked and invalid
# pairs, so this is the fraction report.sh section 2 prints per matrix cell.

| ( [ $judge_ids[] as $j
      | $cond_ids[] as $c
      | ([ $matrix[] | select(.judge == $j and .a == $c) ])                       as $mrows
      | (($mrows | map(.wins) | add) // 0)                                        as $wins
      | (($mrows | map(.n)    | add) // 0)                                        as $n
      | ([ $rows[] | select(.judge == $j and (.x == $c or .y == $c)) ])           as $prs
      | { key: ($j + "/" + $c),
          value: {
            wins: ($wins | r2),
            comparisons: $n,
            score: (if $n > 0 then (100 * $wins / $n | r2) else null end),
            bt_strength: ($bt_ix[$j + "/" + $c].strength // null),
            decisive_wins:   ([ $prs[] | select((.verdict == "x" and .x == $c) or (.verdict == "y" and .y == $c)) ] | length),
            decisive_losses: ([ $prs[] | select((.verdict == "x" and .y == $c) or (.verdict == "y" and .x == $c)) ] | length),
            ties:            ([ $prs[] | select(.verdict == "tie") ] | length),
            position_biased: ([ $prs[] | select(.verdict == "position_biased") ] | length),
            excluded:        ([ $prs[] | select(.verdict == "invalid-evidence" or .verdict == "sanitize-leak") ] | length),
            missing: ((($cond_ids | length) - 1) * ($task_ids | length) - ($prs | length)),
            vs: ( [ $cond_ids[] as $o
                    | select($o != $c)
                    | ($mat_ix[$j + "/" + $c + "/" + $o]) as $m
                    | { key: $o,
                        value: (if ($m != null and $m.n > 0)
                                then { wins: ($m.wins | r2), n: $m.n, rate: (100 * $m.wins / $m.n | r2) }
                                else { wins: 0, n: 0, rate: null } end) } ]
                  | from_entries )
          } } ] | from_entries )                                                  as $scores

# --- pre-registered comparisons ----------------------------------------------

| ( [ { p: "B", q: "A", primary: true,
        label: "Primary: B (cross-vendor bounce) vs A (solo)" },
      { p: "B", q: "D", primary: false,
        label: "Secondary confirmatory: B (cross-vendor bounce) vs D (self-bounce)" } ]
    | map( . as $cmp
      | select(($cond_ids | index($cmp.p)) != null and ($cond_ids | index($cmp.q)) != null)
      | ( [ $judge_ids[] as $j
            | ([ $task_ids[] as $t | oriented(rowat($row_ix; $j; $t; $cmp.p; $cmp.q)) ]) as $vs
            | { judge: $j,
                treatment_wins: ([ $vs[] | select(. == $cmp.p) ] | length),
                baseline_wins:  ([ $vs[] | select(. == $cmp.q) ] | length),
                non_decisive:   ([ $vs[] | select(. != $cmp.p and . != $cmp.q and . != "missing") ] | length),
                missing:        ([ $vs[] | select(. == "missing") ] | length) } ] ) as $tallies
      | ( [ $tasks[] as $t
            | { task: $t.id, difficulty: $t.difficulty,
                verdict: oriented(rowat($row_ix; $primary; $t.id; $cmp.p; $cmp.q)) } ] ) as $per_task
      | ( $tallies | map(select(.judge == $primary)) | .[0] ) as $pt
      | { treatment: $cmp.p, baseline: $cmp.q, label: $cmp.label, primary: $cmp.primary,
          per_judge: $tallies,
          per_task: $per_task,
          per_difficulty: ( $per_task | group_by(.difficulty)
                            | map({ difficulty: .[0].difficulty, tasks: length,
                                    treatment_wins: ([ .[] | select(.verdict == $cmp.p) ] | length),
                                    baseline_wins:  ([ .[] | select(.verdict == $cmp.q) ] | length),
                                    other: ([ .[] | select(.verdict != $cmp.p and .verdict != $cmp.q) ] | length) }) ),
          sign_test: (if ($cmp.primary and $pt != null) then
              { judge: $primary, wins: $pt.treatment_wins, tasks: ($task_ids | length),
                threshold_helps: $prereg_helps, threshold_directional: $prereg_dir,
                prereg_n: $prereg_n,
                outcome: (if   $pt.treatment_wins >= $prereg_helps then "helps"
                          elif $pt.treatment_wins >= $prereg_dir   then "directional"
                          else "no-evidence" end),
                n_caveat: (($task_ids | length) != $prereg_n),
                missing_caveat: ($pt.missing > 0) }
            else null end) } ) )                                                  as $prereg

# --- integrity, length bias, cross-judge agreement ---------------------------

| ( [ $judge_ids[] as $j
      | ([ $rows[] | select(.judge == $j) ]) as $rs
      | { judge: $j, pairs: ($rs | length),
          decisive:         ([ $rs[] | select(.verdict == "x" or .verdict == "y") ] | length),
          ties:             ([ $rs[] | select(.verdict == "tie") ] | length),
          position_biased:  ([ $rs[] | select(.verdict == "position_biased") ] | length),
          invalid_evidence: ([ $rs[] | select(.verdict == "invalid-evidence") ] | length),
          sanitize_leak:    ([ $rs[] | select(.verdict == "sanitize-leak") ] | length) } ] ) as $integrity
| ( [ $judge_ids[] as $j
      | ([ $rows[] | select(.judge == $j and (.verdict == "x" or .verdict == "y")
                            and .words_x > 0 and .words_y > 0 and .words_x != .words_y) ]) as $rs
      | { judge: $j,
          longer_won: ([ $rs[] | select((.verdict == "x" and .words_x > .words_y)
                                     or (.verdict == "y" and .words_y > .words_x)) ] | length),
          comparable_decisive: ($rs | length) } ] )                                as $length_bias
| ( [ $task_ids[] as $t
      | range(0; $cond_ids | length) as $i
      | range($i + 1; $cond_ids | length) as $k
      | { p: $cond_ids[$i], q: $cond_ids[$k] } as $pair
      | ([ $judge_ids[] as $j | oriented(rowat($row_ix; $j; $t; $pair.p; $pair.q)) ]) as $vs
      | select(($vs | index("missing")) == null)
      | { unanimous: (($vs | unique | length) == 1),
          decisive: (all($vs[]; . == $pair.p or . == $pair.q)) } ] )               as $agree_rows

# --- completeness ------------------------------------------------------------

| ( [ $cells[] | select(.status != "complete") | { cell: (.task + "/" + .cond), status: .status } ] ) as $incomplete
| ( [ $cells[] | select(.degraded) | (.task + "/" + .cond) ] )                     as $degraded
| ( (($task_ids | length) * ($cond_ids | length) * (($cond_ids | length) - 1) / 2) | floor ) as $expected_pairs

# --- output ------------------------------------------------------------------

| { schema: "bench-site/1.0",
    batch: $batch,
    generated_at: $generated_at,
    suite: {
      id: "plan-composition",
      title: "Co-Evolution Plan Benchmark",
      summary: "Four plan-composition conditions run on identical planning tasks, scored by three blind automated judges in position-swapped pairwise trials.",
      primary_judge: $primary,
      preregistration: "benchmarks/PREREGISTRATION.md",
      report: ("benchmarks/reports/" + $batch + ".md"),
      judges: $judges
    },
    metric: {
      id: "win_rate",
      label: "Win rate",
      axis_label: "Win rate (%)",
      unit: "percent",
      min: 0, max: 100, parity: 50,
      higher_is_better: true,
      per_judge: true,
      rubric: "Pairwise blind A/B judging — the standard rubric for this suite. Every condition meets every other condition on every task, twice per judge with the document order swapped. A win scores 1; a tie or a position-biased pair scores 0.5 to each side (PREREGISTRATION.md section 4); pairs dropped by sanitization or invalid evidence leave both the numerator and the denominator. 50% is parity with the rest of the field, and 100% means the condition won every comparison it was scored on.",
      note: "Reported separately for each judge and never adjudicated into a single score."
    },
    cost: {
      label: "Captured cost (floor)",
      axis_label: "Captured cost (floor), USD",
      unit: "usd",
      note: "Sums every total_cost_usd in each cell's tokens sidecar. Claude reports that field; the direct GLM and Kimi sidecars report tokens without a price, and Codex has no sidecar. The number is therefore a floor, not a total. Judging cost is not included — the judge CLIs run without token capture."
    },
    completeness: {
      tasks: ($task_ids | length),
      task_ids: $task_ids,
      conditions: ($cond_ids | length),
      condition_ids: $cond_ids,
      judges_requested: $judge_ids,
      judges_with_verdicts: [ $judge_ids[] as $j
                              | select([ $rows[] | select(.judge == $j) ] | length > 0) | $j ],
      expected_pairs_per_judge: $expected_pairs,
      generation_cells_complete: (($incomplete | length) == 0),
      incomplete_cells: $incomplete,
      degraded_cells: $degraded,
      excluded_documents: $excluded,
      per_judge: [ $judge_ids[] as $j
                   | ([ $rows[] | select(.judge == $j) ] | length) as $n
                   | { judge: $j, verdict_files: $n, expected_pairs: $expected_pairs,
                       unjudged: ($expected_pairs - $n) } ],
      note: "Expected pairs assumes every condition survives sanitization and no cell is degraded. A nonzero unjudged count means every rate on this page is computed over what exists, not over what was planned."
    },
    conditions: [ $conds[] as $c
      | ([ $cells[] | select(.cond == $c.id) ]) as $cc
      | ($cc | length) as $n
      | $c + {
          cells: $n,
          mean_words:     (if $n > 0 then (($cc | map(.words)     | add) / $n | floor) else 0 end),
          mean_wall_secs: (if $n > 0 then (($cc | map(.wall_secs) | add) / $n | floor) else 0 end),
          converged:   ([ $cc[] | select(.convergence_status == "converged") ]   | length),
          adjudicated: ([ $cc[] | select(.convergence_status == "adjudicated") ] | length),
          stuck:       ([ $cc[] | select(.convergence_status == "stuck") ]       | length),
          glm_calls: (($cc | map(.glm_calls) | add) // 0),
          captured_cost_usd: ((($cc | map(.cost_usd) | add) // 0) | r4),
          per_judge: ( [ $judge_ids[] as $j | { key: $j, value: ($scores[$j + "/" + $c.id] // null) } ]
                       | from_entries )
        } ],
    preregistered: $prereg,
    integrity: $integrity,
    agreement: { comparable_pairs: ($agree_rows | length),
                 unanimous: ([ $agree_rows[] | select(.unanimous) ] | length),
                 unanimous_decisive: ([ $agree_rows[] | select(.unanimous and .decisive) ] | length) },
    length_bias: $length_bias,
    tasks: [ $tasks[] as $t
      | $t + {
          cells: ( [ $cond_ids[] as $c
                     | { key: $c,
                         value: ( ($cell_ix[$t.id + "/" + $c]) as $cell
                                  | if $cell == null then null
                                    else { status: $cell.status, degraded: $cell.degraded,
                                           words: $cell.words, wall_secs: $cell.wall_secs,
                                           glm_calls: $cell.glm_calls,
                                           convergence_status: $cell.convergence_status,
                                           cost_usd: ($cell.cost_usd | r4) } end ) } ]
                   | from_entries ),
          pairs: [ range(0; $cond_ids | length) as $i
                   | range($i + 1; $cond_ids | length) as $k
                   | { x: $cond_ids[$i], y: $cond_ids[$k] } as $pair
                   | { x: $pair.x, y: $pair.y,
                       judges: ( [ $judge_ids[] as $j
                                   | (rowat($row_ix; $j; $t.id; $pair.x; $pair.y)) as $r
                                   | { key: $j,
                                       value: (if $r == null
                                               then { outcome: "missing", winner: null }
                                               else { outcome: (if ($r.verdict == "x" or $r.verdict == "y")
                                                                then "decisive" else $r.verdict end),
                                                      winner: (if   $r.verdict == "x" then $r.x
                                                               elif $r.verdict == "y" then $r.y
                                                               else null end),
                                                      words_x: (if $r.x == $pair.x then $r.words_x else $r.words_y end),
                                                      words_y: (if $r.x == $pair.x then $r.words_y else $r.words_x end),
                                                      confidence: $r.confidence_pair,
                                                      evidence_verified: $r.evidence_verified } end) } ]
                                 | from_entries ) } ] } ]
  }
