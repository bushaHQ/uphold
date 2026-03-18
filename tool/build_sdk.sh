#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# Bundles all Uphold Widget JS SDKs into the package's assets folder.
#
# Usage:
#   ./tool/build_sdk.sh          # minified production build
#   ./tool/build_sdk.sh --dev    # unminified dev build
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PACKAGE_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PACKAGE_ROOT"

# Ensure node + npm are available.
if ! command -v node &>/dev/null; then
  echo "Error: Node.js is required. Install it from https://nodejs.org" >&2
  exit 1
fi

# Install npm deps (including the Uphold SDKs + esbuild).
echo "Installing dependencies..."
npm install --silent

# Run the appropriate build.
if [[ "${1:-}" == "--dev" ]]; then
  echo "Building SDK bundles (dev)..."
  npm run build:dev
else
  echo "Building SDK bundles (production)..."
  npm run build
fi

echo "Done:"
echo "  → assets/payment_widget_sdk.js"
echo "  → assets/travel_rule_widget_sdk.js"
