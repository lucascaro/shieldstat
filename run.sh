#!/bin/sh
# Launch the built app. Builds first if it isn't there.
set -e
cd "$(dirname "$0")"
APP=build/Build/Products/Release/ShieldStat.app
[ -d "$APP" ] || ./build.sh
open "$APP"
