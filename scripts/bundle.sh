#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-install}"
if [[ "$MODE" != "install" && "$MODE" != "--package-only" ]]; then
    echo "Usage: $0 [--package-only]" >&2
    exit 2
fi

swift build -c release --product notestack
APP="build/Notestack.app"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/notestack "$APP/Contents/MacOS/notestack"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"

if [[ "$MODE" == "install" ]]; then
    ditto "$APP" /Applications/Notestack.app
    echo "Installed /Applications/Notestack.app"
else
    echo "Built $APP"
fi
