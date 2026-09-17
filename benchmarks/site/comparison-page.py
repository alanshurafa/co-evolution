"""Render and independently check protocol-separated composite scores."""
import hashlib,html,json,math
from pathlib import Path
SITE=Path(__file__).resolve().parent
def digest(path):return hashlib.sha256(json.dumps(json.loads(Path(path).read_text(encoding='utf-8')),sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode()).hexdigest()
def validate(data,public=None):
    public=Path(public or SITE/'public')
    if data['weights']!={'bcb':.5,'lcb':.5}:raise ValueError('Unexpected published composite weights')
    for name,sha in data['inventory_hashes'].items():
        if Path(name).name!=name or digest(public/name)!=sha:raise ValueError('Website inventory source changed')
    for name,sha in data['source_hashes'].items():
        if name not in {f'{p}-{b}-results.json' for p in ('fixed','feedback') for b in ('bcb','lcb')}:raise ValueError('Unexpected composite source')
        if digest(public/name)!=sha:raise ValueError('Composite source snapshot changed')
    for group in data['groups']:
        expected_arms=set('ABCDEF' if group['id']=='feedback' else 'ABCDE')
        if {r['arm'] for r in group['rows']}!=expected_arms or len(group['rows'])!=len(expected_arms):raise ValueError('Composite workflow coverage mismatch')
        for row in group['rows']:
            inputs=[o for o in data['observations'] if o['protocol']==group['id'] and o['arm']==row['arm']]
            if len(inputs)!=2 or {o['benchmark'] for o in inputs}!={'bcb','lcb'}:raise ValueError('Composite benchmark coverage mismatch')
            for o in inputs:
                source=json.loads((public/f'{group["id"]}-{o["benchmark"]}-results.json').read_text(encoding='utf-8'));s=source['phases']['main']['scores'][o['arm']]
                if (o['correct'],o['planned'],o['missing'])!=(s['correct'],s['n'],s['missing']):raise ValueError('Composite input mismatch')
            valid=all(o['eligible'] for o in inputs)
            expected={'score':50*sum(o['correct']/o['planned'] for o in inputs) if valid else None,'coverage':50*sum((o['planned']-o['missing'])/o['planned'] for o in inputs) if valid else None,'upper_bound':50*sum((o['correct']+o['missing'])/o['planned'] for o in inputs) if valid else None}
            for key,value in expected.items():
                if value is None:
                    if row[key] is not None:raise ValueError('Unavailable composite represented as score')
                elif not isinstance(row[key],(int,float)) or not math.isclose(row[key],value,abs_tol=1e-9):raise ValueError('Composite calculation mismatch')
        b=next(r['score'] for r in group['rows'] if r['arm']=='B')
        for r in group['rows']:
            expected=r['score']-b if r['score'] is not None and b is not None else None
            if expected is None and r['delta_vs_B'] is not None or expected is not None and not math.isclose(r['delta_vs_B'],expected,abs_tol=1e-9):raise ValueError('Composite delta mismatch')

def render(data,shell):
    e=html.escape
    content='<p class="eyebrow">OUR RESULTS AND EXTERNAL REFERENCES</p><h1>Benchmark comparison</h1><p>The composite averages delivered-correct yield across BigCodeBench and LiveCodeBench within one protocol. Coverage and missing-answer bounds stay visible. External sites provide context; their leaderboard scores are not mixed into our experiments.</p><p><a href="downloads/benchmark-comparison.xlsx" download>Download the comparison workbook ↓</a> · <a href="website-comparison.json" download>Download source data ↓</a></p><h2>Workflow composite, 0–100</h2><div class="comparison-controls"><label>Protocol <select id="protocol">'
    for g in data['groups']:content+=f'<option value="{e(g["id"])}">{e(g["title"])}</option>'
    content+='</select></label><label>BigCodeBench weight (%) <input id="weight" type="number" min="0" max="100" step="5" value="50"></label></div><p id="weight-note"></p><div class="table-scroll" tabindex="0" role="region" aria-label="Composite workflow scores"><table><thead><tr><th>Workflow</th><th>BigCodeBench yield</th><th>LiveCodeBench yield</th><th>Composite</th><th>Coverage</th><th>Upper bound</th><th>Change vs B</th></tr></thead><tbody id="composite-body"></tbody></table></div><p>Yield is correct answers divided by all planned tasks. An unanswered task contributes no delivered success; its latent correctness remains unknown. Upper bounds assume every missing answer would pass and are not confidence intervals. The feedback and tool-free panels use different protocols and cohorts, so their levels are not a before/after treatment effect.</p><h2>Website comparison sheet</h2><label>Website category <select id="site-filter"><option value="all">All websites</option><option>Our result page</option><option>External reference</option><option>Archive</option></select></label><p id="site-count"></p><div class="table-scroll" tabindex="0" role="region" aria-label="Website comparison"><table><thead><tr><th>Website</th><th>Category</th><th>Scoring</th><th>Coverage or scope</th><th>Composite inclusion</th><th>Evidence and use</th></tr></thead><tbody id="sites-body"></tbody></table></div><h2>What belongs in the composite</h2><p>'+e(data['limitations'])+'</p><p>Every current internal test has a dedicated score page and an <a href="evaluations.html#comparison-sheet">evidence assessment</a>. Archives are history, not extra trials. External site descriptions were checked against their official pages or linked project documentation on '+e(data['checked_on'])+'.</p>'
    payload=json.dumps(data,ensure_ascii=True).replace('<','\\u003c')
    script='''<script id="comparison-data" type="application/json">'''+payload+'''</script><script>
const data=JSON.parse(document.getElementById('comparison-data').textContent);
const fmt=x=>x===null?'Unavailable':x.toFixed(1);
function cell(tr,text){const td=document.createElement('td');td.textContent=text;tr.append(td);return td;}
function composites(){const g=data.groups.find(x=>x.id===document.getElementById('protocol').value);const raw=document.getElementById('weight').value;const w=Number(raw);const valid=raw!==''&&Number.isFinite(w)&&w>=0&&w<=100;document.getElementById('weight-note').textContent=valid?`Weights: BigCodeBench ${w}%, LiveCodeBench ${100-w}%. Default is equal weight. These are reporting weights, not statistical confidence.`:'Enter a weight between 0 and 100.';const body=document.getElementById('composite-body');body.replaceChildren();const rows=g.rows.map(r=>{const input=data.observations.filter(o=>o.protocol===g.id&&o.arm===r.arm);const b=input.find(o=>o.benchmark==='bcb'),l=input.find(o=>o.benchmark==='lcb');const ok=valid&&b.eligible&&l.eligible;return {...r,current:ok?w*b.correct/b.planned+(100-w)*l.correct/l.planned:null,cov:ok?w*(b.planned-b.missing)/b.planned+(100-w)*(l.planned-l.missing)/l.planned:null,upper:ok?w*(b.correct+b.missing)/b.planned+(100-w)*(l.correct+l.missing)/l.planned:null};});const baseline=rows.find(r=>r.arm==='B').current;for(const r of rows){const tr=document.createElement('tr');cell(tr,r.arm+' · '+r.label);cell(tr,fmt(r.bcb));cell(tr,fmt(r.lcb));cell(tr,fmt(r.current));cell(tr,fmt(r.cov)+(r.cov===null?'':'%'));cell(tr,fmt(r.upper));cell(tr,r.current===null||baseline===null?'Unavailable':fmt(r.current-baseline));body.append(tr);}}
function sites(){const filter=document.getElementById('site-filter').value;const rows=data.websites.filter(r=>filter==='all'||r.type===filter);const body=document.getElementById('sites-body');body.replaceChildren();document.getElementById('site-count').textContent=rows.length+' websites shown';for(const r of rows){const tr=document.createElement('tr');const td=cell(tr,'');const a=document.createElement('a');a.href=r.url;a.textContent=r.title;td.append(a);cell(tr,r.type);cell(tr,r.metric);cell(tr,r.coverage);cell(tr,r.composite_group==='excluded'?'Excluded':r.composite_group);cell(tr,r.features+' '+r.summary);body.append(tr);}}
document.getElementById('protocol').addEventListener('change',composites);document.getElementById('weight').addEventListener('input',composites);document.getElementById('site-filter').addEventListener('change',sites);composites();sites();
</script>'''
    return shell('Co-Evolution · Benchmark website comparison',content).replace('</body>',script+'</body>').replace('</style>','.comparison-controls{display:flex;gap:24px;flex-wrap:wrap;margin:20px 0}.comparison-controls label{display:flex;flex-direction:column;gap:8px}.evidence select,.evidence input{font:inherit;padding:10px;border:1px solid var(--line);border-radius:6px;max-width:100%}.evidence td{vertical-align:top}#sites-body td:last-child{min-width:320px}</style>')
