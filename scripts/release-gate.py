#!/usr/bin/env python3
"""Behavioral image release checks on the dedicated Docker builder."""
import atexit
import json
import os
import re
from pathlib import Path
import secrets
import subprocess
import sys
import time

EXPECTED = "repo.cylo.net/rutorrent:5.3.14-0.16.22"
PREVIOUS = "repo.cylo.net/rutorrent@sha256:66c591ef9be8b983714a298cc41f7be64ee777731ae2a6a9c770056e7d1b9d7f"
assert len(sys.argv) == 2 and sys.argv[1] == EXPECTED, "Unexpected image reference"
RUN = "rutorrent-package-gate-" + secrets.token_hex(6)
LABEL = "appbox.release-gate=" + RUN
containers, volumes = [], []
network = None
password = secrets.token_urlsafe(24)
test_code = Path(__file__).with_name("watch-test-in-container.py").read_text()


def command(args, *, data=None, env=None, timeout=120):
    result = subprocess.run(args, input=data, text=True, capture_output=True, env=env, timeout=timeout)
    if result.returncode:
        # No container logs or authentication-bearing arguments in error output.
        details = ""
        if args[0] in ("docker", "python3") or args[0] == sys.executable:
            details = "\n" + result.stderr.replace(password, "[REDACTED]")[-4000:]
        raise RuntimeError("Command failed: " + " ".join(args[:3]) + " (exit " + str(result.returncode) + ")" + details)
    return result.stdout.strip()


def cleanup():
    for container in reversed(containers):
        owned = subprocess.run(["docker", "inspect", "--format", '{{index .Config.Labels "appbox.release-gate"}}', container], capture_output=True, text=True)
        if owned.returncode == 0 and owned.stdout.strip() == RUN:
            subprocess.run(["docker", "rm", "-fv", container], capture_output=True)
    for volume in volumes:
        owned = subprocess.run(["docker", "volume", "inspect", "--format", '{{index .Labels "appbox.release-gate"}}', volume], capture_output=True, text=True)
        if owned.returncode == 0 and owned.stdout.strip() == RUN:
            subprocess.run(["docker", "volume", "rm", volume], capture_output=True)
    if network:
        subprocess.run(["docker", "network", "rm", network], capture_output=True)


atexit.register(cleanup)


def startup_diagnostics(container):
    result = subprocess.run(["docker", "logs", "--tail", "100", container], capture_output=True, text=True, timeout=30)
    output = (result.stdout + result.stderr).replace(password, "[REDACTED]")
    output = re.sub(r"(?im)^.*(?:password|Authorization|token).*$", "[authentication detail omitted]", output)
    print(output[-12000:], flush=True)


def wait_healthy(container):
    deadline = time.monotonic() + 240
    while time.monotonic() < deadline:
        status = command(["docker", "inspect", "--format", "{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}", container])
        if status == "running healthy":
            return
        if status.startswith(("exited", "dead")):
            startup_diagnostics(container)
            raise RuntimeError(container + " failed to start: " + status)
        time.sleep(2)
    startup_diagnostics(container)
    raise RuntimeError(container + " did not become healthy")


def run_app(name, image, phase, storage):
    containers.append(name)
    args = ["docker", "run", "-d", "--platform", "linux/amd64", "--name", name, "--label", LABEL,
            "--network", network, "-e", "USERNAME=releasegate", "-e", "PASSWORD",
            "-e", "INSTANCE_ID=" + phase, "-e", "APPBOX_CALLBACK_BASE=http://callback:8123",
            "-e", "WAN_IP=127.0.0.1", "-e", "RT_INC_PORT=51000", "-e", "RT_DHT_PORT=51001", "-e", "XMLRPC_SIZE_LIMIT=10M",
            "-e", "RT_PREALLOCATE_TYPE=2", "-e", "RT_SEND_BUFFER_SIZE=64M", "-e", "RT_RECEIVE_BUFFER_SIZE=64M"]
    for volume, target in storage:
        args += ["-v", volume + ":" + target]
    command(args + [image], env={**os.environ, "PASSWORD": password})
    wait_healthy(name)
    wait_plugins(name)
    print("Healthy disposable container: " + phase, flush=True)


def inside(container, mode, name="appbox-watch-gate-check"):
    output = command(["docker", "exec", "-i", container, "python3", "-", mode, name], data=test_code)
    return json.loads(output.splitlines()[-1])


def wait_plugins(container):
    # Docker health can pass before the ten-second plugin-init schedule runs.
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        value = inside(container, "plugins")
        if value["ready"]:
            return
        time.sleep(2)
    raise RuntimeError("ruTorrent plugin initialization did not finish: " + json.dumps(value))


def wait_state(container, name, state, tied):
    # The bundled AutoWatch schedule runs every 300 seconds. Exercise its
    # real default timing, with a small margin for container execution.
    deadline = time.monotonic() + 360
    while time.monotonic() < deadline:
        value = inside(container, "status", name)
        if value["present"] and value["state"] == state and value["active"] == state and value["tied"] == tied and not value["source_exists"]:
            return value
        time.sleep(2)
    raise RuntimeError("Torrent did not reach expected state: " + json.dumps(value))


