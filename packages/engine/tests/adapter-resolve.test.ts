import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, join } from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";
import { invokeClaudeRead } from "../src/adapters/claude.js";
import { findCmdUnsafeArg, resolveSpawn } from "../src/adapters/resolveBin.js";

describe("findCmdUnsafeArg", () => {
  it("passes the real read-phase argv shape", () => {
    expect(
      findCmdUnsafeArg([
        "-p",
        "--output-format",
        "text",
        "--model",
        "claude-haiku-4-5-20251001",
        "--disallowedTools",
        "Edit,Write,Bash,Glob,Grep,WebSearch,WebFetch",
      ]),
    ).toBeUndefined();
  });

  it.each(["a&b", "a|b", "a>b", "a<b", "a^b", "a%PATH%", 'a"b', "a!b", "a(b", "a)b"])(
    "flags cmd metacharacters (%s)",
    (bad) => {
      expect(findCmdUnsafeArg(["--model", bad])).toBe(bad);
    },
  );
});

describe.runIf(process.platform === "win32")("resolveSpawn on win32", () => {
  let dir: string;
  const savedPath = process.env.PATH;

  beforeAll(() => {
    dir = mkdtempSync(join(tmpdir(), "resolve-bin-"));
    // A .cmd shim that ignores stdin and prints a marker.
    writeFileSync(join(dir, "mocktool.cmd"), "@echo off\r\necho MOCK-CMD-ARTIFACT\r\n");
    // Echoes its argv so ordering through the cmd.exe bridge is observable.
    writeFileSync(join(dir, "echotool.cmd"), "@echo off\r\necho BRIDGE-ARGS:%*\r\n");
    // An empty .exe alongside a .cmd to prove .exe wins (existence check only).
    writeFileSync(join(dir, "bothtool.exe"), "");
    writeFileSync(join(dir, "bothtool.cmd"), "@echo off\r\n");
  });

  afterAll(() => {
    process.env.PATH = savedPath;
    rmSync(dir, { recursive: true, force: true });
  });

  it("resolves a bare name to its .cmd via the search path and bridges through cmd.exe", () => {
    const r = resolveSpawn("mocktool", dir);
    expect(r.file).toBe("cmd.exe");
    expect(r.argsPrefix.slice(0, 3)).toEqual(["/d", "/s", "/c"]);
    expect(r.argsPrefix[3]).toBe(join(dir, "mocktool.cmd"));
  });

  it("prefers .exe over .cmd when both exist", () => {
    const r = resolveSpawn("bothtool", dir);
    expect(r.file).toBe(join(dir, "bothtool.exe"));
    expect(r.argsPrefix).toEqual([]);
  });

  it("returns the bare name when nothing resolves, preserving ENOENT classification", () => {
    const r = resolveSpawn("definitely-not-a-real-binary", dir);
    expect(r.file).toBe("definitely-not-a-real-binary");
    expect(r.argsPrefix).toEqual([]);
  });

  it("probes the extension ladder for an explicit extensionless path", () => {
    const r = resolveSpawn(join(dir, "mocktool"), dir);
    expect(r.file).toBe("cmd.exe");
    expect(r.argsPrefix[3]).toBe(join(dir, "mocktool.cmd"));
  });

  it("keeps prefix args ahead of generated flags through the cmd.exe bridge", async () => {
    process.env.PATH = `${dir}${delimiter}${savedPath ?? ""}`;
    const result = await invokeClaudeRead({
      model: "irrelevant",
      promptText: "x",
      binPath: "echotool",
      binPrefixArgs: ["PREFIX-MARKER"],
      timeoutMs: 30_000,
    });
    expect(result.kind).toBe("artifact");
    if (result.kind === "artifact") {
      const line = result.text.split(/\r?\n/).find((l) => l.includes("BRIDGE-ARGS:"));
      expect(line).toBeDefined();
      const prefixAt = line?.indexOf("PREFIX-MARKER") ?? -1;
      const flagsAt = line?.indexOf("-p") ?? -1;
      expect(prefixAt).toBeGreaterThanOrEqual(0);
      expect(prefixAt).toBeLessThan(flagsAt);
    }
  });

  it("drives invokeClaudeRead end-to-end through a .cmd shim", async () => {
    process.env.PATH = `${dir}${delimiter}${savedPath ?? ""}`;
    const result = await invokeClaudeRead({
      model: "irrelevant",
      promptText: "ignored by the mock",
      binPath: "mocktool",
      timeoutMs: 30_000,
    });
    expect(result.kind).toBe("artifact");
    if (result.kind === "artifact") {
      expect(result.text).toContain("MOCK-CMD-ARTIFACT");
    }
  });

  it("refuses cmd.exe passthrough for unsafe args instead of spawning", async () => {
    process.env.PATH = `${dir}${delimiter}${savedPath ?? ""}`;
    const result = await invokeClaudeRead({
      model: "bad&model",
      promptText: "x",
      binPath: "mocktool",
      timeoutMs: 30_000,
    });
    expect(result.kind).toBe("fatal");
    if (result.kind === "fatal") {
      expect(result.reason).toBe("spawn");
      expect(result.detail).toContain("unsafe argument");
    }
  });
});

describe.runIf(process.platform !== "win32")("resolveSpawn on posix", () => {
  it("is a pass-through", () => {
    expect(resolveSpawn("claude")).toEqual({ file: "claude", argsPrefix: [] });
  });
});
