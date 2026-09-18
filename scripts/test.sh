#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build
swiftc Sources/MenuPocket/Models.swift Tests/CoreTests.swift -o .build/core-tests
.build/core-tests
