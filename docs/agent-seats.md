# Agent seats: GLM-5.3-Flash and Kimi K3

This guide sets up the two free Chinese-model seats on the PC and Mac. The same
accounts also work in each vendor's web chat.

| Seat | Route | Cost |
|------|-------|------|
| `glm` | GLM-5.3-Flash through the `claude` CLI and Z.AI's Anthropic-compatible endpoint | Free tier, reported at about 50 requests per day |
| `kimi` | Kimi K3 through Kimi Code and a kimi.com account | Free consumer account |

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

### kimi.com account

Create or log into a free account at [kimi.com](https://kimi.com). The same login
drives Kimi Code on each machine and the web chat. The CLI authenticates through
the browser, so there is no API key to paste.

## GLM on Z.AI

Facts the launchers depend on:

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

- The free tier is reported at about 50 requests per day. The Mac and PC share
  that quota because they use one account.
- If you outgrow it, the GLM Coding Plan Lite is ~$18/month. OpenRouter is a
  further fallback. Neither is needed to run the seat.

## Kimi K3

The preferred route is the **Kimi Code CLI** (open source,
[github.com/MoonshotAI/kimi-code](https://github.com/MoonshotAI/kimi-code)),
authenticated with the free kimi.com account. The paid Moonshot API is a fallback
only and is not set up here.

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

### Log in and run a prompt

The project uses a kimi.com account, so log in to the mainland-cn region on each
machine and complete the browser flow:

```bash
kimi login --region mainland-cn
```

Kimi Code stores the resulting login under `~/.kimi-code/credentials/`. Do not
copy that directory between machines; log in separately on each one. A headless
Kimi K3 call uses the verified command below:

```bash
kimi -m kimi-code/k3 -p "Two-line sanity check: are you Kimi K3?" --output-format text
```

The co-evolution adapter uses `stream-json` plus `jq` so it can recover raw
assistant Markdown. It runs Kimi in a disposable project with a no-tools policy
and rejects any stream that contains tool activity. Install `jq` before
selecting the `kimi` seat; the runner fails early if it is missing.

Kimi 0.39.1 accepts prompt text only as a command-line argument. On native
Windows, the adapter rejects prompts over 12,000 bytes with a clear error so it
cannot cross the Windows process command-line ceiling. Use a shorter document
or another seat for larger inputs. Kimi also has no reasoning-effort flag, so an
effort override is rejected when that role targets Kimi. An effort override for
the other seat in the pair remains valid.

The account quota is shared between the two machines.

### Mainland China vs global

Moonshot keeps the kimi.com and global accounts separate. This project uses
[kimi.com](https://kimi.com) with `--region mainland-cn`. If you instead have a
kimi.ai global account, use `kimi login --region global` and keep that region on
both machines.

### Web chat

[kimi.com](https://kimi.com) uses the same account as the CLI and needs no local
install.

---

## Verifying the seats

After the CORE seat work has landed in the repo, smoke-test each seat from the
repo root. These count against the free quotas, so keep them to a couple of calls.

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
2. Create or log into the kimi.com account; run
   `kimi login --region mainland-cn` on each machine.
3. On the Mac, run the launcher install blocks above and load `ZAI_API_KEY` from
   1Password or `.env.local`.
4. Mirror `ZAI_API_KEY` into the 1Password Development vault and add its `op://`
   reference to `.env.fill` if the Mac will use the 1Password wrapper.
