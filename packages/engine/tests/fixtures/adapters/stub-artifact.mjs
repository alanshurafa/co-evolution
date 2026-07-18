// Stub: a normal, non-auth artifact on stdout. Exit 0.
// Drains stdin first so the parent's write/end never races an early exit.
let stdin = "";
process.stdin.on("data", (d) => {
  stdin += d;
});
process.stdin.on("end", () => {
  void stdin;
  process.stdout.write("This is a normal artifact document produced by the stub.\n");
  process.exit(0);
});
