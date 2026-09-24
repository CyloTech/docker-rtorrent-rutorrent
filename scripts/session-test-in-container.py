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



def decode(data):
    def item(i):
        if data[i:i+1] == b'i':
            j=data.index(b'e',i);return int(data[i+1:j]),j+1
        if data[i:i+1] in (b'l',b'd'):
            kind=data[i:i+1];i+=1;items=[]
            while data[i:i+1] != b'e':
                value,i=item(i);items.append(value)
            return (items if kind==b'l' else dict(zip(items[::2],items[1::2]))),i+1
        j=data.index(b':',i);n=int(data[i:j]);return data[j+1:j+1+n],j+1+n
    result,end=item(0);assert end==len(data);return result

payload=hashlib.sha256(b'Appbox session regression fixture').digest()*(32*1024*1024//32)
name=b'appbox-session-regression.bin'
piece=16384
info={b'name':name,b'length':len(payload),b'piece length':piece,
      b'pieces':b''.join(hashlib.sha1(payload[i:i+piece]).digest() for i in range(0,len(payload),piece)),b'private':1}
hash_value=hashlib.sha1(encode(info)).hexdigest().upper()
base=Path('/torrents/config/rtorrent/.session')/(hash_value+'.torrent')
mode=sys.argv[1]

def snapshot():
    saved=base.with_suffix(base.suffix+'.rtorrent')
    resume=base.with_suffix(base.suffix+'.libtorrent_resume')
    if not saved.exists() or not resume.exists():return {'saved':-1,'marker':'','mtime':0,'complete':0}
    rt=decode(saved.read_bytes());lt=decode(resume.read_bytes())
    return {'saved':rt.get(b'chunks_done',-1),'marker':rt.get(b'custom1',b'').decode(),
            'mtime':saved.stat().st_mtime_ns,'complete':rt.get(b'complete',0)}

if mode in ('seed','download'):
    rpc('dht.mode.set','','disable')
    if mode=='seed':
        path=Path('/torrents/downloading')/name.decode();path.write_bytes(payload);os.chown(path,1000,1000)
    else:
        rpc('throttle.global_down.max_rate.set_kb','',32)
        assert rpc('throttle.global_down.max_rate') == 32768
    torrent=Path('/tmp/appbox-session-regression.torrent')
    torrent.write_bytes(encode({b'announce':b'http://tracker:8123/announce',b'info':info}));os.chown(torrent,1000,1000)
    rpc('load.start','',str(torrent))
    print(json.dumps({'loaded':mode}))
elif mode=='status':
    result=snapshot()
    result.update(live=rpc('d.completed_chunks',hash_value),hashing=rpc('d.hashing',hash_value),
                  active=rpc('d.is_active',hash_value),live_complete=rpc('d.complete',hash_value),
                  down_limit=rpc('throttle.global_down.max_rate'),down_rate=rpc('d.down.rate',hash_value),
                  throttle=rpc('d.throttle_name',hash_value))
    print(json.dumps(result))
elif mode=='mark':
    rpc('d.custom1.set',hash_value,sys.argv[2]);print(json.dumps(snapshot()))
elif mode=='config':
    rc=Path('/torrents/config/rtorrent/.rtlocal.rc').read_text()
    assert 'schedule = appbox_session_save, 60, 300, ((session.save))' in rc.replace('schedule2 =', 'schedule =')
    assert 'upgrade_recovery' not in rc and 'd.chunks_done' not in rc
    assert Path('/etc/services.d/rtorrent/down-signal').read_text().strip()=='SIGINT'
    assert os.environ['S6_SERVICES_GRACETIME']=='25000'
    assert rpc('session.on_completion')==1
    check_authentication();print(json.dumps({'session_config_verified':True}))
elif mode=='old-custom':
    rc=Path('/torrents/config/rtorrent/.rtorrent.rc')
    rc.write_bytes(rc.read_bytes()+b'\n# Preserved customer schedule\nschedule2 = session_save, 1200, 7200, ((session.save))\nthrottle.max_uploads.set = 27\n')
    rc.with_name('session-gate-before.rc').write_bytes(rc.read_bytes())
    print(json.dumps({'custom_config_saved':True}))
elif mode=='retained-config':
    rc=Path('/torrents/config/rtorrent/.rtorrent.rc')
    assert rc.read_bytes()==rc.with_name('session-gate-before.rc').read_bytes()
    assert rpc('throttle.max_uploads')==27
    print(json.dumps({'custom_config_retained':True}))
elif mode=='disk':
    print(json.dumps(snapshot()))
else:raise ValueError(mode)
