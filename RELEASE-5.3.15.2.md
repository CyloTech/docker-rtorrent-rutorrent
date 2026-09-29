# 5.3.15.2

This Appbox packaging release updates rTorrent and libtorrent to upstream
0.16.24. ruTorrent remains at upstream 5.3.15, using pinned source commit
`fe468360f94b02def11bbf67b16316bbe8081380` with the merged Finished-time
fix. The Appbox catalogue version advances to 5.3.15.2 to identify the new
image. rTorrent 0.16.24 removes the custom `ip%device` bind-address syntax;
custom configurations using it must switch to `network.bind_device.*`.

- Image: `repo.cylo.net/rutorrent:5.3.15.2-0.16.24`
- Digest: `sha256:417626fc0136226ff6f120edfc54ea02e88acd6d8fc41b56fc60400425a73be5`
- Platform: `linux/amd64`
- Exact image build commit: `27bc9e1145be33016c764108021b6645c7ae8aec`
- Build archive SHA-256: `e219b80b57a491200e6b73b5501be07078189d4cf0e27006685ee1f7fb05170e`
- rTorrent source: `v0.16.24` (`05cdd03cd20335725735aa65a431464a5810307a`)
- libtorrent source: `v0.16.24` (`90248b01da400b2d89b5caa625e9bdc143fe7e86`)

The checked-in release gate passed against the new image and the previous
catalogue image. It ran the upstream XML-RPC proxy tests (11 files, 1,992
assertions) and checked fresh install, upgrade with retained data and settings,
Finished times, PHP CLI, DHT and peer ports, callbacks, a 300.5-second session
save, forced-stop recovery, and graceful stop/restart. Static rTorrent and
autowatch configuration tests also passed.

Catalogue app 66 version 1339 is enabled and the sole default. Its `changes`
field was saved and read back. The guarded import preserved all 52 older
versions, their enabled states, the prior version's resources, one app slot,
downgrade support, and the existing catalogue definitions. The import preview,
rollback rehearsal, and independent database readback passed.

Existing customer installations were not updated or restarted.
