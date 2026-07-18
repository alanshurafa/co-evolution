// Stub: report which of the six RNPT-06 harness vars are visible in its OWN
// environment, as JSON on stdout. The adapter must have stripped all six, so
// the test expects `present` to be empty.
const HARNESS = [
  "CLAUDECODE",
  "CLAUDE_CODE_EFFORT_LEVEL",
  "CLAUDE_CODE_ENTRYPOINT",
  "CLAUDE_CODE_EXECPATH",
  "CLAUDE_CODE_PROVIDER_MANAGED_BY_HOST",
  "CLAUDE_CODE_OAUTH_TOKEN",
];
process.stdin.on("data", () => {});
process.stdin.on("end", () => {
  const present = HARNESS.filter((k) => k in process.env);
  process.stdout.write(JSON.stringify({ present }));
  process.exit(0);
});
