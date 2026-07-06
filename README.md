# Co-Evolution

Tools for structured iterative refinement between AI agents and humans. Documents
bounce back and forth between agents using disagreement markers until they
converge, producing tighter and more precise output than any single agent would
alone.

## Default Usage

Start with the general Co-Evolution runner unless the task specifically needs
code execution:

```bash
bash ./co-evolve-bouncer.sh --vanilla "stress test this idea"
```

For an existing markdown document:

```bash
bash ./co-evolve-bouncer.sh --vanilla --bounce-only docs/plan.md
```

Use `dev-review` only when you want a code-focused compose -> bounce -> execute
-> verify workflow.

## Prerequisites

Check your machine in one command — it lists everything below with an
OK / MISSING / OPTIONAL verdict per item:

```bash
bash scripts/doctor.sh
```

What the components need:

- **Everywhere:** Bash (3.2+ works, including stock macOS `/bin/bash`; 4+ recommended), `git`, `jq`, `awk`, and the `claude` CLI — **logged in** (run `claude` once interactively; an unauthenticated CLI is the most common silent failure).
- **Cross-AI passes and `dev-review` (default composer/executor):** the `codex` CLI. `co-evolve --vanilla` works without it.
- **Eval harness (`evals/`) and PEL lab (`lab/pel/`):** the mikefarah/Go `yq` (v4+), **not** the Python `yq` from Debian/Ubuntu's `apt install yq`, which is incompatible. Those components fail fast if the wrong `yq` is on `PATH`. `xxd` is used for byte-level eval diagnostics.
- **PEL PR emission:** the `gh` CLI (dry-run mode works without it).
- **Per-phase timeouts:** `timeout(1)` from GNU coreutils. Stock macOS lacks it — `brew install coreutils` — but a built-in perl fallback keeps timeouts working without it.

## Installation

The runtime is plain Bash, so Co-Evolution installs the same way on every
platform. You need a Bash shell, `git`, and the agent CLIs the bouncer calls —
`claude`, plus `codex` for the default cross-AI pass. `jq` and `yq` (mikefarah's
Go build) are only needed if you run the eval harness under `evals/`.

| Platform | Shell to run it in | Install git (+ optional jq/yq) |
|----------|--------------------|--------------------------------|
| macOS | Terminal | `brew install git jq yq` |
| Linux | any terminal | `apt install git jq`, and `yq` from mikefarah |
| Windows | Git Bash (ships with Git for Windows) or WSL | `scoop install git jq yq` |

From the cloned repo, in that Bash shell, install the `co-evolve` command:

```bash
mkdir -p ~/.claude/skills/co-evolution ~/.local/bin
cp -R skills/co-evolution/* ~/.claude/skills/co-evolution/

cat > ~/.local/bin/co-evolve <<EOF
#!/usr/bin/env bash
cd "$PWD" || exit 1
exec bash ./co-evolve-bouncer.sh "\$@"
EOF
chmod +x ~/.local/bin/co-evolve
```

Make sure `~/.local/bin` is on your `PATH` — `echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc` (use `~/.zshrc` on macOS). Then the default command is:

```bash
co-evolve --vanilla "what should I do next?"
```

Optional code workflow:

```bash
mkdir -p ~/.claude/skills/dev-review
cp -R skills/dev-review/* ~/.claude/skills/dev-review/
```

### Windows

Run from Git Bash or WSL rather than PowerShell or CMD — the tool is a Bash
program. Two cross-platform details are handled for you:

- Shell scripts are pinned to LF line endings (via `.gitattributes`), so they run
  correctly whatever your Git `autocrlf` setting is.
- Path arguments are normalized: under WSL you can pass a Windows path such as
  `C:\work\plan.md` and it is converted automatically; under Git Bash, use
  forward slashes (`C:/work/plan.md`).

## What's In This Repo

### [Co-Evolution Skill](skills/co-evolution/)

`/co-evolution` is the default Claude Code skill for general questions, ideas,
drafts, markdown files, plans, specs, and arguments. It routes to
`co-evolve-bouncer.sh` and does not execute repo changes.

```text
/co-evolution Stress test this launch plan
```

### [Co-Evolve Bouncer](co-evolve-bouncer.sh)

The primary standalone runner. It can compose from a question, bounce an
existing document, or run staged critique -> defend -> tighten passes.

```bash
bash ./co-evolve-bouncer.sh --vanilla "What is the strongest version of this argument?"
bash ./co-evolve-bouncer.sh --vanilla --chain "Should we ship this migration?"
```

### [Agent Bouncer](agent-bouncer/)

A legacy runner (still used by tests/experiments) that bounces any markdown
document between two agents. Agent-agnostic: ships with Claude and Codex
adapters, and new agents can be added by writing one function. Runs from any
terminal.

```bash
# Pass any document you want refined
bash ./agent-bouncer/agent-bouncer.sh your-document.md
```

