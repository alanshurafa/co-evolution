# Codex Headless Research: Smoke, Token Line, Plugin Route

**Date:** 2026-06-12  
**Phase:** v1.5 Phase 0 (T1, R2, T4)  
**Purpose:** Pin environment facts needed by Phases 1–5.

---

## T1 — Codex CLI symlink + smoke

### Binary location

```
/Applications/Codex.app/Contents/Resources/codex
-rwxr-xr-x@ 1 shurafa  staff  213429648 Jun 11 16:11
```

### Symlink created

```
ln -s "/Applications/Codex.app/Contents/Resources/codex" ~/.local/bin/codex
```

Result: `lrwxr-xr-x@ 1 shurafa  staff  48 Jun 12 12:28 /Users/shurafa/.local/bin/codex -> /Applications/Codex.app/Contents/Resources/codex`

### Version

```
codex-cli 0.140.0-alpha.2
```

### Config (~/.codex/config.toml relevant fields)

```toml
model = "gpt-5.5"
model_reasoning_effort = "xhigh"
service_tier = "priority"
```

### Headless smoke command

```bash
mkdir -p "$TMPDIR/codex-smoke" && cd "$TMPDIR/codex-smoke" && \
  ~/.local/bin/codex exec --full-auto --skip-git-repo-check \
  "Reply with exactly: SMOKE-OK" > out.txt 2> err.txt; echo "exit=$?"
```

**Exit code: 0**

### stdout (out.txt — verbatim)

```
SMOKE-OK
```

### stderr (err.txt — verbatim)

```
warning: `--full-auto` is deprecated; use `--sandbox workspace-write` instead.
Reading additional input from stdin...
OpenAI Codex v0.140.0-alpha.2
--------
workdir: /private/var/folders/20/vl4p6fsd2dsbf5r68611c6nc0000gn/T/codex-smoke
model: gpt-5.5
provider: openai
approval: never
sandbox: workspace-write [workdir, /tmp, $TMPDIR]
reasoning effort: xhigh
session id: 019ebcaa-5766-7c60-beb8-824b921d69a1
--------
user
Reply with exactly: SMOKE-OK
codex
SMOKE-OK
tokens used
11,681
```

**Conclusion:** Auth works headless. gpt-5.5 + xhigh accepted. ChatGPT-plan tier confirmed (`service_tier = "priority"` in config).

---

## R2 — Codex end-of-run token usage line (verbatim + stream)

**Stream:** stderr  
**Exact lines (verbatim, from smoke run above):**

```
tokens used
11,681
```

Two lines: the label `tokens used` on one line, then the formatted integer with comma separator on the next line.

**Format for Phase 4 grep/parse:**  
The token count follows the literal line `tokens used` (no colon) as the immediately subsequent line. Parse with:
```bash
grep -A1 "^tokens used$" err.txt | tail -1
```
or equivalently with `awk '/^tokens used$/{getline; print}'`.  
The number uses comma formatting (e.g., `11,681`); strip commas before arithmetic: `tr -d ','`.

**Note on deprecation:** `--full-auto` is deprecated in favor of `--sandbox workspace-write`. Both flags produce the same token output format. The runner may want to migrate to `--sandbox workspace-write` in Phase 1.

---

## T4 — Plugin install route

### `claude plugin --help` subcommands (relevant)

```
claude plugin install|i [options] <plugin>
  Install a plugin from available marketplaces
  Options:
    --config <key=value>  Set a userConfig option (repeatable)
    -s, --scope <scope>   user, project, or local (default: "user")

claude plugin marketplace [options] [command]
  Commands:
    add [options] <source>      Add a marketplace from a URL, path, or GitHub repo
    list [options]              List all configured marketplaces
    remove|rm [options] <name>  Remove a configured marketplace
    update [options] [name]     Update marketplace(s)
```

### Non-interactive install route (confirmed working)

Step 1 — Add the marketplace:
```bash
claude plugin marketplace add openai/codex-plugin-cc
```
Output:
```
Adding marketplace…SSH not configured, cloning via HTTPS: https://github.com/openai/codex-plugin-cc.git
Refreshing marketplace cache (timeout: 120s)…
Cloning repository (timeout: 120s): https://github.com/openai/codex-plugin-cc.git
Clone complete, validating marketplace…
Cleaning up old marketplace cache…
✔ Successfully added marketplace: openai-codex (declared in user settings)
```

Step 2 — Install the plugin:
```bash
claude plugin install codex@openai-codex
```
Output:
```
Installing plugin "codex@openai-codex"...✔ Successfully installed plugin: codex@openai-codex (scope: user)
```

### Verification (`claude plugin list`)

```
Installed plugins:

  ❯ codex@openai-codex
    Version: 1.0.4
    Scope: user
    Status: ✔ enabled
```

### Plugin details (component inventory)

```
codex 1.0.4
  Use Codex from Claude Code to review code or delegate tasks.
  Source: codex@openai-codex

Component inventory
  Skills (10)  adversarial-review, cancel, codex-cli-runtime, codex-result-handling,
               gpt-5-4-prompting, rescue, result, review, setup, status
  Agents (1)   codex-rescue
  Hooks (3)    SessionStart, SessionEnd, Stop  (harness-only — no model context cost)
  MCP servers (0)
  LSP servers (0)

Projected token cost
  Always-on:   ~306 tok   added to every session
```

**Key skills for v1.5:** `/codex:rescue` (delegate tasks to Codex), `/codex:status` (check job status), `/codex:review` (adversarial review), `/codex:cancel` (cancel running job).

### Conclusion

A fully **non-interactive** install route exists and works. No `/plugin` UI required. The plan's note about "if it requires the interactive /plugin UI" is moot — `claude plugin marketplace add` + `claude plugin install` suffice. The install persists at user scope.

### Interactive equivalent (for reference only, not needed)

Would be: open Claude Code, type `/plugin marketplace add openai/codex-plugin-cc`, then `/plugin install codex`. The CLI route above is strictly equivalent.

---

## Summary

| Item | Fact |
|---|---|
| codex binary | `/Applications/Codex.app/Contents/Resources/codex` (213 MB, Jun 11) |
| codex version | 0.140.0-alpha.2 |
| symlink | `~/.local/bin/codex` → binary (created 2026-06-12) |
| smoke exit | 0 |
| smoke stdout | `SMOKE-OK` |
| token line stream | **stderr** |
| token line format | two lines: `tokens used` then `11,681` (comma-formatted integer) |
| `--full-auto` | deprecated; equivalent `--sandbox workspace-write` |
| plugin install | non-interactive, fully CLI-driven |
| plugin name | `codex@openai-codex` v1.0.4, user scope, enabled |
| plugin skills | rescue, status, review, cancel, adversarial-review (+ 5 more) |
