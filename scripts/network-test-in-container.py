#!/usr/bin/env python3
"""Network regressions for disposable ruTorrent test containers only."""
import base64
import hashlib
import json
import os
from pathlib import Path
import socket
import sys
import time
import urllib.request
import xmlrpc.client


def rpc(method, *params):
    body = xmlrpc.client.dumps(params, methodname=method).encode()
    headers = b"CONTENT_LENGTH\0" + str(len(body)).encode() + b"\0SCGI\x001\0"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(10)
        connection.connect("/var/run/rtorrent/scgi.socket")
        connection.sendall(str(len(headers)).encode() + b":" + headers + b"," + body)
        response = b""
        while b"</methodResponse>" not in response:
            part = connection.recv(65536)
            if not part:
                break
            response += part
    return xmlrpc.client.loads(response[response.index(b"<?xml"):])[0][0]


def settings(port):
    login = ("releasegate:" + os.environ["PASSWORD"]).encode()
    request = urllib.request.Request(
        "http://127.0.0.1/plugins/httprpc/action.php",
        data=("mode=setsettings&s=ndht_port&v=" + str(port)).encode(),
        headers={"Authorization": "Basic " + base64.b64encode(login).decode()},
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        assert response.status == 200
        value = json.load(response)
        assert value is not None and value is not False, value


def port_in_use(port):
    # Read the kernel listener table, not just the configured override.
    for name in ("udp", "udp6"):
        for line in Path("/proc/net/" + name).read_text().splitlines()[1:]:
            if int(line.split()[1].split(":")[-1], 16) == port:
                return True
    return False


mode = sys.argv[1]
rc = Path("/torrents/config/rtorrent/.rtorrent.rc")
if mode in ("baseline", "current"):
    assert rpc("network.listen.port") == 51000
    assert rpc("dht.override_port") == 51001
    rpc("dht.mode.set", "", "on")
    deadline = time.monotonic() + 10
    while not port_in_use(51001):
        assert time.monotonic() < deadline, "Initial DHT listener did not open"
        time.sleep(0.2)
    settings(51002)
    if mode == "baseline":
        assert rpc("dht.override_port") == 51001
        assert port_in_use(51001) and not port_in_use(51002)
        print(json.dumps({"old_settings_bug_reproduced": True}))
    else:
        deadline = time.monotonic() + 10
        while not port_in_use(51002):
            assert time.monotonic() < deadline, "Settings write did not change UDP listener"
            time.sleep(0.2)
        assert rpc("dht.override_port") == 51002 and rpc("dht.port") == 51002
        assert not port_in_use(51001), "Old DHT port is still bound"
        settings(51001)
        deadline = time.monotonic() + 10
        while not port_in_use(51001):
            assert time.monotonic() < deadline
            time.sleep(0.2)
        assert rpc("dht.port") == 51001 and not port_in_use(51002)
        assert rpc("network.send_buffer.size") == 0
        assert rpc("network.receive_buffer.size") == 0
        assert "~_save_full" in rpc("method.list_keys", "", "event.download.inserted_new")
        print(json.dumps({"settings_change_moves_udp_listener": True, "assigned_port_restored": True,
                          "tcp_autotuning_defaults": True, "upstream_insert_save_handler": True}))
elif mode == "preserve":
    rc.write_bytes(rc.read_bytes() + b"\n# Custom setting retained through upgrade\nthrottle.max_uploads.set = 27\n")
    marker = Path("/torrents/network-test-preserved.txt")
    marker.write_text("Synthetic network regression data\n")
    expected = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in (rc, marker)}
    Path("/torrents/network-test-fingerprints.json").write_text(json.dumps(expected))
    print(json.dumps({"synthetic_config_and_data_saved": True}))
elif mode == "retained":
    expected = json.loads(Path("/torrents/network-test-fingerprints.json").read_text())
    assert all(hashlib.sha256(Path(p).read_bytes()).hexdigest() == digest for p, digest in expected.items())
    assert rpc("throttle.max_uploads") == 27
    print(json.dumps({"persistent_config_and_data_retained": True}))
else:
    raise SystemExit("Unknown test mode")
