"""Verify an actual torrent transfer between two disposable, isolated containers."""
import atexit
import base64
import hashlib
import json
import os
import re
import secrets
import subprocess
import sys
import time

image = sys.argv[1]
assert image == 'repo.cylo.net/rutorrent:5.3.14-0.16.22' or re.fullmatch(r'repo\.cylo\.net/rutorrent@sha256:[a-f0-9]{64}', image)
prefix = 'rutorrent-transfer-' + secrets.token_hex(6)
label = 'appbox.release-gate=' + prefix
containers = []
network = None
password = secrets.token_urlsafe(24)


def command(args, data=None):
    result = subprocess.run(args, input=data, capture_output=True, text=True, timeout=120,
                            env={**os.environ, 'PASSWORD': password})
    if result.returncode:
        raise RuntimeError('Test command failed: ' + result.stderr.replace(password, '[REDACTED]')[-2000:])
    return result.stdout.strip()


def cleanup():
    for name in reversed(containers):
        owned = subprocess.run(['docker', 'inspect', '--format', '{{index .Config.Labels "appbox.release-gate"}}', name], capture_output=True, text=True)
        if owned.returncode == 0 and owned.stdout.strip() == prefix:
            subprocess.run(['docker', 'rm', '-fv', name], capture_output=True)
    if network:
        subprocess.run(['docker', 'network', 'rm', network], capture_output=True)


atexit.register(cleanup)
artifact_code = r'''
import json, subprocess
def version(command, expected):
    result=subprocess.run(command,capture_output=True,text=True)
    assert result.returncode in (0,7), (command[0],result.returncode,result.stderr)
    assert expected in result.stdout, (command[0],result.stdout[:200])
    return result.stdout.strip().splitlines()[0]
versions={
    'curl':version(['curl','--version'],'curl 8.22.0'),
    'gosu':version(['gosu','--version'],'1.19'),
    'rar':version(['rar'],'RAR 7.23'),
    'unrar':version(['unrar'],'UNRAR 7.23'),
    'php':version(['php','--version'],'PHP 8.5.'),
}
assert 'c-ares/1.34.8' in subprocess.check_output(['curl','--version'],text=True)
versions['alpine']=open('/etc/alpine-release').read().strip()
assert versions['alpine'].startswith('3.24.')
php=r"""require '/var/www/rutorrent/plugins/geoip2/vendor/autoload.php';
$reader = new GeoIp2\Database\Reader('/var/mmdb/GeoLite2-City.mmdb');
$reader->city('8.8.8.8');
echo Composer\InstalledVersions::getPrettyVersion('geoip2/geoip2');"""
versions['geoip2']=subprocess.check_output(['php','-r',php],text=True).strip()
assert versions['geoip2']=='v3.4.0',versions['geoip2']
subprocess.run(['perl','-MArchive::Zip','-MHTML::Entities','-MXML::LibXML','-MDigest::SHA','-MJSON','-MJSON::XS','-e','1'],check=True,capture_output=True)
print(json.dumps(versions))
'''
print('PASS runtime package versions: ' + command(['docker','run','--rm','-i','--entrypoint','python3',image,'-'],artifact_code), flush=True)
network = prefix + '-network'
command(['docker', 'network', 'create', '--internal', '--label', label, network])

for role in ('seed', 'download'):
    name = prefix + '-' + role
    containers.append(name)
    command(['docker', 'run', '-d', '--platform', 'linux/amd64', '--name', name,
             '--label', label, '--network', network, '-e', 'USERNAME=releasegate', '-e', 'PASSWORD',
             '-e', 'SKIP_APPBOX_CALLBACK=1', '-e', 'RT_INC_PORT=51000', '-e', 'RT_DHT_PORT=51001',
             '-e', 'XMLRPC_SIZE_LIMIT=10M', image])

deadline = time.monotonic() + 240
while True:
    states = [command(['docker', 'inspect', '--format', '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}', name]) for name in containers]
    if all(s == 'running healthy' for s in states):
        break
    assert time.monotonic() < deadline, states
    time.sleep(3)
print('PASS transfer containers: healthy', flush=True)

