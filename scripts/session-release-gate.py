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

EXPECTED = "repo.cylo.net/rutorrent:5.3.15.1-0.16.23"
PREVIOUS = "repo.cylo.net/rutorrent@sha256:452cf30b6f99f2274750544d379fad50d8ea26adaf19ae473513cac7970b14b9"
assert len(sys.argv) == 2 and sys.argv[1] == EXPECTED, "Unexpected image reference"
RUN = "rutorrent-upstream-gate-" + secrets.token_hex(6)
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
    # The dedicated builder can spend several minutes on ownership copy-up
    # during concurrent image exports. Still require a healthy running app.
    deadline = time.monotonic() + 900
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


def run_app(name, image, phase, storage, allocation="1", interval=None):
    containers.append(name)
    args = ["docker", "run", "-d", "--platform", "linux/amd64", "--name", name, "--label", LABEL,
            "--network", network, "-e", "USERNAME=releasegate", "-e", "PASSWORD",
            "-e", "INSTANCE_ID=" + phase, "-e", "APPBOX_CALLBACK_BASE=http://callback:8123",
            "-e", "WAN_IP=127.0.0.1", "-e", "RT_INC_PORT=51000", "-e", "RT_DHT_PORT=51001", "-e", "XMLRPC_SIZE_LIMIT=10M"]
    # Fresh installs exercise the image fallback; upgrades exercise catalogue values.
    if phase == "upgrade":
        args += ["-e", "RT_SEND_BUFFER_SIZE=0", "-e", "RT_RECEIVE_BUFFER_SIZE=0"]
    if allocation is not None:
        args += ["-e", "RT_PREALLOCATE_TYPE=" + allocation]
    if interval is not None:
        args += ["-e", "RT_SESSION_SAVE_SECONDS=" + interval]
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
    # A persisted same-version cache can look ready before initplugins refreshes it.
    expected_dht = "dht.override_port.set"
    deadline = time.monotonic() + 120
    waiting_for_refresh = False
    while time.monotonic() < deadline:
        value = inside(container, "plugins")
        if value["ready"] and value["dht_command"] == expected_dht:
            if waiting_for_refresh:
                print("PASS startup refreshed the persisted DHT command cache", flush=True)
            return
        if value["ready"] and not waiting_for_refresh:
            print("Waiting for startup to refresh the previous DHT command cache", flush=True)
            waiting_for_refresh = True
        time.sleep(2)
    raise RuntimeError("ruTorrent plugin initialization did not finish: " + json.dumps(value))



php_cli_code = Path(__file__).with_name("php-cli-test-in-container.py").read_text()

def check_php_cli(container, old=False):
    args = ["docker", "exec", "-i", container, "python3", "-"] + (["old"] if old else [])
    value = command(args, data=php_cli_code, timeout=120)
    print("PASS PHP CLI diagnostic: " + value, flush=True)

seedingtime_code = Path(__file__).with_name("seedingtime-test-in-container.py").read_text()

def check_seedingtime(container, mode):
    value = command(["docker", "exec", "-i", container, "python3", "-", mode], data=seedingtime_code, timeout=240)
    print("PASS Finished time " + mode + ": " + value, flush=True)

network_code = Path(__file__).with_name("network-test-in-container.py").read_text()

def check_network(container, mode="current"):
    value = command(["docker", "exec", "-i", container, "python3", "-", mode], data=network_code)
    print("PASS network " + mode + ": " + value, flush=True)

session_code = Path(__file__).with_name("session-test-in-container.py").read_text()

def session(container, mode, *args):
    value=command(['docker','exec','-i',container,'python3','-',mode,*args],data=session_code)
    return json.loads(value.splitlines()[-1])

def wait_session(container, predicate, timeout=120):
    deadline=time.monotonic()+timeout
    while True:
        result=session(container,'status')
        if predicate(result):return result
        assert time.monotonic()<deadline, result
        time.sleep(3)

