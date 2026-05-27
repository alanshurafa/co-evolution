---
name: codex-access
description: >
  Reference pattern for invoking the OpenAI Codex CLI across environments
  (WSL with Windows-side install, native Linux/macOS, or "codex unavailable"
  fallback). Centralizes the launch matrix used by the co-evolve bouncer,
  dev-review runtime, and PEL adapters so scripts don't reimplement it.
  Triggers on "how do I call codex", "codex not found", "set up codex",
  "codex install", "WSL codex bridge", and "make codex work for co-evolution".
allowed-tools: Bash, Read
---

# /codex-access — Codex CLI Launch Pattern

Use this skill when:
- A script needs to invoke `codex` and you don't want to duplicate the WSL
  bridge / install-detection / fallback logic.
- A user reports "codex command not found" or "codex unavailable" and you need
  to point them at the canonical fix.
- You're writing a new agent adapter and want it to handle codex availability
  the same way `co-evolve-bouncer.sh` does.

This skill does NOT install codex for the user — installation requires their
OpenAI account and an API key. It documents the launch matrix and provides a
sourceable helper.

## The Launch Matrix

Codex is invoked one of three ways, in priority order:

| # | When | How |
|---|------|-----|
| 1 | WSL with Windows-side codex install | `cmd.exe /c codex exec ...` (bridge) |
| 2 | Native Linux/macOS with `codex` on PATH | `codex exec ...` (direct) |
| 3 | Codex not reachable anywhere | Empty output + install hint to stderr |

### Why the WSL bridge

WSL and Windows keep separate auth state — installing codex inside WSL means
re-authenticating with OpenAI and double-billing. The recommended pattern is
to install codex on the Windows side, then call it from WSL via `cmd.exe /c
codex`. Path translation is handled by `wslpath -w` for the `-C <workdir>`
and `-o <output>` flags.

### Why the empty-output fallback

The existing `invoke_*` contract across this codebase is: errors flow through
empty output_file + populated stderr_file. Callers detect failure by checking
`[[ ! -s "$output_file" ]]`. The "codex unreachable" case follows this same
contract so existing callers don't need a new branch — they get the empty
output and surface it with their normal failure UX (e.g. `co-evolve-bouncer.sh`
prints "CO-EVOLVE INCOMPLETE" + HINT when this happens during a bounce pass).

## The Helper

Source `lib/codex-access.sh` and call:

```bash
source "$REPO_ROOT/lib/codex-access.sh"

# Check up-front whether codex is reachable (before committing to a workflow):
if codex_available; then
  echo "codex ready"
else
  codex_install_hint >&2
  exit 1
fi

# Or just invoke and let empty-output handle failure:
codex_invoke "$prompt_file" "$output_file" "$stderr_file"
if [[ ! -s "$output_file" ]]; then
  cat "$stderr_file" >&2  # contains the install hint when codex was missing
  exit 1
fi
```

### Function reference

| Function | Returns | Purpose |
|---|---|---|
| `codex_available` | exit 0 if reachable, 1 otherwise | Up-front check before workflows that require codex |
| `codex_invoke <prompt> <output> <stderr>` | always 0 | Drop-in for the existing `invoke_codex` contract |
| `codex_install_hint` | prints to stdout | Multi-line actionable install/availability message |

`codex_invoke` honors the same env vars as the existing `invoke_codex` in
`lib/co-evolution.sh`:
- `WORKDIR` — codex `-C` argument (defaults to `$PWD`)
- `CODEX_MODEL` — passes `-c model=<value>` to codex

## Install Path For Users

When a user asks how to get codex working:

### Native Linux / macOS

```bash
npm install -g @openai/codex
export OPENAI_API_KEY=sk-...
codex --version  # verify
```

Authenticate once, then `codex_available` will return 0 and `codex_invoke`
will route through the direct path.

### WSL (recommended)

Install on the **Windows** side, not inside WSL:

```powershell
# In a Windows shell (PowerShell or cmd.exe):
npm install -g @openai/codex
setx OPENAI_API_KEY "sk-..."
codex --version
```

Then from WSL, `codex_invoke` will automatically use the `cmd.exe /c codex`
bridge with `wslpath` translation. Don't install codex inside WSL too — auth
state is per-side and you'll be billed twice.

### Remote container / no API key (the cloud case)

If you're running in a managed remote container (e.g. Claude Code on the web,
a CI runner, an ephemeral sandbox) and don't have an OpenAI API key in the
environment, codex won't be reachable regardless of install attempts. The
right move is:

```bash
bash co-evolve-bouncer.sh --single-model claude ...
```

This trades cross-vendor diversity for the ability to run at all. The
`co-evolve-bouncer.sh` failure UX will already suggest this when codex fails
mid-bounce.

## Integration With Existing Code

`lib/co-evolution.sh:invoke_codex` already implements the launch matrix
inline (it predates this helper). Both implementations are kept in sync:
new scripts should source `lib/codex-access.sh` rather than copy the inline
pattern. A future refactor may collapse `invoke_codex` to call `codex_invoke`,
but that's a hot path and gated on a separate change.

The PEL adapters (`lab/pel/*/adapter.sh`) and dev-review runtime
(`dev-review/codex/dev-review.sh`) currently inline the same pattern. They
work — but if you touch them, prefer routing through the helper.

## Verifying The Pattern

The hermetic test `tests/codex-access-simulation.sh` exercises:
- WSL detection branch (when `WSL_DISTRO_NAME` is set and `cmd.exe` is on PATH)
- Direct-call branch (codex on PATH, no WSL)
- Unreachable branch (no codex, no WSL — produces install hint to stderr,
  empty output, exit 0)

Run it before changing the helper:

```bash
bash tests/codex-access-simulation.sh
```

## What This Skill Does NOT Do

- Does not install codex on the user's machine — that requires their account.
- Does not configure `OPENAI_API_KEY` — that's user state.
- Does not fake codex with claude. Same-model co-evolution lives behind
  `--single-model` in `co-evolve-bouncer.sh`; mixing the two would hide
  cross-vendor diversity behind a misleading flag name.
- Does not auto-fall-back from `codex` to `claude`. The invariant in
  `co-evolve-bouncer.sh` is that single-model only activates via explicit
  user flag. This skill respects that.
