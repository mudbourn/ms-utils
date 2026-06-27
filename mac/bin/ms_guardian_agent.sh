#!/usr/bin/env bash
# ms_guardian_agent.sh — mudscript OS-level Guardian
#
# Runs as a macOS Launch Agent (com.mudscript.guardian).
# Triggered by launchd whenever ~/.hammerspoon/ms_core.lua changes on disk
# (WatchPaths) and also once at login (RunAtLoad).
#
# If the file's SHA-256 no longer matches the stored trusted hash,
# Hammerspoon is killed before it can finish reloading the tampered config,
# and a system notification is shown.
#
# This layer operates independently of the in-process Spoon check, so it
# catches tampering even when the Spoon itself has been bypassed (e.g. by
# also editing the stub init.lua or the Spoon).

CORE="$HOME/.hammerspoon/ms_core.lua"
TRUST="$HOME/.hammerspoon/data/.ms_trusted_hash"
LOG="$HOME/.hammerspoon/data/guardian_agent.log"
SENTINEL="$HOME/.hammerspoon/data/.ms_update_pending"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

# No trusted hash = uninitialized state; nothing to enforce.
if [ ! -f "$TRUST" ]; then
    log "No trusted hash on record — skipping check."
    exit 0
fi

if [ ! -f "$CORE" ]; then
    log "ms_core.lua not found at $CORE — skipping check."
    exit 0
fi

# Legitimate update in progress — skip this check.  The sentinel is created
# by ms_core.lua's update paths (and by the deploy helper) before touching
# ms_core.lua, and removed after the trusted hash is re-seeded.
if [ -f "$SENTINEL" ]; then
    log "Update in progress (sentinel present) — skipping check."
    exit 0
fi

trusted=$(tr -d '[:space:]' < "$TRUST")
current=$(shasum -a 256 "$CORE" 2>/dev/null | awk '{print $1}')

if [ -z "$current" ]; then
    log "shasum failed — cannot verify ms_core.lua."
    exit 0
fi

if [ "$current" = "$trusted" ]; then
    log "OK — ms_core.lua matches trusted hash (${current:0:16}…)."
    exit 0
fi

# ── MISMATCH ──────────────────────────────────────────────────────────────────
log "MISMATCH — expected ${trusted:0:16}… got ${current:0:16}… — killing Hammerspoon."

# Kill Hammerspoon before it finishes reloading the tampered config.
killall Hammerspoon 2>/dev/null

# Notify the user.
osascript -e 'display notification "ms_core.lua hash mismatch — Hammerspoon has been stopped.\nVerify the file before restarting." with title "mudscript Guardian" subtitle "Tamper Detected" sound name "Basso"' 2>/dev/null

exit 1
