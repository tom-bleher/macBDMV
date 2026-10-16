#!/bin/zsh
# Wraps a fresh build of macBDMV.app in a drag-to-Applications DMG and verifies it.
#
# Usage: scripts/package-dmg.sh [--version X.Y.Z] [--force]
# Output: dist/macBDMV-VERSION.dmg plus its .sha256.
set -euo pipefail
cd "${0:A:h}/.."

die() { print -u2 "error: $*"; exit 1 }

version=$(plutil -extract CFBundleShortVersionString raw -o - Resources/Info.plist)
force=0
while (( $# )); do
    case $1 in
        --version) version=${2:?--version needs a value}; shift ;;
        --force) force=1 ;;
        *) die "unknown argument: $1" ;;
    esac
    shift
done
mkdir -p dist
dmg=$PWD/dist/macBDMV-$version.dmg
(( force )) || [[ ! -e $dmg ]] || die "$dmg exists; pass --force"

scripts/build_app.sh --version $version

tmp=$(mktemp -d "${TMPDIR:-/tmp}/macbdmv-dmg.XXXXXX")
device=""
smoke_pid=""
cleanup() {
    [[ -n $smoke_pid ]] && kill $smoke_pid 2>/dev/null || true
    [[ -n $device ]] && hdiutil detach $device -quiet -force 2>/dev/null || true
    rm -rf $tmp
}
trap cleanup EXIT INT TERM

stage=$tmp/stage
mkdir $stage
ditto build/macBDMV.app $stage/macBDMV.app
ln -s /Applications $stage/Applications
cp Resources/AppIcon.icns $stage/.VolumeIcon.icns

# Read-write image first so the volume can get its custom-icon flag, then LZFSE-compressed (ULFO).
hdiutil create -srcfolder $stage -volname macBDMV -fs "Journaled HFS+" -format UDRW -ov $tmp/rw.dmg >/dev/null
attach=$(hdiutil attach $tmp/rw.dmg -readwrite -noverify -noautoopen -nobrowse -owners off)
device=$(print -r -- $attach | awk '/^\/dev\// { print $1; exit }')
mounted=$(print -r -- $attach | awk -F '\t' '/^\/dev\// && $NF ~ /^\// { print $NF; exit }')
SetFile -a C $mounted 2>/dev/null || print -u2 "warning: SetFile unavailable; the volume keeps the generic icon"
hdiutil detach $device -quiet
device=""
hdiutil convert $tmp/rw.dmg -format ULFO -o $tmp/final.dmg >/dev/null
hdiutil verify $tmp/final.dmg >/dev/null

# Check the image the way a user meets it: mount read-only, verify the signature, launch from it.
mkdir $tmp/verify
attach=$(hdiutil attach $tmp/final.dmg -readonly -noverify -noautoopen -nobrowse -mountpoint $tmp/verify)
device=$(print -r -- $attach | awk '/^\/dev\// { print $1; exit }')
app=$tmp/verify/macBDMV.app
[[ -L $tmp/verify/Applications ]] || die "image has no Applications link"
codesign --verify --deep --strict $app || die "app in the image fails signature verification"
[[ $(plutil -extract CFBundleShortVersionString raw -o - $app/Contents/Info.plist) == $version ]] || die "image holds the wrong version"
$app/Contents/MacOS/macBDMV -ApplePersistenceIgnoreState YES >$tmp/smoke.log 2>&1 &
smoke_pid=$!
sleep 5
kill -0 $smoke_pid 2>/dev/null || { cat $tmp/smoke.log >&2; die "the app exited during the launch check"; }
kill $smoke_pid; wait $smoke_pid 2>/dev/null || true
smoke_pid=""
hdiutil detach $device -quiet || { sleep 2; hdiutil detach $device -quiet -force; }
device=""

mv -f $tmp/final.dmg $dmg
(cd dist && shasum -a 256 ${dmg:t} > ${dmg:t}.sha256)
print "Created and verified $dmg ($(du -h $dmg | awk '{ print $1 }'))"
