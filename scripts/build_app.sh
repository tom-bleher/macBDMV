#!/bin/zsh
# Builds a release macBDMV.app into build/. Usage: scripts/build_app.sh [--install]  (--install copies it to /Applications)
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release
app=build/macBDMV.app
rm -rf $app
mkdir -p $app/Contents/MacOS $app/Contents/Resources
cp "$(swift build -c release --show-bin-path)/macBDMV" $app/Contents/MacOS/
cp Resources/Info.plist $app/Contents/
cp Resources/AppIcon.icns $app/Contents/Resources/
codesign --force --sign - $app

if [[ ${1:-} == --install ]]; then
  rm -rf /Applications/macBDMV.app
  cp -R $app /Applications/
  echo "Installed /Applications/macBDMV.app"
else
  echo "Built $app"
fi
