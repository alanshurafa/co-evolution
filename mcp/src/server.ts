#!/usr/bin/env node
// @alanshurafa/co-evolution-mcp — MCP server exposing one tool, co_evolve.
// Design: docs/superpowers/specs/2026-04-19-mcp-server-design.md + the
// 2026-06-11 v1.4 addendum (in the main co-evolution repo).
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { existsSync } from "node:fs";
import { dirname, isAbsolute, join, resolve } from "node:path";
import { z } from "zod";
import { AGENTS, BounceError, runBounce } from "./bouncer.js";
import { preflight } from "./preflight.js";

const INPUT_SHAPE = {
  document_path: z
    .string()
    .describe("Path to the markdown document to bounce (absolute, or relative to the server's cwd)"),
  max_bounces: z.number().int().min(1).max(5).default(2)
    .describe("Bounce passes between the agents (default 2)"),
  reviewer_agent: z.enum(AGENTS).default("claude"),
  composer_agent: z.enum(AGENTS).default("codex"),
  in_place: z.boolean().default(false)
    .describe("Overwrite the input document with the bounced result"),
  output_path: z.string().optional()
    .describe("Where to write the bounced document (default: <input>.bounced.md; ignored when in_place=true)"),
  runs_dir: z.string().optional()
    .describe("Where run artifacts (state.json, scores, report) accumulate (default: <document_dir>/.co-evolve/runs)"),
};

export function createServer(): McpServer {
  const server = new McpServer({
    name: "co-evolution",
    version: "1.0.0",
  });

  server.registerTool(
    "co_evolve",
    {
      title: "Co-evolve a document",
      description:
        "Bounce a markdown document between two AI agents (reviewer and composer) using the co-evolution disagreement-marker protocol until it converges. Returns the improved document plus, when jq/yq are installed, a deterministic behavior scorecard (including the marker-fate ledger) and a human-readable report.",
      inputSchema: INPUT_SHAPE,
    },
    async (args, extra) => {
      const agents = [args.reviewer_agent, args.composer_agent];
      const check = preflight(agents);
      if (!check.ok) {
        return {
          isError: true,
          content: [
            {
              type: "text" as const,
              text: JSON.stringify(
                {
                  error: "missing_prerequisite",
                  missing: check.missing,
                  install_instructions: check.installInstructions,
                },
                null,
                2,
              ),
            },
          ],
        };
      }

      const documentPath = resolve(args.document_path);
      if (!existsSync(documentPath)) {
        return {
          isError: true,
          content: [
            { type: "text" as const, text: `document_path does not exist: ${documentPath}` },
          ],
        };
      }

      const outputPath = args.in_place
        ? documentPath
        : resolve(args.output_path ?? `${documentPath}.bounced.md`);
      if (!existsSync(dirname(outputPath))) {
        return {
          isError: true,
          content: [
            {
              type: "text" as const,
              text: `output_path parent directory does not exist: ${dirname(outputPath)} (not auto-created — pick an existing directory)`,
            },
          ],
        };
      }

      const runsDir = args.runs_dir
        ? isAbsolute(args.runs_dir)
          ? args.runs_dir
          : resolve(args.runs_dir)
        : join(dirname(documentPath), ".co-evolve", "runs");

      const progressToken = extra._meta?.progressToken;
      let progressCount = 0;
      const onProgress = (message: string) => {
        if (progressToken === undefined) return;
        progressCount += 1;
        void extra.sendNotification({
          method: "notifications/progress",
          params: { progressToken, progress: progressCount, message },
        });
      };

      try {
        const result = await runBounce({
          documentPath,
          maxBounces: args.max_bounces,
          reviewerAgent: args.reviewer_agent,
          composerAgent: args.composer_agent,
          outputPath,
          runsDir,
          onProgress,
          signal: extra.signal,
        });
        const receiptsNote = check.receipts.jq && check.receipts.yq
          ? null
          : "receipts degraded: install jq (state + scores) and mikefarah yq (scorer) for the full scorecard";
        return {
          content: [
            {
              type: "text" as const,
              text: JSON.stringify(
                receiptsNote ? { ...result, receipts_note: receiptsNote } : result,
                null,
                2,
              ),
            },
          ],
        };
      } catch (error) {
        if (error instanceof BounceError) {
          if (error.code) {
            return {
              isError: true,
              content: [
                {
                  type: "text" as const,
                  text: JSON.stringify(
                    {
                      error: error.code,
                      message: error.message,
                      ...error.details,
                      run_dir: error.runDir,
                    },
                    null,
                    2,
                  ),
                },
              ],
            };
          }
          return {
            isError: true,
            content: [
              {
                type: "text" as const,
                text: JSON.stringify(
                  {
                    error: error.message,
                    run_dir: error.runDir,
                    log_tail: error.stderrTail,
                  },
                  null,
                  2,
                ),
              },
            ],
          };
        }
        throw error;
      }
    },
  );

  return server;
}

// Entry point: stdio transport when invoked as a binary; importable for tests.
const invokedDirectly =
  process.argv[1] !== undefined &&
  import.meta.url.endsWith(process.argv[1].split("/").pop() ?? "");
if (invokedDirectly) {
  const server = createServer();
  const transport = new StdioServerTransport();
  await server.connect(transport);
}