assert command(["docker", "image", "inspect", "--format", "{{.Os}}/{{.Architecture}}", EXPECTED]) == "linux/amd64"
assert command(["docker", "image", "inspect", "--format", '{{index .Config.Labels "io.appbox.rutorrent.revision"}}', EXPECTED]) == "fe468360f94b02def11bbf67b16316bbe8081380"
command([sys.executable, str(Path(__file__).with_name("registry-check.py")), EXPECTED])
# Exercise upstream's existing proxy tests inside the actual runtime image.
# This catches missing PHP extensions that a source-only test run cannot see.
proxy_tests = r'''
from pathlib import Path
import re, subprocess
tests = sorted(Path('/var/www/rutorrent/tests/php').glob('XMLRPCProxy*Test.php'))
assert len(tests) >= 10, 'Upstream proxy tests missing'
runner = """require $argv[1]; foreach(get_declared_classes() as $class) {
    if(get_parent_class($class) === 'TestCase') {
        $test = new $class(); $test->setUp(); $test->run(); $test->tearDown();
    }
}"""
assertions = 0
for test in tests:
    result = subprocess.run(['php', '-d', 'zend.assertions=1', '-d', 'display_errors=1',
                             '-r', runner, str(test)], capture_output=True, text=True)
    output = result.stdout + result.stderr
    if result.returncode or re.search(r'^Failed:|^not ok|failed with error|Fatal error|Parse error|Uncaught', output, re.M):
        raise RuntimeError(test.name + ' failed:\\n' + output[-8000:])
    assertions += output.count('Passed:')
assert assertions > 100, 'Upstream proxy assertions did not run'
print('PASS upstream XML-RPC proxy: ' + str(len(tests)) + ' files, ' + str(assertions) + ' assertions')
'''
print(command(["docker", "run", "--rm", "--network", "none", "--entrypoint", "python3", EXPECTED,
               "-c", proxy_tests]), flush=True)
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

print('Release resources: '+RUN,flush=True)
# Prepare an existing volume using the current catalogue image.
storage=[]
for suffix,target in (('torrents','/torrents'),('passwd','/passwd')):
    volume=RUN+'-'+suffix
    command(['docker','volume','create','--label',LABEL,volume]);volumes.append(volume)
    storage.append((volume,target))
old=RUN+'-old'
run_app(old,PREVIOUS,'old',storage,interval='10800')
check_php_cli(old)
check_seedingtime(old,"old")
inside(old,'web','appbox-watch-gate-session-existing')
inside(old,'save')
check_network(old)
session(old,'old-custom')
command(['docker','stop','--time','30',old])

# Fresh installation doubles as the private seeder.
fresh=RUN+'-fresh'
run_app(fresh,EXPECTED,'fresh',[])
check_php_cli(fresh)
check_seedingtime(fresh,"fresh")
session(fresh,'config');inside(fresh,'versions')
check_network(fresh)
# Docker may complete a restart slowly while other image exports saturate I/O.
# Keep the container's stop grace at 30 seconds; only extend the CLI wait.
command(['docker','restart','--time','30',fresh],timeout=600);wait_healthy(fresh);wait_plugins(fresh)
session(fresh,'config');check_network(fresh)
check_php_cli(fresh)
check_seedingtime(fresh,"retained")
check_seedingtime(fresh,"restarted")
seed_ip=command(['docker','inspect','--format','{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}',fresh])
assert re.fullmatch(r'[0-9.]+',seed_ip)
tracker=RUN+'-tracker';containers.append(tracker)
tracker_code=r"""
from http.server import BaseHTTPRequestHandler,HTTPServer
import socket,struct
peers=socket.inet_aton(SEED_IP)+struct.pack('!H',51000)
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200);self.end_headers();self.wfile.write(b'd8:intervali5e5:peers6:'+peers+b'e')
    def log_message(self,*args):pass
HTTPServer(('0.0.0.0',8123),Handler).serve_forever()
""".replace('SEED_IP',repr(seed_ip))
command(['docker','run','-d','--name',tracker,'--label',LABEL,'--network',network,
         '--network-alias','tracker','--entrypoint','python3',EXPECTED,'-u','-c',tracker_code])
session(fresh,'seed')
wait_session(fresh,lambda v:v['live_complete']==1 and v['complete']==1)
print('PASS fresh install and completion-save: private 32 MiB seed saved as complete',flush=True)

