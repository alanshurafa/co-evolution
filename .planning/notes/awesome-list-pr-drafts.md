# Awesome-list PR Drafts

**Created:** 2026-04-18
**Status:** Drafted, not submitted. Review + approve before forking and PRing.
**Submission timing:** Wait ~1 week after llms.txt + topics ship, so maintainers see a cleanly-indexed repo. Also consider: at 1 star, some lists may reject — revisit once stars reach 10+ or there is demonstrable external adoption.

## Target lists (verify each exists + is actively maintained before PRing)

1. `hesreallyhim/awesome-claude-code` — high fit (Claude Code skill + adapter)
2. `e2b-dev/awesome-ai-agents` — broad multi-agent list
3. Search for active `awesome-llm-agents` variants — don't submit to inactive forks
4. Search for `awesome-multi-agent-systems` / `awesome-multi-agent-llm` variants
5. Consider `awesome-cli` / `awesome-bash` if a dev-tooling angle fits their scope

Check last-merged-PR date on each list. Skip lists with no activity in the last 6–12 months.

## Entry drafts

### awesome-claude-code

Likely section: "Workflows" or "Skills" (read their categorization — match the idiom).

```
- [Co-Evolution](https://github.com/alanshurafa/co-evolution) — Structured iterative refinement between AI agents using expiring in-document disagreement markers (`[CONTESTED]` / `[CLARIFY]`). Ships a Claude Code skill `/dev-review` that runs a compose → bounce → execute → verify workflow with Codex CLI as the bounce partner; every run ends converged, adjudicated, or explicitly flagged stuck — never silently.
```

### awesome-ai-agents

Likely section: "Orchestration" or "Multi-agent frameworks."

```
- [Co-Evolution](https://github.com/alanshurafa/co-evolution) — Agent-agnostic bash harness that bounces a shared markdown document between two CLI agents (Claude Code + Codex CLI by default) using `[CONTESTED]` and `[CLARIFY]` markers that auto-expire after 2 passes. Filesystem as coordination substrate; add any CLI-based agent by writing one adapter function.
```

### awesome-llm-agents (if an active variant exists)

```
- [Co-Evolution](https://github.com/alanshurafa/co-evolution) — Cross-CLI LLM debate tool. Two agents refine a shared markdown artifact using in-document disagreement markers with a 2-pass staleness rule. Bash + adapter pattern; no API orchestration required.
```

## Per-list checklist (before forking)

- [ ] Read `CONTRIBUTING.md` for style rules and placement conventions
- [ ] Identify the correct alphabetical / categorical slot
- [ ] Run a local grep to confirm Co-Evolution isn't already listed
- [ ] Verify our README + llms.txt + topics are live and clean
- [ ] Fork the list repo
- [ ] Add the one-line entry (match the list's tone)
- [ ] Open PR with body: "Add Co-Evolution — <one-line description>. <Relevant repo metric, e.g. recently shipped v1.1, first tool with expiring in-document disagreement markers>"
- [ ] Respond to any style feedback; do not argue categorization

## Risks / wait conditions

- **Low adoption bar:** at 1 star, some lists reject. If rejected, ask what threshold, don't reapply immediately.
- **Inactive maintainer:** if PR sits >30 days, withdraw and target an alternative list.
- **Style mismatch:** each list has its own voice. Use the list's existing entries as a template.
- **Cross-list collision:** don't PR all 4 on the same day. Stagger by ~3 days so one rejection doesn't signal a pattern.
