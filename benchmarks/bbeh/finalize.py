"""Reconcile a lost controller and freeze a terminal calibration result."""
import argparse
from pathlib import Path
import runner

def finish(root, reason):
    root=Path(root)
    with runner.writer_lock(root):
        campaign=runner.Campaign(root,runner.GRANT)
        try:
            for call in campaign.db.execute("SELECT id,job FROM calls WHERE grant_id=? AND state='reserved'",(runner.GRANT,)).fetchall():
                campaign.finish(runner.STAGE,call['job'],call['id'],'failed',error=reason)
            for job in campaign.jobs(runner.STAGE):campaign.block(runner.STAGE,job['id'],reason)
            rows=runner.freeze_and_score(root,campaign,'calibration')
            runner.write_once(root/'gate.json',runner.gate(rows,0,None))
            runner.freeze_and_score(root,campaign,'main')
            runner.snapshot(root,campaign,'finished')
        finally:
            campaign.close()
    runner.write_once(root/'controller.exit.json',{'state':'reconciled-lost-controller','reason':reason,'restart_permitted':False})

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--reason',required=True);a=p.parse_args();finish(a.root,a.reason)
