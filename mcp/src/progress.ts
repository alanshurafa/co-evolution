// Translate co-evolve-bouncer log lines into MCP progress messages.
// The bouncer logs human-readable phase markers via its log() helper
// (stdout); only the load-bearing lines become notifications.

const PATTERNS: RegExp[] = [
  /^-+ (COMPOSE PHASE|END COMPOSE) -+$/,
  /^\s*BOUNCE \d+\/\d+ - \w+ \(\w+\)\s*$/,
  /^\s*\[CONTESTED\] markers: \d+\s*$/,
  /^\s*\[CLARIFY\] markers:\s+\d+\s*$/,
  /^Converged after \d+ passes/,
  /^Skipping compose/,
  /^\s*WARNING: /,
  /^\s*ERROR: /,
];

export function progressMessage(line: string): string | null {
  const trimmed = line.replace(/\r$/, "");
  if (trimmed.trim() === "") return null;
  for (const pattern of PATTERNS) {
    if (pattern.test(trimmed)) return trimmed.trim();
  }
  return null;
}

/** Incremental line splitter over a byte stream. */
export class LineBuffer {
  private buffer = "";

  push(chunk: string, onLine: (line: string) => void): void {
    this.buffer += chunk;
    let index: number;
    while ((index = this.buffer.indexOf("\n")) >= 0) {
      onLine(this.buffer.slice(0, index));
      this.buffer = this.buffer.slice(index + 1);
    }
  }

  flush(onLine: (line: string) => void): void {
    if (this.buffer.length > 0) onLine(this.buffer);
    this.buffer = "";
  }
}
