# 5.3.15.1

Uses ruTorrent master at `fe468360f94b02def11bbf67b16316bbe8081380`, the latest
upstream commit when this release was prepared. It includes merged PR
[3329](https://github.com/Novik/ruTorrent/pull/3329), which fixes blank Finished
times after creating or loading torrents with complete data. The separate local
seedingtime patch has been removed. Upstream reports its version as 5.3.15;
the Appbox catalogue label is 5.3.15.1. rTorrent and libtorrent remain 0.16.23.

The image adds PHP SimpleXML, which upstream's XML-RPC proxy needs. Existing
PHP CLI and DHT compatibility patches remain in place.

- Image: `repo.cylo.net/rutorrent:5.3.15.1-0.16.23`
- Digest: `sha256:fc8a15f0b42d7368b06cf1dd7d16dcb0b1d20d5a2a096f1a3dbfb9d9573e4644`
- Platform: `linux/amd64`
- Exact build commit: `bf9677c1a1b3fa06a288a2331811849ea816db87`
- Build archive SHA-256: `4b1544ae4688a560dd44772372ddfbdd26b1d2623cf42da229e17184cd04673a`
- Upstream revision is also recorded in the image label `io.appbox.rutorrent.revision`.

Validation:

- Upstream [tests](https://github.com/Novik/ruTorrent/actions/runs/36082247322)
  and [lint](https://github.com/Novik/ruTorrent/actions/runs/36082247351) passed
  for the exact source commit. The PHP CI matrix uses 7.4 and 8.1 on Ubuntu.
- Local JavaScript suite: 45 suites, 511 tests passed.
- The actual release image passed upstream's 11 XML-RPC proxy test files: 1,992 assertions.
- The image release gate passed fresh install, restart, upgrade from the current catalogue image, Finished-time preservation, PHP CLI and DHT checks, callbacks, periodic saves (299.3 seconds), forced-stop recovery, and graceful stop/restart (17.6 seconds).
- Registry digest, Linux/amd64 platform, build and upstream revision labels,
  and the seedingtime source hash were checked after publication.

The complete upstream PHP suite was also run on PHP 8.5. It is not fully green:
`DeprecatedFunctionReplacementTest.php` has five failed assertions involving
malformed date parsing, platform-specific `strftime` flags, an existing XMPP
`(boolean)` cast, and the test harness's `ReflectionMethod::setAccessible()`
calls. The latter two emit PHP 8.5 deprecations. These are separate from the
Finished-time regression and XML-RPC proxy checks. The Linux test container
received PCNTL and Tokenizer solely for upstream's test harness; those packages
were not added to the release image. The Linux run executed 112 test files. A process-cleanup test initially failed with a non-reaping test-container PID 1; it passed when rerun with `--init`.

Catalogue:

- App 66, version 1335, enabled and the sole default.
- All 51 previous versions retained, including their enabled states.
- One app slot and downgrade support retained; resource limits unchanged.
- Mounts, environment variables, custom fields, ulimits and other catalogue
  definitions were compared before and after the import.
- Import used the deployed AppsTask through a release-specific transaction
  guard committed in this repository. Dry run and rollback rehearsal passed.

Existing customer installations were not updated or restarted.
