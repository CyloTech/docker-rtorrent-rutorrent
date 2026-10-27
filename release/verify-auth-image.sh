#!/bin/sh
# Release gate for ruTorrent 5.3.15.6 (Dockerfile.auth-fail-closed): the
# 5.3.15.5 image with 03-config.sh, 025-set-passwd.sh and
# appbox-installed-callback replaced so an empty or missing htpasswd file never
# turns basic auth off and the callback token stays off curl's command line.
#
# Usage: release/verify-auth-image.sh <image>
#
#   <image> is repo.cylo.net/rutorrent:5.3.15.6-0.16.24 for a release, or a
#   local/rutorrent-trial:<tag> image for a trial run.
#
# Exits 0 only when the local image passes every check and the authenticated
# registry definitively reports that the release tag does not exist yet. The
# registry check always targets the release tag, whatever image is tested.
# Any indeterminate registry answer fails.
set -eu
LC_ALL=C
export LC_ALL

RELEASE_REF="repo.cylo.net/rutorrent:5.3.15.6-0.16.24"
RELEASE_VERSION="5.3.15.6"
BASE_NAME="5.3.15.5"
BASE_REF="repo.cylo.net/rutorrent@sha256:0f967374ba2396278b15a6c00e8330156d7daf6a14475071f88d5d88b3e9783b"
RUTORRENT_REVISION="fe468360f94b02def11bbf67b16316bbe8081380"
PHP85_ARTIFACT_LABEL="repo.cylo.net/php-artifacts@sha256:c810e2dbf5e5ff8225acc76d816fc76a00495430e9344ccf14acc632d2ad371d"
PHP_VERSION="8.5.12"
# The only files that may differ from 5.3.15.5, each a copy of rootfs/<path>.
CHANGED_FILES="/etc/cont-init.d/025-set-passwd.sh /etc/cont-init.d/03-config.sh /usr/local/bin/appbox-installed-callback"
EXTRA_LAYERS=2
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

release_dir=$(cd "$(dirname "$0")" && pwd)
repo_dir=$(dirname "$release_dir")
for tool in docker curl jq cmp diff od sha256sum; do
    command -v "$tool" >/dev/null 2>&1 || fail "missing tool: $tool"
done

run_id="rutorrent-auth-gate-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
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
    [ "$known_status" = 200 ] || fail "registry read of the $BASE_NAME digest returned HTTP $known_status; state is indeterminate"
    manifest_status=$(registry_get "$registry/v2/$repository/manifests/$tag") || fail "registry unreachable"
    case "$manifest_status" in
        200) fail "$RELEASE_REF already exists in the registry; refusing to replace it" ;;
        404)
            grep -q 'MANIFEST_UNKNOWN' "$work_dir/registry-body" \
                || fail "registry returned 404 without MANIFEST_UNKNOWN: $(head -c 300 "$work_dir/registry-body")"
            echo "$BASE_NAME digest readable; $RELEASE_REF is definitively absent (MANIFEST_UNKNOWN)"
            ;;
        *) fail "registry returned HTTP $manifest_status for $RELEASE_REF" ;;
    esac
}

show_logs() {
    docker logs --tail 80 "$1" 2>&1 | grep -v -i -E 'pass|token' >&2 || true
}

wait_healthy() {
    waited=0
    while :; do
        state=$(docker inspect --format '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$1")
        case "$state" in
            "running healthy") echo "$1 healthy after ${waited}s"; return 0 ;;
            exited*|dead*)
                show_logs "$1"
                fail "$1 stopped during startup: $state"
                ;;
        esac
        [ "$waited" -lt "$HEALTH_TIMEOUT" ] || {
            show_logs "$1"
            fail "$1 did not become healthy within ${HEALTH_TIMEOUT}s ($state)"
        }
        sleep 3
        waited=$((waited + 3))
    done
}

new_volume() {
    docker volume create --label "$gate_label" "$1" >/dev/null
    gate_volumes="$gate_volumes $1"
}

# start_app NAME IMAGE CREDENTIALS TORRENTS_VOLUME PASSWD_VOLUME
#   CREDENTIALS: "login" passes USERNAME and PASSWORD (the password from the
#   environment, not the command line); "user-only" passes only USERNAME.
start_app() {
    app_name=$1
    app_image=$2
    case "$3" in
        login) credential_args="-e USERNAME=releasegate -e PASSWORD" ;;
        user-only) credential_args="-e USERNAME=releasegate" ;;
        *) fail "start_app: unknown credentials $3" ;;
    esac
    gate_containers="$gate_containers $app_name"
    # shellcheck disable=SC2086
    docker run -d --name "$app_name" --label "$gate_label" --platform linux/amd64 --network none \
        $credential_args -e SKIP_APPBOX_CALLBACK=1 -e WAN_IP=127.0.0.1 \
        -v "$4:/torrents" -v "$5:/passwd" "$app_image" >/dev/null
    wait_healthy "$app_name"
}

