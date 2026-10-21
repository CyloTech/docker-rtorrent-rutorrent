#!/bin/sh
# Starts the php85 package build on a build host, as root, in a fresh
# directory made with `mktemp -d /root/php-builds/php85-<ver>.XXXXXX` that
# already holds:
#
#   recipe/                         this directory (git archive of the pushed commit)
#   work/aports/community/php85/    aports community/php85 at the pinned commit
#   work/distfiles/php-<ver>.tar.xz verified php.net tarball
#
# Usage: node-build.sh <build-dir> <php-version>
#
# The container joins the daemon's default bridge network (the bridge
# network with com.docker.network.bridge.default_bridge=true, bridge_1 on
# Cylo nodes, whose dockerd runs with --bridge=none) for apk downloads.
#
# The build runs detached in a throwaway alpine:3.24 container on the host
# docker with --cpu-shares 256, so it only uses idle CPU. Progress is in
# work/build.log; work/exit-code appears when it finishes. The operator
# copies work/out off the host, then removes the container (label
# cylo.php-build=<suffix>), the image if this run pulled it, and the
# directory.
set -eu

ALPINE_REF="alpine@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6"  # alpine:3.24, 2026-09-17

[ "$#" -eq 2 ] || { echo "usage: $0 <build-dir> <php-version>" >&2; exit 1; }
build_dir=$1
php_version=$2
case "$php_version" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "bad php version: $php_version" >&2; exit 1 ;;
esac
case "$php_version" in *[!0-9.]*) echo "bad php version: $php_version" >&2; exit 1 ;; esac
case "$build_dir" in
    /root/php-builds/php85-"$php_version".[A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9][A-Za-z0-9]) ;;
    *) echo "bad build dir: $build_dir" >&2; exit 1 ;;
esac
test -f "$build_dir/recipe/build-in-alpine.sh"
test -f "$build_dir/work/aports/community/php85/APKBUILD"
test -f "$build_dir/work/distfiles/php-$php_version.tar.xz"

suffix=$(basename "$build_dir" | sed "s/^php85-$php_version\.//" | tr 'A-Z' 'a-z')
container="php85-build-$suffix"

# With userns-remap, container root is the remapped uid/gid shown in the
# daemon's root directory name (e.g. /var/lib/docker/100000.100000).
docker_root=$(docker info --format '{{.DockerRootDir}}')
remap=${docker_root##*/}
case "$remap" in
    [0-9]*.[0-9]*) chown -R "${remap%.*}:${remap#*.}" "$build_dir/work" ;;
    *) ;;
esac

build_network=""
for network in $(docker network ls --filter driver=bridge --format '{{.Name}}'); do
    if [ "$(docker network inspect --format '{{index .Options "com.docker.network.bridge.default_bridge"}}' "$network")" = true ]; then
        build_network=$network
    fi
done
[ -n "$build_network" ] || { echo "no default bridge network found" >&2; exit 1; }

if docker image inspect "$ALPINE_REF" >/dev/null 2>&1; then
    echo "image already present: $ALPINE_REF" > "$build_dir/image-was-present"
else
    docker pull -q "$ALPINE_REF" >/dev/null
fi

docker run -d --name "$container" --label "cylo.php-build=$suffix" \
    --cpu-shares 256 --network "$build_network" \
    -v "$build_dir/work:/work" -v "$build_dir/recipe:/recipe:ro" \
    "$ALPINE_REF" \
    sh -c 'sh /recipe/build-in-alpine.sh > /work/build.log 2>&1; echo $? > /work/exit-code'
echo "started $container"
