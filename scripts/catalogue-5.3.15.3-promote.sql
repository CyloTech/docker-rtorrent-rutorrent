-- Promote ruTorrent 5.3.15.3 (app_versions 1412) to the public default for
-- app 66, replacing 5.3.15.2 (1339). Mirrors the importer's --set-default
-- result: resources already match 1339, so the app row changes only version,
-- tag and updated_at. 1339 stays enabled for downgrades.
--
-- One statement; every update depends on the same guard, so either all three
-- apply or none do. Expect: guard_ok = true, old_default = 1, new_default = 1,
-- app_row = 1. Run inside a transaction and commit only on that result.
WITH guard AS (
    SELECT 1 AS ok
    WHERE EXISTS (SELECT 1 FROM app_versions WHERE id = 1339 AND app_id = 66
                  AND version = '5.3.15.2' AND is_default = 1 AND admin_only = 0 AND enabled = 1
                  AND installed_image_digest = 'repo.cylo.net/rutorrent@sha256:417626fc0136226ff6f120edfc54ea02e88acd6d8fc41b56fc60400425a73be5')
      AND EXISTS (SELECT 1 FROM app_versions WHERE id = 1412 AND app_id = 66
                  AND version = '5.3.15.3' AND tag = '5.3.15.3-0.16.24' AND image = 'rutorrent'
                  AND is_default = 0 AND admin_only = 1 AND enabled = 1
                  AND installed_image_digest = 'repo.cylo.net/rutorrent@sha256:f36435f80dd8b415a03133bcecdefae8104ff2f8e02c6d53301533409bc8472b'
                  AND changes IS NOT NULL)
      AND (SELECT count(*) FROM app_versions WHERE app_id = 66 AND is_default = 1) = 1
      AND EXISTS (SELECT 1 FROM apps WHERE id = 66 AND version = '5.3.15.2'
                  AND tag = '5.3.15.2-0.16.24' AND "Image" = 'rutorrent' AND admin_only = 0)
),
old_default AS (
    UPDATE app_versions SET is_default = 0, updated_at = now()
    WHERE id = 1339 AND app_id = 66 AND EXISTS (SELECT 1 FROM guard)
    RETURNING id
),
new_default AS (
    UPDATE app_versions SET is_default = 1, admin_only = 0, updated_at = now()
    WHERE id = 1412 AND app_id = 66 AND EXISTS (SELECT 1 FROM guard)
    RETURNING id
),
app_row AS (
    UPDATE apps SET version = '5.3.15.3', tag = '5.3.15.3-0.16.24', updated_at = now()
    WHERE id = 66 AND EXISTS (SELECT 1 FROM guard)
    RETURNING id
)
SELECT EXISTS (SELECT 1 FROM guard) AS guard_ok,
       (SELECT count(*) FROM old_default) AS old_default,
       (SELECT count(*) FROM new_default) AS new_default,
       (SELECT count(*) FROM app_row) AS app_row;
