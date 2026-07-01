#!/usr/bin/env bash
# install_guardian_agent.sh — installs the mudscript OS-level Guardian as a
# macOS Launch Agent.
#
# Run once after cloning / updating ms-utils:
#   bash ~/.hammerspoon/bin/install_guardian_agent.sh
#
# To uninstall:
#   launchctl unload ~/Library/LaunchAgents/com.mudscript.guardian.plist
#   rm ~/Library/LaunchAgents/com.mudscript.guardian.plist
#   launchctl unload ~/Library/LaunchAgents/com.mudscript.cache-cleaner.plist
#   rm ~/Library/LaunchAgents/com.mudscript.cache-cleaner.plist

set -euo pipefail

HS="$HOME/.hammerspoon"
PLIST_TEMPLATE="$HS/bin/com.mudscript.guardian.plist"
AGENT_SCRIPT="$HS/bin/ms_guardian_agent.sh"
PLIST_DST="$HOME/Library/LaunchAgents/com.mudscript.guardian.plist"

# ── Preflight checks ──────────────────────────────────────────────────────────
if [ ! -f "$PLIST_TEMPLATE" ]; then
    echo "ERROR: plist template not found at $PLIST_TEMPLATE"
    echo "       Make sure ms-utils is installed to ~/.hammerspoon/"
    exit 1
fi

if [ ! -f "$AGENT_SCRIPT" ]; then
    echo "ERROR: agent script not found at $AGENT_SCRIPT"
    exit 1
fi

# ── Make the agent script executable ─────────────────────────────────────────
chmod 755 "$AGENT_SCRIPT"
echo "Agent script: $AGENT_SCRIPT"

# ── Expand placeholders and write the plist ───────────────────────────────────
mkdir -p "$HOME/Library/LaunchAgents"

sed \
    -e "s|%%AGENT_PATH%%|$AGENT_SCRIPT|g" \
    -e "s|%%CORE_PATH%%|$HS/ms_core.lua|g" \
    -e "s|%%SPOONS_DIR%%|$HS/Spoons|g" \
    -e "s|%%LOG_PATH%%|$HS/data/guardian_agent.log|g" \
    "$PLIST_TEMPLATE" > "$PLIST_DST"

echo "Plist written:  $PLIST_DST"

# ── Load (reload if already registered) ──────────────────────────────────────
launchctl unload "$PLIST_DST" 2>/dev/null || true
launchctl load "$PLIST_DST"

echo ""
echo "mudscript Guardian agent installed and running."
echo "It watches:  $HS/ms_core.lua + $HS/Spoons/"
echo "Log file:    $HS/data/guardian_agent.log"

# ── Install Roblox cache cleaner agent ────────────────────────────────────────

CACHE_SCRIPT="$HS/bin/clean_roblox_cache.sh"
CACHE_PLIST_TEMPLATE="$HS/bin/com.mudscript.cache-cleaner.plist"
CACHE_PLIST_DST="$HOME/Library/LaunchAgents/com.mudscript.cache-cleaner.plist"

if [ -f "$CACHE_PLIST_TEMPLATE" ] && [ -f "$CACHE_SCRIPT" ]; then
    chmod 755 "$CACHE_SCRIPT"
    sed "s|%%AGENT_PATH%%|$CACHE_SCRIPT|g" \
        "$CACHE_PLIST_TEMPLATE" > "$CACHE_PLIST_DST"
    launchctl unload "$CACHE_PLIST_DST" 2>/dev/null || true
    launchctl load "$CACHE_PLIST_DST"
    echo ""
    echo "Roblox cache cleaner installed (every 6 h + at login)."
    echo "Log file:    $HS/data/cache_cleaner.log"
else
    echo ""
    echo "⚠  Cache cleaner files not found — skipping."
fi

echo ""
echo "Optional: make the stub read-only for stronger protection:"
echo "  chmod 444 ~/.hammerspoon/init.lua"
