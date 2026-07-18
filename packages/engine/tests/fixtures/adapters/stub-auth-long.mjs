// Stub: a long document (>50 words) that MENTIONS auth phrases mid-body. This
// is the deb4669 false-positive guard: because the output exceeds the 50-word
// ceiling, the classifier must return `artifact`, NOT fatal/auth, even though
// the text contains "Not logged in" and "Unauthorized".
const doc = [
  "This design note explains how the runtime detects authentication failures",
  "without misfiring on legitimate documents. A real banner such as Not logged in",
  "appears alone at the very top of the output before any work happens. By",
  "contrast, this paragraph discusses the word Unauthorized purely as an example",
  "of prose that a genuine artifact might contain while describing the login flow,",
  "so the length ceiling is what keeps this long body from being misclassified as",
  "an auth error page rather than the useful document that it actually is here.",
].join(" ");
process.stdin.on("data", () => {});
process.stdin.on("end", () => {
  process.stdout.write(doc + "\n");
  process.exit(0);
});
