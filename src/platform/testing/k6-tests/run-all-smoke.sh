#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧪 Running all smoke tests..."

for test in "$SCRIPT_DIR"/tests/01-smoke/platform/*.yaml; do
  [ -f "$test" ] || continue
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  "$SCRIPT_DIR/run-test.sh" "$test"
  echo "════════════════════════════════════════════════════════════════"
  sleep 2
done

echo "✅ Platform smoke tests completed"
