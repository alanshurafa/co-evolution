"""CPU-only bridge to pinned upstream checkers, executed inside Docker."""
import ast,collections,contextlib,importlib,io,json,sys,types
from fractions import Fraction
from pathlib import Path

def package(name,path):
    m=types.ModuleType(name);m.__path__=[str(path)];sys.modules[name]=m

def gym_modules():
    base=Path('/rg/reasoning_gym')
    package('reasoning_gym',base);package('reasoning_gym.coaching',base/'coaching')
    package('reasoning_gym.algorithmic',base/'algorithmic');package('reasoning_gym.games',base/'games')
    attrs=importlib.import_module('reasoning_gym.coaching.attributes');curr=importlib.import_module('reasoning_gym.coaching.base_curriculum')
    p=sys.modules['reasoning_gym.coaching']
    for name in ('RangeAttributeDefinition','ScalarAttributeDefinition'):setattr(p,name,getattr(attrs,name))
    p.BaseCurriculum=curr.BaseCurriculum
    graph=importlib.import_module('reasoning_gym.algorithmic.graph_color')
    countdown=importlib.import_module('reasoning_gym.games.countdown')
    return graph,countdown

def strict_expression(answer,entry):
    numbers=[]
    def value(node):
        if isinstance(node,ast.Constant) and type(node.value) is int and node.value>0:
            numbers.append(node.value);return Fraction(node.value)
        if isinstance(node,ast.BinOp) and type(node.op) in (ast.Add,ast.Sub,ast.Mult,ast.Div):
            a,b=value(node.left),value(node.right)
            if isinstance(node.op,ast.Add):return a+b
            if isinstance(node.op,ast.Sub):return a-b
            if isinstance(node.op,ast.Mult):return a*b
            return a/b
        raise ValueError('unsupported expression syntax')
    try:
        result=value(ast.parse(answer,mode='eval').body)
        return result==entry['metadata']['target'] and sorted(numbers)==sorted(entry['metadata']['numbers'])
    except (ValueError,SyntaxError,ZeroDivisionError):return False

def execute(payload):
    kind=payload['kind']
    if kind=='generate-gym':
        graph,countdown=gym_modules();out=[]
        for phase,seed,n in [('calibration',20260918,4),('main',20260919,12)]:
            datasets=[('graph_color',graph.GraphColorDataset(graph.GraphColorConfig(min_num_vertices=20,max_num_vertices=25,num_colors=3,edge_probability=.15,seed=seed,size=n))),('countdown',countdown.CountdownDataset(countdown.CountdownConfig(min_numbers=6,max_numbers=6,min_target=100,max_target=999,seed=seed,size=n)))]
            for family,dataset in datasets:
                for i in range(n):out.append(dict(id=f'{family}-{seed}-{i}',family=family,phase=phase,entry=dataset[i]))
        return out
    if kind=='gym':
        graph,countdown=gym_modules();entry=payload['entry'];answer=payload['answer']
        if payload['family']=='graph_color':
            dataset=graph.GraphColorDataset(graph.GraphColorConfig());reward=dataset.score_answer(answer,entry)
            return dict(correct=reward==1.0,reward=reward)
        # Reject executable/prohibited expressions before passing to SymPy's parser.
        strict=strict_expression(answer,entry)
        reward=countdown.CountdownDataset(countdown.CountdownConfig()).score_answer(answer,entry) if strict else None
        return dict(correct=strict and reward==1.0,reward=reward,strict_valid=strict)
    if kind=='lcb':
        package('lcb_runner','/lcb/lcb_runner');package('lcb_runner.evaluation','/lcb/lcb_runner/evaluation')
        from lcb_runner.evaluation.testing_util import run_test
        result,metadata=run_test({'input_output':json.dumps(payload['tests'])},test=payload['code'],debug=False,timeout=6)
        return dict(correct=bool(result) and all(x==True for x in result),verdicts=[int(x) for x in result],metadata=metadata)
    if kind=='bcb':
        sys.path.insert(0,'/bcb')
        from bigcodebench.eval import untrusted_check
        result=untrusted_check(payload['code'],payload['test'],payload['entry_point'],2*1024**3,2*1024**3,128*1024**2,1,2)
        return dict(correct=result[0]=='pass',verdict=str(result[0]),details=str(result[1:]))
    raise ValueError(kind)

if __name__=='__main__':
    payload=json.load(sys.stdin)
    with contextlib.redirect_stdout(io.StringIO()):result=execute(payload)
    print('RESULT:'+json.dumps(result,default=str))
