"""Validate and render recovered AIME evidence; never invokes a provider."""
import hashlib, html, json, re

def sha(text):
    return hashlib.sha256(text.encode('utf-8')).hexdigest()

def parse(text):
    match=re.fullmatch(r'The final answer is: ([0-9]{1,3})\s*',text)
    return match.group(1).zfill(3) if match else None

def validate(data):
    questions={q['id']:q for q in data['questions']}
    if len(questions)!=6 or len(data['outcomes'])!=18:raise ValueError('AIME coverage mismatch')
    seen=set();counts={a:0 for a in 'ABE'};pairs={}
    for q in questions.values():
        if sha(q['problem'])!=q['sha256']:raise ValueError('AIME question hash mismatch')
        if not re.fullmatch('[0-9]{3}',q['reference']):raise ValueError('AIME invalid reference')
    for row in data['outcomes']:
        ident,arm=row['job'].rsplit('.',1)
        if arm not in counts or ident not in questions or row['job'] in seen:raise ValueError('AIME unexpected outcome')
        seen.add(row['job'])
        if row['status']!='succeeded' or row['tool_calls']!=0:raise ValueError('AIME incomplete or tool-using response')
        if sha(row['text'])!=row['response_sha256']:raise ValueError('AIME response hash mismatch')
        answer=parse(row['text']);correct=answer==questions[ident]['reference']
        if answer is None or answer!=row['parsed_answer'] or correct!=row['correct']:raise ValueError('AIME score mismatch')
        counts[arm]+=int(correct);pairs.setdefault(ident,{})[arm]=correct
    if counts!=data['gate']['correct'] or data['gate']['passed']!=all(1<=n<=5 for n in counts.values()):raise ValueError('AIME gate mismatch')
    for arm,n in counts.items():
        if data['scores'][arm]!=dict(correct=n,total=6,score=100*n/6):raise ValueError('AIME aggregate mismatch')
    expected=dict(n=6,repairs=sum(not p['A'] and p['B'] for p in pairs.values()),regressions=sum(p['A'] and not p['B'] for p in pairs.values()),delta_pp=100*(counts['B']-counts['A'])/6)
    if data['plain_revision']!=expected:raise ValueError('AIME paired comparison mismatch')

def render(data,shell):
    esc=html.escape
    content='<p class="eyebrow">AIME 2024 · SIX-QUESTION CALIBRATION</p><h1>Plain revision reached 100%.</h1><p>'+esc(data['assessment']['finding'])+'</p><div class="notice"><strong>Main comparison not run.</strong> This calibration rejected the test because both plain revision and Terra alone answered every selected question correctly. Co-Evolution’s effect is unmeasured.</div><h2>All 18 answers completed</h2><div class="table-scroll" tabindex="0" role="region" aria-label="AIME baseline scores"><table><thead><tr><th>Workflow</th><th>Correct</th><th>Score</th></tr></thead><tbody>'
    for arm,label in [('A','Sonnet original'),('B','Sonnet plain revision'),('E','Terra alone')]:
        s=data['scores'][arm];content+=f'<tr><th scope="row">{label}</th><td>{s["correct"]}/6</td><td>{s["score"]:.1f}%</td></tr>'
    content+='</tbody></table></div><h2>What changed</h2><p>Plain Sonnet revision fixed one original answer, from 023 to the correct 321. It introduced no regressions: a net gain of one answer, or 16.7 percentage points. This measures plain revision on six questions; it does not measure cross-model review.</p><h2>How the screen worked</h2><p>The saved selection excluded the setup question, sorted the other problem hashes and took six. A and E answered independently; B checked A against the original question. All responses used an exact integer final-answer format. The saved gate required all 18 answers, valid formatting and 1–5 correct per baseline. B and E each reached 6/6, rejecting the main phase.</p><h2>Calls and provenance</h2><p>18 calibration calls completed, plus four calls across two excluded setup attempts: 22 recorded invocations in total. The first setup check rejected missing Terra response-side model metadata; the corrected check accepted the explicitly requested model identity. No additional model calls were made to recover or publish these results. Monetary cost is unavailable because usage and prices were not saved.</p><article id="assessment"><h2>Evaluation of this test</h2>'
    for key,label in [('test_quality','Verification'),('limitation','Limits'),('decision','Conclusion'),('next_action','Next step')]:content+=f'<h3>{label}</h3><p>{esc(data["assessment"][key])}</p>'
    content+='</article><h2>Question-level results</h2><div class="table-scroll" tabindex="0" role="region" aria-label="AIME task outcomes"><table><thead><tr><th>Source row</th><th>Reference</th><th>Original</th><th>Revision</th><th>Terra</th></tr></thead><tbody>'
    by={r['job']:r for r in data['outcomes']}
    for q in data['questions']:
        content+=f'<tr><th scope="row">{q["source_row"]}</th><td>{q["reference"]}</td>'
        for arm in 'ABE':
            r=by[q['id']+'.'+arm];content+=f'<td>{esc(r["parsed_answer"])} ({"correct" if r["correct"] else "incorrect"})</td>'
        content+='</tr>'
    content+='</tbody></table></div><p>Source rows identify the saved mirror snapshot, not official problem numbers. This is a six-question workflow screen, not a full AIME benchmark submission.</p><p><a href="aime-calibration-results.json" download>Download evidence ↓</a> · <a href="evaluations.html#aime-calibration">All test assessments →</a> · <a href="https://huggingface.co/datasets/OpenRLHF/aime-2024">Dataset mirror ↗</a></p>'
    return shell('Co-Evolution · AIME calibration and assessment',content)
