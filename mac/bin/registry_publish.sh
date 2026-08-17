#!/usr/bin/env bash
# bin/registry_publish.sh
# ─────────────────────────────────────────────────────────────────────────────
# Publishes a .mspkg to the registry: uploads it as a GitHub release asset and
# writes its entry into registry/index.json. This is steps 1–2 of registry/
# README.md's "Publishing" — signing (step 3) stays with the Sign Registry
# workflow, or `registry_sign.sh --sign` for key holders.
#
#   bash mac/bin/registry_publish.sh aurora.mspkg
#   bash mac/bin/registry_publish.sh aurora.mspkg --id aurora-theme --release v1.2.0
#   bash mac/bin/registry_publish.sh aurora.mspkg --dry-run      # print the row, touch nothing
#   bash mac/bin/registry_publish.sh aurora.mspkg --no-upload    # asset already uploaded
#
# A .spoon plugin bundle can be published directly. The script packs it into a
# temporary plugin .mspkg (type "plugin", files under Spoons/) and publishes
# that. Metadata is sniffed from the Spoon's init.lua (version/name/author/
# homepage) and can be overridden per field:
#
#   bash mac/bin/registry_publish.sh MyPlugin.spoon --id my-plugin
#   bash mac/bin/registry_publish.sh MyPlugin.spoon --id my-plugin --version 1.2.0 --author you
#
# Re-running on a package whose id is already listed UPDATES that entry —
# re-uploads the asset and refreshes sha256/size/version/… from the new bytes.
# That is the normal way to ship a new version; no flag is needed.
#   bash mac/bin/registry_publish.sh aurora.mspkg --sign --key k.pem   # publish + sign locally
#
# Most fields come from the package's own mspkg.json manifest, so the row can
# never disagree with the bytes it points at. The one field the manifest does
# not carry is `id` (the registry's stable handle): it defaults to a
# type-name slug and can be pinned with --id.
#
# The index is left UNSIGNED. Adding a row invalidates the old signature, and
# an unsigned index serves zero entries until re-signed — so publishing is not
# live until the Sign Registry workflow (or --sign here) runs. This script
# validates the result with registry_sign.sh before it finishes, so a row the
# client would reject fails here rather than after a commit.
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
INDEX="$ROOT/registry/index.json"
SIGN_SH="$SCRIPT_DIR/registry_sign.sh"

PKG=""
ID=""
REPO=""
TAG="packages"
TRUST="trusted"
DO_UPLOAD=true
DO_SIGN=false
DRY_RUN=false
KEY_FILE=""
# Metadata overrides, only used when packing a .spoon (a .mspkg carries its own).
P_NAME=""
P_VERSION=""
P_AUTHOR=""
P_WEBSITE=""
P_DESCRIPTION=""

usage() { sed -n '2,41p' "$0"; }

while [ $# -gt 0 ]; do
    case "$1" in
        --id)        ID="${2:-}"; shift 2 ;;
        --repo)      REPO="${2:-}"; shift 2 ;;
        --release)   TAG="${2:-}"; shift 2 ;;
        --trust)     TRUST="${2:-}"; shift 2 ;;
        --name)      P_NAME="${2:-}"; shift 2 ;;
        --version)   P_VERSION="${2:-}"; shift 2 ;;
        --author)    P_AUTHOR="${2:-}"; shift 2 ;;
        --website)   P_WEBSITE="${2:-}"; shift 2 ;;
        --description) P_DESCRIPTION="${2:-}"; shift 2 ;;
        --no-upload) DO_UPLOAD=false; shift ;;
        --sign)      DO_SIGN=true; shift ;;
        --key)       KEY_FILE="${2:-}"; shift 2 ;;
        --dry-run)   DRY_RUN=true; shift ;;
        --replace)   shift ;;   # accepted for muscle memory; updating is now the default
        -h|--help)   usage; exit 0 ;;
        -*)          echo "ERROR: unknown argument '$1'"; exit 2 ;;
        *)           [ -z "$PKG" ] && PKG="$1" || { echo "ERROR: only one package at a time (got extra '$1')."; exit 2; }; shift ;;
    esac
done

# ── Preconditions ────────────────────────────────────────────────────────────
command -v jq     >/dev/null || { echo "ERROR: jq is required.";     exit 1; }
command -v unzip  >/dev/null || { echo "ERROR: unzip is required.";  exit 1; }
command -v shasum >/dev/null || { echo "ERROR: shasum is required."; exit 1; }
[ -n "$PKG" ]     || { echo "ERROR: no package given."; usage; exit 2; }
[ -f "$INDEX" ]   || { echo "ERROR: index not found at $INDEX"; exit 1; }
[ "$TRUST" = "trusted" ] || [ "$TRUST" = "community" ] \
    || { echo "ERROR: --trust must be 'trusted' or 'community'."; exit 1; }

