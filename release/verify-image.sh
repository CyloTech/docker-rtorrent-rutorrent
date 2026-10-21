#!/bin/sh
# Release gate for ruTorrent 5.3.15.5 (Dockerfile.php-security): the 5.3.15.4
# image with only its php85 packages upgraded.
#
# Usage: release/verify-image.sh <image>
#
#   <image> is repo.cylo.net/rutorrent:5.3.15.5-0.16.24 for a release, or a
#   local/rutorrent-trial:<tag> image for a trial run.
#
# Exits 0 only when the local image passes every check and the authenticated
# registry definitively reports that the release tag does not exist yet. The
# registry check always targets the release tag, whatever image is tested.
# Any indeterminate registry answer fails.
#
# A trial run may lower the PHP floor with GATE_TRIAL_PHP85_MIN_VERSION (for
# proving the gate against today's unpatched packages). That variable is
# refused for the release image.
set -eu
LC_ALL=C
export LC_ALL

RELEASE_REF="repo.cylo.net/rutorrent:5.3.15.5-0.16.24"
RELEASE_VERSION="5.3.15.5"
BASE_REF="repo.cylo.net/rutorrent@sha256:d0d5e6f7577aef143f171f4d05995c045122380311396694b430ec758947d5ee"
RUTORRENT_REVISION="fe468360f94b02def11bbf67b16316bbe8081380"
PHP85_FLOOR="8.5.12"
HEALTH_TIMEOUT=900

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

[ "$#" -eq 1 ] || fail "usage: $0 <image>"
image_ref=$1
case "$image_ref" in
    "$RELEASE_REF") gate_mode=release ;;
    local/rutorrent-trial:*)
        case "${image_ref#local/rutorrent-trial:}" in
            ''|*[!A-Za-z0-9._-]*) fail "invalid trial tag: $image_ref" ;;
        esac
        gate_mode=trial
        ;;
    *) fail "unexpected image reference: $image_ref (expected $RELEASE_REF or local/rutorrent-trial:<tag>)" ;;
esac

php85_floor=$PHP85_FLOOR
if [ -n "${GATE_TRIAL_PHP85_MIN_VERSION:-}" ]; then
    [ "$gate_mode" = trial ] || fail "refusing to lower the PHP floor for $image_ref"
    case "$GATE_TRIAL_PHP85_MIN_VERSION" in
        *[!0-9.]*|.*|*.) fail "invalid GATE_TRIAL_PHP85_MIN_VERSION" ;;
    esac
    php85_floor=$GATE_TRIAL_PHP85_MIN_VERSION
    echo "TRIAL: PHP floor lowered from $PHP85_FLOOR to $php85_floor; this run cannot approve a release"
fi

release_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(dirname "$release_dir")
for tool in docker curl jq comm cmp diff od; do
    command -v "$tool" >/dev/null 2>&1 || fail "missing tool: $tool"
done

run_id="rutorrent-php-gate-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
gate_label="appbox.release-gate=$run_id"
work_dir=$(mktemp -d)
gate_containers=""
gate_volumes=""

