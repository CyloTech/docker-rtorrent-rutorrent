"""Exercise the ruTorrent PHP diagnostic in disposable release containers."""
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import urllib.request

old = sys.argv[1:] == ['old']
login = base64.b64encode(('releasegate:' + os.environ['PASSWORD']).encode()).decode()
request = urllib.request.Request('http://127.0.0.1/php/getplugins.php', headers={'Authorization': 'Basic ' + login})
with urllib.request.urlopen(request, timeout=60) as response:
    assert response.status == 200
    body = response.read().decode()
warning = "noty(theUILang.phpParameterUnavailable"
assert (warning in body) == old, 'Unexpected PHP argument warning in plugin initialization response'
assert "rPlugin('create'" in body.replace(' ', '') or "rPlugin(\"create\"" in body.replace(' ', ''), 'Create plugin missing from initialization response'
if old:
    print(json.dumps({'old_warning_reproduced': True}))
    raise SystemExit(0)

def php(code, *args):
    result = subprocess.run(['gosu', '1000:1000', 'php', '-r', code, '--', *args], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, 'PHP diagnostic test failed'
    return json.loads(result.stdout)

value = php('echo json_encode([PHP_VERSION, PHP_SAPI, ini_get("register_argc_argv"), $argc, $argv[1]]);', 'argument-check')
assert value[0].startswith('8.5.') and value[1:] == ['cli', '0', 2, 'argument-check'], value
fpm = subprocess.run(['php-fpm85', '-i'], capture_output=True, text=True, timeout=30)
assert fpm.returncode == 0 and 'register_argc_argv => Off => Off' in fpm.stdout

probe = 'require "/var/www/rutorrent/php/cli-arguments.php"; echo json_encode(ruTorrentPhpCliHasArguments($argv[1]));'
assert php(probe, '/usr/bin/php') is True
with tempfile.TemporaryDirectory(prefix='rutorrent-cli-check-') as directory:
    root = Path(directory)
    root.chmod(0o755)
    for name, script, expected in [
        ('php with spaces', '#!/bin/sh\nexec /usr/bin/php "$@"\n', True),
        ('missing arguments', '#!/bin/sh\nexit 0\n', False),
        ('failed php', '#!/bin/sh\nexit 7\n', False),
    ]:
        executable = root / name
        executable.write_text(script)
        executable.chmod(0o755)
        assert php(probe, str(executable)) is expected, name
    assert php(probe, str(root / 'absent-php')) is False

# This bundled plugin is invoked by rTorrent with the profile in argv[1].
result = subprocess.run(['gosu', '1000:1000', 'php', '/var/www/rutorrent/plugins/scheduler/update.php', 'releasegate'], capture_output=True, text=True, timeout=30)
assert result.returncode == 0, 'Scheduler CLI plugin failed'
assert 'Fatal error' not in result.stdout + result.stderr and 'Warning:' not in result.stdout + result.stderr
print(json.dumps({'web_warning_absent': True, 'web_argv_off': True, 'cli_arguments_work': True,
                  'missing_arguments_detected': True, 'failed_or_missing_php_detected': True,
                  'quoted_executable_works': True, 'scheduler_plugin_passed': True}))