# ── Accept a .spoon: pack it into a temporary plugin .mspkg ───────────────────
# A .spoon is a Spoon bundle *directory*, not a typed package, so there is no
# mspkg.json to read. Build one here (type "plugin", files staged under Spoons/,
# each hashed into the contents map) exactly as ms.package.pack would, then let
# the rest of the script publish that .mspkg. A real .mspkg skips all of this.
case "$PKG" in
    *.spoon)
        [ -d "$PKG" ]              || { echo "ERROR: a .spoon must be a Spoon bundle directory: $PKG"; exit 1; }
        command -v zip >/dev/null  || { echo "ERROR: zip is required to pack a .spoon."; exit 1; }

        SPOON_DIR="${PKG%/}"                    # strip any trailing slash
        SPOON_NAME="$(basename "$SPOON_DIR")"   # Foo.spoon
        SPOON_BASE="${SPOON_NAME%.spoon}"       # Foo
        INIT="$SPOON_DIR/init.lua"

        # Metadata: --flags win, else sniff the Spoon's init.lua, else a default.
        sniff() {  # $1 = lua field (version/name/author/homepage) -> quoted value
            [ -f "$INIT" ] || return 0
            grep -oE "\\.$1[[:space:]]*=[[:space:]]*\"[^\"]*\"" "$INIT" 2>/dev/null \
                | head -1 | sed -E 's/.*"([^"]*)".*/\1/' || true
        }
        PK_NAME="${P_NAME:-$(sniff name)}";           PK_NAME="${PK_NAME:-$SPOON_BASE}"
        PK_VERSION="${P_VERSION:-$(sniff version)}";  PK_VERSION="${PK_VERSION:-1.0.0}"
        PK_AUTHOR="${P_AUTHOR:-$(sniff author)}"
        PK_WEBSITE="${P_WEBSITE:-$(sniff homepage)}"
        PK_DESCRIPTION="$P_DESCRIPTION"

        TMPROOT="$(mktemp -d)"
        trap 'rm -rf "$TMPROOT"' EXIT
        STAGE="$TMPROOT/stage"
        mkdir -p "$STAGE/Spoons"
        cp -R "$SPOON_DIR" "$STAGE/Spoons/$SPOON_NAME"
        find "$STAGE/Spoons/$SPOON_NAME" \( -name '.DS_Store' -o -name '._*' \) -delete 2>/dev/null || true

        # contents: { "Spoons/Foo.spoon/rel": sha256 }. The client re-verifies
        # each of these on install, so the hashes must match the staged bytes.
        CONTENTS="$(cd "$STAGE" && find Spoons -type f | LC_ALL=C sort | while IFS= read -r rel; do
            h="$(shasum -a 256 "$rel" | cut -c1-64 | tr '[:upper:]' '[:lower:]')"
            printf '%s\t%s\n' "$rel" "$h"
        done | jq -R -s 'split("\n") | map(select(length > 0) | split("\t")) | map({(.[0]): .[1]}) | add // {}')"
        [ "$(printf '%s' "$CONTENTS" | jq 'length')" != "0" ] \
            || { echo "ERROR: $SPOON_NAME has no files to pack."; exit 1; }

        ARCH="$(uname -m | tr -d '[:space:]')"
        jq -n \
            --arg name "$PK_NAME" --arg version "$PK_VERSION" \
            --arg author "$PK_AUTHOR" --arg website "$PK_WEBSITE" \
            --arg description "$PK_DESCRIPTION" --arg arch "$ARCH" \
            --argjson contents "$CONTENTS" '
            {formatVersion: 1, type: "plugin", name: $name, version: $version}
            + (if $author      != "" then {author: $author}          else {} end)
            + (if $website     != "" then {website: $website}         else {} end)
            + (if $description != "" then {description: $description} else {} end)
            + {created: (now | todate),
               platform: {os: "macos", arch: $arch, mudscript: "unknown"},
               contents: $contents}
        ' > "$STAGE/mspkg.json"

        MSPKG="$TMPROOT/$SPOON_BASE.mspkg"
        ( cd "$STAGE" && zip -qq -r -X "$MSPKG" . )
        [ -f "$MSPKG" ] || { echo "ERROR: could not build .mspkg from $SPOON_NAME."; exit 1; }
        echo "Packed $SPOON_NAME → plugin .mspkg (v$PK_VERSION)."
        PKG="$MSPKG"
        ;;
    *.mspkg)
        [ -f "$PKG" ] || { echo "ERROR: package not found: $PKG"; exit 1; }
        ;;
    *)
        echo "ERROR: not a .mspkg or .spoon: $PKG"; exit 1 ;;
