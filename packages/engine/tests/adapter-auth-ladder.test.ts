import { describe, expect, it } from "vitest";
import {
  classifyClaudeOutput,
  invokeClaudeRead,
  outputContainsAuthBanner,
} from "../src/adapters/claude.js";

const LONG_TROUBLESHOOT = Array.from({ length: 70 }, (_, i) => `word${i}`).join(" ");

describe("output auth ladder (A-2 + C-8 port)", () => {
  it("flags a long auth-error page led by a banner (the pre-A-2 false negative)", () => {
    const page = `Not logged in · Please run /login\n\nTroubleshooting: ${LONG_TROUBLESHOOT}`;
    const r = classifyClaudeOutput(page, "");
    expect(r.kind).toBe("fatal");
    if (r.kind === "fatal") {
      expect(r.reason).toBe("auth");
      expect(r.detail).toContain("A-2");
    }
  });

  it("passes a long document that quotes a banner inside a code fence", () => {
    const doc = `# Auth handling notes\n\nThe adapter must catch this case:\n\n\`\`\`\nNot logged in · Please run /login\n\`\`\`\n\n${LONG_TROUBLESHOOT}`;
    expect(classifyClaudeOutput(doc, "").kind).toBe("artifact");
  });

  it("passes a long document mentioning an auth phrase mid-sentence", () => {
    const doc = `# Session notes\n\nThe old Session expired handling was replaced last year.\n\n${LONG_TROUBLESHOOT}`;
    expect(classifyClaudeOutput(doc, "").kind).toBe("artifact");
  });

  it("still flags a bare short banner the anchor excludes, via the word ceiling (C-8)", () => {
    const r = classifyClaudeOutput("Unauthorized", "");
    expect(r.kind).toBe("fatal");
    if (r.kind === "fatal") expect(r.reason).toBe("auth");
  });

  it("limits the head-scan to the first 20 non-empty lines, like the Bash source", () => {
    const filler = Array.from({ length: 25 }, (_, i) => `line ${i} of an ordinary document`).join("\n");
    expect(outputContainsAuthBanner(`${filler}\nNot logged in · Please run /login`)).toBe(false);
  });

  it("classifies shell missing-binary stderr with empty stdout as missing-cli, not empty", () => {
    const stderr =
      "'claude' is not recognized as an internal or external command,\r\noperable program or batch file.";
    const r = classifyClaudeOutput("", stderr);
    expect(r.kind).toBe("fatal");
    if (r.kind === "fatal") expect(r.reason).toBe("missing-cli");
  });
});

describe("invokeClaudeRead boundary validation", () => {
  it("throws on a non-positive timeout instead of masquerading as a real timeout", () => {
    expect(() => invokeClaudeRead({ model: "m", promptText: "x", timeoutMs: -1 })).toThrow(
      TypeError,
    );
  });
});
