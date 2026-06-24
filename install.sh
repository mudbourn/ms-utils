#!/usr/bin/env bash
# install.sh — one-shot installer for mudscript (macOS)
#
# Run this from the repo root after cloning:
#   bash install.sh
#
# It does everything the manual install docs describe:
#   1. Copies repo contents to ~/.hammerspoon/
#   2. Installs the OS-level Guardian Launch Agent
#   3. Locks init.lua (chmod 444)
#   4. Reloads Hammerspoon
#
# To uninstall:
#   launchctl unload ~/Library/LaunchAgents/com.mudscript.guardian.plist
#   rm ~/Library/LaunchAgents/com.mudscript.guardian.plist
#   rm -rf ~/.hammerspoon/

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HS="$HOME/.hammerspoon"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║        mudscript — macOS Installer          ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Preflight ────────────────────────────────────────────────────────────────

if [ ! -f "$SCRIPT_DIR/ms_core.lua" ]; then
    echo "ERROR: ms_core.lua not found."
    echo "       Run this script from the ms-utils repo root."
    exit 1
fi

if [ ! -f "$SCRIPT_DIR/init.lua" ]; then
    echo "ERROR: init.lua not found."
    exit 1
fi

# ── Step 1: Copy files ───────────────────────────────────────────────────────

echo "❶  Copying to ~/.hammerspoon/ …"
mkdir -p "$HS"
cp -R "$SCRIPT_DIR"/* "$HS/"
# Remove the install script itself from the target
rm -f "$HS/install.sh"
echo "   ✓ Files copied."

# ── Step 2: Install Guardian Launch Agent ────────────────────────────────────

echo ""
echo "❷  Installing OS-level Guardian …"
if [ -f "$HS/bin/install_guardian_agent.sh" ]; then
    bash "$HS/bin/install_guardian_agent.sh"
    echo "   ✓ Guardian installed."
else
    echo "   ⚠  install_guardian_agent.sh not found — skipping."
fi

# ── Step 3: Lock init.lua ────────────────────────────────────────────────────

echo ""
echo "❸  Locking bootstrap stub (chmod 444) …"
chmod 444 "$HS/init.lua" 2>/dev/null && echo "   ✓ init.lua locked." || echo "   ⚠  Could not chmod init.lua."

# ── Step 4: Reload Hammerspoon ────────────────────────────────────────────────

echo ""
echo "❹  Reloading Hammerspoon …"
open -g "hammerspoon://reload" 2>/dev/null && echo "   ✓ Hammerspoon reloaded." || echo "   ⚠  Could not trigger reload — reload manually."

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║            Installation complete             ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "   Directory:  $HS"
echo "   Guardian:   ~/Library/LaunchAgents/com.mudscript.guardian.plist"
echo ""
echo "   The trusted hash is auto-seeded from MANIFEST.json on first load."
echo "   Macros are enabled by default when Roblox is focused."
echo ""
echo "   Keybindings (Roblox focused):"
echo "     ⌥P      Toggle settings"
echo "     ⌥[      Reload script"
echo "     ⌥]      Reload settings"
echo "     ⌥F10    Panic (disable macros)"
echo "     /       Disable macros"
echo "     Return  Enable macros"
echo ""
