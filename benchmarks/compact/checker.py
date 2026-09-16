"""Run pinned checkers in disposable network-isolated containers."""
import json,subprocess,uuid
from pathlib import Path
def linux(path):
    path=Path(path).resolve().as_posix();return '/mnt/'+path[0].lower()+path[2:]
def invoke(payload,image,root,timeout=180):
    name='coe-eval-'+uuid.uuid4().hex
    command=['wsl','-d','Ubuntu','--','docker','run','--rm','-i','--name',name,'--network','none','--cpus','2','--memory','3g','--pids-limit','128','--cap-drop','ALL','--security-opt','no-new-privileges','--read-only','--tmpfs','/tmp:rw,size=512m','--env','PYTHONDONTWRITEBYTECODE=1','--env','HOME=/tmp']
    if payload['kind']=='bcb':
        command+=['--mount',f'type=bind,src={linux(root / "bigcodebench-upstream")},dst=/bcb,readonly','--mount',f'type=bind,src={linux(root / "verifier.py")},dst=/verifier.py,readonly','--entrypoint','python3',image,'/verifier.py']
    else:command+=[image]
    try:
        result=subprocess.run(command,input=json.dumps(payload),capture_output=True,text=True,encoding='utf-8',timeout=timeout)
    except subprocess.TimeoutExpired:
        subprocess.run(['wsl','-d','Ubuntu','--','docker','rm','-f',name],capture_output=True,timeout=30)
        raise RuntimeError('Evaluator envelope timeout; outcome unavailable')
    lines=[s[7:] for s in result.stdout.splitlines() if s.startswith('RESULT:')]
    if result.returncode or len(lines)!=1:raise RuntimeError('Evaluator failed: '+result.stderr[-1600:])
    return json.loads(lines[0])
