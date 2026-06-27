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

# Copy UI files if they changed.
cp "$REPO/ui/ms_settings_ui.html" "$HS/ui/ms_settings_ui.html" 2>/dev/null || true

# Copy Guardian spoon.
cp -R "$REPO/mac/Spoons/MsGuardian.spoon" "$HS/Spoons/MsGuardian.spoon" 2>/dev/null || true

# Copy guardian agent script.
cp "$REPO/mac/bin/ms_guardian_agent.sh" "$HS/bin/ms_guardian_agent.sh" 2>/dev/null || true

# Re-seed the trusted hash from the file we just deployed.
HASH=$(shasum -a 256 "$HS/ms_core.lua" | awk '{print $1}')
echo "$HASH" > "$HS/data/.ms_trusted_hash"

# Remove sentinel — guardian agent can resume normal checks.
rm -f "$SENTINEL"

echo "Deployed. Hash: ${HASH:0:16}…"