### [Codex Runtime](dev-review/codex/)

A standalone Bash runtime for the full `dev-review` compose -> bounce -> execute
-> optional verify workflow. Use it when the task is a real repo change and you
want a bounced plan, an execution trail, or a verifier pass outside Claude Code.

```bash
# Produce a plan and stop
bash dev-review/codex/dev-review.sh --plan-only "Add docs for the Codex runtime"

# Execute an approved plan file
bash dev-review/codex/dev-review.sh --skip-plan --plan .planning/phases/04-docs-and-routing/04-01-PLAN.md
```

Start with [dev-review/codex/README.md](dev-review/codex/README.md) for usage
details and [dev-review/codex/instructions.md](dev-review/codex/instructions.md)
when you want Codex to route between the repo entrypoints automatically.

### [Dev-Review Skill](skills/dev-review/)

`/dev-review` is a Claude Code skill that wraps the bounce protocol in a
code-focused compose-bounce-execute-verify workflow. Use it inside Claude Code
when the intended deliverable is a repo change, not a general answer or document
refinement.

### [Lab](lab/)

First-class beta channel for experimental features that could break the core
runner if shipped prematurely. Opt-in only: users who never pass `--lab <mode>`
see zero behavior change. See [lab/README.md](lab/README.md) for the boundary
conventions, graduation criteria, anti-criteria, and sandbox guarantee.

```bash
# Invoke a lab mode
co-evolve --lab pel-proposer "task"
bash dev-review/codex/dev-review.sh --lab pel-proposer "task"
```

Unknown modes fail fast with a list of available modes. There is no silent
fallthrough.

### Picking The Right Entrypoint

| Task shape | Tool |
|------------|------|
| General question, idea, strategy, draft, or argument | `co-evolve-bouncer.sh` |
| Existing markdown document needs refinement | `co-evolve-bouncer.sh --bounce-only` |
| Small, low-risk repo edit in 1-2 files | Direct execution |
| Multi-file code change, medium/high risk, or plan/verify workflow | `dev-review/codex/dev-review.sh` |
| Codex builds in the background while the session plans and reviews | `skills/codex-build/` (`--preset codex-build`, detached) |
| General co-evolution inside Claude Code | `skills/co-evolution/` |
| Code pipeline inside Claude Code | `skills/dev-review/` |
| External MCP client (Claude Desktop, Cursor, Continue) | `npm i -g @alanshurafa/co-evolution-mcp` |

### Interactive Tooling vs The Pipeline

The pipeline above (`co-evolve-bouncer.sh`, `dev-review/codex/dev-review.sh`) is
headless and plugin-free by design — no live-session dependencies. In an
interactive Claude Code session on this repo, the official Codex plugin is
also available for ad-hoc work: `/plugin marketplace add openai/codex-plugin-cc`
then `/plugin install codex@openai-codex` gets you `/codex:adversarial-review`,
`/codex:transfer`, and related commands. Leave the plugin's review gate off —
this repo's own review engine already covers that job. The Anthropic advisor
tool is API-only and has no role in either the pipeline or the plugin.

### [MCP Server](mcp/)

The bounce protocol without `git clone`: `@alanshurafa/co-evolution-mcp`
wraps the co-evolve bouncer as an MCP server with one `co_evolve` tool.
External clients get the bounced document plus the v1.3 receipts — behavior
scorecard, marker-fate ledger, human report — on every call. See
[mcp/README.md](mcp/README.md) for install and client config.

### The Bounce Protocol

The shared foundation. Two markers - `[CONTESTED]` and `[CLARIFY]` - coordinate
structured disagreement between agents. Markers do not silently expire: a
`co-evolve-bouncer.sh` run either **converges** (markers reach 0 within the
configured passes), gets **adjudicated** (a final forced pass resolves every
leftover marker and records each choice, with a one-line rationale, in
`adjudication-report.md`), or is marked **stuck** (no defensible resolution was
possible, so the markers are preserved and the document is labeled NOT-final).
Every run therefore ends with an auditable convergence verdict rather than a
possibly-forced "0 markers". The protocol is customizable: swap in
domain-specific markers, adjust the pass count, change role lenses.

## Status

Early development. The Co-Evolution skill, Co-Evolve Bouncer, Agent Bouncer,
Dev-Review skill, and standalone Codex runtime are functional and run
cross-platform on macOS, Linux, and Windows (Git Bash or WSL) — shell scripts
are pinned to LF endings and Windows/WSL path arguments are normalized
automatically. The 3-OS CI suite validates the hermetic (stubbed-CLI)
simulations, not live-LLM runs. Next steps:

- Additional agent adapters (Gemini CLI, Ollama, direct API calls)
- Standalone bounce protocol spec
- Proper CLI (`co-evolve bounce`, `co-evolve init`)

## License

MIT
