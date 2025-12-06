#!/bin/bash
# Show Makefile help

MAKEFILE_LIST="$1"

echo ""
echo "OpenCloudHub GitOps - Development Commands"
echo ""
echo "Usage: make <target>"
echo ""
grep -E '^[a-zA-Z_%-]+:.*?## .*$' "$MAKEFILE_LIST" | \
  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $1, $2}'
echo ""
echo "Examples:"
echo "  make dev              # Start full local environment"
echo "  make test             # Run smoke tests"
echo "  make test-load        # Run load tests"
echo "  make info             # Show all summaries"
echo "  make status           # Show cluster status"
echo ""
