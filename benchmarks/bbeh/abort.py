"""Close an interrupted calibration without permitting a restart."""
import argparse, json
from pathlib import Path
import runner

def close(root, reason):
    root=Path(root)
    with runner.writer_lock(root):
        campaign=runner.Campaign(root,runner.GRANT)
        try:
            for call in campaign.db.execute("SELECT id,job FROM calls WHERE grant_id=? AND state='reserved'",(runner.GRANT,)).fetchall():
                campaign.finish(runner.STAGE,call['job'],call['id'],'failed',error=reason)
            for job in campaign.jobs(runner.STAGE):
                campaign.block(runner.STAGE,job['id'],reason)
            runner.snapshot(root,campaign,'aborted')
        finally:
            campaign.close()
    runner.write_once(root/'controller.aborted.json',{'reason':reason,'restart_permitted':False})

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path,required=True);p.add_argument('--reason',required=True);a=p.parse_args();close(a.root,a.reason)