esac

# GitHub rewrites spaces (and some other characters) in an uploaded asset's
# name, which silently desyncs the download URL from the real asset — a URL
# with a space 404s. Normalise the name ourselves so it is deterministic and
# URL-safe: any run of characters outside [A-Za-z0-9._-] collapses to a dot.
# The bytes (and therefore the sha256) are untouched; only the filename changes.
ASSET_SRC="$(basename "$PKG")"
ASSET="$(printf '%s' "$ASSET_SRC" | LC_ALL=C sed -E 's/[^A-Za-z0-9._-]+/./g')"

# ── Read the manifest out of the package ─────────────────────────────────────
MANIFEST="$(unzip -p "$PKG" mspkg.json 2>/dev/null || true)"
[ -n "$MANIFEST" ] || { echo "ERROR: $ASSET has no mspkg.json manifest (is it a typed package?)."; exit 1; }
echo "$MANIFEST" | jq empty 2>/dev/null || { echo "ERROR: $ASSET manifest is not valid JSON."; exit 1; }

field() { printf '%s' "$MANIFEST" | jq -r --arg k "$1" '.[$k] // "" | if type=="string" then . else "" end'; }
TYPE="$(field type)"
NAME="$(field name)"
VERSION="$(field version)"
AUTHOR="$(field author)"
WEBSITE="$(field website)"
DESCRIPTION="$(field description)"
REQUIRES="$(field requires)"
MANIFEST_ID="$(field id)"

[ -n "$TYPE" ] || { echo "ERROR: manifest has no type."; exit 1; }
[ -n "$NAME" ] || NAME="$ASSET"

