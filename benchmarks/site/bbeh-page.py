"""BBEH calibration page using the observatory's existing page shell."""
import html

def render(result,shell):
    esc=html.escape
    protocol=result['title']=='BBEH format and runtime calibration'
    eyebrow='BBEH MINI SUBSET · FORMAT AND RUNTIME SCREEN' if protocol else 'BBEH MINI SUBSET · CALIBRATION ONLY'
    headline='Exact answers.<br>Still incomplete.' if protocol else 'Harder questions.<br>The comparison stopped.'
    content=f'<p class="eyebrow">{eyebrow}</p><h1>{headline}</h1><p>'+esc(result['assessment']['finding'])+'</p><div class="notice"><strong>Calibration gate rejected. Main test not run.</strong> This result measures whether the proposed test is usable. It does not measure a Co-Evolution benefit.</div><h2>Official calibration scores</h2><div class="table-scroll" tabindex="0" role="region" aria-label="Calibration scores"><table><thead><tr><th>Workflow</th><th>Correct / received</th><th>Missing / 12</th><th>Score / 100</th></tr></thead><tbody>'
    labels={'A':'Sonnet original','B':'Sonnet plain revision','E':'Terra alone'}
    for arm,s in result['calibration']['scores'].items():
        score=f'{s["score"]:.1f}' if s['score'] is not None else 'Unavailable<br><small>Bounds 8.3–66.7%</small>'
        content+=f'<tr><th scope="row">{labels[arm]}</th><td>{s["correct"]}/{s["evaluated"]}</td><td>{s["missing"]}</td><td>{score}</td></tr>'
    content+='</tbody></table></div><p>Missing-answer bounds show the range if every missing answer were wrong or correct. They are not confidence intervals. An incomplete Sonnet result is not a 12-question accuracy score.</p><h2>What the evaluation tested</h2>'
    if protocol:
        content+='<p>Four fresh questions each from Multistep Arithmetic, Web of Lies and Hyperbaton formed this replacement calibration. The gate required all 36 answers, 3–9 correct per baseline, and no formatting-only scorer mismatches. Participants returned one exact final-answer line at medium effort. Two Sonnet calls timed out at 180 seconds, and the controller session ended before four active calls settled.</p><p>This was a transport and answer-format test. The review arms were intentionally absent; no Co-Evolution effect was tested.</p><h2>Formatting result</h2><p>The stricter final-answer instruction produced zero formatting-only mismatches among received answers. That resolves the previous bracket issue, but it does not resolve the runtime-completion problem.</p><h2>Compute and stopping</h2>'
    else:
        content+='<p>Four questions each from Multistep Arithmetic, Web of Lies and Hyperbaton formed the calibration. Another eight per family were reserved for the main comparison. The predefined gate required all 36 calibration responses and 3–9 correct answers per baseline, plus sufficient remaining runtime. Seven Sonnet timeouts prevented that gate from passing.</p><p>The planned main comparison would have tested Terra review against Sonnet self-review, plain revision and Terra alone, using shared original answers and an official deterministic scorer. Those review arms were never launched. Both participants used medium effort: claude-sonnet-5 and gpt-5.6-terra.</p><h2>Formatting also affected the result</h2><p>Eight answers match the normalized reference except for surrounding angle brackets, which the official scorer does not accept: three Sonnet originals, three revisions and two Terra answers. The official scores above are unchanged. This diagnostic means the low score cannot be interpreted purely as weak reasoning.</p><h2>Compute and stopping</h2>'
    spend=result['spend']
    content+=f'<p><strong>{spend["calls"]}/220 calls used</strong>: 17 Sonnet and 12 Terra. The controller ran for about six minutes. No conditional main calls were launched. Known list-equivalent cost was ${spend["known_list_equivalent_usd"]:.4f}, with seven calls unpriced; this is an incomplete cost estimate, not a total bill.</p><article id="assessment"><h2>Evaluation of this test</h2>'
    for key,label in [('question','Question'),('test_quality','Checks'),('limitation','Limits'),('decision','Conclusion'),('next_action','Next step')]:
        content+=f'<h3>{label}</h3><p>{esc(result["assessment"][key])}</p>'
    content+='</article><h2>Evidence and provenance</h2><p>This is a selected subset of BBEH Mini, not an official leaderboard submission. Calibration inputs, answers, references, hashes and charged attempts are available in the data download. Unused main answer keys are excluded.</p>'
    content+=f'<p>Official benchmark commit: <code>{esc(result["benchmark"]["commit"])}</code>.</p><p><a href="https://github.com/google-deepmind/bbeh">Official BBEH source ↗</a> · <a href="bbeh-results.json" download>Download results ↓</a> · <a href="evaluations.html#bbeh-compact">All test assessments →</a> · <a href="planbench-sonnet-terra.html">Earlier Sonnet/Terra planning results →</a></p>'
    return shell('Co-Evolution · BBEH calibration and assessment',content)