upgraded=RUN+'-upgrade'
run_app(upgraded,EXPECTED,'upgrade',storage,interval='10800')
check_php_cli(upgraded)
check_seedingtime(upgraded,"upgrade")
check_seedingtime(upgraded,"upgraded")
session(upgraded,'config');session(upgraded,'retained-config')
inside(upgraded,'versions');inside(upgraded,'retained')
check_network(upgraded)
assert inside(upgraded,'status','appbox-watch-gate-session-existing')['present']
print('PASS upgrade: old 10800-second environment migrated; custom 7200-second timer, data and authentication retained',flush=True)

session(upgraded,'download')
transfer=wait_session(upgraded,lambda v:v['live']>=16)
print('Transfer start: '+json.dumps(transfer),flush=True)
assert transfer['down_limit']==32768 and not transfer['live_complete'],transfer
session(upgraded,'mark','periodic-one')
first=wait_session(upgraded,lambda v:v['marker']=='periodic-one' and v['saved']>0,timeout=370)
assert first['down_limit']==32768 and not first['live_complete'],first
print('PASS automatic snapshot during partial transfer: '+json.dumps(first),flush=True)
session(upgraded,'mark','periodic-two')
started=time.monotonic()
second=wait_session(upgraded,lambda v:v['marker']=='periodic-two' and v['saved']>first['saved'],timeout=340)
elapsed=time.monotonic()-started
assert second['down_limit']==32768 and not second['live_complete'],second
assert 240<=elapsed<=340,(elapsed,second)
print('PASS five-minute save interval despite custom session_save timer: '+json.dumps({'seconds':round(elapsed,1),**second}),flush=True)

# Crash recovery must retain the most recent automatic snapshot.
command(['docker','kill','--signal','KILL',upgraded])
command(['docker','start',upgraded]);wait_healthy(upgraded);wait_plugins(upgraded)
recovered=wait_session(upgraded,lambda v:v['hashing']==0 and v['live']>=second['saved'])
assert recovered['marker']=='periodic-two',recovered
print('PASS forced-stop recovery retains the last periodic snapshot: '+json.dumps(recovered),flush=True)

# Stop peer traffic without stopping the torrent, then test a final unsaved change.
command(['docker','network','disconnect',network,fresh])
time.sleep(3)
before=session(upgraded,'status')
session(upgraded,'mark','graceful-stop')
assert session(upgraded,'disk')['marker']!='graceful-stop'
started=time.monotonic();command(['docker','stop','--time','30',upgraded]);elapsed=time.monotonic()-started
exit_code=command(['docker','inspect','--format','{{.State.ExitCode}}',upgraded])
assert exit_code=='0',(exit_code,elapsed)
disk=json.loads(command(['docker','run','--rm','-i','--entrypoint','python3',
                         '-v',storage[0][0]+':/torrents:ro',EXPECTED,'-','disk'],data=session_code))
assert disk['marker']=='graceful-stop' and disk['saved']>=before['live'],(before,disk)
command(['docker','start',upgraded]);wait_healthy(upgraded);wait_plugins(upgraded)
after=wait_session(upgraded,lambda v:v['hashing']==0 and v['live']>=disk['saved'])
session(upgraded,'retained-config');inside(upgraded,'retained')
check_network(upgraded)
check_seedingtime(upgraded,'retained')
print('PASS graceful stop flushes latest resume state and restart preserves it: '+json.dumps({'seconds':round(elapsed,1),'saved_chunks':disk['saved'],'restored_chunks':after['live']}),flush=True)
# Observe beyond the removed thirty-second startup recovery timer.
time.sleep(35)
assert session(upgraded,'status')['hashing']==0
assert inside(upgraded,'status','appbox-watch-gate-session-existing')['present']
print('PASS no forced startup hash queue; existing torrent retained',flush=True)
callbacks=command(['docker','exec',callback,'cat','/tmp/callbacks']).splitlines()
assert callbacks.count('/v1/apps/installed/fresh')==1 and callbacks.count('/v1/apps/installed/upgrade')==1,callbacks
print('PASS installation callbacks; restarts do not duplicate callbacks',flush=True)
command([sys.executable,str(Path(__file__).with_name('registry-check.py')),EXPECTED])
print('Release gate passed for '+EXPECTED,flush=True)
