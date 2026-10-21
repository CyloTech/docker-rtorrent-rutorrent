#!/bin/sh
# Builds Alpine's community/php85 APKBUILD and signs the packages with a new
# abuild key. Runs as root inside alpine:3.24 (pinned by digest, see
# README.md), started by node-build.sh with the build directory at /work:
#
#   /work/aports/community/php85/   the APKBUILD directory, exported from
#                                   aports at the commit in README.md
#   /work/distfiles/php-<ver>.tar.xz  the php.net tarball (signature and
#                                   checksums verified before upload)
#
# Writes /work/out/packages/community/x86_64/*.apk + APKINDEX.tar.gz,
# /work/out/keys/<key>.rsa.pub and build metadata. The private key stays in
# /work/keys and must be moved off the build host by the operator; it is
# never part of /work/out.
set -eu

work=/work
aport=$work/aports/community/php85
test -f "$aport/APKBUILD"
pkgver=$(sed -n 's/^pkgver=//p' "$aport/APKBUILD")
pkgrel=$(sed -n 's/^pkgrel=//p' "$aport/APKBUILD")
case "$pkgver-r$pkgrel" in
    [0-9]*.[0-9]*.[0-9]*-r[0-9]*) ;;
    *) echo "unexpected pkgver/pkgrel: $pkgver-r$pkgrel" >&2; exit 1 ;;
esac
test -f "$work/distfiles/php-$pkgver.tar.xz"

apk add --no-cache abuild build-base openssl
adduser -D -G abuild -h "$work/home" -s /bin/sh builder

mkdir -p "$work/keys" "$work/packages" "$work/out"
key_name="cylo-php85-$(date -u +%Y%m%d%H%M%S)"
umask 077
openssl genrsa -out "$work/keys/$key_name.rsa" 4096 2>/dev/null
umask 022
openssl rsa -in "$work/keys/$key_name.rsa" -pubout -out "$work/keys/$key_name.rsa.pub" 2>/dev/null
cp "$work/keys/$key_name.rsa.pub" /etc/apk/keys/
mkdir -p "$work/home/.abuild"
cat > "$work/home/.abuild/abuild.conf" <<EOF
PACKAGER="Cylo php-artifacts build"
PACKAGER_PRIVKEY="$work/keys/$key_name.rsa"
EOF
chown -R builder:abuild "$work/home" "$work/keys" "$work/packages" "$work/aports" "$work/distfiles"

# Install makedepends (abuild-sudo, abuild group) and record the exact
# build environment, then build. check() runs PHP's test suite; TESTS adds
# parallel workers to it.
su builder -s /bin/sh -c "cd '$aport' && abuild deps"
apk info -v | sort > "$work/out/build-environment-packages.txt"
su builder -s /bin/sh -c "cd '$aport' && SRCDEST='$work/distfiles' REPODEST='$work/packages' TESTS='-j48 --show-diff' abuild"

repo_dir=$work/packages/community/x86_64
test -f "$repo_dir/APKINDEX.tar.gz"
test -f "$repo_dir/php85-$pkgver-r$pkgrel.apk"

mkdir -p "$work/out/packages/community/x86_64" "$work/out/keys"
cp "$repo_dir"/*.apk "$repo_dir/APKINDEX.tar.gz" "$work/out/packages/community/x86_64/"
cp "$work/keys/$key_name.rsa.pub" "$work/out/keys/"
{
    echo "alpine-release: $(cat /etc/alpine-release)"
    echo "apk: $(apk --version)"
    echo "abuild: $(apk info -v abuild 2>/dev/null | head -n 1)"
    echo "pkgver: $pkgver-r$pkgrel"
    echo "key: $key_name.rsa.pub"
} > "$work/out/build-info.txt"
(cd "$work/out" && find packages keys -type f | sort | xargs sha256sum > SHA256SUMS)
echo "build-in-alpine: done $pkgver-r$pkgrel"
