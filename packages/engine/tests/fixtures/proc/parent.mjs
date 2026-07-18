// Parent fixture: record our PID, spawn ONE grandchild with a PLAIN (non-detached)
// spawn, then stay alive ~60s.
//
// Why plain spawn (no detached, no new group):
//   POSIX  -> the grandchild inherits our process group. runWithDeadline put US
//             (the top child) in our own group via detached:true, so a group kill
//             reaps the grandchild too. If the killer instead only signalled our
//             PID, the grandchild would be re-parented to init and survive --
//             which is exactly the failure the test must catch. So we deliberately
//             do NOT create our own group here.
//   Windows -> the grandchild is an ordinary child process. Killing only our PID
//             leaves it orphaned and running; only taskkill /T walks the tree and
//             reaps it. Again: proves the killer, not luck.
import { spawn } from "node:child_process";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const here = dirname(fileURLToPath(import.meta.url));

const parentPidFile = process.argv[2];
const grandchildPidFile = process.argv[3];
if (!parentPidFile || !grandchildPidFile) {
  console.error("parent.mjs: usage: parent.mjs <parentPidFile> <grandchildPidFile>");
  process.exit(2);
}

writeFileSync(parentPidFile, String(process.pid), "utf8");

// Plain spawn -- NOT detached. Inherit stdio as "ignore" so no pipe buffers.
spawn(process.execPath, [join(here, "grandchild.mjs"), grandchildPidFile], {
  stdio: "ignore",
});

// ~60s keep-alive; the test kills the tree within ~1.5s.
setTimeout(() => {
  process.exit(0);
}, 60_000);
