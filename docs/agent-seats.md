# Agent seats: GLM-5.3-Flash and Kimi K3

This guide sets up two Chinese-model seats on the PC and Mac. The same
accounts also work in each vendor's web chat.

| Seat | Route | Cost |
|------|-------|------|
| `glm` | GLM-5.3-Flash through Z.AI's direct Chat Completions API | Z.AI API balance or an eligible resource package |
| `kimi` | Kimi K3 through Moonshot's direct Chat Completions API | Kimi Platform API balance |

Both are document-pipeline-only. They compose or review bounces; they never
adjudicate and never touch the dev-review code-execution or verify paths. Seat
selection is covered in [../CLAUDE.md](../CLAUDE.md) under Model Routing > Seat
selection.

Two rules that hold everywhere in this guide:

- The GLM launcher uses a separate config directory, `~/.claude-glm`. Do not put
  the Z.AI base URL or token in `~/.claude/settings.json`; that would redirect
  ordinary Claude sessions to Z.AI.
- Never paste the key into the repo or chat. Keep `ZAI_API_KEY` in the gitignored
  `.env.local` file or in 1Password.

## Account setup (manual)

Account creation, key entry, and interactive login remain manual steps.

### Z.AI account + API key

1. Create a Z.AI account at [z.ai](https://z.ai) and generate an API key
   (Account → API Keys / manage-apikey).
2. Take the key into the repo without pasting it into chat. From the repo root:

   ```bash
   # Run in a terminal, then open the printed localhost link and paste the key there.
   py -3.13 C:/Users/alan/Project/Admin/scripts/setup/secret-intake.py \
     --name ZAI_API_KEY --env-file .env.local
   ```

   The browser sends the value directly to the local intake server, which writes
   `.env.local`. The value never enters the transcript.
3. Confirm `.env.local` is gitignored (it is in this repo; check before adding a
   key to any other clone).
4. For Mac access, mirror the same key into the 1Password **Development** vault
   and add an
   `op://Development/...` reference to `.env.fill`. One key works on both machines.

### Kimi Platform account + API key

Create or log into [Kimi Platform](https://platform.kimi.ai/), add API balance,
and create an API key. Take `KIMI_API_KEY` into the repo through the same
`secret-intake.py` flow used for Z.AI; never paste it into chat or commit it.

## GLM on Z.AI

The document seat uses Z.AI directly, without Claude Code's internal agent
messages. The standalone `glm` convenience launchers continue to use Z.AI's
official Claude-compatible route for interactive prompts.

| Use | Endpoint | Authentication |
|-----|----------|----------------|
| Co-Evolution document seat | `https://api.z.ai/api/paas/v4/chat/completions` | `Authorization: Bearer ZAI_API_KEY` |
| Standalone `glm` launcher | `https://api.z.ai/api/anthropic` | `ZAI_API_KEY` → `ANTHROPIC_AUTH_TOKEN` |

Facts the standalone launchers depend on:

| Setting | Value |
|---------|-------|
| Endpoint | `https://api.z.ai/api/anthropic` (Anthropic-compatible) |
| Auth | `ZAI_API_KEY` → passed as `ANTHROPIC_AUTH_TOKEN` |
| Model string | `glm-5.3-flash` |
| Base URL var | `ANTHROPIC_BASE_URL` |
| Config dir | `CLAUDE_CONFIG_DIR=~/.claude-glm` (isolated from the Max account) |

Each launcher applies those environment variables to one child process. It does
not export `ANTHROPIC_BASE_URL` or `ANTHROPIC_AUTH_TOKEN`, and it never writes
them to `~/.claude/settings.json`. The launcher also uses Claude Code's safe mode
so project hooks, plugins, MCP servers, skills, and local customization cannot
leak into the Z.AI session.

### PC (Windows)

The repo supplies two Windows launchers:

- `scripts/launchers/glm.cmd` for `cmd.exe` and double-click use
- `scripts/launchers/glm.ps1` for PowerShell

Add the launcher directory to your user `PATH`, or call the launcher by its full
path. To add it for the current PowerShell session:

```powershell
# Add this line to $PROFILE if you want it in every PowerShell session.
$env:Path += ";C:\Users\alan\Project\co-evolution\scripts\launchers"
```

Then run a prompt through the seat:

```powershell
glm "Two-line sanity check: are you GLM?"
```

The launchers use `ZAI_API_KEY` from the repo's `.env.local`. They also accept a
key already present in the calling process, but the intake flow above is the
normal PC setup.

### PC (Git Bash)

Use the portable shell launcher directly from the repo root:

```bash
chmod u+x scripts/launchers/glm.sh
./scripts/launchers/glm.sh "Two-line sanity check: are you GLM?"
```

### Mac / Linux

`scripts/launchers/glm.sh` is also the Mac launcher. From the repo root, install
a copy in `~/bin`:

```zsh
mkdir -p "$HOME/bin"
cp scripts/launchers/glm.sh "$HOME/bin/glm"
chmod 700 "$HOME/bin/glm"
```

If 1Password is the key source on this Mac, add a small wrapper to `~/.zshrc`.
The reference below matches this repo's `.env.fill`:

```zsh
glm() {
  local zai_api_key
  zai_api_key="$(op read 'op://Development/Z.AI/api_key')" || return
  ZAI_API_KEY="$zai_api_key" "$HOME/bin/glm" "$@"
}
```

Reload the shell (`source ~/.zshrc`) and test:

```zsh
glm "Two-line sanity check: are you GLM?"
```

### Web chat

There is nothing to install for [chat.z.ai](https://chat.z.ai). Sign in with the
same Z.AI account used for the API key.

### Quota and upgrades

- Direct API calls consume the Z.AI account balance or an attached resource
  package. The Mac and PC share that account.
- The GLM Coding Plan and OpenRouter are alternative routes, not requirements
  for the direct document adapter.

## Kimi K3

The document seat calls Kimi Platform directly at
`https://api.moonshot.ai/v1/chat/completions` with model `kimi-k3`. This avoids
Kimi Code's agent loop, which may invoke Read/Write tools even for a document
prompt. The seat requires `KIMI_API_KEY`, `curl`, and `jq`.

Kimi Code remains an optional standalone interactive client. Its install and
login do not control the Co-Evolution document seat.

### Install on Windows

Run the official installer in PowerShell:

```powershell
irm https://code.kimi.com/kimi-code/install.ps1 | iex
```

### Install on macOS or Linux

Run the official shell installer:

```bash
curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash
```

The source and current install notes are in the official
[MoonshotAI/kimi-code repository](https://github.com/MoonshotAI/kimi-code).

### Configure and run a standalone prompt

Inside Kimi Code, run `/login`, select `Kimi Platform (API key ·
platform.kimi.ai)`, paste the API key locally, and select `kimi-k3`. A headless
standalone call then uses the configured default model:

```bash
kimi -p "Two-line sanity check: are you Kimi K3?" --output-format text
```

The Co-Evolution adapter sends only the Bounce Protocol prompt and extracts the
returned assistant content. It does not grant Kimi file, shell, or MCP tools.
K3 requires `temperature: 1`; the adapter pins that provider requirement. Role
effort overrides remain unsupported for the Kimi seat.

The account quota is shared between the two machines.

### Web chat

[kimi.com](https://kimi.com) needs no local install, but its consumer account is
separate from Kimi Platform API billing.

---

## Verifying the seats

After the CORE seat work has landed in the repo, smoke-test each seat from the
repo root. These consume provider quota or balance, so keep them to a couple of calls.

```bash
# GLM seat through the bouncer (2–4 requests)
bash ./co-evolve-bouncer.sh --vanilla --agents claude,glm "Two-line test question"

# Kimi seat
bash ./co-evolve-bouncer.sh --vanilla --agents claude,kimi "Two-line test question"
```

- `state.json` in the run directory should show a concrete model for each seat.
- **Env-leak check:** after a `glm` run, a plain `claude -p 'ping'` must still hit
  the Anthropic (Max) account. No Z.AI base URL should linger. If a plain run
  suddenly answers as GLM, the launcher or seat is leaking the override; stop and
  fix it before using the seat again.

---

## Manual gates

1. Create the Z.AI account and API key; take the key in through `secret-intake.py`.
2. Create the Kimi Platform API key and take `KIMI_API_KEY` into each machine's
   gitignored `.env.local` without exposing the value.
3. On the Mac, run the launcher install blocks above and load `ZAI_API_KEY` from
   1Password or `.env.local`.
4. Mirror `ZAI_API_KEY` into the 1Password Development vault and add its `op://`
   reference to `.env.fill` if the Mac will use the 1Password wrapper.
