#!/bin/bash
# Local fallback for .github/workflows/release.yml: builds a release on this Mac and publishes it
# to GitHub through the REST API.
#
# Usage: GH_TOKEN=<token with contents:write> scripts/release.sh X.Y.Z
#
# Steps: checks (clean tree, CHANGELOG section, tag not taken, HEAD pushed) → swift test →
# universal zip → draft GitHub release with the CHANGELOG notes → asset uploads → local annotated tag.
# It never pushes: it prints the commands to push the tag and to publish the draft.
#
# The release is created as a draft on purpose: a published release would create the tag on GitHub
# by itself, and pushing the annotated tag afterwards would then be rejected.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="${CLAUDEDECK_REPO:-yentur/ClaudeDeck}"
API="https://api.github.com/repos/$REPO"
UPLOADS="https://uploads.github.com/repos/$REPO"

die() {
  echo "error: $*" >&2
  exit 1
}

[ $# -eq 1 ] || die "usage: GH_TOKEN=<token> scripts/release.sh X.Y.Z"
VERSION="${1#v}"
TAG="v$VERSION"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || die "'$1' is not a semantic version like 1.2.0"
[ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN is not set (needs contents:write on $REPO)"
command -v python3 >/dev/null || die "python3 is required to build the API request"

# --- Checks -------------------------------------------------------------------------------------

[ -z "$(git status --porcelain)" ] || die "the working tree is not clean; commit or stash your changes first"
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
  die "tag $TAG already exists"
fi
COMMIT="$(git rev-parse HEAD)"
[ -n "$(git branch -r --contains "$COMMIT" 2>/dev/null)" ] ||
  die "HEAD ($COMMIT) is not on any remote branch; push it first (git push origin HEAD)"

extract_notes() {
  awk -v header="## [$VERSION]" '
    index($0, header) == 1 { found = 1; next }
    found && (/^## \[/ || /^\[[^]]+\]: /) { exit }
    found { print }
  ' CHANGELOG.md
}
NOTES="$(extract_notes)"
printf '%s' "$NOTES" | grep -q '[^[:space:]]' || die "CHANGELOG.md has no '## [$VERSION]' section"

# --- Build --------------------------------------------------------------------------------------

echo "==> swift test"
swift test

echo "==> building universal zip"
./scripts/build-app.sh --universal --version "$VERSION" --zip
ZIP="dist/ClaudeDeck-$VERSION.zip"
SHA="$ZIP.sha256"
[ -f "$ZIP" ] && [ -f "$SHA" ] || die "build did not produce $ZIP and $SHA"
(cd dist && shasum -a 256 -c "$(basename "$SHA")") || die "checksum verification failed"

# --- GitHub release -----------------------------------------------------------------------------

# The token goes to curl through a process substitution, so it never shows up in `ps`.
github() {
  local method="$1" url="$2"
  shift 2
  curl -sS --fail-with-body -X "$method" \
    -H @<(printf 'Authorization: Bearer %s\n' "$GH_TOKEN") \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "$@" "$url"
}

json_field() {
  python3 -c 'import json, sys; print(json.load(sys.stdin)[sys.argv[1]])' "$1"
}

PRERELEASE=false
case "$VERSION" in *-*) PRERELEASE=true ;; esac

PAYLOAD="$(TAG="$TAG" COMMIT="$COMMIT" VERSION="$VERSION" NOTES="$NOTES" PRERELEASE="$PRERELEASE" python3 -c '
import json, os
print(json.dumps({
    "tag_name": os.environ["TAG"],
    "target_commitish": os.environ["COMMIT"],
    "name": "ClaudeDeck " + os.environ["VERSION"],
    "body": os.environ["NOTES"].strip() + "\n",
    "draft": True,
    "prerelease": os.environ["PRERELEASE"] == "true",
}))')"

echo "==> creating draft release $TAG on $REPO"
RELEASE="$(printf '%s' "$PAYLOAD" | github POST "$API/releases" -H "Content-Type: application/json" --data-binary @-)" ||
  die "could not create the release: $RELEASE"
RELEASE_ID="$(printf '%s' "$RELEASE" | json_field id)"
RELEASE_URL="$(printf '%s' "$RELEASE" | json_field html_url)"

upload() {
  local file="$1" type="$2" name
  name="$(basename "$file")"
  echo "==> uploading $name"
  github POST "$UPLOADS/releases/$RELEASE_ID/assets?name=$name" \
    -H "Content-Type: $type" --data-binary @"$file" >/dev/null ||
    die "upload of $name failed; the draft release is at $RELEASE_URL"
}
upload "$ZIP" application/zip
upload "$SHA" text/plain

# --- Tag ----------------------------------------------------------------------------------------

git tag -a "$TAG" -m "ClaudeDeck $VERSION" "$COMMIT"

cat <<EOF

Draft release created: $RELEASE_URL
  assets: $(basename "$ZIP"), $(basename "$SHA")
  sha256: $(cut -d' ' -f1 "$SHA")

Next steps (nothing has been pushed):

  1. Push the tag:
       git push origin $TAG

  2. Publish the draft — open the URL above and click "Publish release", or:
       curl -sS -X PATCH -H "Authorization: Bearer \$GH_TOKEN" \\
         -H "Accept: application/vnd.github+json" \\
         $API/releases/$RELEASE_ID -d '{"draft":false}'

  3. Update Casks/claudedeck.rb in yentur/homebrew-tap: version "$VERSION", sha256 above.
EOF
