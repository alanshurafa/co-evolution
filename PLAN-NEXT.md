# Plan: Next

Product features only, priority order, from the last committed ROADMAP.md
(`.planning/` is owned by another writer and not touched here). Audit,
calibration, and dogfood-evidence phases (v1.2 SC-4, v1.3 bounce
calibration, v1.5 Phase 6 evidence-gathering) are excluded — done, or not
a feature.

1. Publish `@alanshurafa/co-evolution-mcp` to npm (v1.4 Phase 5) — done when `npm install -g @alanshurafa/co-evolution-mcp` works and `co_evolve` responds from an external MCP client (Claude Desktop/Cursor/Continue).
   - 2026-09-12 OPERATOR: npm package lookup returned E404, npm identity returned E401, and no GitHub publishing secret exists; Alan must authenticate and publish using mcp/PUBLISH.md, then exercise the registry install and `co-evolve --help` (the current goal's acceptance condition).
2. Submit the MCP server to the MCP registry and open the awesome-mcp-list PR (v1.4 Phase 6) — done when the registry listing is live or the PR is merged.
   - 2026-09-12: Opened https://github.com/punkpeye/awesome-mcp-servers/pull/14263; observed the public PR in OPEN state with the source-linked server entry (the current goal requires an open submission, not upstream merge).
3. Give `co-evolve` a real subcommand CLI (`co-evolve bounce <file>`, `co-evolve init`) instead of positional-only flags — done when both subcommands run against a fresh checkout without reading the script source.
4. Add one more agent adapter beyond Claude/Codex (Gemini CLI, Ollama, or a direct API call) — done when a bounce completes end-to-end using the new adapter for at least one side.
5. Write the standalone Bounce Protocol spec (markers, convergence rules, role lenses) independent of any single runner's code — done when a new agent adapter can be built from the spec alone, without reading `co-evolve-bouncer.sh`.
6. Ship the automated branch/worktree cleanup utility carried forward from v1.1 — done when a single command removes worktrees/branches left by completed `dev-review` runs.
7. PEL Option 2 (Auto-Promote, `lab/pel-auto/`) — done when a mutation that passes canary and beats the champion on eval auto-merges under an explicit opt-in flag, no PR review step.
