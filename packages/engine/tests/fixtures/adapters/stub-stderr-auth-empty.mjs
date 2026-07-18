// Stub: empty stdout, an auth banner on stderr, nonzero exit. Exercises the
// "output empty + stderr auth-regex -> fatal/auth" branch of the ladder.
process.stdin.on("data", () => {});
process.stdin.on("end", () => {
  process.stderr.write("Failed to authenticate: please run claude /login\n");
  process.exit(1);
});
