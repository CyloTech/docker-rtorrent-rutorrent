# 5.3.15.4

Stops the Appbox installed callback from blocking startup. `05-appbox.sh` used
to retry `POST /v1/apps/installed/<id>` forever inside cont-init, so when the
API rejected it (a 401 after a migration had cleared the instance's token)
nginx, PHP-FPM and rTorrent never started and the app returned 502. The callback
now runs from the `appbox-callback` s6 service after the other services start.
It retries network errors, 408, 429 and 5xx with backoff capped at 60s, logs
any other status once, and sends `CALLBACK_TOKEN` as `X-Cylo-Callback-Token`.
rTorrent, libtorrent, ruTorrent and plugins are unchanged from 5.3.15.3.

- Image: `repo.cylo.net/rutorrent:5.3.15.4-0.16.24`
- Digest: `sha256:d0d5e6f7577aef143f171f4d05995c045122380311396694b430ec758947d5ee`
- Platform: `linux/amd64`
- Exact image build commit: `f06eb117225f40e69c4d8f23c08cf9a3df22494f`
- Build archive SHA-256: `c55776182959c6750b03e9df2d4ecd3e87753cb35bc5560d9a056434b203880b`

`scripts/session-release-gate.py` passed against the new image (28 checks), with
the 5.3.15.3 image as the upgrade baseline: upstream XML-RPC proxy tests (11
files, 1,992 assertions), a new phase where the callback API returns 401 (the
app became healthy, sent one callback, did not retry and sent none after a
restart), fresh install, upgrade with retained data and settings, Finished
times, PHP CLI, DHT and peer ports, ratiocolor, the five-minute session save,
forced-stop recovery, graceful stop/restart, and exactly one callback each for
the fresh install and the upgrade.

Catalogue: `scripts/catalogue-5.3.15.4-admin-test.sql` added this version as
app_versions 1425 (admin-only, non-default). Its `changes` text and every
resource field were read back and match 1412. It was installed on the grant
Cylo through Appbox (instance 264430): installation completed through the
normal callback (installing=0, token cleared), the UI and XML-RPC answered with
the test credentials (rTorrent 0.16.24), and an Appbox restart did not send a
second callback. `scripts/catalogue-5.3.15.4-promote.sql` makes 1425 the
public default; it has not been applied.