cleanup() {
    for gate_container in $gate_containers; do
        owner=$(docker inspect --format '{{index .Config.Labels "appbox.release-gate"}}' "$gate_container" 2>/dev/null || true)
        [ "$owner" = "$run_id" ] && docker rm -fv "$gate_container" >/dev/null 2>&1 || true
    done
    for gate_volume in $gate_volumes; do
        owner=$(docker volume inspect --format '{{index .Labels "appbox.release-gate"}}' "$gate_volume" 2>/dev/null || true)
        [ "$owner" = "$run_id" ] && docker volume rm "$gate_volume" >/dev/null 2>&1 || true
    done
    rm -rf "$work_dir"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

in_image() {
    gate_image=$1
    shift
    gate_entrypoint=$1
    shift
    docker run --rm --platform linux/amd64 --network none --entrypoint "$gate_entrypoint" "$gate_image" "$@"
}

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
    base_digest=${BASE_REF#*@}
    registry_auth=$(jq -r --arg host "$registry" '.auths[$host].auth // empty' "$HOME/.docker/config.json")
    [ -n "$registry_auth" ] || fail "no stored credentials for $registry"

    api_status=$(registry_get "$registry/v2/") || fail "registry unreachable"
    [ "$api_status" = 200 ] || fail "registry API check returned HTTP $api_status"
    known_status=$(registry_get "$registry/v2/$repository/manifests/$base_digest") || fail "registry unreachable"
    [ "$known_status" = 200 ] || fail "registry read of the 5.3.15.4 digest returned HTTP $known_status; state is indeterminate"
    manifest_status=$(registry_get "$registry/v2/$repository/manifests/$tag") || fail "registry unreachable"
    case "$manifest_status" in
        200) fail "$RELEASE_REF already exists in the registry; refusing to replace it" ;;
        404)
            grep -q 'MANIFEST_UNKNOWN' "$work_dir/registry-body" \
                || fail "registry returned 404 without MANIFEST_UNKNOWN: $(head -c 300 "$work_dir/registry-body")"
            echo "5.3.15.4 digest readable; $RELEASE_REF is definitively absent (MANIFEST_UNKNOWN)"
            ;;
        *) fail "registry returned HTTP $manifest_status for $RELEASE_REF" ;;
    esac
}

wait_healthy() {
    waited=0
    while :; do
        state=$(docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$1")
        case "$state" in
            "running healthy") echo "$1 healthy after ${waited}s"; return 0 ;;
            exited*|dead*)
                docker logs --tail 80 "$1" 2>&1 | grep -v -i -E 'pass|auth|token' >&2 || true
                fail "$1 stopped during startup: $state"
                ;;
        esac
        [ "$waited" -lt "$HEALTH_TIMEOUT" ] || {
            docker logs --tail 80 "$1" 2>&1 | grep -v -i -E 'pass|auth|token' >&2 || true
            fail "$1 did not become healthy within ${HEALTH_TIMEOUT}s ($state)"
        }
        sleep 3
        waited=$((waited + 3))
    done
}

# start_app NAME IMAGE [VOLUME:TARGET ...]
start_app() {
    app_name=$1
    app_image=$2
    shift 2
    mount_args=""
    for mount in "$@"; do
        mount_args="$mount_args -v $mount"
    done
    gate_containers="$gate_containers $app_name"
    # PASSWORD comes from the environment, not the command line.
    docker run -d --name "$app_name" --label "$gate_label" --platform linux/amd64 --network none \
        -e USERNAME=releasegate -e PASSWORD -e SKIP_APPBOX_CALLBACK=1 -e WAN_IP=127.0.0.1 \
        $mount_args "$app_image" >/dev/null
    wait_healthy "$app_name"
}

in_app() {
    app_name=$1
    shift
    docker exec -i "$app_name" python3 - "$@" < "$release_dir/runtime-checks.py"
}

echo "== Gate $run_id: $image_ref ($gate_mode)"
grep -q "^  version: \"$RELEASE_VERSION\"\$" "$repo_dir/appbox.yml" \
    && grep -q "^  tag: \"${RELEASE_REF##*:}\"\$" "$repo_dir/appbox.yml" \
    || fail "appbox.yml image.version/tag do not match $RELEASE_REF"
check_registry

echo "== Image identity"
docker image inspect "$image_ref" >/dev/null 2>&1 || fail "$image_ref is not a local image"
docker image inspect "$BASE_REF" >/dev/null 2>&1 || docker pull --platform linux/amd64 "$BASE_REF" >/dev/null
[ "$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$image_ref")" = linux/amd64 ] || fail "image is not linux/amd64"
[ "$(docker image inspect --format '{{index .Config.Labels "io.appbox.rutorrent.revision"}}' "$image_ref")" = "$RUTORRENT_REVISION" ] \
    || fail "ruTorrent revision label differs from 5.3.15.4"
[ "$(docker image inspect --format '{{index .Config.Labels "io.appbox.rutorrent.base-image"}}' "$image_ref")" = "$BASE_REF" ] \
    || fail "base-image label is not the 5.3.15.4 digest"
