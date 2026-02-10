#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "=== Starting Anvil ==="
anvil --silent &
ANVIL_PID=$!
trap "kill $ANVIL_PID 2>/dev/null" EXIT

sleep 2

echo "=== Running integration test ==="
npx tsx bot/test/integration.ts

echo "=== Integration tests passed ==="
