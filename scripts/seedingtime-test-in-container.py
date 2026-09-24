"""Finished-time regression checks for disposable release-gate containers."""
import base64
import hashlib
import json
import os
from pathlib import Path
import socket
import sys
import time
import urllib.parse
import urllib.request
import xmlrpc.client


def rpc(method, *params):
    body = xmlrpc.client.dumps(params, methodname=method).encode()
    headers = b"CONTENT_LENGTH\0" + str(len(body)).encode() + b"\0SCGI\x001\0"
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(20)
        connection.connect('/var/run/rtorrent/scgi.socket')
        connection.sendall(str(len(headers)).encode() + b":" + headers + b"," + body)
        response = b""
        while b"</methodResponse>" not in response:
            part = connection.recv(65536)
            if not part:
                break
            response += part
    return xmlrpc.client.loads(response[response.index(b"<?xml"):])[0][0]


def http(path, data=None):
    login = ('releasegate:' + os.environ['PASSWORD']).encode()
    headers = {'Authorization': 'Basic ' + base64.b64encode(login).decode()}
    request = urllib.request.Request('http://127.0.0.1' + path, headers=headers,
        data=urllib.parse.urlencode(data).encode() if data else None)
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read().decode()


def encode(value):
    if isinstance(value, int):
        return b'i' + str(value).encode() + b'e'
    if isinstance(value, str):
        value = value.encode()
    if isinstance(value, bytes):
        return str(len(value)).encode() + b':' + value
    if isinstance(value, list):
        return b'l' + b''.join(encode(item) for item in value) + b'e'
    return b'd' + b''.join(encode(key) + encode(value[key]) for key in sorted(value)) + b'e'


def completed(name):
    deadline = time.monotonic() + 90
    while time.monotonic() < deadline:
        matches = [row for row in rpc('d.multicall2', '', 'main', 'd.hash=', 'd.name=', 'd.complete=')
                   if row[1] == name and row[2] == 1]
        if matches:
            return matches[0][0]
        time.sleep(.25)
    raise AssertionError('Complete-data torrent did not become complete: ' + name)


def create(name):
    path = Path('/torrents/completed') / name
    path.write_bytes((name.encode() + b' create fixture') * 50000)
    os.chown(path, 1000, 1000)
    result = json.loads(http('/plugins/create/action.php', {
        'cmd': 'create', 'path_edit': str(path), 'trackers': 'http://127.0.0.1:1/announce',
        'comment': 'release regression', 'source': '', 'start_seeding': '1',
        'piece_size': '256', 'private': '1', 'hybrid': '0'}))
    assert result.get('status') == 0, result
    return completed(name)


def timing(hash_value):
    return rpc('d.custom', hash_value, 'seedingtime')


def assert_time(hash_value):
    value = timing(hash_value)
    assert value.strip().isdigit() and int(value.strip()) > 0, 'Missing Finished time'
    assert value == rpc('d.custom', hash_value, 'addtime'), 'Expected existing plugin added-time convention'
    return value


mode = sys.argv[1]
http('/php/getplugins.php')
assert 'seedingtimecheckreleasegate' in rpc('method.list_keys', '', 'event.download.hash_done')
record = Path('/torrents/config/seedingtime-release-gate.json')
saved = json.loads(record.read_text()) if record.exists() else {}

if mode in ('retained', 'upgrade'):
    assert saved, 'No persisted timing fixtures'
    for hash_value, expected in saved.items():
        assert timing(hash_value) == expected, 'Finished time changed across restart/upgrade'
        if mode == 'upgrade' and not expected:
            rpc('event.download.hash_done', hash_value)
            saved[hash_value] = assert_time(hash_value)
    print(json.dumps({'retained_times': len(saved), 'phase': mode}))
elif mode == 'old':
    for suffix in ('missing', 'preserved'):
        hash_value = create('timing-old-' + suffix + '.bin')
        assert timing(hash_value) == '', 'Previous image did not reproduce the defect'
        if suffix == 'preserved':
            rpc('d.custom.set', hash_value, 'seedingtime', '1234567890')
        saved[hash_value] = timing(hash_value)
    print(json.dumps({'previous_image_bug_reproduced': True, 'fixtures': len(saved)}))
elif mode in ('fresh', 'restarted', 'upgraded'):
    hash_value = create('timing-' + mode + '-created.bin')
    saved[hash_value] = assert_time(hash_value)
    # Rechecking completed data must not rewrite a pre-existing Finished time.
    rpc('d.custom.set', hash_value, 'seedingtime', '1234567890')
    rpc('event.download.hash_done', hash_value)
    assert timing(hash_value) == '1234567890'
    saved[hash_value] = timing(hash_value)
    for fast in (False, True):
        name = 'timing-' + mode + '-' + str(fast) + '.bin'
        data = name.encode().ljust(16384, b'X')
        path = Path('/torrents/completed') / name
        path.write_bytes(data)
        os.chown(path, 1000, 1000)
        info = {'name': name, 'length': len(data), 'piece length': len(data),
                'pieces': hashlib.sha1(data).digest(), 'private': 1}
        torrent = {'info': info, 'announce': 'http://127.0.0.1:1/announce'}
        if fast:
            torrent['libtorrent_resume'] = {'bitfield': 1, 'files': [{'priority': 2, 'mtime': int(path.stat().st_mtime)}]}
        rpc('load.raw_start', '', xmlrpc.client.Binary(encode(torrent)), 'd.directory.set=/torrents/completed')
        hash_value = completed(name)
        saved[hash_value] = assert_time(hash_value)
    info = {'name': 'timing-' + mode + '-incomplete.bin', 'length': 16384,
            'piece length': 16384, 'pieces': hashlib.sha1(b'X' * 16384).digest(), 'private': 1}
    hash_value = hashlib.sha1(encode(info)).hexdigest().upper()
    rpc('load.raw', '', xmlrpc.client.Binary(encode({'info': info})), 'd.directory.set=/torrents/downloading')
    for attempt in range(50):
        try:
            assert rpc('d.complete', hash_value) == 0
            break
        except xmlrpc.client.Fault:
            time.sleep(.1)
    else:
        raise AssertionError('Incomplete fixture did not load')
    rpc('event.download.hash_done', hash_value)
    assert timing(hash_value) == '', 'Incomplete torrent got a Finished time'
    print(json.dumps({'create': True, 'normal_and_fast_resume': True,
                      'existing_preserved': True, 'incomplete_untouched': True, 'phase': mode}))
else:
    raise ValueError(mode)

for hash_value in saved:
    rpc('d.save_full_session', hash_value)
record.write_text(json.dumps(saved))