# ── Component summary (profiles only) ────────────────────────────────────────
# A profile carries a `components` map (theme / sound / macro slices). Surface a
# LIGHTWEIGHT summary in the index row — which shareable slices exist, plus the
# theme's optional-sounds flag — so Browse can offer the install choices without
# downloading first. The authoritative file map stays inside the package
# manifest, which the client reads when it actually installs a slice.
# Every value here MUST be a non-empty object. hs.json (the client) encodes an
# empty Lua table as `[]`, not `{}`, so an empty component value would make the
# client's re-canonicalization differ from the signed bytes and the whole index
# would fail signature verification. Hence `{present:true}` rather than `{}`.
COMPONENTS="$(printf '%s' "$MANIFEST" | jq -c '
    (.components // {}) as $c
    | reduce (["theme","sound","macro"][]) as $k ({};
        if $c[$k] != null then
            .[$k] = (if $k == "theme"
                     then {includesSounds: (($c.theme.includesSounds) == true)}
                     else {present: true} end)
        else . end)
' 2>/dev/null || echo '{}')"
[ -n "$COMPONENTS" ] || COMPONENTS='{}'

# ── id: manifest.id, else --id, else a slug of type-name ─────────────────────
slug() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//'; }
if [ -z "$ID" ]; then
    if [ -n "$MANIFEST_ID" ]; then ID="$MANIFEST_ID"; else ID="$(slug "$TYPE-$NAME")"; fi
fi
[ -n "$ID" ] || { echo "ERROR: could not derive an id; pass --id."; exit 1; }

# ── Hash + size ──────────────────────────────────────────────────────────────
SHA="$(shasum -a 256 "$PKG" | cut -c1-64 | tr '[:upper:]' '[:lower:]')"
SIZE="$(wc -c < "$PKG" | tr -d ' ')"

# ── Resolve OWNER/REPO for the asset URL ─────────────────────────────────────
# The registry index and its release assets live in mudbourn/mudscript (this is
# the repo registry_sign_ci.sh signs and the client fetches from). Do NOT derive
# it from the local git origin: mudscript is checked out inside ms-utils, so the
# origin is mudbourn/ms-utils and every asset URL would point at the wrong repo.
# Default to the canonical repo. --repo still overrides for a one-off.
REPO="${REPO:-mudbourn/mudscript}"
case "$REPO" in
    */*) ;;
    *) echo "ERROR: invalid --repo '$REPO', expected owner/name."; exit 1 ;;
esac

ASSET_URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"

# ── Build the entry (omit empty optionals; the client reads absent as "") ────
ENTRY="$(jq -n \
    --arg id "$ID" --arg type "$TYPE" --arg name "$NAME" --arg version "$VERSION" \
    --arg author "$AUTHOR" --arg description "$DESCRIPTION" --arg website "$WEBSITE" \
    --arg sha256 "$SHA" --arg url "$ASSET_URL" --argjson size "$SIZE" \
    --arg requires "$REQUIRES" --arg trust "$TRUST" --argjson components "$COMPONENTS" '
    {id: $id, type: $type, name: $name}
    + (if $version     != "" then {version: $version}         else {} end)
    + (if $author      != "" then {author: $author}           else {} end)
    + (if $description != "" then {description: $description}  else {} end)
    + (if $website     != "" then {website: $website}         else {} end)
    + {sha256: $sha256, url: $url, size: $size}
    + (if $requires    != "" then {requires: $requires}       else {} end)
    + (if ($components | length) > 0 then {components: $components} else {} end)
    + {trust: $trust}
')"

echo "── Entry ─────────────────────────────────────────"
printf '%s\n' "$ENTRY" | jq .
echo "  asset : $ASSET  ($SIZE bytes)"
echo "  url   : $ASSET_URL"
echo "──────────────────────────────────────────────────"

# ── Add vs update ────────────────────────────────────────────────────────────
# An id already in the index is an update, not a collision: re-running with a
# newer .mspkg is how a version ships. Show the transition so it is never a
# silent overwrite. Only a sha reused under a *different* id is a real mistake.
ID_HITS="$(jq --arg id "$ID" '[.entries[] | select(.id == $id)] | length' "$INDEX")"
if [ "$ID_HITS" != "0" ]; then
    OLD_VER="$(jq -r --arg id "$ID" 'first(.entries[] | select(.id == $id) | .version) // ""' "$INDEX")"
    OLD_SHA="$(jq -r --arg id "$ID" 'first(.entries[] | select(.id == $id) | .sha256) // ""' "$INDEX")"
    echo "Updating existing entry '$ID' (v${OLD_VER:-?} → v${VERSION:-?})."
    [ "$OLD_SHA" = "$SHA" ] && echo "  note: the package bytes are unchanged (same sha256)."
fi
SHA_OTHER="$(jq -r --arg id "$ID" --arg sha "$SHA" \
    '[.entries[] | select((.sha256 | ascii_downcase) == $sha and .id != $id)] | first | .id // empty' "$INDEX")"
[ -z "$SHA_OTHER" ] || { echo "ERROR: this sha256 is already published under id '$SHA_OTHER'."; exit 1; }

if [ "$DRY_RUN" = true ]; then
    echo "Dry run: nothing uploaded, index untouched."
    exit 0
fi

# ── Upload the asset ─────────────────────────────────────────────────────────
if [ "$DO_UPLOAD" = true ]; then
    command -v gh >/dev/null || { echo "ERROR: gh (GitHub CLI) is required to upload — or pass --no-upload if the asset already exists."; exit 1; }
    if ! gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
        echo "Release '$TAG' does not exist; creating it."
        gh release create "$TAG" --repo "$REPO" \
            --title "Package assets" \
            --notes "Registry package binaries. Managed by registry_publish.sh." \
            >/dev/null
    fi
    # gh uploads under the file's own basename, so when normalisation changed
    # the name, stage a copy under the intended name rather than letting GitHub
    # pick. Same bytes, predictable URL.
    UP="$PKG"; STAGE=""
    if [ "$ASSET" != "$ASSET_SRC" ]; then
        STAGE="$(mktemp -d)"
        cp "$PKG" "$STAGE/$ASSET"
        UP="$STAGE/$ASSET"
    fi
    echo "Uploading $ASSET to release '$TAG'…"
    gh release upload "$TAG" "$UP" --repo "$REPO" --clobber
    [ -n "$STAGE" ] && rm -rf "$STAGE"
else
    echo "Skipping upload (--no-upload). Assuming $ASSET_URL already exists."
fi

# ── Write the row (replace-by-id, then append) ───────────────────────────────
TMP="$(mktemp)"
jq --argjson entry "$ENTRY" '
    .entries = ((.entries // []) | map(select(.id != $entry.id)) + [$entry])
' "$INDEX" > "$TMP"
mv "$TMP" "$INDEX"
echo "Wrote entry '$ID' into $INDEX ($(jq '.entries | length' "$INDEX") total)."

# ── Validate (and optionally sign) via the single source of truth ────────────
echo "── Validating index ──────────────────────────────"
if [ "$DO_SIGN" = true ]; then
    if [ -n "$KEY_FILE" ]; then
        bash "$SIGN_SH" --sign --key "$KEY_FILE"
    else
        bash "$SIGN_SH" --sign
    fi
else
    bash "$SIGN_SH"
    echo
    echo "Index updated but UNSIGNED — it serves zero entries until re-signed."
    echo "Commit registry/index.json and run the Sign Registry workflow, or"
    echo "re-run with --sign --key <file> if you hold the signing key."
fi
