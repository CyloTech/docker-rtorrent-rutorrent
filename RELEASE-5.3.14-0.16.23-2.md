# 5.3.14-0.16.23-2

Fixes blank Finished times for torrents created with complete data on rTorrent
0.16.23. The seedingtime hash-done hook now uses nested conditions. It preserves
existing timestamps and leaves incomplete torrents unset.

- Upstream PR: https://github.com/Novik/ruTorrent/pull/3329
- Image: `repo.cylo.net/rutorrent:5.3.14-0.16.23-2`
- Digest: `sha256:1c1b22481e08d1f34796186e74e93b3159a34165c6f5936c26533169975fe8d7`
- Platform: `linux/amd64`
- Exact build commit: `35445ef46f9aad9ac9795275a8a6e4a14e9dc481`
- Release archive SHA-256: `e7d2e0d7f0c8a4f23f095f9fd58d701b44e92dff7bcaa927bfc49c8c17b553c0`

The image was built on the dedicated builder from the pushed commit, passed
`scripts/session-release-gate.py`, and was then pushed. This follow-up records
the resulting digest; it changes no image build inputs.

Validation passed:

- Full upstream PHP suite, including the added regression test. The regression
  fails with the original hook and passes with the fix for both alias sets.
- Actual Create Torrent, ordinary complete-data imports, and fast-resume imports.
- Existing timestamps preserved; incomplete torrents left unset.
- Fresh installation, restart, and upgrade from immutable 5.3.14-0.16.23-1.
- Custom configuration, authentication, and torrent data retained.
- Automatic session saves during a partial transfer; measured interval 305.6 s.
- Forced-stop recovery and graceful shutdown/restart; saved timestamps retained.
- PHP CLI diagnostics, network settings, and installation callback behavior.

The manifest retains one app slot and allows downgrades. Registry publication
does not update the central catalogue or existing installations.

The preceding baseline commit records the already-published Appbox build inputs:
468 runtime source files were compared byte-for-byte with the previous image.
The original development checkout was preserved.
