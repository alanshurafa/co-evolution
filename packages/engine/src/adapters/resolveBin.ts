/**
 * Windows-aware binary resolution for adapter spawns.
 *
 * `spawn("claude", …)` with `shell: false` does no PATHEXT resolution, and on
 * this machine (like most npm installs) `claude` exists only as a `.cmd` shim —
 * so the bare spawn fails ENOENT. Worse, Node refuses to spawn `.cmd`/`.bat`
 * files directly without a shell (EINVAL, the CVE-2024-27980 hardening). The
 * safe pattern is therefore: resolve the shim's full path ourselves, then run
 * it through `cmd.exe /d /s /c <full-path> <args…>` — but ONLY after checking
 * every arg against cmd.exe metacharacters, because cmd.exe re-parses its
 * command line. Our argv is fixed flags plus a model id, and the prompt travels
 * on stdin, so the guard should never fire in practice; it exists so that a
 * future caller cannot smuggle shell syntax through an adapter option.
 *
 * POSIX needs none of this: spawn resolves PATH and executes scripts via their
 * shebang, so resolution is a pass-through there.
 */

import { existsSync } from "node:fs";
import { delimiter, extname, isAbsolute, join } from "node:path";

/** What to actually spawn: the file plus any prefix argv (cmd.exe bridge). */
export interface ResolvedSpawn {
  file: string;
  argsPrefix: string[];
}

/** Windows extensions we resolve, in preference order. Extensionless files are
 * skipped on win32 — CreateProcess cannot execute them. */
const WIN_EXTS = [".exe", ".cmd", ".bat"] as const;

/** cmd.exe metacharacters (plus quotes, parens, and newlines) that make an
 * argument unsafe to pass through `cmd.exe /c` — parens are grouping
 * metacharacters in batch parsing contexts. */
const CMD_UNSAFE = /[&|<>^%!"()\r\n]/;

/** Return the first argument unsafe for cmd.exe passthrough, if any. */
export function findCmdUnsafeArg(args: readonly string[]): string | undefined {
  return args.find((a) => CMD_UNSAFE.test(a));
}

function bridgeFor(fullPath: string): ResolvedSpawn {
  if (/\.(cmd|bat)$/i.test(fullPath)) {
    return { file: "cmd.exe", argsPrefix: ["/d", "/s", "/c", fullPath] };
  }
  return { file: fullPath, argsPrefix: [] };
}

/**
 * Resolve a binary name/path into something `spawn(file, args)` can execute
 * with `shell: false` on the current platform.
 *
 * `searchPath` defaults to `process.env.PATH`; injectable for tests.
 */
export function resolveSpawn(
  binPath: string,
  searchPath: string | undefined = process.env.PATH,
): ResolvedSpawn {
  if (process.platform !== "win32") {
    return { file: binPath, argsPrefix: [] };
  }

  // Explicit path: honor it. An extensionless explicit path cannot execute on
  // win32 (CreateProcess), so probe the extension ladder against it — an npm
  // global dir's "claude" is really "claude.cmd" sitting beside the
  // extensionless git-bash shim.
  if (binPath.includes("/") || binPath.includes("\\") || isAbsolute(binPath)) {
    if (extname(binPath) !== "") {
      return bridgeFor(binPath);
    }
    for (const ext of WIN_EXTS) {
      const candidate = binPath + ext;
      if (existsSync(candidate)) {
        return bridgeFor(candidate);
      }
    }
    return { file: binPath, argsPrefix: [] };
  }
  // Bare name with an explicit extension: honor it, adding the cmd.exe bridge
  // when it is a batch script.
  if (extname(binPath) !== "") {
    return bridgeFor(binPath);
  }

  for (const dir of (searchPath ?? "").split(delimiter)) {
    const cleaned = dir.replace(/^"|"$/g, "").trim();
    if (cleaned === "") {
      continue;
    }
    for (const ext of WIN_EXTS) {
      const candidate = join(cleaned, binPath + ext);
      if (existsSync(candidate)) {
        return bridgeFor(candidate);
      }
    }
  }

  // Nothing found: return the bare name so spawn fails with its normal ENOENT
  // and the caller's missing-cli classification stays intact.
  return { file: binPath, argsPrefix: [] };
}
