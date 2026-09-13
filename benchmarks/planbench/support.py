"""File primitives retained from the tested custom planning runner."""
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
import hashlib, json, os

def now():
    return datetime.now(timezone.utc).isoformat()

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write_once(path,obj):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('x',encoding='utf-8',newline='\n') as handle:
        json.dump(obj,handle,indent=2,ensure_ascii=False);handle.write('\n')

def atomic_json(path,obj):
    path=Path(path);tmp=path.with_suffix('.tmp')
    tmp.write_text(json.dumps(obj,indent=2)+'\n',encoding='utf-8');os.replace(tmp,path)

@contextmanager
def writer_lock(run):
    run=Path(run);run.mkdir(parents=True,exist_ok=True)
    with (run/'writer.lock').open('a+b') as lock:
        lock.seek(0,2)
        if lock.tell()==0:lock.write(b'0');lock.flush()
        lock.seek(0)
        if os.name=='nt':
            import msvcrt
            msvcrt.locking(lock.fileno(),msvcrt.LK_NBLCK,1)
        else:
            import fcntl
            fcntl.flock(lock.fileno(),fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:yield
        finally:
            if os.name=='nt':
                lock.seek(0);msvcrt.locking(lock.fileno(),msvcrt.LK_UNLCK,1)
