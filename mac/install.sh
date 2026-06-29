#!/usr/bin/env bash
# install.sh — mudscript one-shot installer (macOS)
#
# Usage:
#   curl -L https://raw.githubusercontent.com/mudbourn/ms-utils/main/install.sh | bash
#   # or download and:
#   bash install.sh
#
# Works whether you have the full repo or just this file.
# Downloads the latest release from GitHub if the repo isn't local.
#
# To uninstall:
#   launchctl unload ~/Library/LaunchAgents/com.mudscript.guardian.plist 2>/dev/null
#   rm -f ~/Library/LaunchAgents/com.mudscript.guardian.plist
#   rm -rf ~/.hammerspoon/

set -euo pipefail

REPO="mudbourn/ms-utils"
HS="$HOME/.hammerspoon"
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd || pwd)"

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║        mudscript — macOS Installer          ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Step 1: Ensure Hammerspoon is installed ───────────────────────────────────

if [ -d "/Applications/Hammerspoon.app" ]; then
    echo "❶  Hammerspoon is already installed."
else
    echo "❶  Hammerspoon not found — downloading latest release …"
    HS_API="https://api.github.com/repos/Hammerspoon/hammerspoon/releases/latest"
    HS_ZIP_URL=$(curl -sf "$HS_API" \
        | grep -o '"browser_download_url": *"[^"]*\.zip"' \
        | head -1 | sed 's/.*": *"//; s/"//')

    if [ -z "$HS_ZIP_URL" ]; then
        echo "   ✗ Could not determine Hammerspoon download URL."
        echo "     Please install manually: https://www.hammerspoon.org"
        exit 1
    fi

    echo "   Downloading: $HS_ZIP_URL"
    HS_TMP=$(mktemp -d)
    curl -sfL "$HS_ZIP_URL" -o "$HS_TMP/hammerspoon.zip"
    unzip -qo "$HS_TMP/hammerspoon.zip" -d "$HS_TMP"
    # The zip contains Hammerspoon.app at the top level
    cp -R "$HS_TMP/Hammerspoon.app" /Applications/
    rm -rf "$HS_TMP"
    echo "   ✓ Hammerspoon installed to /Applications/."
fi

# ── Step 2: Source the files ──────────────────────────────────────────────────

if [ -f "$SCRIPT_DIR/ms_core.lua" ] && [ -f "$SCRIPT_DIR/init.lua" ]; then
    # Full repo detected — copy directly
    echo "❷  Copying local repo to ~/.hammerspoon/ …"
    mkdir -p "$HS"
    cp -R "$SCRIPT_DIR"/* "$HS/"
    # MANIFEST.json lives at the repo root (one level up from mac/)
    [ -f "$SCRIPT_DIR/../MANIFEST.json" ] && cp "$SCRIPT_DIR/../MANIFEST.json" "$HS/"
    rm -f "$HS/install.sh"
    echo "   ✓ Files copied from $SCRIPT_DIR"
else
    # Standalone script — download latest release
    echo "❷  Downloading latest release from GitHub …"
    mkdir -p "$HS"

    # Try to get the latest release download URL via the GitHub API
    echo "   Checking for latest release..."
    API="https://api.github.com/repos/$REPO/releases/latest"
    TAR_URL=$(curl -sf "$API" | grep -o '"browser_download_url": *"[^"]*macos[^"]*"' | head -1 | sed 's/.*": *"//; s/"//')

    if [ -n "$TAR_URL" ]; then
        echo "   Downloading: $TAR_URL"
        TMP_FILE=$(mktemp)
        curl -sfL "$TAR_URL" -o "$TMP_FILE"
        tar xzf "$TMP_FILE" -C "$HS" --strip-components=1
        rm -f "$TMP_FILE"
        echo "   ✓ Release downloaded and extracted."
    else
        # No release yet — download the repo archive directly
        echo "   No release found — downloading main branch..."
        ZIP_URL="https://github.com/$REPO/archive/refs/heads/main.tar.gz"
        TMP_FILE=$(mktemp)
        curl -sfL "$ZIP_URL" -o "$TMP_FILE"
        mkdir -p "$HS-tmp"
        tar xzf "$TMP_FILE" -C "$HS-tmp" --strip-components=1
        # Only copy macOS files
        cp -R "$HS-tmp"/* "$HS/"
        rm -rf "$HS-tmp" "$TMP_FILE"
        rm -f "$HS/install.bat" "$HS"/*.ahk
        rm -rf "$HS/bin"/*.bat "$HS/bin"/*.ps1
        echo "   ✓ Repository downloaded and macOS files extracted."
    fi

    # Remove the downloaded install script from the target
    rm -f "$HS/install.sh" 2>/dev/null || true
fi

# ── Step 3: Install Guardian Launch Agent ────────────────────────────────────

echo ""
echo "❸  Installing OS-level Guardian …"
if [ -f "$HS/bin/install_guardian_agent.sh" ]; then
    bash "$HS/bin/install_guardian_agent.sh"
    echo "   ✓ Guardian installed."
else
    echo "   ⚠  install_guardian_agent.sh not found — skipping."
fi

# ── Step 4: Lock init.lua ────────────────────────────────────────────────────

echo ""
echo "❹  Locking bootstrap stub (chmod 444) …"
chmod 444 "$HS/init.lua" 2>/dev/null && echo "   ✓ init.lua locked." || echo "   ⚠  Could not chmod init.lua."

# ── Step 5: Reload Hammerspoon ────────────────────────────────────────────────

echo ""
echo "❺  Reloading Hammerspoon …"
if command -v open &>/dev/null; then
    open -g "hammerspoon://reload" 2>/dev/null && echo "   ✓ Hammerspoon reloaded." || echo "   ⚠  Reload manually (menubar icon → Reload)."
else
    echo "   ⚠  Reload manually (menubar icon → Reload)."
fi

# ── Done ─────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════════╗"
echo "║          Installation complete               ║"
echo "╚══════════════════════════════════════════════╝"
echo ""
echo "   Directory:  $HS"
echo "   Guardian:   ~/Library/LaunchAgents/com.mudscript.guardian.plist"
echo ""
echo "   The trusted hash is auto-seeded from MANIFEST.json on first load."
echo ""
echo "   Keybindings (Roblox focused):"
echo "     ⌥P      Toggle settings"
echo "     ⌥[      Reload script"
echo "     ⌥]      Reload settings"
echo "     ⌥F10    Panic (disable macros)"
echo "     /       Disable macros"
echo "     Return  Enable macros"
echo ""