def remains_active(container, name):
    # Observe across more than three former five-second stop intervals.
    deadline = time.monotonic() + 18
    while time.monotonic() < deadline:
        value = inside(container, "status", name)
        assert value["state"] == value["active"] == 1 and not value["tied"] and not value["source_exists"], value
        time.sleep(3)


def import_pair(container, suffix):
    # Check the immediate importer before waiting for the scheduled one.
    for mode in ("web", "watch"):
        name = "appbox-watch-gate-" + suffix + "-" + mode
        inside(container, mode, name)
        wait_state(container, name, 1, False)
        remains_active(container, name)
    print("PASS " + suffix + ": watch and web imports remain active after source removal", flush=True)


def registry_absent():
    command([sys.executable, str(Path(__file__).with_name("registry-check.py")), EXPECTED])


assert command(["docker", "image", "inspect", "--format", "{{.Os}}/{{.Architecture}}", EXPECTED]) == "linux/amd64"
command(["docker", "run", "--rm", "--entrypoint", "sh", EXPECTED, "-ec",
         "grep -Fq 'version: \"5.3.14\"' /var/www/rutorrent/js/webui.js && "
         "grep -Fq 'html[data-theme=dark] .metric-value' /var/www/rutorrent/plugins/mobile/appbox.css && "
         "test -f /usr/local/bin/migrate-rtorrent-016-config.py && "
         "php -r 'exit(PHP_MAJOR_VERSION === 8 && PHP_MINOR_VERSION === 5 ? 0 : 1);' && "
         "curl --version | head -1 && unrar | head -3 && rar | head -3 && "
         "php -r 'require \"/var/www/rutorrent/plugins/geoip2/vendor/autoload.php\"; echo \"GeoIP2 \" . Composer\\InstalledVersions::getPrettyVersion(\"geoip2/geoip2\") . PHP_EOL;'"])
command(["docker", "pull", PREVIOUS])
network = RUN + "-network"
command(["docker", "network", "create", "--internal", "--label", LABEL, network])
callback = RUN + "-callback"
containers.append(callback)
callback_code = """
from http.server import BaseHTTPRequestHandler,HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        with open('/tmp/callbacks','a') as f: f.write(self.path+'\\n')
        self.send_response(200);self.end_headers()
    def log_message(self,*args): pass
HTTPServer(('0.0.0.0',8123),Handler).serve_forever()
"""
command(["docker", "run", "-d", "--name", callback, "--label", LABEL, "--network", network,
         "--network-alias", "callback", "--entrypoint", "python3", EXPECTED, "-u", "-c", callback_code])

fresh = RUN + "-fresh"
run_app(fresh, EXPECTED, "fresh", [])
inside(fresh, "config")
inside(fresh, "versions")
import_pair(fresh, "fresh")
inside(fresh, "save")
command(["docker", "restart", fresh])
wait_healthy(fresh)
wait_plugins(fresh)
inside(fresh, "retained")
for kind in ("watch", "web"):
    remains_active(fresh, "appbox-watch-gate-fresh-" + kind)
print("PASS restart: torrent state, data, settings and authentication preserved", flush=True)

storage = []
for suffix, target in (("torrents", "/torrents"), ("passwd", "/passwd")):
    volume = RUN + "-" + suffix
    command(["docker", "volume", "create", "--label", LABEL, volume])
    volumes.append(volume)
    storage.append((volume, target))
old = RUN + "-old"
run_app(old, PREVIOUS, "old", storage)
repro = "appbox-watch-gate-upgrade-repro"
inside(old, "watch", repro)
wait_state(old, repro, 1, False)
inside(old, "save-compat")
inside(old, "save")
print("PASS baseline: current catalog image imports and saves a synthetic torrent", flush=True)
command(["docker", "stop", old])

upgraded = RUN + "-upgrade"
run_app(upgraded, EXPECTED, "upgrade", storage)
inside(upgraded, "config")
inside(upgraded, "versions")
inside(upgraded, "verify-compat")
inside(upgraded, "retained")
assert inside(upgraded, "status", repro)["present"], "Upgrade lost the existing torrent"
inside(upgraded, "start", repro)
remains_active(upgraded, repro)
import_pair(upgraded, "upgraded")
print("PASS upgrade: existing torrent, data, authentication and custom configuration preserved", flush=True)

callbacks = command(["docker", "exec", callback, "cat", "/tmp/callbacks"]).splitlines()
assert callbacks.count("/v1/apps/installed/fresh") == 1, callbacks
assert callbacks.count("/v1/apps/installed/upgrade") == 1, callbacks
print("PASS install callbacks on fresh install and upgrade; restart does not duplicate callbacks", flush=True)

# Verify real peer traffic, runtime archive tools and the GeoIP2 database.
print(command([sys.executable, str(Path(__file__).with_name("transfer-test.py")), EXPECTED], timeout=600), flush=True)

# The caller pushes only after this final, fail-closed registry check.
registry_absent()
print("Release gate passed for " + EXPECTED, flush=True)
