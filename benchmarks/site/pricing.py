#!/usr/bin/env python3
"""Price a cell's provider usage at the list rates in benchmarks/code/pricing.json.

The Claude CLI already returns a dollar figure per dispatch. Codex, GLM and Kimi
return tokens only, so their seats were unpriced and a bounce arm's cost read
lower than a solo arm's purely because half of it was missing. This module
turns the token figures each cell's own logs carry into dollars at the tracked
list price, and says how precise that figure is:

  exact      the log carried an input / cached / output split
  estimated  the log carried one total (Codex before --json capture); priced
             with the recorded assumed split, with low and high bounds that
             price the whole total at the cached-input and output rates
  unpriced   no token figure, or no rate for the model
"""
import datetime
import json
import os
import re


def load_pricing(path):
    with open(path, encoding='utf-8') as handle:
        data = json.load(handle)
    if data.get('schema') != 'code-bench-pricing/1.0':
        raise ValueError('unexpected pricing schema in %s' % path)
    return data


def rates_for(pricing, model):
    """Rates for a model name; None when the pricing file has no entry."""
    if not model:
        return None
    return (pricing.get('models') or {}).get(model)


def price_split(rates, input_tokens, cached_tokens, output_tokens):
    """Dollars for an exact token split at the given per-million rates."""
    return ((input_tokens or 0) * rates['input']
            + (cached_tokens or 0) * rates['cached_input']
            + (output_tokens or 0) * rates['output']) / 1e6


def price_total_only(pricing, rates, total_tokens):
    """Point estimate and bounds for a log that carried one total figure."""
    split = pricing['codex_total_only']['assumed_split']
    point = price_split(rates,
                        total_tokens * split['input'],
                        total_tokens * split['cached_input'],
                        total_tokens * split['output'])
    low = total_tokens * rates['cached_input'] / 1e6
    high = total_tokens * rates['output'] / 1e6
    return point, low, high


CODEX_TS_RE = re.compile(r'^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.\d+)?Z')
CODEX_TOKENS_RE = re.compile(r'^([\d,]+)$')
CODEX_VERSION_RE = re.compile(r'^OpenAI Codex v(\S+)')


def codex_stderr_summary(stderr_path):
    """(wall seconds, total tokens, cli version) from one Codex phase's stderr.

    The figure under "tokens used" is the only token count Codex 0.144.x prints,
    and it is a total with no split. The version banner is the first line.
    """
    first = last = None
    tokens = 0
    version = None
    want_tokens = False
    try:
        with open(stderr_path, encoding='utf-8', errors='replace') as handle:
            for line in handle:
                if version is None:
                    match = CODEX_VERSION_RE.match(line)
                    if match:
                        version = match.group(1)
                match = CODEX_TS_RE.match(line)
                if match:
                    if first is None:
                        first = match.group(1)
                    last = match.group(1)
                stripped = line.strip()
                if want_tokens:
                    count = CODEX_TOKENS_RE.match(stripped)
                    if count:
                        tokens += int(count.group(1).replace(',', ''))
                    want_tokens = False
                elif stripped == 'tokens used':
                    want_tokens = True
    except OSError:
        return 0, 0, None
    seconds = 0
    if first and last and last >= first:
        fmt = '%Y-%m-%dT%H:%M:%S'
        seconds = int((datetime.datetime.strptime(last, fmt)
                       - datetime.datetime.strptime(first, fmt)).total_seconds())
    return seconds, tokens, version


def _find_key(obj, key):
    if isinstance(obj, dict):
        if key in obj:
            return obj[key]
        for value in obj.values():
            hit = _find_key(value, key)
            if hit is not None:
                return hit
    elif isinstance(obj, list):
        for value in obj:
            hit = _find_key(value, key)
            if hit is not None:
                return hit
    return None


def _usage_dicts(obj, found):
    """Collect every dict that looks like a token-usage record."""
    if isinstance(obj, dict):
        if 'input_tokens' in obj and 'output_tokens' in obj:
            found.append(obj)
        for value in obj.values():
            _usage_dicts(value, found)
    elif isinstance(obj, list):
        for value in obj:
            _usage_dicts(value, found)


