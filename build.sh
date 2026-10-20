#!/bin/sh
# ./build.sh                 build build/HABar.app
# ./build.sh install         build, copy to /Applications, launch
# ./build.sh release [x.y.z] bump version (patch by default), tag, GitHub release, update the Homebrew cask
set -e
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
cd "$(dirname "$0")"
PLIST=Info.plist
TAP=mathieuletyrant/homebrew-tap

if [ "$1" = "release" ]; then
    git diff --quiet && git diff --cached --quiet || { echo "error: commit your changes first"; exit 1; }
    CURRENT=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" $PLIST)
    VERSION=${2:-$(echo "$CURRENT" | awk -F. '{ printf "%d.%d.%d", $1, $2, $3 + 1 }')}
    /usr/libexec/PlistBuddy -c "Set CFBundleShortVersionString $VERSION" $PLIST
    echo "Releasing $CURRENT -> $VERSION"
fi

# every L("…") needs an English entry in Localization.swift
grep -rhoE 'L\("[^"]+"\)' Sources | sort -u | sed -E 's/^L\((".*")\)$/\1/' | while read -r k; do
    grep -qF "$k:" Sources/Core/Localization.swift || echo "warning: missing English for $k"
done
swift build -c release
APP=build/HABar.app
rm -rf "$APP" && mkdir -p "$APP/Contents/MacOS"
cp .build/release/HABar "$APP/Contents/MacOS/"
cp $PLIST "$APP/Contents/"
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

if [ "$1" = "release" ]; then
    ditto -c -k --keepParent "$APP" build/HABar.zip
    SHA=$(shasum -a 256 build/HABar.zip | cut -d' ' -f1)

    git commit -qm "chore(release): $VERSION" $PLIST
    git tag "v$VERSION"
    git push -q && git push -q origin "v$VERSION"
    gh release create "v$VERSION" build/HABar.zip --title "HABar $VERSION" --generate-notes

    # Versioned cask, so a plain `brew update && brew upgrade` picks the new release up.
    CASK=$(cat <<EOF
cask "habar" do
  version "$VERSION"
  sha256 "$SHA"

  url "https://github.com/mathieuletyrant/habar/releases/download/v#{version}/HABar.zip"
  name "HABar"
  desc "Native menu bar app for Home Assistant"
  homepage "https://github.com/mathieuletyrant/habar"

  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "HABar.app"

  # Not notarized (no Apple Developer account): drop quarantine so Gatekeeper lets it launch.
  postflight do
    system_command "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "#{appdir}/HABar.app"]
  end

  uninstall quit: "com.mathieuletyrant.habar"

  zap trash: [
    "~/Library/Caches/com.mathieuletyrant.habar",
    "~/Library/Preferences/com.mathieuletyrant.habar.plist",
  ]
end
EOF
)
    FILE_SHA=$(gh api "repos/$TAP/contents/Casks/habar.rb" --jq .sha)
    gh api -X PUT "repos/$TAP/contents/Casks/habar.rb" -f message="feat(habar): $VERSION" \
        -f content="$(printf '%s\n' "$CASK" | base64)" -f sha="$FILE_SHA" >/dev/null
    echo "Released $VERSION. Update with: brew update && brew upgrade"
fi
