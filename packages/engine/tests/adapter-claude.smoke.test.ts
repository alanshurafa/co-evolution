import { describe, expect, it } from "vitest";
import { invokeClaudeRead } from "../src/adapters/claude.js";

/**
 * Paid smoke test — a single REAL `claude` call against subscription auth.
 * Skipped everywhere unless CO_EVOLVE_SMOKE=1 (so `npm test` / CI stay
 * hermetic). The CLI must be logged in (ithelast@hotmail.com). Run by the
 * orchestrator, never by workers:
 *
 *   CO_EVOLVE_SMOKE=1 npm test -- adapter-claude.smoke
 */
describe.skipIf(process.env.CO_EVOLVE_SMOKE !== "1")(
  "invokeClaudeRead smoke (paid, real claude)",
  () => {
    it("returns an artifact containing OK", async () => {
      const result = await invokeClaudeRead({
        model: "claude-haiku-4-5-20251001",
        promptText: "Reply with exactly: OK",
        timeoutMs: 120_000,
      });
      expect(result.kind).toBe("artifact");
      if (result.kind === "artifact") {
        expect(result.text).toContain("OK");
      }
    }, 130_000);
  },
);