def codex_usage_from_events(log_path):
    """Exact token split from a `codex exec --json` event stream, or None.

    Two shapes are accepted. A cumulative `total_token_usage` record (the
    token_count event) is taken at its last value; per-turn `usage` records
    (turn.completed events) are summed. A transcript that is not JSONL, which
    is what every pre-capture cell holds, yields None and the caller falls back
    to the stderr total.
    """
    cumulative = None
    per_turn = []
    saw_json = False
    try:
        with open(log_path, encoding='utf-8', errors='replace') as handle:
            for line in handle:
                line = line.strip()
                if not line.startswith('{'):
                    continue
                try:
                    event = json.loads(line)
                except ValueError:
                    continue
                if not isinstance(event, dict):
                    continue
                saw_json = True
                total = _find_key(event, 'total_token_usage')
                if isinstance(total, dict) and 'input_tokens' in total:
                    cumulative = total
                    continue
                found = []
                _usage_dicts(event, found)
                if found:
                    per_turn.append(found[0])
    except OSError:
        return None
    if not saw_json:
        return None
    if cumulative is not None:
        record = cumulative
    elif per_turn:
        record = {key: sum(int(u.get(key) or 0) for u in per_turn)
                  for key in ('input_tokens', 'cached_input_tokens', 'output_tokens')}
    else:
        return None
    return {
        'input_tokens': int(record.get('input_tokens') or 0),
        'cached_input_tokens': int(record.get('cached_input_tokens') or 0),
        'output_tokens': int(record.get('output_tokens') or 0),
        'source': 'codex-json-events',
    }


def price_codex_phase(pricing, model, log_path, stderr_path):
    """Everything the site needs for one Codex phase."""
    seconds, total, version = codex_stderr_summary(stderr_path)
    usage = codex_usage_from_events(log_path) if os.path.isfile(log_path) else None
    rates = rates_for(pricing, model)
    out = {
        'model': model,
        'cli_version': version,
        'wall_seconds': seconds,
        'total_tokens': total,
        'input_tokens': None,
        'cached_input_tokens': None,
        'output_tokens': None,
        'cost_usd': None,
        'cost_low_usd': None,
        'cost_high_usd': None,
        'precision': 'unpriced',
    }
    if usage is not None:
        out['input_tokens'] = usage['input_tokens']
        out['cached_input_tokens'] = usage['cached_input_tokens']
        out['output_tokens'] = usage['output_tokens']
        # OpenAI reports cached tokens as a subset of input tokens.
        uncached = max(0, usage['input_tokens'] - usage['cached_input_tokens'])
        if not out['total_tokens']:
            out['total_tokens'] = usage['input_tokens'] + usage['output_tokens']
        if rates:
            cost = price_split(rates, uncached, usage['cached_input_tokens'],
                               usage['output_tokens'])
            out['cost_usd'] = out['cost_low_usd'] = out['cost_high_usd'] = cost
            out['precision'] = 'exact'
    elif total and rates:
        point, low, high = price_total_only(pricing, rates, total)
        out['cost_usd'], out['cost_low_usd'], out['cost_high_usd'] = point, low, high
        out['precision'] = 'estimated'
    return out


def price_sidecar(pricing, model, sidecar_path):
    """Dollars for a GLM/Kimi call from the usage sidecar the adapter wrote."""
    try:
        with open(sidecar_path, encoding='utf-8') as handle:
            usage = json.load(handle)
    except (OSError, ValueError):
        return None
    rates = rates_for(pricing, model)
    if not rates or usage.get('input_tokens') is None:
        return None
    cached = int(usage.get('cache_read_input_tokens') or 0)
    uncached = max(0, int(usage.get('input_tokens') or 0) - cached)
    output = int(usage.get('output_tokens') or 0)
    return {
        'model': model,
        'input_tokens': int(usage.get('input_tokens') or 0),
        'cached_input_tokens': cached,
        'output_tokens': output,
        'cost_usd': price_split(rates, uncached, cached, output),
        'precision': 'exact',
    }


def combine_precision(parts):
    """The weakest precision among the seats that ran."""
    levels = [p for p in parts if p]
    if not levels:
        return 'exact'
    if 'unpriced' in levels:
        return 'unpriced'
    if 'estimated' in levels:
        return 'estimated'
    return 'exact'
