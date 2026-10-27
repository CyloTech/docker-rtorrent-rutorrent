"""Basic-auth checks run inside a started, healthy ruTorrent container.

release/verify-auth-image.sh pipes this file to
`docker exec -i -e PASSWORD <container> python3 - <mode>`.

  login    USERNAME/PASSWORD (from the environment) can sign in everywhere,
           and no login or a wrong password is refused everywhere
  locked   no password file holds a user: every protected path refuses any
           login, while the public /no-auth/share.php still answers
  refused  every protected path refuses USERNAME/PASSWORD (run with the
           password files deleted); prints the status codes seen

Protected paths: ruTorrent on port 80 (static page, PHP and /RPC2), the
XML-RPC listener on port 8000 and WebDAV on port 9000. Every mode also
checks that the rendered nginx configuration still has basic auth on.
The last line printed is a JSON summary.
"""
import base64
import json
import os
import re
import sys
import urllib.error
import urllib.request

RPC_BODY = (b"<?xml version='1.0'?><methodCall><methodName>system.api_version"
            b"</methodName></methodCall>")

# (name, url, method, body, headers, status with a valid login)
PROTECTED = [
    ("ui", "http://127.0.0.1/", "GET", None, {}, 200),
    ("ui_index", "http://127.0.0.1/index.html", "GET", None, {}, 200),
    ("ui_php", "http://127.0.0.1/php/getsettings.php", "GET", None, {}, 200),
    # addtorrent.php answers a request without a torrent with a redirect.
    ("ui_addtorrent", "http://127.0.0.1/php/addtorrent.php", "GET", None, {}, 302),
    ("ui_rpc2", "http://127.0.0.1/RPC2", "POST", RPC_BODY, {"Content-Type": "text/xml"}, 200),
    ("xmlrpc_8000", "http://127.0.0.1:8000/", "POST", RPC_BODY, {"Content-Type": "text/xml"}, 200),
    ("webdav_9000", "http://127.0.0.1:9000/", "GET", None, {}, 200),
]
# The server blocks whose basic auth must stay on, and the password file each uses.
NGINX_AUTH = {
    "/etc/nginx/conf.d/rutorrent.conf": ["/passwd/rutorrent.htpasswd", "/passwd/rpc.htpasswd"],
    "/etc/nginx/conf.d/rpc.conf": ["/passwd/rpc.htpasswd"],
    "/etc/nginx/conf.d/webdav.conf": ["/passwd/webdav.htpasswd"],
}


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


OPENER = urllib.request.build_opener(NoRedirect)


def basic(user, password):
    return "Basic " + base64.b64encode((user + ":" + password).encode()).decode()


def status(url, method, body, headers, authorization=None):
    request = urllib.request.Request(url, data=body, method=method, headers=dict(headers))
    if authorization:
        request.add_header("Authorization", authorization)
    try:
        with OPENER.open(request, timeout=60) as response:
            response.read()
            return response.status
    except urllib.error.HTTPError as error:
        error.read()
        return error.code


def nginx_auth_on():
    for path, user_files in NGINX_AUTH.items():
        text = open(path).read()
        assert not re.search(r"^\s*#\s*auth_basic", text, re.M), (path, "auth_basic commented out")
        assert re.search(r'^\s*auth_basic\s+"[^"]*restricted access";', text, re.M), (path, "no auth_basic realm")
        for user_file in user_files:
            assert re.search(r"^\s*auth_basic_user_file\s+" + re.escape(user_file) + ";", text, re.M), (path, user_file)
    return "auth_basic and auth_basic_user_file active in rutorrent.conf, rpc.conf and webdav.conf"


def login():
    user, password = os.environ["USERNAME"], os.environ["PASSWORD"]
    assert user and password, "USERNAME and PASSWORD must be set"
    seen = {}
    for name, url, method, body, headers, expected in PROTECTED:
        anonymous = status(url, method, body, headers)
        wrong = status(url, method, body, headers, basic(user, password + "x"))
        good = status(url, method, body, headers, basic(user, password))
        assert anonymous == 401, (name, "no login", anonymous)
        assert wrong == 401, (name, "wrong password", wrong)
        assert good == expected, (name, "valid login", good, expected)
        seen[name] = "401/401/" + str(good)
    return seen


def locked():
    attempts = [None, basic("releasegate", "anything"), basic("", ""), basic("rtorrent", "")]
    if os.environ.get("USERNAME") and os.environ.get("PASSWORD"):
        attempts.append(basic(os.environ["USERNAME"], os.environ["PASSWORD"]))
    seen = {}
    for name, url, method, body, headers, _ in PROTECTED:
        codes = [status(url, method, body, headers, attempt) for attempt in attempts]
        assert all(code == 401 for code in codes), (name, "served without a valid login", codes)
        seen[name] = "401 x" + str(len(codes))
    share = status("http://127.0.0.1/no-auth/share.php", "GET", None, {})
    assert share == 200, ("/no-auth/share.php", share)
    seen["no_auth_share"] = share
    return seen


def refused():
    authorization = basic(os.environ["USERNAME"], os.environ["PASSWORD"])
    seen = {}
    for name, url, method, body, headers, _ in PROTECTED:
        code = status(url, method, body, headers, authorization)
        assert code >= 400, (name, "served with the password files missing", code)
        seen[name] = code
    return seen


def main():
    mode = sys.argv[1] if len(sys.argv) == 2 else ""
    checks = {"login": login, "locked": locked, "refused": refused}
    assert mode in checks, "usage: login | locked | refused"
    summary = {"nginx": nginx_auth_on(), mode: checks[mode]()}
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
