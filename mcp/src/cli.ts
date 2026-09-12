#!/usr/bin/env node
import { spawn } from "node:child_process";
import { join } from "node:path";
import { findBash, pathForBash, VENDOR_ROOT } from "./bouncer.js";

const bash = findBash();
if (!bash) {
  console.error("co-evolve requires Bash. On Windows, install Git for Windows.");
  process.exit(1);
}
const child = spawn(bash, [pathForBash(join(VENDOR_ROOT, "co-evolve"), bash), ...process.argv.slice(2)], {
  stdio: "inherit",
});
child.on("error", (error) => {
  console.error(`Could not start co-evolve: ${error.message}`);
  process.exitCode = 1;
});
child.on("exit", (code, signal) => {
  process.exitCode = code ?? (signal === "SIGINT" ? 130 : 1);
});
process.on("SIGINT", () => child.kill("SIGINT"));
process.on("SIGTERM", () => child.kill("SIGTERM"));
