# lab/pel/proposer/policy/bounds.jq
# Co-Evolution PEL v1.2 policy-delta bounds validator (Phase 6 PEL-03 D-12, D-13).
#
# Single source of truth for the 6-knob allowlist and per-knob bounds from
# policy.yaml. Called by proposer.sh AFTER adapter.sh emits the delta, and
# by the Plan 02 simulation's adversarial scenarios.
#
# Input (stdin): JSON delta object per CONTEXT.md D-10 —
#   {"mutations": [{"key": <knob>, "old": <val>, "new": <val>}, ...],
#    "rationale": "...", "flavor": "...", "policy_path": "..."}
#
# Output (stdout): {valid: true, count: <N>} on success.
#
# Exit codes (D-12):
#   0   valid delta
#   4   bounds violation (legal knob, illegal value)
#   5   non-enumerated knob (key not in D-03 allowlist)

# --- Helpers ---------------------------------------------------------------

def is_int($v):
  ($v | type) == "number" and (($v - ($v | floor)) == 0);

def in_range($v; $lo; $hi):
  ($v | type) == "number" and $v >= $lo and $v <= $hi;

# flavor_weights sub-key allowlist.
def FW_SUBKEYS: ["bug_catcher", "faster_converger", "blind_spot_surfacer", "general"];

# Whole-object flavor_weights validation.
# Every sub-key in FW_SUBKEYS must be present (nothing extra), each value in
# [0.0, 1.0], and the sum in [0.95, 1.05] per D-14 soft bound.
def validate_flavor_weights($v):
  if ($v | type) != "object"
  then {violation: "bounds", key: "flavor_weights", new: $v,
        expected: "object with bug_catcher, faster_converger, blind_spot_surfacer, general sub-keys"}
       | halt_error(4)
  else
    ($v | keys | sort) as $got |
    (FW_SUBKEYS | sort) as $want |
    if $got != $want
    then {violation: "bounds", key: "flavor_weights", new: $v,
          expected: "exactly the 4 sub-keys: bug_catcher, faster_converger, blind_spot_surfacer, general"}
         | halt_error(4)
    else
      # Each value in [0.0, 1.0]
      [FW_SUBKEYS[] | $v[.]] as $vals |
      if ($vals | map(in_range(.; 0.0; 1.0)) | all) | not
      then {violation: "bounds", key: "flavor_weights", new: $v,
            expected: "each sub-value in [0.0, 1.0]"}
           | halt_error(4)
      else
        ($vals | add) as $sum |
        if ($sum < 0.95) or ($sum > 1.05)
        then {violation: "bounds", key: "flavor_weights", new: $v, sum: $sum,
              expected: "sum in [0.95, 1.05]"}
             | halt_error(4)
        else null
        end
      end
    end
  end;

# --- Per-knob validator ----------------------------------------------------

# Handles both whole-key mutations (key == knob name) and dotted sub-key
# mutations for flavor_weights (key == "flavor_weights.<sub>"). The dotted
# form lets the LLM propose a single flavor_weights sub-field without having
# to restate the whole object (caller is responsible for ensuring the
# resulting sum still lands in [0.95, 1.05] when combining; per-mutation
# sum check for dotted form is impossible without the current policy).
def validate_knob($m):
  ($m.key) as $k | ($m.new) as $v |
  if $k == "retry_cap" then
    if is_int($v) and in_range($v; 0; 10) then null
    else {violation: "bounds", key: $k, new: $v, expected: "integer in [0, 10]"} | halt_error(4)
    end
  elif $k == "marker_semantics" then
    if ($v == "strict") or ($v == "lax") then null
    else {violation: "bounds", key: $k, new: $v, expected: "enum: strict or lax"} | halt_error(4)
    end
  elif $k == "writable_phase_default" then
    if ($v == true) or ($v == false) then null
    else {violation: "bounds", key: $k, new: $v, expected: "boolean: true or false"} | halt_error(4)
    end
  elif $k == "arbitrate_threshold" then
    if in_range($v; 0.0; 1.0) then null
    else {violation: "bounds", key: $k, new: $v, expected: "number in [0.0, 1.0]"} | halt_error(4)
    end
  elif $k == "max_passes" then
    if is_int($v) and in_range($v; 1; 10) then null
    else {violation: "bounds", key: $k, new: $v, expected: "integer in [1, 10]"} | halt_error(4)
    end
  elif $k == "flavor_weights" then
    validate_flavor_weights($v)
  # Dotted-path: flavor_weights.<sub> — each sub-value in [0.0, 1.0].
  elif ($k | startswith("flavor_weights.")) then
    ($k | split(".") | .[1]) as $sub |
    if (FW_SUBKEYS | index($sub)) == null then
      {violation: "non-enumerated knob", key: $k,
       expected: "flavor_weights.<sub> where sub is one of bug_catcher, faster_converger, blind_spot_surfacer, general"}
      | halt_error(5)
    elif in_range($v; 0.0; 1.0) then null
    else {violation: "bounds", key: $k, new: $v, expected: "number in [0.0, 1.0]"} | halt_error(4)
    end
  else
    {violation: "non-enumerated knob", key: $k,
     expected: "one of: retry_cap, marker_semantics, writable_phase_default, arbitrate_threshold, max_passes, flavor_weights (or flavor_weights.<sub>)"}
    | halt_error(5)
  end;

# --- Top-level program -----------------------------------------------------

.mutations // []
| if type != "array"
  then {violation: "schema", field: "mutations", expected: "array"} | halt_error(4)
  else . end
| if length == 0
  then {valid: true, count: 0}
  else
    # Map through validator; discard per-knob null results, then report count.
    (map(validate_knob(.)) | length) as $n |
    {valid: true, count: $n}
  end
