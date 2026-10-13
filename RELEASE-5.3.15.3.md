# 5.3.15.3

Restores the `ratiocolor` ruTorrent plugin that earlier Appbox images shipped.
The Ratio column text is coloured red at 0, orange at 1, green at 3 and blue at
30 or above. The plugin is pinned to Gyran/rutorrent-ratiocolor
`3ab4962be86d17fb83649b6db44767796ee377de` and patched by
`scripts/patch-ratiocolor.py` to use text colouring and to recolour after
ruTorrent 5's in-place `syncDOM()` updates. rTorrent, libtorrent and ruTorrent
are unchanged from 5.3.15.2.

- Image: `repo.cylo.net/rutorrent:5.3.15.3-0.16.24`
- Digest: `sha256:f36435f80dd8b415a03133bcecdefae8104ff2f8e02c6d53301533409bc8472b`
- Platform: `linux/amd64`
- Exact image build commit: `5bff3f2a646e9a42b6f5699e954a9c5bb59e0e81`
- Build archive SHA-256: `dba863e23c7ec23ec817dd81ab2f340557960af06b234c75bca1b8aa79902cd3`

`scripts/session-release-gate.py` passed against the new image, with the
5.3.15.2 image as the upgrade baseline: upstream XML-RPC proxy tests (11 files,
1,992 assertions), fresh install, upgrade with retained data and settings,
Finished times, PHP CLI, DHT and peer ports, callbacks, the five-minute session
save, forced-stop recovery and graceful stop/restart. It also confirmed
ratiocolor is enabled and patched after both fresh install and upgrade.

Catalogue: `scripts/catalogue-5.3.15.3-admin-test.sql` adds this version as
admin-only and non-default for testing on the grant Cylo. 5.3.15.2 remains the
default. Existing customer installations were not updated.
