import { describe, expect, it } from "vitest";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  AUTH_FAILURE_REGEX,
  DISALLOWED_TOOLS,
  HARNESS_ENV_VARS,
  buildClaudeReadArgs,
  classifyClaudeOutput,
  invokeClaudeRead,
  type AdapterCallOptions,
  type AdapterResult,
} from "../src/adapters/index.js";

const FIXTURES = fileURLToPath(new URL("./fixtures/adapters/", import.meta.url));
const stub = (name: string): string => path.join(FIXTURES, name);

/** Build options that run a Node stub cross-platform via [node, stubScript]. */
const runStub = (
  name: string,
  extra: Partial<AdapterCallOptions> = {},
): AdapterCallOptions => ({
  model: "test-model",
  promptText: "PROMPT-TEXT-123",
  binPath: process.execPath,
  binPrefixArgs: [stub(name)],
  timeoutMs: 15_000,
  ...extra,
});

describe("buildClaudeReadArgs (PRTP-03: never a schema flag)", () => {
  const combos: AdapterCallOptions[] = [
    { model: "claude-opus-4-8", promptText: "p" },
    { model: "claude-haiku-4-5-20251001", promptText: "p", effort: "high" },
    { model: "m", promptText: "p", effort: "" }, // empty effort => omitted
    { model: "m", promptText: "p", effort: "xhigh", binPath: "/x/claude" },
  ];

  for (const opts of combos) {
    it(`emits no schema flag for ${JSON.stringify({ model: opts.model, effort: opts.effort })}`, () => {
      const args = buildClaudeReadArgs(opts);
      // PRTP-03: a schema flag hangs `claude -p` headless on Windows. No option
      // combination may ever produce one.
      expect(args).not.toContain("--output-schema");
      for (const arg of args) {
        expect(arg.toLowerCase()).not.toContain("schema");
      }
      // The only output flag is text.
      const fmt = args.indexOf("--output-format");
      expect(fmt).toBeGreaterThanOrEqual(0);
      expect(args[fmt + 1]).toBe("text");
    });
  }

  it("orders flags exactly and gates --effort on a truthy value", () => {
    expect(buildClaudeReadArgs({ model: "M", promptText: "p" })).toEqual([
      "-p",
      "--output-format",
      "text",
      "--model",
      "M",
      "--disallowedTools",
      DISALLOWED_TOOLS,
    ]);
    expect(
      buildClaudeReadArgs({ model: "M", promptText: "p", effort: "high" }),
    ).toEqual([
      "-p",
      "--output-format",
      "text",
      "--model",
      "M",
      "--effort",
      "high",
      "--disallowedTools",
      DISALLOWED_TOOLS,
    ]);
  });

  it("restricts the read-phase tool set verbatim", () => {
    expect(DISALLOWED_TOOLS).toBe("Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch");
  });
});

describe("classifyClaudeOutput (ported Bash ladder)", () => {
  it("non-empty, non-auth output is an artifact", () => {
    const r = classifyClaudeOutput("a genuine multi word document", "");
    expect(r.kind).toBe("artifact");
    if (r.kind === "artifact") {
      expect(r.text).toBe("a genuine multi word document");
    }
  });

  it("short auth banner in output is fatal/auth", () => {
    const r = classifyClaudeOutput("Not logged in · Please run /login", "");
    expect(r).toMatchObject({ kind: "fatal", reason: "auth" });
  });

  it("long document mentioning auth mid-body passes as artifact", () => {
    const long = `${"word ".repeat(60)}Unauthorized appears here mid sentence.`;
    const r = classifyClaudeOutput(long, "");
    expect(r.kind).toBe("artifact");
  });

  it("empty output with auth stderr is fatal/auth", () => {
    const r = classifyClaudeOutput("", "Not logged in\n");
    expect(r).toMatchObject({ kind: "fatal", reason: "auth" });
  });

  it("empty output with benign stderr is empty (retryable)", () => {
    const r = classifyClaudeOutput("", "some progress noise\n");
    expect(r.kind).toBe("empty");
  });

  it("auth regex matches the ported banners", () => {
    expect(AUTH_FAILURE_REGEX.test("Not logged in")).toBe(true);
    expect(AUTH_FAILURE_REGEX.test("authentication_error")).toBe(true);
    expect(AUTH_FAILURE_REGEX.test("a normal sentence")).toBe(false);
  });
});

