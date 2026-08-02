#!/usr/bin/env bash
# bin/registry_sign.sh
# ─────────────────────────────────────────────────────────────────────────────
# Validates registry/index.json against the rules the client enforces, and
# optionally signs it with MS_SIGNING_KEY.
#
#   bash mac/bin/registry_sign.sh                 # validate only
#   bash mac/bin/registry_sign.sh --sign          # validate, then sign
#   bash mac/bin/registry_sign.sh --sign --key k.pem
#
# Validation is the point of this script. The client rejects a malformed index
# *whole* — one bad row leaves every package unlisted — so a row that would be
# refused must never reach a signature. Running with no arguments is safe and
# needs no key; use it before committing an index edit.
#
# The signing key normally lives only in the MS_SIGNING_KEY repository secret,
# so --sign is what the Sign Registry workflow runs. Signing locally is for
# holders of the key.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INDEX="$ROOT/registry/index.json"

FORMAT_VERSION=1
DO_SIGN=false
KEY_FILE=""

while [ $# -gt 0 ]; do
    case "$1" in
        --sign)  DO_SIGN=true; shift ;;
        --key)   KEY_FILE="${2:-}"; shift 2 ;;
        --index) INDEX="${2:-}"; shift 2 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) echo "ERROR: unknown argument '$1'"; exit 2 ;;
    esac
done

command -v jq >/dev/null || { echo "ERROR: jq is required."; exit 1; }
[ -f "$INDEX" ] || { echo "ERROR: index not found at $INDEX"; exit 1; }
jq empty "$INDEX" 2>/dev/null || { echo "ERROR: $INDEX is not valid JSON."; exit 1; }

# ── Validate ─────────────────────────────────────────────────────────────────
# Mirrors `normalise` and `adopt` in mac/lib/ms_registry.lua. Keep the two in
# step: a rule that only exists here lets a bad index ship, and a rule that only
# exists there turns a publish into a silent outage.

fail() { echo "INVALID: $1"; exit 1; }

FMT=$(jq -r '.formatVersion // empty' "$INDEX")
[ "$FMT" = "$FORMAT_VERSION" ] || fail "formatVersion must be $FORMAT_VERSION (got '${FMT:-absent}')."

# `generated` is the publish timestamp, so --sign stamps it below rather than
# asking the editor to keep it current. It matters beyond being informative:
# the client rebuilds the signed payload as {formatVersion, generated, entries},
# and if the key were absent hs.json.encode would omit it while `jq -c -S`
# emits an explicit null — two different byte sequences. A signature taken over
# an empty or missing `generated` therefore never verifies, so a document that
# already claims a signature must carry one.
GEN=$(jq -r 'if (.generated | type) == "string" and (.generated != "") then .generated else empty end' "$INDEX")
SIG_PRESENT=$(jq -r 'if (.signature | type) == "string" and (.signature != "") then "yes" else empty end' "$INDEX")
if [ -n "$SIG_PRESENT" ] && [ -z "$GEN" ]; then
    fail "document is signed but generated is empty — that signature cannot verify."
fi

ENTRY_COUNT=$(jq '.entries | length' "$INDEX")

# Package types are read out of ms_package.lua, not restated here. The client
# checks `type` with ms.package.spec(), so a hardcoded list would quietly go
# stale the day a sixth type is added — and it would fail in the safe-looking
# direction, rejecting a valid new type only after it was already published.
PKG_LUA="$ROOT/mac/lib/ms_package.lua"
TYPES_JSON=""
if [ -f "$PKG_LUA" ]; then
    TYPES_JSON=$(sed -n 's/.*ms\.package\.TYPES *= *{\(.*\)}.*/\1/p' "$PKG_LUA" \
        | head -1 \
        | tr -d ' "' \
        | jq -R 'split(",") | map(select(length > 0))' 2>/dev/null || echo "")
fi
if [ -z "$TYPES_JSON" ] || [ "$(printf '%s' "$TYPES_JSON" | jq 'length')" = "0" ]; then
    fail "could not read ms.package.TYPES from $PKG_LUA — refusing to validate against a guessed type list."
fi
echo "Types (from ms_package.lua): $(printf '%s' "$TYPES_JSON" | jq -r 'join(", ")')"

