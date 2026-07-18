// Stub: echo the prompt received on stdin back to stdout, proving the adapter
// delivers promptText via stdin. Prefixed so the assertion is unambiguous.
let stdin = "";
process.stdin.on("data", (d) => {
  stdin += d;
});
process.stdin.on("end", () => {
  process.stdout.write("STDIN>>>" + stdin);
  process.exit(0);
});
