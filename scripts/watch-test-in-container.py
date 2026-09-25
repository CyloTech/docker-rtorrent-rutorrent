"""Synthetic private torrents, for disposable release-gate containers only."""
import hashlib
import json
import os
from pathlib import Path
import re
import socket
import subprocess
import sys
import xmlrpc.client
import base64
import urllib.request
import urllib.error
import time


def rpc(method, *params):
    body = xmlrpc.client.dumps(params, methodname=method, allow_none=True).encode()
    headers = b"CONTENT_LENGTH\0" + str(len(body)).encode() + b"\0SCGI\x001\0"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(20)
        connection.connect("/var/run/rtorrent/scgi.socket")
        connection.sendall(str(len(headers)).encode() + b":" + headers + b"," + body)
        response = b""
        while b"</methodResponse>" not in response:
            part = connection.recv(65536)
            if not part:
                break
            response += part
    return xmlrpc.client.loads(response[response.index(b"<?xml"):])[0][0]


def encode(value):
    if isinstance(value, int):
        return b"i" + str(value).encode() + b"e"
    if isinstance(value, bytes):
        return str(len(value)).encode() + b":" + value
    if isinstance(value, dict):
        return b"d" + b"".join(encode(k) + encode(value[k]) for k in sorted(value)) + b"e"
    raise TypeError(type(value))


def check_authentication():
    url = "http://127.0.0.1:80/"
    try:
        urllib.request.urlopen(url, timeout=15)
        raise AssertionError("Unauthenticated request unexpectedly accepted")
    except urllib.error.HTTPError as error:
        assert error.code == 401
    login = ("releasegate:" + os.environ["PASSWORD"]).encode()
    request = urllib.request.Request(url, headers={"Authorization": "Basic " + base64.b64encode(login).decode()})
    with urllib.request.urlopen(request, timeout=15) as response:
        assert response.status == 200


RULES = [
    b'directory.watch.added = (cat,(cfg.watch)), load.start',
    b'schedule2 = untied_directory, 5, 5, (cat,"stop_untied=",(cfg.watch),"*.torrent")',
]
rc = Path("/torrents/config/rtorrent/.rtorrent.rc")
mode, name = sys.argv[1:3]
assert re.fullmatch(r"appbox-watch-gate-[a-z0-9-]+", name)
info = {b"name": name.encode(), b"length": 65536, b"piece length": 16384,
        b"pieces": hashlib.sha1(b"\0" * 16384).digest() * 4, b"private": 1}
hash_value = hashlib.sha1(encode(info)).hexdigest().upper()
torrent = encode({b"announce": b"http://127.0.0.1:9/announce", b"info": info})
watch_file = Path("/torrents/watch") / (name + ".torrent")

if mode in ("watch", "web"):
    path = watch_file if mode == "watch" else Path("/tmp") / (name + ".torrent")
    assert not path.exists()
    temporary = path.with_suffix(".incoming")
    temporary.write_bytes(torrent)
    os.chown(temporary, 1000, 1000)
    temporary.rename(path)
    if mode == "web":
        # The importer called by the actual web upload handler.
        php = r'''
        $_SERVER['REMOTE_USER'] = 'releasegate';
        chdir('/var/www/rutorrent/php');
        require './rtorrent.php';
        $hash = rTorrent::sendTorrent($argv[1], true, true, '/torrents/downloading/', null, false, false);
        if ($hash === false) { exit(1); }
        '''
        result = subprocess.run(["php", "-r", php, str(path)], capture_output=True, text=True)
        assert result.returncode == 0, "Web import failed: " + (result.stdout + result.stderr).replace(os.environ["PASSWORD"], "[REDACTED]")[-3000:]
    print(json.dumps({"hash": hash_value, "mode": mode}))
elif mode == "status":
    rows = rpc("d.multicall2", "", "main", "d.hash=", "d.state=", "d.is_active=", "d.complete=", "d.tied_to_file=")
    match = [r for r in rows if r[0] == hash_value]
    print(json.dumps({"present": bool(match), "state": match[0][1] if match else None,
                      "active": match[0][2] if match else None, "tied": bool(match[0][4]) if match else None,
                      "tied_exists": os.path.exists(match[0][4]) if match and match[0][4] else False,
                      "source_exists": watch_file.exists(), "total": len(rows)}))
elif mode == "start":
    assert rpc("d.hash", hash_value) == hash_value
    rpc("d.tied_to_file.set", hash_value, "")
    rpc("d.start", hash_value)
    rpc("d.save_full_session", hash_value)
    print(json.dumps({"started": True}))
elif mode == "save":
    rpc("session.save", "")
    sentinel = Path("/torrents/downloading/appbox-watch-gate-retained-data.txt")
    sentinel.write_bytes(b"Appbox release gate: preserve this data.\n")
    profile = Path("/torrents/config/rutorrent/share/users/releasegate/settings/autotools.dat")
    theme = profile.with_name("theme.dat")
    theme.write_text('O:6:"rTheme":3:{s:4:"hash";s:9:"theme.dat";s:8:"modified";b:0;s:7:"current";s:13:"club-QuickBox";}')
    os.chown(theme, 1000, 1000)
    fingerprints = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in (sentinel, profile, theme)}
    Path("/torrents/config/rtorrent/release-gate-fingerprints.json").write_text(json.dumps(fingerprints))
    print(json.dumps({"saved": True}))
elif mode == "retained":
    expected = json.loads(Path("/torrents/config/rtorrent/release-gate-fingerprints.json").read_text())
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest() == digest for p, digest in expected.items())
    check_authentication()
    print(json.dumps({"data_settings_auth_retained": True}))
