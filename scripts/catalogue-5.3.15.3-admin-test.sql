-- Add ruTorrent 5.3.15.3 to app 66 as an admin-only, non-default version for
-- testing on the grant Cylo. Resources and install text are copied from the
-- current default (5.3.15.2, id 1339). The app row and other versions are not
-- touched. Apply as one statement through the Postgres MCP; expect one row.
INSERT INTO app_versions (
    app_id, version, tag, image, installed_image_digest, enabled, is_default,
    admin_only, deprecated, changes, min_memory, min_cpus, memory, memory_swap,
    memory_reservation, cpus, init, privileged, cap_add, cap_drop,
    tcp_port_range, udp_port_range, tcp_dynamic_ports, udp_dynamic_ports,
    pids_limit, combined_port_range, combined_dynamic_ports, app_slots,
    custom_field_preinstall_description, custom_field_postinstall_description,
    user_id, created_at, updated_at)
SELECT
    b.app_id, '5.3.15.3', '5.3.15.3-0.16.24', 'rutorrent', 'repo.cylo.net/rutorrent@sha256:f36435f80dd8b415a03133bcecdefae8104ff2f8e02c6d53301533409bc8472b', 1, 0,
    1, 0, 'Brings back ratio colours in ruTorrent. The Ratio column text changes colour with each torrent''s ratio: red at 0, orange at 1, green at 3 and blue at 30 or above, blending in between. No action is needed after updating.', b.min_memory, b.min_cpus, b.memory, b.memory_swap,
    b.memory_reservation, b.cpus, b.init, b.privileged, b.cap_add, b.cap_drop,
    b.tcp_port_range, b.udp_port_range, b.tcp_dynamic_ports, b.udp_dynamic_ports,
    b.pids_limit, b.combined_port_range, b.combined_dynamic_ports, b.app_slots,
    b.custom_field_preinstall_description, b.custom_field_postinstall_description,
    b.user_id, now(), now()
FROM app_versions b
WHERE b.id = 1339 AND b.app_id = 66 AND b.is_default = 1 AND b.version = '5.3.15.2'
  AND b.installed_image_digest = 'repo.cylo.net/rutorrent@sha256:417626fc0136226ff6f120edfc54ea02e88acd6d8fc41b56fc60400425a73be5'
  AND (SELECT count(*) FROM app_versions WHERE app_id = 66 AND is_default = 1) = 1
  AND NOT EXISTS (SELECT 1 FROM app_versions WHERE app_id = 66
                  AND (version = '5.3.15.3' OR tag = '5.3.15.3-0.16.24'))
RETURNING id, app_id, version, tag, installed_image_digest, enabled, is_default, admin_only;