describe("invokeClaudeRead (hermetic, Node stubs)", () => {
  it("returns an artifact for normal output", async () => {
    const r = await invokeClaudeRead(runStub("stub-artifact.mjs"));
    expect(r.kind).toBe("artifact");
    if (r.kind === "artifact") {
      expect(r.text).toContain("normal artifact document");
    }
  });

  it("returns empty for no output", async () => {
    const r = await invokeClaudeRead(runStub("stub-empty.mjs"));
    expect(r.kind).toBe("empty");
  });

  it("returns fatal/auth for a short auth banner", async () => {
    const r = await invokeClaudeRead(runStub("stub-auth-short.mjs"));
    expect(r).toMatchObject({ kind: "fatal", reason: "auth" });
  });

  it("returns artifact for a long doc that merely mentions auth", async () => {
    const r = await invokeClaudeRead(runStub("stub-auth-long.mjs"));
    expect(r.kind).toBe("artifact");
  });

  it("returns fatal/auth when output is empty but stderr shows auth failure", async () => {
    const r = await invokeClaudeRead(runStub("stub-stderr-auth-empty.mjs"));
    expect(r).toMatchObject({ kind: "fatal", reason: "auth" });
    if (r.kind === "fatal") {
      expect(r.stderrTail).toContain("Failed to authenticate");
    }
  });

  it("delivers promptText to the child on stdin", async () => {
    const r = await invokeClaudeRead(
      runStub("stub-echo-stdin.mjs", { promptText: "hello-from-stdin-42" }),
    );
    expect(r.kind).toBe("artifact");
    if (r.kind === "artifact") {
      expect(r.text).toBe("STDIN>>>hello-from-stdin-42");
    }
  });

  it("strips all six RNPT-06 harness vars from the child env", async () => {
    const saved = new Map<string, string | undefined>();
    for (const key of HARNESS_ENV_VARS) {
      saved.set(key, process.env[key]);
      process.env[key] = "SENTINEL"; // present in parent, must be gone in child
    }
    let r: AdapterResult;
    try {
      r = await invokeClaudeRead(runStub("stub-env-echo.mjs"));
    } finally {
      for (const [key, value] of saved) {
        if (value === undefined) {
          delete process.env[key];
        } else {
          process.env[key] = value;
        }
      }
    }
    expect(r.kind).toBe("artifact");
    if (r.kind === "artifact") {
      const seen = JSON.parse(r.text) as { present: string[] };
      expect(seen.present).toEqual([]);
    }
  });

  it("returns fatal/missing-cli when the binary does not exist", async () => {
    const r = await invokeClaudeRead({
      model: "m",
      promptText: "p",
      binPath: path.join(FIXTURES, "definitely-not-a-real-binary"),
      binPrefixArgs: [],
      timeoutMs: 15_000,
    });
    expect(r).toMatchObject({ kind: "fatal", reason: "missing-cli" });
  });

  it("returns fatal/timeout and kills a hanging child", async () => {
    const start = Date.now();
    const r = await invokeClaudeRead(
      runStub("stub-hang.mjs", { timeoutMs: 400 }),
    );
    const elapsed = Date.now() - start;
    expect(r).toMatchObject({ kind: "fatal", reason: "timeout" });
    // Resolved far sooner than the stub's ~1000s sleep => the child was killed.
    expect(elapsed).toBeLessThan(5_000);
  }, 15_000);
});
