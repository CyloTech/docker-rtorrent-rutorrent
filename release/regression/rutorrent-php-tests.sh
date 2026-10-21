#!/bin/sh
# ruTorrent's own PHP tests (XML-RPC proxy) under the image's php85, so a PHP
# upgrade that breaks ruTorrent's PHP code fails the gate. Same runner as
# scripts/session-release-gate.py.
set -eu
exec python3 - <<'PY'
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
    result = subprocess.run(['php85', '-d', 'zend.assertions=1', '-d', 'display_errors=1',
                             '-r', runner, str(test)], capture_output=True, text=True)
    output = result.stdout + result.stderr
    if result.returncode or re.search(r'^Failed:|^not ok|failed with error|Fatal error|Parse error|Uncaught', output, re.M):
        raise SystemExit(test.name + ' failed:\n' + output[-8000:])
    assertions += output.count('Passed:')
assert assertions > 100, 'Upstream proxy assertions did not run'
print('ruTorrent PHP tests: ' + str(len(tests)) + ' files, ' + str(assertions) + ' assertions passed')
PY