runtime_check() {
    app_name=$1
    shift
    docker exec -i -e PASSWORD "$app_name" python3 - "$@" < "$release_dir/runtime-checks.py"
}

auth_check() {
    docker exec -i -e PASSWORD "$1" python3 - "$2" < "$release_dir/auth-checks.py"
}

# step DESCRIPTION COMMAND...: run one check; on failure show the end of its
# output and fail the gate, otherwise print its last line (the JSON summary).
step() {
    step_description=$1
    shift
    step_output=$("$@" 2>&1) || {
        printf '%s\n' "$step_output" | tail -n 20 >&2
        fail "$step_description"
    }
    printf '%s\n' "$step_output" | tail -n 1
}

# Persistent state an upgrade must keep: .rtorrent.rc, the session's
# .torrent files and a file under /torrents/completed.
volume_state() {
    docker exec "$1" sh -c 'set -e
        sha256sum /torrents/config/rtorrent/.rtorrent.rc /torrents/completed/appbox-gate-marker.txt
        cd /torrents/config/rtorrent/.session
        for f in *.torrent; do [ -f "$f" ] && echo "$f"; done'
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
    || fail "ruTorrent revision label differs from $BASE_NAME"
[ "$(docker image inspect --format '{{index .Config.Labels "io.appbox.rutorrent.base-image"}}' "$image_ref")" = "$BASE_REF" ] \
    || fail "base-image label is not the $BASE_NAME digest"
[ "$(docker image inspect --format '{{index .Config.Labels "io.appbox.php85-artifact"}}' "$image_ref")" = "$PHP85_ARTIFACT_LABEL" ] \
    || fail "php85-artifact label differs from $BASE_NAME"
for field in '{{json .Config.Entrypoint}}' '{{json .Config.Cmd}}' '{{json .Config.Healthcheck}}' '{{json .Config.Env}}' '{{json .Config.User}}' '{{json .Config.ExposedPorts}}' '{{json .Config.Volumes}}' '{{json .Config.WorkingDir}}'; do
    [ "$(docker image inspect --format "$field" "$image_ref")" = "$(docker image inspect --format "$field" "$BASE_REF")" ] \
        || fail "image config $field differs from $BASE_NAME"
done
docker image inspect --format '{{range .RootFS.Layers}}{{println .}}{{end}}' "$BASE_REF" | sed '/^$/d' > "$work_dir/base-layers"
docker image inspect --format '{{range .RootFS.Layers}}{{println .}}{{end}}' "$image_ref" | sed '/^$/d' > "$work_dir/image-layers"
base_layer_count=$(wc -l < "$work_dir/base-layers")
extra_layers=$(( $(wc -l < "$work_dir/image-layers") - base_layer_count ))
head -n "$base_layer_count" "$work_dir/image-layers" | cmp -s - "$work_dir/base-layers" \
    || fail "image does not start with the $BASE_NAME layers"
[ "$extra_layers" -eq "$EXTRA_LAYERS" ] || fail "image adds $extra_layers layer(s) to $BASE_NAME; expected $EXTRA_LAYERS"
echo "$BASE_NAME layers ($base_layer_count) plus $extra_layers; labels, entrypoint, healthcheck and environment unchanged"

echo "== Filesystem: only $CHANGED_FILES differ from $BASE_NAME"
# Every path's type, mode, owner and link target, and every regular file's
# SHA-256. Docker bind-mounts the three /etc files below per container.
fs_listing='find / -xdev \( -path /etc/hostname -o -path /etc/hosts -o -path /etc/resolv.conf \) -prune -o -printf "%y %m %u:%g %p -> %l\n" | sort; find / -xdev \( -path /etc/hostname -o -path /etc/hosts -o -path /etc/resolv.conf \) -prune -o -type f -exec sha256sum {} + | sort -k 2'
in_image "$BASE_REF" sh -c "$fs_listing" > "$work_dir/base-fs"
in_image "$image_ref" sh -c "$fs_listing" > "$work_dir/image-fs"
[ "$(wc -l < "$work_dir/image-fs")" -gt 10000 ] || fail "filesystem listing looks incomplete"
diff "$work_dir/base-fs" "$work_dir/image-fs" | sed -n 's/^> //p' | sort -k 2 > "$work_dir/fs-added" || true
diff "$work_dir/base-fs" "$work_dir/image-fs" | sed -n 's/^< //p' | sort -k 2 > "$work_dir/fs-removed" || true
expected_changes=""
for changed_file in $CHANGED_FILES; do
    repo_file="$repo_dir/rootfs$changed_file"
    [ -f "$repo_file" ] || fail "missing source file rootfs$changed_file"
    repo_sum=$(sha256sum "$repo_file" | awk '{print $1}')
    grep -qxF "$repo_sum  $changed_file" "$work_dir/image-fs" || fail "$changed_file in the image is not rootfs$changed_file"
    grep -qxF "f 775 root:root $changed_file -> " "$work_dir/image-fs" || fail "$changed_file is not a 0775 root:root file"
    expected_changes="$expected_changes$repo_sum  $changed_file
"
done
printf '%s' "$expected_changes" | sort -k 2 > "$work_dir/fs-expected"
cmp -s "$work_dir/fs-added" "$work_dir/fs-expected" \
    || { diff "$work_dir/fs-expected" "$work_dir/fs-added" >&2 || true; fail "unexpected filesystem additions or changes"; }
[ "$(wc -l < "$work_dir/fs-removed")" -eq "$(echo "$CHANGED_FILES" | wc -w)" ] \
    || { cat "$work_dir/fs-removed" >&2; fail "unexpected filesystem removals"; }
echo "$(wc -l < "$work_dir/image-fs") entries; only the $(echo "$CHANGED_FILES" | wc -w) replaced files differ, each identical to rootfs/ and 0775 root:root"

echo "== Script syntax"
in_image "$image_ref" sh -n /etc/cont-init.d/03-config.sh || fail "03-config.sh syntax"
in_image "$image_ref" bash -n /etc/cont-init.d/025-set-passwd.sh || fail "025-set-passwd.sh syntax"
in_image "$image_ref" bash -n /usr/local/bin/appbox-installed-callback || fail "appbox-installed-callback syntax"
if in_image "$image_ref" grep -q -E 'removing authentication|#auth_basic' /etc/cont-init.d/03-config.sh; then
    fail "03-config.sh can still comment out auth_basic"
fi
echo "sh -n / bash -n ok; 03-config.sh has no auth-removal path"

echo "== Installed callback helper"
callback_test() {
    docker run --rm --platform linux/amd64 --network none -v "$repo_dir/scripts:/gate-scripts:ro" \
        -e APPBOX_CALLBACK_HELPER=/usr/local/bin/appbox-installed-callback \
        --entrypoint bash "$1" /gate-scripts/test-installed-callback.sh
}
callback_test "$image_ref" > "$work_dir/callback-new" 2>&1 || { cat "$work_dir/callback-new" >&2; fail "callback helper tests failed"; }
sed 's/^/  /' "$work_dir/callback-new"
# Control: the same test must catch the token on the command line in 5.3.15.5.
if callback_test "$BASE_REF" > "$work_dir/callback-base" 2>&1; then
    fail "callback test passed against $BASE_NAME; it does not detect the command-line token"
fi
grep -q '^FAIL tokens not on the command line (curl seen=1, leaked=1)' "$work_dir/callback-base" \
    || { cat "$work_dir/callback-base" >&2; fail "callback control failed for an unexpected reason"; }
echo "  control: $BASE_NAME helper fails only on the command-line token ($(grep -c '^FAIL' "$work_dir/callback-base") FAIL)"
[ "$(grep -c '^FAIL' "$work_dir/callback-base")" -eq 1 ] || fail "callback control had other failures"

echo "== Regression checks"
for check in "$release_dir"/regression/*.sh; do
    [ -e "$check" ] || continue
    echo "-- $(basename "$check")"
    docker run --rm --platform linux/amd64 --network none -v "$release_dir:/release:ro" --entrypoint sh "$image_ref" \
        "/release/regression/$(basename "$check")" || fail "regression check $(basename "$check") failed"
done

PASSWORD=$(od -An -N18 -tx1 /dev/urandom | tr -d ' \n')
export PASSWORD

echo "== Fresh install, then restart"
new_volume "$run_id-fresh-torrents"
new_volume "$run_id-fresh-passwd"
start_app "$run_id-fresh" "$image_ref" login "$run_id-fresh-torrents" "$run_id-fresh-passwd"
fresh_summary=$(runtime_check "$run_id-fresh" check "$PHP_VERSION") || fail "fresh install runtime checks failed"
echo "$fresh_summary" | tail -n 1
fresh_hash=$(echo "$fresh_summary" | tail -n 1 | jq -r '.addtorrent_upload')
step "fresh install login checks failed" auth_check "$run_id-fresh" login
if docker logs "$run_id-fresh" 2>&1 | grep -q 'htpasswd is empty'; then
    fail "fresh install logged an empty password file"
fi
docker restart --time 30 "$run_id-fresh" >/dev/null
wait_healthy "$run_id-fresh"
step "login checks after restart failed" auth_check "$run_id-fresh" login
step "runtime checks after restart failed" runtime_check "$run_id-fresh" check "$PHP_VERSION" "$fresh_hash"
docker rm -fv "$run_id-fresh" >/dev/null

echo "== Empty password files: auth stays on"
new_volume "$run_id-empty-torrents"
new_volume "$run_id-empty-passwd"
# USERNAME without PASSWORD: 025-set-passwd.sh leaves /passwd alone and
# 03-config.sh creates the three files empty.
start_app "$run_id-empty" "$image_ref" user-only "$run_id-empty-torrents" "$run_id-empty-passwd"
docker exec "$run_id-empty" sh -c 'for f in rutorrent rpc webdav; do test -f /passwd/$f.htpasswd && test ! -s /passwd/$f.htpasswd || exit 1; done' \
    || fail "the negative test did not start with three empty password files"
for f in rutorrent rpc webdav; do
    docker logs "$run_id-empty" 2>&1 | grep -qF "ERROR: /passwd/$f.htpasswd is empty or missing; authentication stays on" \
        || fail "no error logged for the empty $f.htpasswd"
done
echo "error logged for each empty file"
step "an empty password file let a request through" auth_check "$run_id-empty" locked
echo "-- password files deleted while running"
docker exec "$run_id-empty" rm -f /passwd/rutorrent.htpasswd /passwd/rpc.htpasswd /passwd/webdav.htpasswd
step "a missing password file let a request through" auth_check "$run_id-empty" refused
echo "-- /moduser.sh restores access without a restart"
docker exec -e PASSWORD "$run_id-empty" sh -c 'exec /moduser.sh "$PASSWORD"' > /dev/null 2>&1 \
    || fail "/moduser.sh failed"
step "login after /moduser.sh failed" auth_check "$run_id-empty" login
echo "-- restart with the empty password files restored"
docker exec "$run_id-empty" sh -c ': > /passwd/rutorrent.htpasswd; : > /passwd/rpc.htpasswd; : > /passwd/webdav.htpasswd'
docker restart --time 30 "$run_id-empty" >/dev/null
wait_healthy "$run_id-empty"
step "an empty password file let a request through after restart" auth_check "$run_id-empty" locked
docker rm -fv "$run_id-empty" >/dev/null

echo "== Upgrade from $BASE_NAME with the same /torrents and /passwd"
new_volume "$run_id-up-torrents"
new_volume "$run_id-up-passwd"
start_app "$run_id-old" "$BASE_REF" login "$run_id-up-torrents" "$run_id-up-passwd"
seeded=$(step "could not add a torrent on $BASE_NAME" runtime_check "$run_id-old" seed | jq -r '.seeded')
seeded_two=$(step "could not add a second torrent on $BASE_NAME" runtime_check "$run_id-old" seed | jq -r '.seeded')
for seed_hash in "$seeded" "$seeded_two"; do
    case "$seed_hash" in
        [0-9A-F][0-9A-F][0-9A-F][0-9A-F]*) ;;
        *) fail "unexpected seed hash: $seed_hash" ;;
    esac
done
[ "$seeded" != "$seeded_two" ] || fail "both seeded torrents have the same hash"
docker exec "$run_id-old" sh -c 'echo appbox-gate > /torrents/completed/appbox-gate-marker.txt && chown rtorrent:rtorrent /torrents/completed/appbox-gate-marker.txt'
step "login checks on $BASE_NAME failed" auth_check "$run_id-old" login
# Let rTorrent write its session before stopping, as a running instance would have.
docker exec "$run_id-old" python3 -c 'import xmlrpc.client; xmlrpc.client.ServerProxy("http://127.0.0.1:8001/").session.save()'
volume_state "$run_id-old" > "$work_dir/state-old"
grep -q "^$seeded\.torrent\$" "$work_dir/state-old" || fail "seeded torrent missing from the $BASE_NAME session"
docker stop --time 30 "$run_id-old" >/dev/null
start_app "$run_id-new" "$image_ref" login "$run_id-up-torrents" "$run_id-up-passwd"
volume_state "$run_id-new" > "$work_dir/state-new"
diff "$work_dir/state-old" "$work_dir/state-new" || fail "upgrade changed .rtorrent.rc, the session or completed data"
upgrade_summary=$(runtime_check "$run_id-new" check "$PHP_VERSION" "$seeded") || fail "upgrade runtime checks failed"
echo "$upgrade_summary" | tail -n 1
step "second torrent missing after upgrade" runtime_check "$run_id-new" check "$PHP_VERSION" "$seeded_two" > /dev/null
step "login checks after upgrade failed" auth_check "$run_id-new" login
echo "upgrade kept .rtorrent.rc, $(grep -c '\.torrent$' "$work_dir/state-new") session torrents and completed data; the $BASE_NAME login still works"
docker rm -fv "$run_id-old" "$run_id-new" >/dev/null

check_registry

if [ "$gate_mode" = release ]; then
    echo "PASS: $image_ref"
else
    echo "TRIAL PASS: $image_ref; not a release approval"
fi
