// Stub: no output at all. Exit 0. Classifier should return `empty`.
process.stdin.on("data", () => {});
process.stdin.on("end", () => {
  process.exit(0);
});
