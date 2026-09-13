"""Single cumulative authorization and attempt ledger for planning stages."""
from contextlib import ExitStack
import hashlib
import json
from pathlib import Path
import sqlite3
import time
from support import writer_lock, write_once, now

CAP = 200
FAMILY_CAPS = {'claude': 80, 'codex': 80, 'glm': 20, 'kimi': 20}
FAMILY = {'sonnet': 'claude', 'fable': 'claude', 'codex': 'codex',
          'astra': 'codex', 'glm': 'glm', 'kimi': 'kimi'}


class BudgetError(RuntimeError):
    pass


class Campaign:
    def __init__(self, root, grant='pilot'):
        self.root = Path(root).resolve()
        self.grant_id = grant
        self.db = sqlite3.connect(self.root / 'campaign.sqlite', timeout=30)
        self.db.row_factory = sqlite3.Row
        self.db.executescript('''
            CREATE TABLE IF NOT EXISTS history (name TEXT PRIMARY KEY, count INTEGER, digest TEXT);
            CREATE TABLE IF NOT EXISTS stages (id TEXT PRIMARY KEY, cap INTEGER, family_caps TEXT,
                manifest_sha TEXT, deadline REAL);
            CREATE TABLE IF NOT EXISTS jobs (stage TEXT, id TEXT, definition TEXT,
                state TEXT DEFAULT 'pending', result TEXT, error TEXT, not_before REAL DEFAULT 0,
                PRIMARY KEY(stage,id));
            CREATE TABLE IF NOT EXISTS calls (id INTEGER PRIMARY KEY, stage TEXT, job TEXT,
                seat TEXT, family TEXT, attempt_index INTEGER, started TEXT, finished TEXT,
                state TEXT, prompt_sha TEXT, UNIQUE(stage,job,attempt_index));
            CREATE TABLE IF NOT EXISTS grants (id TEXT PRIMARY KEY, cap INTEGER,
                family_caps TEXT, authorization TEXT);
        ''')
        for table in ('calls', 'stages'):
            if 'grant_id' not in {r[1] for r in self.db.execute('PRAGMA table_info(' + table + ')')}:
                self.db.execute("ALTER TABLE " + table + " ADD COLUMN grant_id TEXT NOT NULL DEFAULT 'pilot'")
        self.db.execute('INSERT OR IGNORE INTO grants VALUES(?,?,?,?)',
                        ('pilot', CAP, json.dumps(FAMILY_CAPS), 'Original 200-call planning pilot authorization'))
        self.db.commit()

    def close(self):
        self.db.close()

    def authorize(self, cap, families, authorization):
        """Record a NEW user-approved grant; never enlarge an existing grant."""
        if cap <= 0 or any(v < 0 for v in families.values()) or sum(families.values()) != cap or set(families) != set(FAMILY_CAPS) or not authorization.strip():
            raise BudgetError('Invalid authorization')
        with self.db:
            old = self.db.execute('SELECT * FROM grants WHERE id=?', (self.grant_id,)).fetchone()
            if old:
                if old['cap'] != cap or json.loads(old['family_caps']) != families:
                    raise BudgetError('Existing authorization cannot be raised or replaced')
                return
            self.db.execute('INSERT INTO grants VALUES(?,?,?,?)',
                            (self.grant_id, cap, json.dumps(families), authorization))

    def limits(self):
        grant = self.db.execute('SELECT * FROM grants WHERE id=?', (self.grant_id,)).fetchone()
        if not grant:
            raise BudgetError('No authorization recorded for this grant')
        return grant['cap'], json.loads(grant['family_caps'])

    def lifetime_count(self):
        return self.db.execute('SELECT count(*) FROM calls').fetchone()[0]

    def import_history(self):
        """Close historical controllers before importing all spent reservations."""
        if self.grant_id != 'pilot':
            raise BudgetError('Historical pilot spend belongs to its original grant')
        with ExitStack() as stack:
            for name in ('pilot-001', 'pilot-002'):
                stack.enter_context(writer_lock(self.root / name))
            snapshots = []
            for name in ('pilot-001', 'pilot-002'):
                path = self.root / name / 'ledger.sqlite'
                old = sqlite3.connect(path.as_uri() + '?mode=ro', uri=True)
                old.row_factory = sqlite3.Row
                if old.execute("SELECT count(*) FROM jobs WHERE state IN ('pending','running')").fetchone()[0]:
                    old.close()
                    raise RuntimeError('Historical controller must be settled: ' + name)
                rows = [dict(r) for r in old.execute('SELECT * FROM attempts ORDER BY id')]
                old.close()
                digest = hashlib.sha256(path.read_bytes()).hexdigest()
                marker = self.root / name / 'CLOSED.json'
                if not marker.exists():
                    write_once(marker, dict(at=now(), reason='Allocation transferred to central planning campaign', spent=len(rows)))
                if json.loads(marker.read_text(encoding='utf-8'))['spent'] != len(rows):
                    raise RuntimeError('Historical budget changed after closure')
                snapshots.append((name, rows, digest))
            self.db.execute('BEGIN IMMEDIATE')
            try:
                for name, rows, digest in snapshots:
                    previous = self.db.execute('SELECT * FROM history WHERE name=?', (name,)).fetchone()
                    if previous:
                        if previous['count'] != len(rows) or previous['digest'] != digest:
                            raise RuntimeError('Historical ledger changed; refusing to allocate more spend')
                        continue
                    for row in rows:
                        self.db.execute('INSERT INTO calls(stage,job,seat,family,attempt_index,started,finished,state,prompt_sha) VALUES(?,?,?,?,?,?,?,?,?)',
                                        ('history:' + name, str(row['id']), row['seat'], row['family'], 1,
                                         row['started'], row.get('finished'), row['state'], row.get('prompt_sha')))
                    self.db.execute('INSERT INTO history VALUES(?,?,?)', (name, len(rows), digest))
                if self.db.execute('SELECT sum(count) FROM history').fetchone()[0] != 143:
                    raise BudgetError('Expected 143 historical reservations; reconcile before proceeding')
                self.db.commit()
            except Exception:
                self.db.rollback()
                raise

    def allocate(self, stage, cap, families, manifest_sha, jobs, deadline):
        if sum(families.values()) != cap or cap <= 0 or any(v < 0 for v in families.values()):
            raise BudgetError('Invalid allocation')
        self.db.execute('BEGIN IMMEDIATE')
        try:
            old = self.db.execute('SELECT * FROM stages WHERE id=?', (stage,)).fetchone()
            if old:
                if old['grant_id'] != self.grant_id:
                    raise BudgetError('Stage belongs to another authorization')
                if (old['cap'], json.loads(old['family_caps']), old['manifest_sha']) != (cap, families, manifest_sha):
                    raise BudgetError('Cannot replace an existing frozen allocation')
                self.db.commit()
                return
            historical = dict(self.db.execute("SELECT family,count(*) FROM calls WHERE grant_id=? AND stage LIKE 'history:%' GROUP BY family", (self.grant_id,)))
            if self.grant_id == 'pilot' and sum(historical.values()) != 143:
                raise BudgetError('History must be imported before allocating')
            grant_cap, grant_families = self.limits()
            allocations = self.db.execute('SELECT cap,family_caps FROM stages WHERE grant_id=?', (self.grant_id,)).fetchall()
            if sum(historical.values()) + sum(x['cap'] for x in allocations) + cap > grant_cap:
                raise BudgetError('New allocation exceeds the campaign cap')
            for family, limit in grant_families.items():
                total = historical.get(family, 0) + sum(json.loads(x['family_caps']).get(family, 0) for x in allocations) + families.get(family, 0)
                if total > limit:
                    raise BudgetError('Allocation exceeds family cap: ' + family)
            self.db.execute('INSERT INTO stages(id,cap,family_caps,manifest_sha,deadline,grant_id) VALUES(?,?,?,?,?,?)',
                            (stage, cap, json.dumps(families), manifest_sha, deadline, self.grant_id))
            for job in jobs:
                self.db.execute('INSERT INTO jobs(stage,id,definition) VALUES(?,?,?)', (stage, job['id'], json.dumps(job)))
            self.db.commit()
        except Exception:
            self.db.rollback()
            raise

    def jobs(self, stage):
        return self.db.execute('SELECT * FROM jobs WHERE stage=? ORDER BY id', (stage,)).fetchall()

    def count(self, stage=None, family=None):
        terms, args = ['grant_id=?'], [self.grant_id]
        if stage is not None:
            terms.append('stage=?'); args.append(stage)
        if family is not None:
            terms.append('family=?'); args.append(family)
        query = 'SELECT count(*) FROM calls' + (' WHERE ' + ' AND '.join(terms) if terms else '')
        return self.db.execute(query, args).fetchone()[0]

    def attempts(self, stage, job):
        return self.db.execute('SELECT * FROM calls WHERE stage=? AND job=? ORDER BY attempt_index', (stage, job)).fetchall()

    def reserve(self, stage, ident, prompt_sha):
        self.db.execute('BEGIN IMMEDIATE')
        try:
            allocation = self.db.execute('SELECT * FROM stages WHERE id=?', (stage,)).fetchone()
            job = self.db.execute('SELECT * FROM jobs WHERE stage=? AND id=?', (stage, ident)).fetchone()
            if not allocation or allocation['grant_id'] != self.grant_id or not job or job['state'] != 'pending':
                raise BudgetError('Job is not pending in an allocated stage')
            if time.time() >= allocation['deadline']:
                raise BudgetError('Absolute stage deadline reached')
            definition = json.loads(job['definition'])
            seat = definition['seat']; family = FAMILY[seat]
            caps = json.loads(allocation['family_caps'])
            grant_cap, grant_families = self.limits()
            if (self.count() >= grant_cap or self.count(family=family) >= grant_families[family]
                    or self.count(stage) >= allocation['cap'] or self.count(stage, family) >= caps.get(family, 0)):
                raise BudgetError('Cumulative dispatch limit reached')
            attempts = self.attempts(stage, ident)
            if len(attempts) >= 2:
                raise BudgetError('One retry per job maximum')
            if attempts and attempts[0]['prompt_sha'] != prompt_sha:
                raise RuntimeError('Retry would change the frozen prompt')
            cursor = self.db.execute('INSERT INTO calls(stage,job,seat,family,attempt_index,started,state,prompt_sha,grant_id) VALUES(?,?,?,?,?,?,?,?,?)',
                                     (stage, ident, seat, family, len(attempts) + 1, now(), 'reserved', prompt_sha, self.grant_id))
            self.db.execute("UPDATE jobs SET state='running',error=NULL WHERE stage=? AND id=?", (stage, ident))
            self.db.commit()
            return cursor.lastrowid
        except Exception:
            self.db.rollback()
            raise

    def finish(self, stage, ident, call, state, result=None, error=None, retry_at=0):
        with self.db:
            self.db.execute('UPDATE calls SET state=?,finished=? WHERE id=?',
                            ('failed' if state == 'pending' else state, now(), call))
            self.db.execute('UPDATE jobs SET state=?,result=?,error=?,not_before=? WHERE stage=? AND id=?',
                            (state, json.dumps(result) if result is not None else None, error, retry_at, stage, ident))

    def block(self, stage, ident, reason):
        with self.db:
            self.db.execute("UPDATE jobs SET state='blocked',error=? WHERE stage=? AND id=? AND state='pending'", (reason, stage, ident))
