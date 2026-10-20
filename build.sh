#!/bin/sh
set -e
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")"
# every L("…") needs an English entry in Localization.swift
grep -rhoE 'L\("[^"]+"\)' Sources | sort -u | sed -E 's/^L\((".*")\)$/\1/' | while read -r k; do
    grep -qF "$k:" Sources/Core/Localization.swift || echo "warning: missing English for $k"
done
swift build -c release
APP=build/HABar.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
cp .build/release/HABar "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
mkdir -p "$APP/Contents/Resources" && cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP"

if [ "$1" = "install" ]; then
    pkill -x HABar || true
    rm -rf /Applications/HABar.app
    cp -R "$APP" /Applications/
    open /Applications/HABar.app
    echo "Installed /Applications/HABar.app"
fi