for field in '{{json .Config.Entrypoint}}' '{{json .Config.Cmd}}' '{{json .Config.Healthcheck}}' '{{json .Config.Env}}' '{{json .Config.User}}' '{{json .Config.ExposedPorts}}' '{{json .Config.Volumes}}' '{{json .Config.WorkingDir}}'; do
    [ "$(docker image inspect --format "$field" "$image_ref")" = "$(docker image inspect --format "$field" "$BASE_REF")" ] \
        || fail "image config $field differs from 5.3.15.4"
done
docker image inspect --format '{{range .RootFS.Layers}}{{println .}}{{end}}' "$BASE_REF" | sed '/^$/d' > "$work_dir/base-layers"
docker image inspect --format '{{range .RootFS.Layers}}{{println .}}{{end}}' "$image_ref" | sed '/^$/d' > "$work_dir/image-layers"
base_layer_count=$(wc -l < "$work_dir/base-layers")
[ "$(wc -l < "$work_dir/image-layers")" -eq $((base_layer_count + 1)) ] \
    && head -n "$base_layer_count" "$work_dir/image-layers" | cmp -s - "$work_dir/base-layers" \
    || fail "image is not the 5.3.15.4 layers plus exactly one layer"
echo "5.3.15.4 layers ($base_layer_count) plus one PHP layer; entrypoint, healthcheck and environment unchanged"

echo "== Packages (only php85 may change)"
in_image "$BASE_REF" apk info -v | sort > "$work_dir/base-packages"
in_image "$image_ref" apk info -v | sort > "$work_dir/image-packages"
package_name() { sed -E 's/-[0-9][^-]*-r[0-9]+$//' "$1" | sort; }
package_name "$work_dir/base-packages" > "$work_dir/base-names"
package_name "$work_dir/image-packages" > "$work_dir/image-names"
cmp -s "$work_dir/base-names" "$work_dir/image-names" \
    || fail "installed package set changed: $(comm -3 "$work_dir/base-names" "$work_dir/image-names" | tr -s ' \t\n' ' ')"
comm -13 "$work_dir/base-packages" "$work_dir/image-packages" > "$work_dir/changed-packages"
allowed_packages=$(sed -n 's/^package://p' "$release_dir/allowed-changes.txt" 2>/dev/null || true)
unexpected=""
while read -r changed; do
    [ -n "$changed" ] || continue
    changed_name=$(printf '%s\n' "$changed" | sed -E 's/-[0-9][^-]*-r[0-9]+$//')
    old=$(grep -E "^$(printf '%s' "$changed_name" | sed 's/[.+]/\\&/g')-[0-9][^-]*-r[0-9]+\$" "$work_dir/base-packages" || true)
    echo "  $old -> $changed"
    case "$changed_name" in
        php85|php85-*) ;;
        *) printf '%s\n' "$allowed_packages" | grep -qxF "$changed_name" || unexpected="$unexpected $changed_name" ;;
    esac
done < "$work_dir/changed-packages"
[ -z "$unexpected" ] || fail "non-PHP packages changed:$unexpected (review, then list each as package:<name> in release/allowed-changes.txt)"
[ -s "$work_dir/changed-packages" ] || echo "  (no package changed)"
php85_builds=$(grep -E '^php85(-[a-z0-9]+)*-[0-9]' "$work_dir/image-packages" | sed -E 's/^php85(-[a-z0-9]+)*-//' | sort -u)
[ "$(printf '%s\n' "$php85_builds" | wc -l)" -eq 1 ] || fail "php85 packages come from different builds: $php85_builds"

echo "== PHP version (floor $php85_floor)"
php85_version=$(in_image "$image_ref" php85 -r 'echo PHP_VERSION;')
fpm_version=$(in_image "$image_ref" php-fpm85 -v | head -n 1 | awk '{print $2}')
echo "php85 $php85_version, php-fpm85 $fpm_version, packages $php85_builds"
[ "$fpm_version" = "$php85_version" ] || fail "php-fpm85 ($fpm_version) and php85 ($php85_version) differ"
in_image "$image_ref" php85 -r 'exit(version_compare(PHP_VERSION, $argv[1], ">=") ? 0 : 1);' "$php85_floor" \
    || fail "php85 $php85_version is older than $php85_floor"

