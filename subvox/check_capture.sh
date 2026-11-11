#!/bin/bash
# Compile Hex/Clients/SubvoxCapture.swift with its standalone check and run it.
set -euo pipefail
cd "$(dirname "$0")/.."
out=$(mktemp -d)
swiftc -O -module-name SubvoxCheck Hex/Clients/SubvoxCapture.swift subvox/check/main.swift -o "$out/check" 2>&1 | grep -v warning || true
"$out/check"
