#!/usr/bin/env bash
# deploy.sh — Deploy repo files to ~/.hammerspoon safely.
# Creates a guardian sentinel before touching ms_core.lua so the
# launchd WatchPaths agent doesn't kill Hammerspoon on file change.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
HS="$HOME/.hammerspoon"
SENTINEL="$HS/data/.ms_update_pending"

mkdir -p "$HS/data"

# Signal the guardian agent to stand down.
touch "$SENTINEL"

# Copy core file.
cp "$REPO/mac/ms_core.lua" "$HS/ms_core.lua"

# Copy all UI HTML files.
mkdir -p "$HS/ui"
for f in "$REPO/ui/"*.html; do
    cp "$f" "$HS/ui/$(basename "$f")" 2>/dev/null || true
done

# Copy UI fonts.
if [ -d "$REPO/ui/fonts" ]; then
    mkdir -p "$HS/ui/fonts"
    cp -R "$REPO/ui/fonts/"* "$HS/ui/fonts/" 2>/dev/null || true
fi

# Copy all spoons.
for spoon in "$REPO/mac/Spoons/"*.spoon; do
    cp -R "$spoon" "$HS/Spoons/$(basename "$spoon")" 2>/dev/null || true
done

# Copy guardian agent script.
cp "$REPO/mac/bin/ms_guardian_agent.sh" "$HS/bin/ms_guardian_agent.sh" 2>/dev/null || true

# Copy hidinject binary.
cp "$REPO/mac/bin/hidinject" "$HS/bin/hidinject" 2>/dev/null || true

# Copy sounds (defaults + active + macro).
if [ -d "$REPO/sounds" ]; then
    mkdir -p "$HS/sounds/defaults" "$HS/sounds/active" "$HS/sounds/macro"
    # Default sounds — always bundled, never overwritten by profile imports.
    if [ -d "$REPO/sounds/Default" ]; then
        cp -R "$REPO/sounds/Default/"* "$HS/sounds/defaults/" 2>/dev/null || true
    fi
fi

# Copy MANIFEST.json so version tracking stays in sync.
cp "$REPO/MANIFEST.json" "$HS/MANIFEST.json" 2>/dev/null || true

# Increment build number (resets when stable version changes).
BUILD_NUM_FILE="$HS/data/.ms_build_num"
BUILD_BASE_FILE="$HS/data/.ms_build_base"
STABLE_VER=$(grep -o '"version": *"[^"]*"' "$REPO/MANIFEST.json" | head -1 | grep -o '[0-9][0-9.]*')

if [ -f "$BUILD_BASE_FILE" ]; then
    PREV_BASE=$(cat "$BUILD_BASE_FILE")
else
    PREV_BASE=""
fi

if [ "$STABLE_VER" != "$PREV_BASE" ]; then
    # Stable version changed — reset build counter.
    echo "0" > "$BUILD_NUM_FILE"
    echo "$STABLE_VER" > "$BUILD_BASE_FILE"
else
    # Same stable version — increment.
    if [ -f "$BUILD_NUM_FILE" ]; then
        OLD=$(cat "$BUILD_NUM_FILE")
        NEW=$((OLD + 1))
    else
        NEW=1
    fi
    echo "$NEW" > "$BUILD_NUM_FILE"
fi

# Re-seed the trusted hash from the file we just deployed.
HASH=$(shasum -a 256 "$HS/ms_core.lua" | awk '{print $1}')
echo "$HASH" > "$HS/data/.ms_trusted_hash"

# Remove sentinel — guardian agent can resume normal checks.
rm -f "$SENTINEL"

BUILD=$(cat "$BUILD_NUM_FILE" 2>/dev/null || echo "0")
echo "Deployed. Hash: ${HASH:0:16}… (build $STABLE_VER-pre.$BUILD)"
