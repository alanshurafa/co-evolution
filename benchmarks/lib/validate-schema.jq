# benchmarks/lib/validate-schema.jq — validate a document against the subset of
# JSON Schema draft-07 that docs/data/schema.json uses.
#
#   jq -n --slurpfile schema S.json --slurpfile doc D.json -f validate-schema.jq
#
# Emits one line per violation as "<json pointer>: <message>", and nothing at
# all when the document is valid — so the caller's pass/fail is "did anything
# come out". Exit status stays 0 either way; check the output, not the code.
#
# Supported keywords: type (string or array, with "integer" distinguished from
# "number"), const, enum, required, properties, additionalProperties (boolean
# or schema), items, minimum, maximum, minItems. The schema is kept inside that
# subset deliberately, so this file stays small enough to trust and the schema
# stays a real draft-07 document that ajv or check-jsonschema also accept.
#
# Unsupported keywords are ignored rather than failed: a schema that grows a
# keyword this validator does not know still validates on everything it does
# know, and the missing check shows up as a gap in coverage, never as a false
# pass being reported as a real one.

def typename:
  if   . == null      then "null"
  elif type == "number" then (if (. | floor) == . then "integer" else "number" end)
  else type end;

def type_ok($want):
  typename as $got
  | ($want | if type == "array" then . else [.] end) as $ws
  | ($ws | index($got)) != null
    # every integer is also a valid "number"
    or ($got == "integer" and ($ws | index("number")) != null);

def check($schema; $path):
  . as $v
  | ( if ($schema | has("type")) and (($v | type_ok($schema.type)) | not)
      then ["\($path): expected type \($schema.type | tostring), got \($v | typename)"]
      else [] end )
  + ( if ($schema | has("const")) and $v != $schema.const
      then ["\($path): expected const \($schema.const | tojson), got \($v | tojson)"]
      else [] end )
  + ( if ($schema | has("enum")) and (($schema.enum | index($v)) == null)
      then ["\($path): \($v | tojson) is not one of \($schema.enum | tojson)"]
      else [] end )
  + ( if ($schema | has("minimum")) and ($v | type) == "number" and $v < $schema.minimum
      then ["\($path): \($v) is below minimum \($schema.minimum)"]
      else [] end )
  + ( if ($schema | has("maximum")) and ($v | type) == "number" and $v > $schema.maximum
      then ["\($path): \($v) is above maximum \($schema.maximum)"]
      else [] end )
  + ( if ($v | type) == "object" then
        ( ($schema.required // [])
          | map(select((. as $k | $v | has($k)) | not) | "\($path): missing required property \"\(.)\"") )
        + ( [ $v | keys_unsorted[] as $k
              | if (($schema.properties // {}) | has($k))
                then ($v[$k] | check($schema.properties[$k]; "\($path)/\($k)"))
                elif ($schema | has("additionalProperties")) then
                  ( if ($schema.additionalProperties | type) == "boolean"
                    then (if $schema.additionalProperties then [] else ["\($path): unexpected property \"\($k)\""] end)
                    else ($v[$k] | check($schema.additionalProperties; "\($path)/\($k)")) end )
                else [] end ] | flatten )
      else [] end )
  + ( if ($v | type) == "array" then
        ( if ($schema | has("minItems")) and ($v | length) < $schema.minItems
          then ["\($path): has \($v | length) item(s), minimum \($schema.minItems)"] else [] end )
        + ( if ($schema | has("items"))
            then ([ range(0; $v | length) as $i | ($v[$i] | check($schema.items; "\($path)/\($i)")) ] | flatten)
            else [] end )
      else [] end );

($doc[0] | check($schema[0]; "")) | .[]
