# R1: claude -p JSON Envelope — Field Reference

**Date:** 2026-06-12  
**Phase:** v1.5 Phase 0  
**Purpose:** Pin the exact JSON output structure of `claude -p --output-format json` for Phase 4 token-capture parsing.

## Command run

```
claude -p --output-format json --model claude-haiku-4-5-20251001 "Reply with exactly: PING"
```

## Verbatim output (not-logged-in state; all usage fields present and zero)

```json
{"type":"result","subtype":"success","is_error":true,"api_error_status":null,"duration_ms":1103,"duration_api_ms":0,"num_turns":1,"result":"Not logged in · Please run /login","stop_reason":"stop_sequence","session_id":"4642f382-c299-4d72-bcaf-3e7bca396c7d","total_cost_usd":0,"usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"output_tokens":0,"server_tool_use":{"web_search_requests":0,"web_fetch_requests":0},"service_tier":"standard","cache_creation":{"ephemeral_1h_input_tokens":0,"ephemeral_5m_input_tokens":0},"inference_geo":"","iterations":[],"speed":"standard"},"modelUsage":{},"permission_denials":[],"terminal_reason":"completed","fast_mode_state":"off","uuid":"def45115-84e3-4e92-a601-20e0dae05dda"}
```

Exit code: 1 (error because not logged in; envelope still emitted on stdout)

## Top-level fields

| Field | Type | Notes |
|---|---|---|
| `type` | string | Always `"result"` |
| `subtype` | string | `"success"` even on error |
| `is_error` | bool | `true` when auth fails or API error |
| `api_error_status` | null/int | HTTP status code on API errors; null here |
| `duration_ms` | int | Wall time in ms |
| `duration_api_ms` | int | API time in ms |
| `num_turns` | int | Number of conversation turns |
| `result` | string | The model's text output (or error message) |
| `stop_reason` | string | e.g. `"stop_sequence"`, `"end_turn"` |
| `session_id` | string | UUID |
| `total_cost_usd` | float | Total cost in USD (0 when not logged in) |
| `usage` | object | Token usage breakdown — see below |
| `modelUsage` | object | Per-model usage breakdown (empty when not logged in) |
| `permission_denials` | array | Tool permission denial events |
| `terminal_reason` | string | `"completed"` |
| `fast_mode_state` | string | `"off"` |
| `uuid` | string | Run UUID |

## usage subfields

| Field | Type | Notes |
|---|---|---|
| `input_tokens` | int | Prompt input tokens |
| `cache_creation_input_tokens` | int | Cache write tokens |
| `cache_read_input_tokens` | int | Cache hit tokens |
| `output_tokens` | int | Response tokens |
| `server_tool_use.web_search_requests` | int | Web search count |
| `server_tool_use.web_fetch_requests` | int | Web fetch count |
| `service_tier` | string | `"standard"` or `"priority"` |
| `cache_creation.ephemeral_1h_input_tokens` | int | 1-hour ephemeral cache write tokens |
| `cache_creation.ephemeral_5m_input_tokens` | int | 5-min ephemeral cache write tokens |
| `inference_geo` | string | Inference geography code |
| `iterations` | array | Per-iteration usage (for multi-turn) |
| `speed` | string | `"standard"` |

## Notes for Phase 4

- All token fields live under `.usage`. Phase 4's `invoke_claude` gated JSON mode should extract: `.usage.input_tokens`, `.usage.output_tokens`, `.usage.cache_creation_input_tokens`, `.usage.cache_read_input_tokens`.
- `.total_cost_usd` is a direct top-level field, not nested.
- The envelope is always emitted to **stdout** even when `is_error=true`.
- The exit code is 1 on auth error; Phase 4 must handle non-zero exit with usable envelope (capture stdout regardless of exit code using `|| true`).
- **Limitation:** This capture is from a not-logged-in shell. When logged in, `modelUsage` will be populated and `iterations` may have per-turn breakdown. Field names are stable across auth state.

## Auth status at capture time

`claude whoami` returns: `Not logged in · Please run /login`  
(The Mac's interactive Claude Code sessions authenticate through the Electron app, not this shell. The sub-agent shell does not carry the session token.)
