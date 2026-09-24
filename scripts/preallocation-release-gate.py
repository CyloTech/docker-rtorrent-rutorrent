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

EXPECTED = "repo.cylo.net/rutorrent:5.3.14-0.16.22-1"
PREVIOUS = "repo.cylo.net/rutorrent@sha256:7d8938e9f372a3e778b77566dfea28eab5b0a9f74a66a1234e0d64dbafd77a93"
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


def run_app(name, image, phase, storage, allocation="1"):
    containers.append(name)
    args = ["docker", "run", "-d", "--platform", "linux/amd64", "--name", name, "--label", LABEL,
            "--network", network, "-e", "USERNAME=releasegate", "-e", "PASSWORD",
            "-e", "INSTANCE_ID=" + phase, "-e", "APPBOX_CALLBACK_BASE=http://callback:8123",
            "-e", "WAN_IP=127.0.0.1", "-e", "RT_INC_PORT=51000", "-e", "RT_DHT_PORT=51001", "-e", "XMLRPC_SIZE_LIMIT=10M",
            "-e", "RT_SEND_BUFFER_SIZE=64M", "-e", "RT_RECEIVE_BUFFER_SIZE=64M"]
    if allocation is not None:
        args += ["-e", "RT_PREALLOCATE_TYPE=" + allocation]
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



def allocation(container, generated, active=None):
    if active is None:
        active = generated
    code = test_code.split("RULES =")[0] + fr"""
config = Path('/torrents/config/rtorrent/.rtlocal.rc').read_text()
assert 'system.file.allocate.set = {generated}\n' in config, 'Incorrect generated preallocation setting'
assert rpc('system.file.allocate') == {active}, 'Incorrect live preallocation setting'
check_authentication()
print(json.dumps({{'generated': {generated}, 'active': {active}}}))
"""
    value = command(["docker", "exec", "-i", container, "python3", "-"], data=code)
    print("PASS preallocation: " + value, flush=True)


def saved_config(container, mode):
    code = r"""
from pathlib import Path
import sys
rc=Path('/torrents/config/rtorrent/.rtorrent.rc')
backup=rc.with_name('preallocation-gate-original.rc')
if sys.argv[1] == 'save':
    backup.write_bytes(rc.read_bytes())
elif sys.argv[1] == 'verify':
    assert rc.read_bytes() == backup.read_bytes(), 'Saved configuration changed'
elif sys.argv[1] == 'override':
    rc.write_bytes(rc.read_bytes()+b'\n# Custom preallocation override\nsystem.file.allocate.set = 0\n')
    backup.write_bytes(rc.read_bytes())
"""
    command(["docker", "exec", "-i", container, "python3", "-", mode], data=code)


assert command(["docker", "image", "inspect", "--format", "{{.Os}}/{{.Architecture}}", EXPECTED]) == "linux/amd64"
command([sys.executable, str(Path(__file__).with_name("registry-check.py")), EXPECTED])
command(["docker", "pull", PREVIOUS])
network = RUN + "-network"
command(["docker", "network", "create", "--internal", "--label", LABEL, network])
callback = RUN + "-callback"
containers.append(callback)
callback_code = r"""
from http.server import BaseHTTPRequestHandler,HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        with open('/tmp/callbacks','a') as f: f.write(self.path+'\n')
        self.send_response(200);self.end_headers()
    def log_message(self,*args): pass
HTTPServer(('0.0.0.0',8123),Handler).serve_forever()
"""
command(["docker", "run", "-d", "--name", callback, "--label", LABEL, "--network", network,
         "--network-alias", "callback", "--entrypoint", "python3", EXPECTED, "-u", "-c", callback_code])

fresh = RUN + "-fresh"
run_app(fresh, EXPECTED, "fresh", [])
allocation(fresh, 1)
inside(fresh, "config")
inside(fresh, "versions")
inside(fresh, "web", "appbox-watch-gate-preallocation-fresh")
inside(fresh, "save")
saved_config(fresh, "save")
command(["docker", "restart", fresh])
wait_healthy(fresh)
wait_plugins(fresh)
allocation(fresh, 1)
inside(fresh, "retained")
saved_config(fresh, "verify")
assert inside(fresh, "status", "appbox-watch-gate-preallocation-fresh")["present"]
print("PASS fresh/restart: authentication, torrent, data, theme and settings retained", flush=True)

for phase, value in (("disabled", "0"), ("default", None)):
    name = RUN + "-" + phase
    run_app(name, EXPECTED, phase, [], value)
    allocation(name, 0)

storage = []
for suffix, target in (("torrents", "/torrents"), ("passwd", "/passwd")):
    volume = RUN + "-" + suffix
    command(["docker", "volume", "create", "--label", LABEL, volume])
    volumes.append(volume)
    storage.append((volume, target))
old = RUN + "-old"
run_app(old, PREVIOUS, "old", storage, "2")
allocation(old, 2)
inside(old, "web", "appbox-watch-gate-preallocation-upgrade")
inside(old, "save")
saved_config(old, "save")
command(["docker", "stop", old])
upgraded = RUN + "-upgrade"
run_app(upgraded, EXPECTED, "upgrade", storage, "2")
allocation(upgraded, 1)
inside(upgraded, "config")
inside(upgraded, "versions")
inside(upgraded, "retained")
saved_config(upgraded, "verify")
assert inside(upgraded, "status", "appbox-watch-gate-preallocation-upgrade")["present"]
print("PASS upgrade: legacy environment 2 renders 1; torrent, data and configuration retained", flush=True)
saved_config(upgraded, "override")
command(["docker", "restart", upgraded])
wait_healthy(upgraded)
wait_plugins(upgraded)
allocation(upgraded, 1, 0)
saved_config(upgraded, "verify")
print("PASS persistent custom override: generated 1, live value 0 after restart", flush=True)

callbacks = command(["docker", "exec", callback, "cat", "/tmp/callbacks"]).splitlines()
assert callbacks.count("/v1/apps/installed/fresh") == 1, callbacks
assert callbacks.count("/v1/apps/installed/upgrade") == 1, callbacks
print("PASS fresh/upgrade callbacks; restart does not duplicate callbacks", flush=True)
command([sys.executable, str(Path(__file__).with_name("registry-check.py")), EXPECTED])
print("Release gate passed for " + EXPECTED, flush=True)
