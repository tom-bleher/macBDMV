#!/bin/zsh
# Builds build/macBDMV.app (Release, arm64, ad-hoc signed) with Sparkle embedded.
#
# Usage: scripts/build_app.sh [--version X.Y.Z] [--install]
#   --version  CFBundleShortVersionString (default: Resources/Info.plist's)
#   --install  also copy the app to /Applications
# CFBundleVersion is the git commit count (override with MACBDMV_BUILD); Sparkle orders updates by it.
set -euo pipefail
cd "${0:A:h}/.."

version=$(plutil -extract CFBundleShortVersionString raw -o - Resources/Info.plist)
install=0
while (( $# )); do
    case $1 in
        --version) version=${2:?--version needs a value}; shift ;;
        --install) install=1 ;;
        *) print -u2 "unknown argument: $1"; exit 1 ;;
    esac
    shift
done
[[ $version =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] || { print -u2 "version must look like 1.2 or 1.2.3: $version"; exit 1 }
build=${MACBDMV_BUILD:-$(git rev-list --count HEAD)}

swift build -c release --arch arm64 >&2
bin=$(swift build -c release --arch arm64 --show-bin-path)

app=build/macBDMV.app
rm -rf $app
mkdir -p $app/Contents/MacOS $app/Contents/Resources $app/Contents/Frameworks
cp $bin/macBDMV $app/Contents/MacOS/
ditto $bin/Sparkle.framework $app/Contents/Frameworks/Sparkle.framework
cp Resources/AppIcon.icns $app/Contents/Resources/
cp Resources/Info.plist $app/Contents/
plutil -replace CFBundleShortVersionString -string $version $app/Contents/Info.plist
plutil -replace CFBundleVersion -string $build $app/Contents/Info.plist

# Sparkle ships universal binaries; the app is Apple Silicon only.
find $app -type f -print0 | while IFS= read -r -d '' f; do
    [[ $(lipo -archs $f 2>/dev/null) == *x86_64* ]] && lipo -thin arm64 $f -output $f.thin && mv $f.thin $f
done
codesign --force --deep --sign - $app
codesign --verify --deep --strict $app

if (( install )); then
    rm -rf /Applications/macBDMV.app
    ditto $app /Applications/macBDMV.app
    print "Installed /Applications/macBDMV.app ($version, build $build)"
else
    print "Built $app ($version, build $build)"
fi
