// Stub: a short auth banner (well under 50 words) on stdout. Matches the auth
// regex -> classifier should return fatal/auth. Exit code is irrelevant (the
// Bash source `|| true`s the call; classification is by content).
process.stdin.on("data", () => {});
process.stdin.on("end", () => {
  process.stdout.write("Not logged in · Please run /login\n");
  process.exit(1);
});
