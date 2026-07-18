/**
 * isProcessAlive -- a platform-agnostic liveness probe for a PID we do NOT own
 * (e.g. a grandchild spawned by a child). Kept behind one API so test code is
 * OS-agnostic.
 *
 * POSIX:   `process.kill(pid, 0)` delivers no signal but throws ESRCH if the PID
 *          is gone. EPERM means "exists but owned by another user" -> alive.
 *   Windows: `process.kill(pid, 0)` is UNRELIABLE here. Windows keeps a PID's
 *          kernel object alive while any handle to it stays open, so a probe can
 *          report a terminated PID as still alive. `tasklist` queries the live
 *          process table instead and is immune to that lingering-handle quirk,
 *          which is why the tree-kill test relies on it.
 */
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);
const isWindows = process.platform === "win32";

export async function isProcessAlive(pid: number): Promise<boolean> {
  if (isWindows) {
    return isProcessAliveWindows(pid);
  }
  try {
    process.kill(pid, 0);
    return true; // exists and signalable
  } catch (err) {
    const code = (err as NodeJS.ErrnoException).code;
    if (code === "EPERM") return true; // exists, just not ours
    return false; // ESRCH => no such process
  }
}

async function isProcessAliveWindows(pid: number): Promise<boolean> {
  try {
    const { stdout } = await execFileAsync(
      "tasklist",
      ["/FI", `PID eq ${pid}`, "/NH", "/FO", "CSV"],
      { windowsHide: true },
    );
    // A match is a CSV row whose 2nd column is the quoted PID, e.g.
    //   "node.exe","1234","Console","1","12,345 K"
    // No match prints: INFO: No tasks are running which match the specified criteria.
    // The memory column carries commas/spaces/"K", so a bare `"<pid>"` cannot
    // collide with it.
    return stdout.includes(`"${pid}"`);
  } catch {
    // If tasklist itself fails, prefer a false negative over a false "alive":
    // callers use this to assert death, and a stuck true would mask a leak.
    return false;
  }
}
