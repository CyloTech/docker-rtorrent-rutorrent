# September ruTorrent catalogue notes

Backfills the six empty `app_versions.changes` fields among the nine September
releases for app 66. The app store displays these notes directly. The three
existing notes are preserved.

The text is in `scripts/catalogue-notes-20260925.json`. The version numbers come
from the catalogue and release manifests. The watch-folder, DHT/TCP buffer,
PHP CLI warning and Finished-time changes are documented in `README.md`;
`RELEASE-5.3.15.1.md` also records the upstream fix and SimpleXML dependency.

Deliver this commit through Git to a temporary checkout on farm, then run from
`/usr/local/cylo-api` with the host PHP runtime:

```sh
php /path/to/checkout/scripts/backfill-catalogue-notes-20260925.php --preview
php /path/to/checkout/scripts/backfill-catalogue-notes-20260925.php --rehearse=PLAN_SHA256
php /path/to/checkout/scripts/backfill-catalogue-notes-20260925.php --apply=PLAN_SHA256
```

Use the plan hash returned by the preview. The transaction checks the six exact
IDs, version labels, tags, empty notes and hashes of every other version field.
It requires the reviewed app settings and 52 existing versions, then verifies
that only those six notes changed. Rehearsal rolls back; apply commits. A repeat
apply fails because the notes are no longer empty.

This migration does not rebuild an image or update running instances. Verify
the saved notes and metadata independently through read-only PostgreSQL MCP.
