#!/bin/bash
set -euo pipefail
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
lua "$TEST_DIR/test_client.lua" "$TEST_DIR/../lib/client.lua"
