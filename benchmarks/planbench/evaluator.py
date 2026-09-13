"""Official zero-shot PDDL extraction and bundled VAL, without model scoring."""
import ast, json, subprocess
from pathlib import Path
from support import sha

def upstream_function(upstream,name,relative):
    tree=ast.parse((Path(upstream)/relative).read_text(encoding='utf-8'))
    function=next(n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name==name)
    namespace={}
    exec(compile(ast.Module(body=[function],type_ignores=[]),relative,'exec'),namespace)
    return namespace[name]

def linux(path):
    p=Path(path).resolve().as_posix()
    return '/mnt/'+p[0].lower()+p[2:]

def evaluate(upstream,problem,text,dest):
    upstream=Path(upstream);dest=Path(dest);dest.mkdir(parents=True,exist_ok=True)
    extract=upstream_function(upstream,'save_gpt3_response','llm_planning_analysis/utils/llm_utils.py')
    plan=extract(text,str(dest/'plan.pddl'))
    if not plan.strip():
        return dict(valid=False,category='invalid_serialization',extracted_plan_sha=sha(dest/'plan.pddl'))
    command=['wsl','-d','Ubuntu','--',linux(upstream/'planner_tools/VAL/validate'),
      linux(upstream/'llm_planning_analysis/instances/blocksworld_hard/generated_domain.pddl'),linux(problem),linux(dest/'plan.pddl')]
    try:
        proc=subprocess.run(command,capture_output=True,text=True,encoding='utf-8',errors='replace',timeout=15)
    except (OSError,subprocess.TimeoutExpired) as e:
        return dict(valid=None,category='validator_infrastructure',error=type(e).__name__)
    output=proc.stdout+'\n'+proc.stderr
    (dest/'validator.txt').write_text(output,encoding='utf-8')
    if proc.returncode not in (0,1) or 'Problem in domain' in output or not any(s in output for s in ('Plan valid','Plan failed','Failed plans','Bad plan','Plan invalid')):
        return dict(valid=None,category='validator_infrastructure',returncode=proc.returncode,output=output)
    return dict(valid='Plan valid' in proc.stdout,category='valid' if 'Plan valid' in proc.stdout else 'invalid_plan',returncode=proc.returncode,extracted_plan_sha=sha(dest/'plan.pddl'))

def check(root):
    root=Path(root);fixture=root/'validator-fixture';fixture.mkdir(exist_ok=True)
    problem=fixture/'problem.pddl'
    problem.write_text('(define (problem fixture) (:domain blocksworld-4ops) (:objects a b) (:init (handempty) (ontable a) (ontable b) (clear a) (clear b)) (:goal (on a b)))',encoding='utf-8')
    results={name:evaluate(root/'upstream',problem,text,fixture/name) for name,text in
      [('valid','(pick-up a)\n(stack a b)'),('invalid','(stack a b)'),('malformed','this is not a plan')]}
    assert results['valid']['valid'] is True,results
    assert results['invalid']['valid'] is False,results
    assert results['malformed']['valid'] is False,results
    return results
