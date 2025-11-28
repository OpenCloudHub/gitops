#!/bin/bash
# Run all smoke tests
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "🧪 Running all smoke tests..."

for test in "$SCRIPT_DIR"/tests/01-smoke/platform/*.yaml; do
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "Running: $(basename $test)"
  echo "════════════════════════════════════════════════════════════════"
  "$SCRIPT_DIR/run-test.sh" "$test"
  sleep 2
done

echo ""
echo "✅ All platform smoke tests completed"
