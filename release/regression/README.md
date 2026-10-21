# Regression checks

Each `*.sh` file here is mounted read-only into the image at
`/release/regression/` and run with `sh` and no network by
`release/verify-image.sh`. It must exit 0 only when the behaviour it covers
works. Add one for any PHP issue found in testing a release.