# Private torrent and internal-only tracker exercise HTTP announces plus peer traffic.
seed_ip = command(['docker', 'inspect', '--format', '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}', containers[0]])
assert re.fullmatch(r'[0-9.]+', seed_ip)
tracker_code = '''
from http.server import BaseHTTPRequestHandler, HTTPServer
import socket, struct
peers = socket.inet_aton(SEED_IP) + struct.pack('!H',51000)
class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        body = b'd8:intervali5e5:peers6:' + peers + b'e'
        self.send_response(200);self.end_headers();self.wfile.write(body)
    def log_message(self,*args):pass
HTTPServer(('0.0.0.0',8123),Handler).serve_forever()
'''.replace('SEED_IP', repr(seed_ip))
tracker = prefix + '-tracker'
containers.append(tracker)
command(['docker', 'run', '-d', '--name', tracker, '--label', label, '--network', network,
         '--network-alias', 'tracker', '--entrypoint', 'python3', image, '-u', '-c', tracker_code])

inside_code = r'''
from pathlib import Path
import hashlib, json, os, socket, subprocess, sys, time, xmlrpc.client
def rpc(method,*args):
    body=xmlrpc.client.dumps(args,methodname=method).encode()
    headers=b'CONTENT_LENGTH\0'+str(len(body)).encode()+b'\0SCGI\x001\0'
    with socket.socket(socket.AF_UNIX,socket.SOCK_STREAM) as s:
        s.settimeout(20);s.connect('/var/run/rtorrent/scgi.socket')
        s.sendall(str(len(headers)).encode()+b':'+headers+b','+body)
        response=b''
        while b'</methodResponse>' not in response:
            part=s.recv(65536)
            if not part:break
            response+=part
    return xmlrpc.client.loads(response[response.index(b'<?xml'):])[0][0]
def encode(x):
    if isinstance(x,int):return b'i'+str(x).encode()+b'e'
    if isinstance(x,bytes):return str(len(x)).encode()+b':'+x
    if isinstance(x,dict):return b'd'+b''.join(encode(k)+encode(x[k]) for k in sorted(x))+b'e'
payload=(b'Appbox synthetic torrent transfer verification.\n'*25000)[:1048576]
name=b'appbox-release-transfer.bin'
pieces=b''.join(hashlib.sha1(payload[i:i+16384]).digest() for i in range(0,len(payload),16384))
info={b'name':name,b'length':len(payload),b'piece length':16384,b'pieces':pieces,b'private':1}
hash_value=hashlib.sha1(encode(info)).hexdigest().upper()
mode=sys.argv[1]
if mode in ('seed','download'):
    rpc('dht.mode.set','','disable')
    if mode=='seed':
        path=Path('/torrents/downloading')/name.decode();path.write_bytes(payload);os.chown(path,1000,1000)
    torrent=Path('/tmp/appbox-release-transfer.torrent')
    torrent.write_bytes(encode({b'announce':b'http://tracker:8123/announce',b'info':info}))
    os.chown(torrent,1000,1000)
    rpc('load.start','',str(torrent))
    print(json.dumps({'loaded':mode}))
elif mode=='status':
    complete=rpc('d.complete',hash_value)
    active=rpc('d.is_active',hash_value)
    size=rpc('d.completed_bytes',hash_value)
    verified=False
    if complete:
        for folder in ('downloading','completed'):
            path=Path('/torrents')/folder/name.decode()
            if path.is_file():
                assert hashlib.sha256(path.read_bytes()).digest()==hashlib.sha256(payload).digest()
                verified=True
        assert verified,'Completed data not found'
    print(json.dumps({'complete':complete,'active':active,'bytes':size,'sha256_verified':verified}))
'''


def inside(name, mode):
    return json.loads(command(['docker', 'exec', '-i', name, 'python3', '-', mode], inside_code).splitlines()[-1])


inside(containers[0], 'seed')
deadline = time.monotonic() + 90
while not inside(containers[0], 'status')['complete']:
    assert time.monotonic() < deadline, 'Seed hash check did not finish'
    time.sleep(2)
inside(containers[1], 'download')
deadline = time.monotonic() + 180
while True:
    result = inside(containers[1], 'status')
    if result['complete'] and result['sha256_verified']:
        break
    assert time.monotonic() < deadline, result
    time.sleep(3)
print('PASS private torrent transfer through local HTTP tracker: ' + json.dumps(result), flush=True)
