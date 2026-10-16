#!/bin/zsh
# Builds the DMG, signs it as a Sparkle update and publishes it as a GitHub release.
#
# The DMG is both the installer and the update archive. Installed apps read the appcast attached to the
# latest release (SUFeedURL = …/releases/latest/download/appcast.xml), so the release is published with the
# DMG and appcast together, and only after the new build is checked to sort after the published one.
set -euo pipefail
cd "${0:A:h}/.."

usage() {
    cat <<'USAGE'
Usage: scripts/release.sh --version X.Y.Z [--notes-file F] [--first-release]

  --version X.Y.Z  Release version; tagged vX.Y.Z.
  --notes-file F   Markdown release notes for GitHub and the in-app update alert (default: one-liner).
  --first-release  No published feed yet: skip the check that the new build sorts after the published one.

Needs a clean checkout whose HEAD is pushed to origin/main, an authenticated gh, and the EdDSA private key:
SPARKLE_ED_KEY_FILE, ~/.config/macbdmv/sparkle-private-key, or the "macbdmv" account in the login keychain.
Builds are ad-hoc signed (no Developer ID): fresh installs need right-click → Open once; in-app updates are
trusted through the EdDSA signature.
USAGE
}

die() { print -u2 "error: $*"; exit 1 }

version=""
notes_file=""
first_release=0
while (( $# )); do
    case $1 in
        --version) version=${2:?--version needs a value}; shift ;;
        --notes-file) notes_file=${2:?--notes-file needs a path}; shift ;;
        --first-release) first_release=1 ;;
        -h|--help) usage; exit 0 ;;
        *) die "unknown argument: $1 (see --help)" ;;
    esac
    shift
done
[[ $version =~ '^[0-9]+\.[0-9]+(\.[0-9]+)?$' ]] || die "pass --version X.Y.Z (see --help)"
[[ -z $notes_file || -f $notes_file ]] || die "notes file not found: $notes_file"
notes_file=${notes_file:+${notes_file:a}}
tag=v$version

# MARK: Preconditions

gh auth status >/dev/null 2>&1 || die "gh is not authenticated (gh auth login)"
git fetch --quiet origin
[[ -z $(git status --porcelain) ]] || die "release builds need a clean checkout"
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || die "HEAD is not origin/main; push first"
! git rev-parse -q --verify "refs/tags/$tag" >/dev/null && ! gh release view $tag >/dev/null 2>&1 || \
    die "$tag already exists"

feed_url=$(plutil -extract SUFeedURL raw -o - Resources/Info.plist)
repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
[[ $feed_url == "https://github.com/$repo/releases/latest/download/appcast.xml" ]] || \
    die "SUFeedURL does not point at this repo's latest release: $feed_url"

# MARK: Sparkle tools, pinned to the version the app links

sparkle_version=$(python3 -I -c 'import json; print(next(p["state"]["version"] for p in json.load(open("Package.resolved"))["pins"] if p["identity"] == "sparkle"))')
tools=${XDG_CACHE_HOME:-$HOME/.cache}/macbdmv/sparkle-$sparkle_version
if [[ ! -x $tools/bin/generate_appcast ]]; then
    print "Downloading Sparkle $sparkle_version tools..."
    mkdir -p $tools
    gh release download $sparkle_version -R sparkle-project/Sparkle --pattern "Sparkle-$sparkle_version.tar.xz" --dir $tools --clobber
    tar -xf $tools/Sparkle-$sparkle_version.tar.xz -C $tools
fi

if [[ -n ${SPARKLE_ED_KEY_FILE:-} ]]; then
    key_args=(--ed-key-file $SPARKLE_ED_KEY_FILE)
elif [[ -f ~/.config/macbdmv/sparkle-private-key ]]; then
    key_args=(--ed-key-file ~/.config/macbdmv/sparkle-private-key)
else
    key_args=(--account macbdmv)
fi

# MARK: DMG, signature, appcast

scripts/package-dmg.sh --version $version --force
dmg=$PWD/dist/macBDMV-$version.dmg
build=$(plutil -extract CFBundleVersion raw -o - build/macBDMV.app/Contents/Info.plist)

tmp=$(mktemp -d "${TMPDIR:-/tmp}/macbdmv-release.XXXXXX")
trap 'rm -rf $tmp' EXIT INT TERM
mkdir $tmp/updates
cp $dmg $tmp/updates/
if [[ -n $notes_file ]]; then cp $notes_file $tmp/notes.md; else print "macBDMV $version." > $tmp/notes.md; fi
cp $tmp/notes.md $tmp/updates/macBDMV-$version.md

print "Signing the update and writing the appcast..."
$tools/bin/generate_appcast $key_args -o $tmp/appcast.xml \
    --download-url-prefix "https://github.com/$repo/releases/download/$tag/" --embed-release-notes $tmp/updates
appcast=$tmp/appcast.xml
grep -Fq 'sparkle:edSignature="' $appcast || die "appcast has no EdDSA signature"
grep -Fq "<sparkle:version>$build</sparkle:version>" $appcast || die "appcast does not advertise build $build"

# MARK: The new build must sort after the published one, or no installed app is offered it

if curl -fsSL $feed_url -o $tmp/published.xml; then
    old_build=$(grep -o '<sparkle:version>[^<]*' $tmp/published.xml | head -1 | sed 's/.*>//')
    old_version=$(grep -o '<sparkle:shortVersionString>[^<]*' $tmp/published.xml | head -1 | sed 's/.*>//')
    [[ $old_build =~ '^[0-9]+$' ]] || die "could not read the published feed's build number"
    (( build > old_build )) || die "published build $old_build is not older than $build"
    autoload -Uz is-at-least
    is-at-least $old_version $version || die "$version would go back behind the published $old_version"
    print "Build $build ($version) sorts after the published build $old_build ($old_version)."
elif (( ! first_release )); then
    die "could not read the published feed $feed_url (pass --first-release for the first release)"
fi

# MARK: Publish (gh uploads the assets before the release goes live)

gh release create $tag $dmg $dmg.sha256 $appcast --target $(git rev-parse HEAD) \
    --title "macBDMV $version" --notes-file $tmp/notes.md
curl -fsSL $feed_url -o $tmp/live.xml && cmp -s $appcast $tmp/live.xml || die "the live feed differs from the generated one"
print "Published $tag: https://github.com/$repo/releases/tag/$tag"
