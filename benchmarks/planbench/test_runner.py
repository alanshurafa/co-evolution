"""One offline lifecycle check: dependency execution, retry charge, safe resume."""
import json, tempfile, time, unittest
from pathlib import Path
from unittest.mock import patch
from campaign import Campaign
from run import GRANT,STAGE,CAPS,definitions,dispatch_loop
from support import write_once,sha
from transport import ProviderFailure,classify

class Fake:
    def __init__(self):self.calls=[];self.failed=False
    def invoke(self,seat,prompt,output_limit=None):
        self.calls.append((seat,prompt))
        if not self.failed:
            self.failed=True;raise ProviderFailure('network_error','fixture transient')
        return dict(text='(pick-up a)\n(stack a b)',requested_model='gpt-6-astra' if seat=='astra' else 'claude-fable-5-1',reported_model='claude-fable-5-1' if seat=='fable' else None,tool_calls=0,seconds=0,usage={})

class Lifecycle(unittest.TestCase):
    def test_sonnet_terra_roles_caps_and_concurrency(self):
        import run
        try:
            run.configure({'author_seat':'sonnet','reviewer_seat':'codex','grant':'test-sonnet-terra'})
            defs=run.definitions(['fixture'],[])
            self.assertEqual([d['seat'] for d in defs],['sonnet','sonnet','sonnet','codex','sonnet','sonnet'])
            self.assertEqual(run.CAPS,{'codex':56,'claude':280,'glm':0,'kimi':0})
            self.assertEqual(run.WORKERS,{'claude':4,'codex':2})
            self.assertEqual(run.RETRIES,{'claude':20,'codex':4})
        finally:run.configure()
    def test_specific_content_refusal_is_not_family_unavailability(self):
        self.assertEqual(classify("API Error: safeguards flagged this message. Details: [reasoning_extraction]"),'content_refusal')
        self.assertEqual(classify("API Error: response exceeded the 1024 output token maximum"),'output_truncated')
        self.assertEqual(classify('unknown model'),'model_unavailable')
        self.assertEqual(classify('unclassified upstream error'),'provider_error')
    def test_resume_and_retry(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            write_once(root/'manifest.json',dict(smoke_tasks=['fixture'],execution_order=[],dispatch_cutoff=time.time()+60,deadline_epoch=time.time()+60,models={'astra':'gpt-6-astra','fable':'claude-fable-5-1'}))
            c=Campaign(root,GRANT);c.authorize(336,CAPS,'offline fixture');c.allocate(STAGE,336,CAPS,sha(root/'manifest.json'),definitions(['fixture'],['fixture']),time.time()+60)
            fake=Fake()
            with patch('run.prompt',side_effect=lambda root,d,j:'fixed:'+d['id']):
                dispatch_loop(root,c,fake,True)
                self.assertEqual(c.count(),7)
                self.assertTrue(all(j['state']=='succeeded' for j in c.jobs(STAGE)))
                before=[dict(x) for x in c.db.execute('SELECT * FROM calls')]
                dispatch_loop(root,c,fake,True)
                self.assertEqual(before,[dict(x) for x in c.db.execute('SELECT * FROM calls')])
                self.assertEqual(len(fake.calls),7)
                self.assertEqual(fake.calls[0],fake.calls[1])
            c.close()

if __name__=='__main__':unittest.main()
