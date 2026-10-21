# 5.3.15.5

PHP security release for the PHP 8.5.12 fixes of 21 October 2026
(CVE-2026-109618 / GHSA-w8hw-w9fx-j79w and CVE-2026-109619 /
GHSA-6wmf-4rv5-p3rp, multipart/form-data parsing). ruTorrent's nginx passes
`/no-auth/*.php` to php-fpm without a login (`/no-auth/share.php`), so the
parser is reachable before authentication.

The image is the published 5.3.15.4 image
(`repo.cylo.net/rutorrent@sha256:d0d5e6f7577aef143f171f4d05995c045122380311396694b430ec758947d5ee`,
built from `f06eb117225f40e69c4d8f23c08cf9a3df22494f`) with only its 16 php85
packages upgraded from 8.5.11-r0 to 8.5.12-r0 (`Dockerfile.php-security`).
rTorrent, libtorrent, ruTorrent, the plugins, rootfs, configuration and all
other Alpine packages are unchanged from 5.3.15.4.

Alpine's v3.24 index still had php85 8.5.11-r0, so the 8.5.12-r0 packages are
our own build of Alpine's community/php85 APKBUILD (aports `0161a10b0614`,
3.24-stable `f169399075e2` plus Alpine MR !110201's test exclusion), signed
with our key `cylo-php85-20261021161817` and published as
`repo.cylo.net/php-artifacts:php85-8.5.12-r0-alpine3.24` =
`sha256:c810e2dbf5e5ff8225acc76d816fc76a00495430e9344ccf14acc632d2ad371d`
(provenance, test results and per-package SHA-256 in
`release/php85-artifact/README.php85-8.5.12-r0-alpine3.24.md`). The build
installs from that repository only, with no network and its own key
directory, so nothing else can change and the key is not added to
`/etc/apk/keys`.

- Image: `repo.cylo.net/rutorrent:5.3.15.5-0.16.24`
- Build: `docker build --pull --no-cache --platform linux/amd64 -f Dockerfile.php-security -t repo.cylo.net/rutorrent:5.3.15.5-0.16.24 .`
- Gate: `release/verify-image.sh repo.cylo.net/rutorrent:5.3.15.5-0.16.24`
- Bases (pinned by digest): `repo.cylo.net/rutorrent@sha256:d0d5e6f7577aef143f171f4d05995c045122380311396694b430ec758947d5ee`,
  `repo.cylo.net/php-artifacts@sha256:c810e2dbf5e5ff8225acc76d816fc76a00495430e9344ccf14acc632d2ad371d`

Recorded after the push (commit "Pin 5.3.15.5 digest"):

- Digest: pending
- Exact image build commit: pending
- Build archive SHA-256: pending
- php85 packages (`apk info -v | grep '^php85'`): pending
- Gate output: pending
