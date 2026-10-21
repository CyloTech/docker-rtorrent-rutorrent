"""Checks run inside a started, healthy ruTorrent container.

The release gate pipes this file to `docker exec -i <container> python3 -`.

  seed                         add one .torrent through the web upload; print its hash
  check PHP_VERSION [HASH]     nginx/php-fpm config tests, multipart through
                               nginx + php-fpm, a .torrent upload, the
                               unauthenticated /no-auth/share.php path, and
                               (with HASH) that an earlier torrent survived

The container's USERNAME and PASSWORD environment set the basic-auth login.
The last line printed is a JSON summary.
"""
import base64
import hashlib
import json
import os
import secrets
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import xmlrpc.client

BASE = "http://127.0.0.1"
LOGIN = base64.b64encode((os.environ["USERNAME"] + ":" + os.environ["PASSWORD"]).encode()).decode()
PROBE = "/var/www/rutorrent/appbox-gate-multipart.php"


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


OPENER = urllib.request.build_opener(NoRedirect)


def http(path, data=None, headers=None, auth=True, timeout=60):
    request = urllib.request.Request(BASE + path, data=data, headers=dict(headers or {}))
    if auth:
        request.add_header("Authorization", "Basic " + LOGIN)
    try:
        with OPENER.open(request, timeout=timeout) as response:
            return response.status, dict(response.headers), response.read()
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers), error.read()


def multipart(fields, files):
    boundary = "----appbox-gate-" + secrets.token_hex(8)
    body = b""
    for name, value in fields:
        body += ("--" + boundary + "\r\nContent-Disposition: form-data; name=\"" + name + "\"\r\n\r\n").encode()
        body += value.encode() + b"\r\n"
    for name, filename, content_type, content in files:
        body += ("--" + boundary + "\r\nContent-Disposition: form-data; name=\"" + name
                 + "\"; filename=\"" + filename + "\"\r\nContent-Type: " + content_type + "\r\n\r\n").encode()
        body += content + b"\r\n"
    body += ("--" + boundary + "--\r\n").encode()
    return body, {"Content-Type": "multipart/form-data; boundary=" + boundary}


def bencode(value):
    if isinstance(value, int):
        return b"i" + str(value).encode() + b"e"
    if isinstance(value, str):
        value = value.encode()
    if isinstance(value, bytes):
        return str(len(value)).encode() + b":" + value
    if isinstance(value, dict):
        return b"d" + b"".join(bencode(k) + bencode(value[k]) for k in sorted(value)) + b"e"
    raise TypeError(type(value))


def make_torrent():
    data = secrets.token_bytes(32768)
    piece = 16384
    info = {
        "length": len(data),
        "name": "appbox-gate-" + secrets.token_hex(6) + ".bin",
        "piece length": piece,
        "pieces": b"".join(hashlib.sha1(data[i:i + piece]).digest() for i in range(0, len(data), piece)),
        "private": 1,
    }
    torrent = bencode({"announce": "http://127.0.0.1:9/announce", "info": info})
    return torrent, hashlib.sha1(bencode(info)).hexdigest().upper()


def rtorrent_hashes():
    proxy = xmlrpc.client.ServerProxy("http://127.0.0.1:8001/")
    return {h.upper() for h in proxy.download_list("", "main")}


def upload_torrent():
    torrent, info_hash = make_torrent()
    body, headers = multipart([], [("torrent_file", "gate.torrent", "application/x-bittorrent", torrent)])
    status, response_headers, _ = http("/php/addtorrent.php?json=1", body, headers)
    location = response_headers.get("Location", "")
    assert status == 302 and location, ("addtorrent.php did not redirect", status)
    # ruTorrent answers with a scheme-relative //host/php/addtorrent.php?... URL.
    if location.startswith(("//", "http://", "https://")):
        location = "/" + location.split("//", 1)[1].split("/", 1)[1]
    status, _, result = http(location)
    assert status == 200, ("addtorrent result page", status)
    assert json.loads(result.decode()) == {"result": "Success"}, ("addtorrent result", result[:200])
    deadline = time.monotonic() + 60
    while info_hash not in rtorrent_hashes():
        assert time.monotonic() < deadline, "uploaded torrent did not appear in rTorrent"
        time.sleep(1)
    return info_hash


def config_tests():
    subprocess.run(["nginx", "-t"], check=True, capture_output=True, timeout=60)
    # php-fpm runs as the rtorrent user (s6-setuidgid 1000:1000); test the
    # rendered configuration as that user. Its error_log is /proc/self/fd/2,
    # so stderr must be a file that user can open.
    with tempfile.NamedTemporaryFile() as log:
        os.chown(log.name, 1000, 1000)
        result = subprocess.run(["s6-setuidgid", "1000:1000", "php-fpm85", "-t"],
                                stdout=log, stderr=log, timeout=60)
        log.seek(0)
        output = log.read().decode(errors="replace")
    assert result.returncode == 0 and "test is successful" in output, ("php-fpm85 -t", output[-2000:])


def fpm_multipart(expected_version):
    with open(PROBE, "w") as probe:
        probe.write("<?php echo PHP_VERSION, '|', php_sapi_name(), '|', count($_FILES), '|', "
                    "$_FILES['f']['size'] ?? -1, '|', $_FILES['f']['error'] ?? -1, '|', $_POST['a'] ?? '';")
    os.chmod(PROBE, 0o644)
    try:
        body, headers = multipart([("a", "b")], [("f", "x.txt", "text/plain", b"hello")])
        status, _, unauthenticated = http("/appbox-gate-multipart.php", body, headers, auth=False)
        assert status == 401, ("unauthenticated multipart POST was not rejected", status)
        status, _, output = http("/appbox-gate-multipart.php", body, headers)
        assert status == 200, ("multipart POST through nginx and php-fpm", status, output[:200])
        expected = expected_version + "|fpm-fcgi|1|5|0|b"
        assert output.decode() == expected, ("multipart through php-fpm", output[:200], expected)
    finally:
        os.remove(PROBE)
    return expected


def no_auth_share():
    status, _, body = http("/no-auth/share.php", auth=False)
    assert status == 200 and body.strip() == b"No such file or it expired", ("/no-auth/share.php", status, body[:200])
    status, _, _ = http("/php/addtorrent.php", auth=False)
    assert status == 401, ("unauthenticated ruTorrent PHP was not rejected", status)
    return "200 from php-fpm without login (share.php answered 'No such file or it expired')"


def main():
    mode = sys.argv[1]
    if mode == "seed":
        print(json.dumps({"seeded": upload_torrent()}))
        return
    assert mode == "check" and len(sys.argv) in (3, 4), "usage: check PHP_VERSION [HASH]"
    expected_version = sys.argv[2]
    summary = {}
    config_tests()
    summary["config"] = "nginx -t and php-fpm85 -t (as uid 1000) ok"
    summary["fpm_multipart"] = fpm_multipart(expected_version)
    summary["addtorrent_upload"] = upload_torrent()
    if len(sys.argv) == 4:
        assert sys.argv[3].upper() in rtorrent_hashes(), "torrent added before the upgrade is missing"
        summary["retained"] = sys.argv[3].upper()
    summary["no_auth_share"] = no_auth_share()
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
