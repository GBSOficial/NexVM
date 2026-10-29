#!/usr/bin/env bash
# Local developer tasks: scripts/dev.sh build|release|test|package
set -euo pipefail
cd "$(dirname "$0")/.."
case "${1:-}" in
  build)   swift build ;;
  release) swift build -c release ;;
  test)    swift test ;;
  package) scripts/package-app.sh release ;;
  *) echo "usage: $0 build|release|test|package" >&2; exit 2 ;;
esac
