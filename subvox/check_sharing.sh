#!/bin/bash
# Live upload check against the DEV Convex deployment, using a real saved session folder.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
swiftc -O -module-name SubvoxShareCheck Hex/Clients/SubvoxCapture.swift Hex/Clients/SubvoxSharing.swift \
  subvox/check_sharing/main.swift -o "$out/check" 2>&1 | grep -E "error" || true
SUBVOX_BACKEND=${SUBVOX_BACKEND:-https://insightful-orca-743.convex.cloud} "$out/check" "$1"
