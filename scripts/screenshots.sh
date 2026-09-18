#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc -swift-version 5 -parse-as-library \
  Sources/MenuPocket/Models.swift Sources/MenuPocket/AppState.swift \
  Sources/MenuPocket/MenuScanner.swift Sources/MenuPocket/ItemOperator.swift \
  Sources/MenuPocket/Views.swift Sources/MenuPocket/QuickPanel.swift \
  Sources/MenuPocket/ThumbnailService.swift tools/Screenshots.swift \
  -o .build/screenshot-export
.build/screenshot-export "${1:-docs/images}"