# One jq pass over the rows, reporting the first offender by index and id.
PROBLEM=$(jq -r --argjson known "$TYPES_JSON" '
  def known: $known;
  def hosts: ["github.com","objects.githubusercontent.com",
              "raw.githubusercontent.com","api.github.com"];
  def host($u): $u | capture("^https://(?<h>[^/:]+)") | .h | ascii_downcase;

  [ .entries
    | to_entries[]
    | . as {key: $i, value: $e}
    | ($i + 1) as $n
    | ("entry #\($n) (\($e.id // "?")): ") as $at
    | if ($e | type) != "object" then "\($at)not an object"
      elif (($e.id | type) != "string") or ($e.id == "") then "\($at)missing id"
      elif (($e.sha256 | type) != "string")
        or ($e.sha256 | test("^[0-9a-fA-F]{64}$") | not)
        then "\($at)sha256 is not 64 hex characters"
      elif ([$e.type] - known | length) > 0 then "\($at)unknown type \($e.type)"
      elif ($e.url != null)
        and (($e.url | type) != "string"
             or ($e.url | test("^https://")   | not)
             or ([host($e.url)] - hosts | length) > 0)
        then "\($at)download URL not permitted"
      else empty end
  ] | first // empty
' "$INDEX")
[ -z "$PROBLEM" ] || fail "$PROBLEM"

DUP_ID=$(jq -r '[.entries[].id] | group_by(.) | map(select(length > 1)) | first | first // empty' "$INDEX")
[ -z "$DUP_ID" ] || fail "duplicate id $DUP_ID"

DUP_HASH=$(jq -r '[.entries[].sha256 | ascii_downcase] | group_by(.)
                  | map(select(length > 1)) | first | first // empty' "$INDEX")
[ -z "$DUP_HASH" ] || fail "duplicate sha256 $DUP_HASH"

echo "Index valid: $ENTRY_COUNT entr$([ "$ENTRY_COUNT" = 1 ] && echo y || echo ies)${GEN:+, generated $GEN}"

# ── Sign ─────────────────────────────────────────────────────────────────────

if [ "$DO_SIGN" != true ]; then
    echo "Validate-only. Pass --sign to sign."
    exit 0
fi

KEY_TMP=""
cleanup() { [ -n "$KEY_TMP" ] && rm -f "$KEY_TMP"; rm -f /tmp/idx_msg.bin /tmp/idx_sig.bin; }
trap cleanup EXIT

if [ -n "$KEY_FILE" ]; then
    [ -f "$KEY_FILE" ] || { echo "ERROR: key file not found: $KEY_FILE"; exit 1; }
elif [ -n "${MS_SIGNING_KEY:-}" ]; then
    KEY_TMP=$(mktemp)
    chmod 600 "$KEY_TMP"
    printf '%s\n' "$MS_SIGNING_KEY" > "$KEY_TMP"
    KEY_FILE="$KEY_TMP"
else
    echo "ERROR: no key. Set MS_SIGNING_KEY or pass --key <file>."
    exit 1
fi

# Stamp the publish time, then sign. Order matters — `generated` is inside the
# signed payload, so stamping after signing would invalidate the signature.
STAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
jq --arg g "$STAMP" '.generated = $g' "$INDEX" > "$INDEX.tmp"
mv "$INDEX.tmp" "$INDEX"

# `jq -c -S` is required: the client rebuilds this exact byte sequence.
jq -c -S '{formatVersion, generated, entries}' "$INDEX" > /tmp/idx_msg.bin
openssl dgst -sha256 -sign "$KEY_FILE" -out /tmp/idx_sig.bin /tmp/idx_msg.bin

if base64 --help 2>&1 | grep -q -- '-w'; then
    SIG=$(base64 -w0 /tmp/idx_sig.bin)      # GNU coreutils (CI)
else
    SIG=$(base64 < /tmp/idx_sig.bin | tr -d '\n')   # BSD/macOS
fi

jq --arg sig "$SIG" '.signature = $sig' "$INDEX" > "$INDEX.tmp"
mv "$INDEX.tmp" "$INDEX"

echo "Signed $INDEX"
