// Leaf fixture: record our PID, then stay alive ~60s.
//
// Doubles as the single-process fixture for the "no tree" timeout test. We stay
// alive purely on a long timer -- no SIGTERM handler -- so on POSIX the default
// SIGTERM action reaps us promptly, and on Windows taskkill /F stops us. We must
// NOT exit merely because a parent died; only the killer (group kill / taskkill
// /T) should reap us. That is the whole point the test is proving.
import { writeFileSync } from "node:fs";

const pidFile = process.argv[2];
if (!pidFile) {
  console.error("grandchild.mjs: missing pid-file argument");
  process.exit(2);
}

writeFileSync(pidFile, String(process.pid), "utf8");

// ~60s keep-alive. The test kills us within ~1.5s; this is just headroom so we
// never self-exit and produce a false "it died on its own" reading.
setTimeout(() => {
  process.exit(0);
}, 60_000);
