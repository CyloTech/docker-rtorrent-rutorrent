-- Add ruTorrent 5.3.15.4 to app 66 as an admin-only, non-default version for
-- testing on the grant Cylo. Resources and install text are copied from the
-- current default (5.3.15.3, id 1412). The app row and other versions are not
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
    b.app_id, '5.3.15.4', '5.3.15.4-0.16.24', 'rutorrent', 'repo.cylo.net/rutorrent@sha256:d0d5e6f7577aef143f171f4d05995c045122380311396694b430ec758947d5ee', 1, 0,
    1, 0, 'Fixes ruTorrent sometimes not starting after your Appbox moved to a new server or changed plan, which showed "The webserver received an invalid response from the upstream application". ruTorrent now finishes starting even if its install check-in with Appbox is delayed or refused. No action is needed after updating.', b.min_memory, b.min_cpus, b.memory, b.memory_swap,
    b.memory_reservation, b.cpus, b.init, b.privileged, b.cap_add, b.cap_drop,
    b.tcp_port_range, b.udp_port_range, b.tcp_dynamic_ports, b.udp_dynamic_ports,
    b.pids_limit, b.combined_port_range, b.combined_dynamic_ports, b.app_slots,
    b.custom_field_preinstall_description, b.custom_field_postinstall_description,
    b.user_id, now(), now()
FROM app_versions b
WHERE b.id = 1412 AND b.app_id = 66 AND b.is_default = 1 AND b.version = '5.3.15.3'
  AND b.installed_image_digest = 'repo.cylo.net/rutorrent@sha256:f36435f80dd8b415a03133bcecdefae8104ff2f8e02c6d53301533409bc8472b'
  AND (SELECT count(*) FROM app_versions WHERE app_id = 66 AND is_default = 1) = 1
  AND NOT EXISTS (SELECT 1 FROM app_versions WHERE app_id = 66
                  AND (version = '5.3.15.4' OR tag = '5.3.15.4-0.16.24'))
RETURNING id, app_id, version, tag, installed_image_digest, enabled, is_default, admin_only;
