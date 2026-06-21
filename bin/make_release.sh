#!/usr/bin/env bash
# bin/make_release.sh
# ─────────────────────────────────────────────────────────────────────────────
# Stamps the SHA-256 of ms_core.lua into MANIFEST.json locally.
# Signing is handled automatically by GitHub Actions (.github/workflows/release.yml)
# whenever ms_core.lua is pushed to main — you do not need to sign manually.
#
# Use this script when you want to verify the hash locally before pushing,
# or to bump the version number:
#   bash bin/make_release.sh [version]
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
CORE="$ROOT/ms_core.lua"
MANIFEST="$ROOT/MANIFEST.json"
URL="https://raw.githubusercontent.com/mudbourn/ms-utils/main/ms_core.lua"

# ── Preflight ─────────────────────────────────────────────────────────────────

if [ ! -f "$CORE" ]; then
    echo "ERROR: ms_core.lua not found at $CORE"
    exit 1
fi

if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: MANIFEST.json not found at $MANIFEST"
    exit 1
fi

# ── Hash ──────────────────────────────────────────────────────────────────────

HASH=$(shasum -a 256 "$CORE" | awk '{print $1}')
echo "ms_core.lua  SHA-256: $HASH"

# ── Version ───────────────────────────────────────────────────────────────────

# Read current version from MANIFEST, fall back to 1.0.0 if unreadable.
CURRENT_VERSION=$(python3 -c "
import json, sys
try:
    d = json.load(open('$MANIFEST'))
    print(d.get('version', '1.0.0'))
except:
    print('1.0.0')
" 2>/dev/null || echo "1.0.0")

NEW_VERSION="${1:-$CURRENT_VERSION}"

# ── Write MANIFEST.json ───────────────────────────────────────────────────────

cat > "$MANIFEST" <<EOF
{
  "version": "$NEW_VERSION",
  "sha256": "$HASH",
  "url": "$URL"
}
EOF

echo "MANIFEST.json updated  (version=$NEW_VERSION)"
echo ""
echo "Stage and commit both files together:"
echo "  git add ms_core.lua MANIFEST.json"
echo "  git commit -m 'release: v$NEW_VERSION'"