elif mode == "save-compat":
    assert b"encoding.add = UTF-8" in rc.read_bytes()
    original = rc.read_bytes() + b"\n# Release upgrade custom setting\nthrottle.max_uploads.set = 27\n"
    rc.write_bytes(original)
    Path("/torrents/config/rtorrent/release-gate-compat-before.rc").write_bytes(original)
    print(json.dumps({"old_configuration_saved": True}))
elif mode == "verify-compat":
    original = Path("/torrents/config/rtorrent/release-gate-compat-before.rc").read_bytes()
    expected = b"".join(line for line in original.splitlines(keepends=True)
                        if b"".join(line.split()) != b"encoding.add=UTF-8")
    assert rc.read_bytes() == expected, "Retained rTorrent configuration differs from the expected migration"
    backup = rc.with_name(rc.name + ".pre-01622-" + hashlib.sha256(original).hexdigest()[:12])
    assert backup.read_bytes() == original
    assert rpc("throttle.max_uploads", "") == 27
    print(json.dumps({"compatibility_backup_and_custom_setting_verified": True}))
elif mode == "plugins":
    # Read the cache written at the end of initplugins.php; do not initialize it here.
    php = r'''$_SERVER['REMOTE_USER'] = 'releasegate';
chdir('/var/www/rutorrent/php'); require './rtorrent.php';
$settings = rTorrentSettings::get();
echo json_encode(array('linked' => (bool)$settings->linkExist, 'version' => $settings->version,
    'dht_command' => $settings->getCommand('set_dht_port')));'''
    value = json.loads(subprocess.check_output(["gosu", "1000", "php", "-r", php], text=True).splitlines()[-1])
    value["ready"] = value["linked"] and value["version"] == rpc("system.client_version")
    print(json.dumps(value))
elif mode == "versions":
    assert rpc("system.client_version") == "0.16.23"
    assert rpc("system.library_version") == "0.16.23"
    assert rpc("network.listen.port") == 51000
    assert rpc("dht.override_port") == 51001
    assert 'version: "5.3.15"' in Path("/var/www/rutorrent/js/webui.js").read_text()
    assert subprocess.check_output(["php", "-r", "echo PHP_MAJOR_VERSION.'.'.PHP_MINOR_VERSION;"], text=True) == "8.5"
    pid = int(rpc("system.pid"))
    rtorrent_status = dict(line.split(":", 1) for line in Path(f"/proc/{pid}/status").read_text().splitlines() if ":" in line)
    assert rtorrent_status["Uid"].split()[1] == "1000", "rTorrent effective UID"
    assert subprocess.check_output(["gosu", "1000", "readlink", f"/proc/{pid}/exe"], text=True).strip().endswith("/rtorrent")
    found = {"rtorrent"}
    for status in Path('/proc').glob('[0-9]*/status'):
        try:
            fields = dict(line.split(':', 1) for line in status.read_text().splitlines() if ':' in line)
        except (FileNotFoundError, ProcessLookupError):
            continue
        name = fields.get('Name', '').strip()
        if name in ('rtorrent', 'nginx', 'php-fpm85'):
            assert fields['Uid'].split()[1] == '1000', name
            found.add(name)
    assert {'rtorrent', 'nginx', 'php-fpm85'} <= found, found
    for route in ('/RPC2', '/php/rpc2.php', '/plugins/httprpc/action.php'):
        try:
            urllib.request.urlopen(urllib.request.Request('http://127.0.0.1' + route, data=b''), timeout=15)
            raise AssertionError('Unauthenticated POST accepted: ' + route)
        except urllib.error.HTTPError as error:
            assert error.code == 401, (route, error.code)
    print(json.dumps({"versions_and_ports_verified": True, "service_uid": 1000, "unauthenticated_rpc_denied": True}))
elif mode == "config":
    active = [b"".join(line.split()) for line in rc.read_bytes().splitlines() if not line.lstrip().startswith(b"#")]
    assert not any(b"".join(rule.split()) in active for rule in RULES)
    # Preserve the existing image behavior: rTorrent starts unlimited, then
    # ruTorrent applies its configured 20 Gbps ceiling in whole KiB/s units.
    php_config = Path("/var/www/rutorrent/conf/config.php").read_text()
    ceiling = int(re.search(r"\$throttleMaxSpeed\s*=\s*(\d+);", php_config).group(1))
    assert ceiling == 2500000000
    allowed_rates = {0, (ceiling // 1024) * 1024}
    deadline = time.monotonic() + 30
    while True:
        rates = [rpc("throttle.global_down.max_rate", ""), rpc("throttle.global_up.max_rate", "")]
        if all(rate in allowed_rates for rate in rates):
            break
        assert time.monotonic() < deadline, {"unexpected_global_limits": rates}
        time.sleep(2)
    check_authentication()
    print(json.dumps({"config_correct": True}))
elif mode == "inject-stock":
    before = rc.read_bytes() + b"\n# Preserve custom configuration\nthrottle.max_uploads.set = 27\n" + b"\n".join(RULES) + b"\n"
    rc.write_bytes(before)
    Path("/torrents/config/rtorrent/release-gate-before.rc").write_bytes(before)
    print(json.dumps({"stock_rules_injected": True}))
elif mode == "migration":
    before = Path("/torrents/config/rtorrent/release-gate-before.rc").read_bytes()
    expected = b"".join(line for line in before.splitlines(keepends=True) if line.rstrip(b"\r\n") not in RULES)
    assert rc.read_bytes() == expected, "Retained rTorrent configuration differs from the expected migration"
    backup = rc.with_name(rc.name + ".pre-autowatch-" + hashlib.sha256(before).hexdigest()[:12])
    assert backup.read_bytes() == before
    assert rpc("throttle.max_uploads", "") == 27
    print(json.dumps({"migration_exact": True, "backup_verified": True, "custom_setting_retained": True}))
else:
    raise ValueError(mode)