echo "== PHP modules and configuration match 5.3.15.4"
for sapi in php85 php-fpm85; do
    in_image "$BASE_REF" "$sapi" -m > "$work_dir/base-$sapi-modules"
    in_image "$image_ref" "$sapi" -m > "$work_dir/image-$sapi-modules"
    diff -u "$work_dir/base-$sapi-modules" "$work_dir/image-$sapi-modules" || fail "$sapi module list differs from 5.3.15.4"
done
config_listing='find /etc/php85 /etc/nginx /tpls -type f -exec sha256sum {} + | sort -k 2; find / -xdev -name "*.apk-new" 2>/dev/null'
in_image "$BASE_REF" sh -c "$config_listing" > "$work_dir/base-config"
in_image "$image_ref" sh -c "$config_listing" > "$work_dir/image-config"
allowed_files=$(sed -n 's/^file://p' "$release_dir/allowed-changes.txt" 2>/dev/null || true)
config_changes=$(diff "$work_dir/base-config" "$work_dir/image-config" | sed -n 's/^[<>] //p' | awk '{print $NF}' | sort -u)
for changed_file in $config_changes; do
    printf '%s\n' "$allowed_files" | grep -qxF "$changed_file" \
        || fail "configuration changed: $changed_file (review, then list it as file:<path> in release/allowed-changes.txt)"
done
echo "php85/php-fpm85 modules identical; /etc/php85, /etc/nginx and /tpls unchanged; no .apk-new files"

echo "== Multipart upload (php85 CLI server)"
docker run --rm --platform linux/amd64 --network none -v "$release_dir:/release:ro" --entrypoint sh "$image_ref" \
    /release/multipart-smoke.sh || fail "multipart upload smoke test failed"

echo "== Regression checks"
for check in "$release_dir"/regression/*.sh; do
    [ -e "$check" ] || continue
    echo "-- $(basename "$check")"
    docker run --rm --platform linux/amd64 --network none -v "$release_dir:/release:ro" --entrypoint sh "$image_ref" \
        "/release/regression/$(basename "$check")" || fail "regression check $(basename "$check") failed"
done

PASSWORD=$(od -An -N18 -tx1 /dev/urandom | tr -d ' \n')
export PASSWORD

echo "== Fresh install"
start_app "$run_id-fresh" "$image_ref"
fresh_summary=$(in_app "$run_id-fresh" check "$php85_version") || fail "fresh install runtime checks failed"
echo "$fresh_summary" | tail -n 1
docker rm -fv "$run_id-fresh" >/dev/null

echo "== Upgrade from 5.3.15.4 with the same /torrents and /passwd"
for suffix in torrents passwd; do
    docker volume create --label "$gate_label" "$run_id-$suffix" >/dev/null
    gate_volumes="$gate_volumes $run_id-$suffix"
done
start_app "$run_id-old" "$BASE_REF" "$run_id-torrents:/torrents" "$run_id-passwd:/passwd"
seeded=$(in_app "$run_id-old" seed | tail -n 1 | jq -r '.seeded') || fail "could not add a torrent on 5.3.15.4"
case "$seeded" in [0-9A-F][0-9A-F]*) ;; *) fail "unexpected seed hash: $seeded" ;; esac
docker stop --time 30 "$run_id-old" >/dev/null
start_app "$run_id-new" "$image_ref" "$run_id-torrents:/torrents" "$run_id-passwd:/passwd"
upgrade_summary=$(in_app "$run_id-new" check "$php85_version" "$seeded") || fail "upgrade runtime checks failed"
echo "$upgrade_summary" | tail -n 1

check_registry

if [ "$gate_mode" = release ]; then
    echo "PASS: $image_ref (php85 $php85_version)"
else
    echo "TRIAL PASS: $image_ref (php85 $php85_version, floor $php85_floor); not a release approval"
fi
