"""Require a fresh, published evidence assessment for every non-archived result export."""
import hashlib, json
from pathlib import Path

SITE=Path(__file__).resolve().parent
FIELDS=('question','finding','test_quality','limitation','decision','next_action')

def digest(path):
    # Semantic digest avoids platform line-ending differences without ignoring data changes.
    obj=json.loads(Path(path).read_text(encoding='utf-8-sig'))
    return hashlib.sha256(json.dumps(obj,sort_keys=True,separators=(',',':'),ensure_ascii=True,allow_nan=False).encode()).hexdigest()

def validate(site=SITE,check_pages=True):
    site=Path(site);public=site/'public'
    archives=json.loads((site/'archive-manifest.json').read_text(encoding='utf-8'))['files']
    for name,expected in archives.items():
        path=public/name
        if not path.is_file() or hashlib.sha256(path.read_bytes()).hexdigest()!=expected:
            raise ValueError('Archived evidence changed: '+name)
    registry=json.loads((public/'test-evaluations.json').read_text(encoding='utf-8'))
    if registry.get('schema')!='publication-assessments/1.0':raise ValueError('Invalid assessment registry')
    expected={p.relative_to(public).as_posix() for p in public.rglob('*.json') if p.relative_to(public).as_posix() not in archives and p.name!='test-evaluations.json'}
    entries=registry['studies'];found=set();ids=set()
    for e in entries:
        name=e['data']
        if name in found or e['id'] in ids:raise ValueError('Duplicate evidence assessment')
        found.add(name);ids.add(e['id'])
        if name not in expected:raise ValueError('Unexpected or archived assessment target: '+name)
        if e['data_sha256']!=digest(public/name):raise ValueError('Stale assessment; evaluate changed results: '+name)
        for field in FIELDS:
            if not isinstance(e.get(field),str) or len(e[field].strip())<20:raise ValueError('Missing substantive '+field+': '+name)
        if not isinstance(e.get('coverage'),str) or not e['coverage'].strip():raise ValueError('Missing coverage: '+name)
        if e.get('status') not in ('complete','partial','mixed','readiness-failed'):raise ValueError('Missing explicit status: '+name)
        if check_pages:
            page=(public/'evaluations.html').read_text(encoding='utf-8')
            import html
            if f'id="{html.escape(e["id"])}"' not in page:raise ValueError('Assessment not published: '+name)
            for field in FIELDS:
                if html.escape(e[field]) not in page:raise ValueError('Published assessment is stale: '+name)
    if found!=expected:raise ValueError('Results without evaluation: '+', '.join(sorted(expected-found)))
    if check_pages and 'evaluations.html' not in (public/'index.html').read_text(encoding='utf-8'):
        raise ValueError('Assessment page is not linked from homepage')
    return entries

if __name__=='__main__':print(f'Publication gate passed: {len(validate())} current result exports have fresh, visible assessments; archives unchanged.')
