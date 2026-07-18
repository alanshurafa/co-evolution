// Stub: never produces output and never exits on its own. Holds the event loop
// open with a far-future timer. Does NOT trap signals, so the adapter's
// child.kill() (SIGTERM / Windows TerminateProcess) reliably ends it, letting
// the timeout path resolve fatal/timeout.
process.stdin.on("data", () => {});
setTimeout(() => {}, 1_000_000_000);
