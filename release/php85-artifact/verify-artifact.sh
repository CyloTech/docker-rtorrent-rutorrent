#!/bin/sh
# Release gate for the php85 package artifact image.
#
# Usage: release/php85-artifact/verify-artifact.sh <image>
#
#   <image> is repo.cylo.net/php-artifacts:php85-8.5.12-r0-alpine3.24 for a
#   release, or local/php-artifacts-trial:<tag> for a trial run.
#
# Exits 0 only when the local image holds exactly the signed php85
# repository, public key and manifest described by its SHA256SUMS, every
# package verifies and installs in alpine:3.24 (pinned), PHP is the fixed
# version, every module loads, php-fpm85 -t and httpd -t pass, multipart
# uploads parse through the CLI server, php-fpm and apache2 + mod_php85,
# and the authenticated registry definitively reports that the release
# tag does not exist. Any indeterminate registry answer fails.
set -eu
LC_ALL=C
export LC_ALL

RELEASE_REF="repo.cylo.net/php-artifacts:php85-8.5.12-r0-alpine3.24"
PHP_VERSION="8.5.12"
PACKAGE_VERSION="8.5.12-r0"
ALPINE_REF="alpine@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6"  # alpine:3.24
# An existing manifest, read first to prove the credentials work.
KNOWN_REPOSITORY="rutorrent"
KNOWN_DIGEST="sha256:d0d5e6f7577aef143f171f4d05995c045122380311396694b430ec758947d5ee"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ "$#" -eq 1 ] || fail "usage: $0 <image>"
image_ref=$1
case "$image_ref" in
    "$RELEASE_REF") gate_mode=release ;;
    local/php-artifacts-trial:*)
        case "${image_ref#local/php-artifacts-trial:}" in
            ''|*[!A-Za-z0-9._-]*) fail "invalid trial tag: $image_ref" ;;
        esac
        gate_mode=trial
        ;;
    *) fail "unexpected image reference: $image_ref" ;;
esac

recipe_dir=$(cd "$(dirname "$0")" && pwd)
for tool in docker curl jq tar sha256sum od; do
    command -v "$tool" >/dev/null 2>&1 || fail "missing tool: $tool"
done

run_id="php-artifact-gate-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
work_dir=$(mktemp -d)
gate_container=""
cleanup() {
    if [ -n "$gate_container" ]; then
        owner=$(docker inspect --format '{{index .Config.Labels "appbox.release-gate"}}' "$gate_container" 2>/dev/null || true)
        [ "$owner" = "$run_id" ] && docker rm -f "$gate_container" >/dev/null 2>&1 || true
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

registry_auth=""
registry_get() {
    printf 'header = "Authorization: Basic %s"\n' "$registry_auth" \
        | curl -sS --max-time 60 -K - -o "$work_dir/registry-body" -w '%{http_code}' \
            -H 'Accept: application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json' \
            "https://$1"
}

check_registry() {
    echo "== Registry: $RELEASE_REF must not exist"
    registry=${RELEASE_REF%%/*}
    repository_and_tag=${RELEASE_REF#*/}
    repository=${repository_and_tag%:*}
    tag=${repository_and_tag##*:}
    registry_auth=$(jq -r --arg host "$registry" '.auths[$host].auth // empty' "$HOME/.docker/config.json")
    [ -n "$registry_auth" ] || fail "no stored credentials for $registry"
    api_status=$(registry_get "$registry/v2/") || fail "registry unreachable"
    [ "$api_status" = 200 ] || fail "registry API check returned HTTP $api_status"
    known_status=$(registry_get "$registry/v2/$KNOWN_REPOSITORY/manifests/$KNOWN_DIGEST") || fail "registry unreachable"
    [ "$known_status" = 200 ] || fail "registry read of a known manifest returned HTTP $known_status; state is indeterminate"
    manifest_status=$(registry_get "$registry/v2/$repository/manifests/$tag") || fail "registry unreachable"
    case "$manifest_status" in
        200) fail "$RELEASE_REF already exists in the registry; refusing to replace it" ;;
        404)
            grep -q -E 'MANIFEST_UNKNOWN|NAME_UNKNOWN' "$work_dir/registry-body" \
                || fail "registry returned 404 without MANIFEST_UNKNOWN/NAME_UNKNOWN: $(head -c 300 "$work_dir/registry-body")"
            echo "known manifest readable; $RELEASE_REF is definitively absent ($(jq -r '.errors[0].code' "$work_dir/registry-body"))"
            ;;
        *) fail "registry returned HTTP $manifest_status for $RELEASE_REF" ;;
    esac
}

echo "== Gate $run_id: $image_ref ($gate_mode)"
check_registry

