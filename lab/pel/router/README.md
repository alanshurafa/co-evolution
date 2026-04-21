# PEL Router

Complexity-aware model routing for PEL invocations. Picks Sonnet for NORMAL mutations, escalates to Opus + thinking budget for COMPLEX. Invoked from `lab/pel/pr-emitter/pr-emitter.sh` between flavor classification and proposer dispatch.

## Contract

### Inputs (env vars set by caller)
- `TARGET` — target file path (already known to pr-emitter)
- `PEL_TIER` — `template`/`policy`/`code` (already resolved)
- `PEL_FLAVOR` — flavor classifier output
- `PEL_FEEDBACK` — path to eval feedback JSON
- `PEL_COMPLEXITY_OVERRIDE` — optional; skips Haiku call if set

### Output (single JSON object on stdout)

```json
{
  "complexity": "NORMAL" | "COMPLEX",
  "model": "sonnet" | "opus",
  "fallback_model": "sonnet",
  "thinking_budget": null | "harder",
  "rationale": "<one-sentence explanation>",
  "inputs": {
    "pel_tier": "...",
    "target": "...",
    "target_size_bytes": ...,
    "flavor": "...",
    "user_override": null | "..."
  }
}
```

## Tier-to-model mapping

| Complexity | Model | Thinking budget | Use cases |
|------------|-------|-----------------|-----------|
| NORMAL | `sonnet` | none | Most template + policy mutations |
| COMPLEX | `opus` | `harder` (append "think harder" to prompt) | Code-tier always; large/risky template/policy changes |

## Bias hints (passed to Haiku in prompt)

- `pel_tier == "code"` → strongly bias COMPLEX
- `pel_tier == "template" && target_size_bytes < 2000` → bias NORMAL
- `pel_tier == "policy"` → bias NORMAL
- Otherwise → Haiku decides from feedback content + flavor

## Failure handling

- Router script not found / unexecutable → caller prints WARN, falls back to current hardcoded `opus` default
- Haiku call fails → router emits canonical JSON with `complexity: "COMPLEX"` (safe-side default) + `rationale: "router-failure-fallback"` and exits 0
- `--complexity` override → skip Haiku entirely; emit canonical JSON with `inputs.user_override` set

The router is best-effort. PEL must keep working even if the router itself misbehaves.

## See also

- Spec: [`docs/superpowers/specs/2026-04-21-adaptive-co-evolve-design.md`](../../../docs/superpowers/specs/2026-04-21-adaptive-co-evolve-design.md)
- Pattern reference: `lab/pel/classifier/` (the frozen Phase 4 classifier this router structure mirrors)
