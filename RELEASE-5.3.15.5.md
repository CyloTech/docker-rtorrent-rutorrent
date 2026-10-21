# 5.3.15.5

PHP security release for the PHP vulnerabilities in multipart/form-data
(uploaded form data) parsing announced on 21 October 2026. ruTorrent's nginx
passes `/no-auth/*.php` to php-fpm without a login (`/no-auth/share.php`), so
the parser is reachable before authentication.

The image is the published 5.3.15.4 image
(`repo.cylo.net/rutorrent@sha256:d0d5e6f7577aef143f171f4d05995c045122380311396694b430ec758947d5ee`,
built from `f06eb117225f40e69c4d8f23c08cf9a3df22494f`) with only its php85
packages upgraded from Alpine 3.24 (`Dockerfile.php-security`). rTorrent,
libtorrent, ruTorrent, the plugins, rootfs, configuration and all other Alpine
packages are unchanged from 5.3.15.4.

- Image: `repo.cylo.net/rutorrent:5.3.15.5-0.16.24`
- Build: `docker build --pull --no-cache --platform linux/amd64 -f Dockerfile.php-security -t repo.cylo.net/rutorrent:5.3.15.5-0.16.24 .`
- Gate: `release/verify-image.sh repo.cylo.net/rutorrent:5.3.15.5-0.16.24`
- Minimum php85: `8.5.12` (`PHP85_MIN_VERSION`; the build fails below it)

Recorded after the push (commit "Pin 5.3.15.5 digest"):

- Digest: pending
- Exact image build commit: pending
- Build archive SHA-256: pending
- php85 packages (`apk info -v | grep '^php85'`): pending
- Gate output: pending
