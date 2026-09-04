#!/bin/sh
# Build ShieldStat.app into ./build/Build/Products/Release/
set -e
cd "$(dirname "$0")"
swift test --package-path Core
xcodebuild -project ShieldStat.xcodeproj -scheme ShieldStat -configuration Release \
  -derivedDataPath build build