echo "== Image contents"
docker image inspect "$image_ref" >/dev/null 2>&1 || fail "$image_ref is not a local image"
[ "$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image_ref")" = linux/amd64 ] || fail "image is not linux/amd64"
gate_container=$(docker create --label "appbox.release-gate=$run_id" "$image_ref" /none)
docker export "$gate_container" > "$work_dir/rootfs.tar"
docker rm -f "$gate_container" >/dev/null
gate_container=""
# docker export adds these mount points to every container filesystem.
tar -tf "$work_dir/rootfs.tar" | sed 's|/$||' \
    | grep -v -x -E '\.dockerenv|dev|dev/.*|proc|sys|etc|etc/hosts|etc/hostname|etc/resolv\.conf|etc/mtab' \
    | sort > "$work_dir/members"
mkdir "$work_dir/rootfs"
tar -xf "$work_dir/rootfs.tar" -C "$work_dir/rootfs" README.md SHA256SUMS build-info.txt build-environment-packages.txt keys packages
rootfs=$work_dir/rootfs
(cd "$rootfs" && find packages keys -type f | sort) > "$work_dir/payload-files"
sed 's/^[0-9a-f]\{64\}  //' "$rootfs/SHA256SUMS" | sort > "$work_dir/listed-files"
cmp -s "$work_dir/payload-files" "$work_dir/listed-files" \
    || fail "SHA256SUMS does not list exactly the packages and keys: $(comm -3 "$work_dir/payload-files" "$work_dir/listed-files" | tr -s ' \t\n' ' ')"
(cd "$rootfs" && sha256sum -c --quiet SHA256SUMS) || fail "SHA256SUMS does not match the image contents"
{
    echo README.md; echo SHA256SUMS; echo build-environment-packages.txt; echo build-info.txt
    echo keys; echo packages; echo packages/community; echo packages/community/x86_64
    cat "$work_dir/payload-files"
} | sort > "$work_dir/expected-members"
cmp -s "$work_dir/members" "$work_dir/expected-members" \
    || fail "unexpected image members: $(comm -3 "$work_dir/members" "$work_dir/expected-members" | tr -s ' \t\n' ' ')"
key_count=$(find "$rootfs/keys" -type f -name '*.rsa.pub' | wc -l)
[ "$key_count" -eq 1 ] || fail "expected one public key, found $key_count"
[ -z "$(find "$rootfs/keys" "$rootfs/packages" -type f ! -name '*.rsa.pub' ! -name '*.apk' ! -name APKINDEX.tar.gz)" ] \
    || fail "unexpected file types in keys/ or packages/"
grep -q -E 'BEGIN (RSA )?PRIVATE KEY' -r "$rootfs" && fail "a private key is in the image"
tar -xzOf "$rootfs/packages/community/x86_64/APKINDEX.tar.gz" APKINDEX > "$work_dir/APKINDEX"
awk -F: '/^P:/{p=$2} /^V:/{print p "-" $2}' "$work_dir/APKINDEX" | sort > "$work_dir/index-packages"
grep -q -x "php85-$PACKAGE_VERSION" "$work_dir/index-packages" || fail "APKINDEX has no php85-$PACKAGE_VERSION"
grep -v -E -- "-$PACKAGE_VERSION\$" "$work_dir/index-packages" | grep . && fail "APKINDEX has packages that are not $PACKAGE_VERSION"
(cd "$rootfs/packages/community/x86_64" && ls *.apk | sed 's/\.apk$//' | sort) > "$work_dir/apk-files"
cmp -s "$work_dir/index-packages" "$work_dir/apk-files" || fail "APKINDEX and .apk files differ"
echo "$(wc -l < "$work_dir/apk-files") packages, all $PACKAGE_VERSION; SHA256SUMS verified; one public key; no private key"
sed 's/^/  /' "$rootfs/build-info.txt"

echo "== Install and test in alpine:3.24 ($ALPINE_REF)"
docker image inspect "$ALPINE_REF" >/dev/null 2>&1 || docker pull -q --platform linux/amd64 "$ALPINE_REF" >/dev/null
docker run --rm --platform linux/amd64 --label "appbox.release-gate=$run_id" \
    -v "$rootfs:/artifact:ro" -v "$recipe_dir/artifact-smoke.sh:/artifact-smoke.sh:ro" \
    --entrypoint sh "$ALPINE_REF" /artifact-smoke.sh "$PHP_VERSION" "$PACKAGE_VERSION" \
    || fail "install and runtime tests failed"

check_registry

if [ "$gate_mode" = release ]; then
    echo "PASS: $image_ref (php85 $PACKAGE_VERSION)"
else
    echo "TRIAL PASS: $image_ref (php85 $PACKAGE_VERSION); not a release approval"
fi
