#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build
xcrun swiftc -O -module-cache-path build/ModuleCache -target arm64-apple-macosx12.0 Host.swift -o build/deskassit-arm64
xcrun swiftc -O -module-cache-path build/ModuleCache -target x86_64-apple-macosx12.0 Host.swift -o build/deskassit-x86_64
lipo -create build/deskassit-arm64 build/deskassit-x86_64 -output build/deskassit-native
codesign --force --sign - build/deskassit-native
./build/deskassit-native --self-test
