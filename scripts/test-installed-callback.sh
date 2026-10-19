#!/usr/bin/env bash
# Exercise rootfs/usr/local/bin/appbox-installed-callback against a local mock
# API: retryable statuses back off, any other rejection stops after one try,
# and the callback token in INSTANCE_ID never reaches the log.
set -u

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
helper="${repo_root}/rootfs/usr/local/bin/appbox-installed-callback"

mock_server='
import http.server, json, os, sys
port, codes, log = int(sys.argv[1]), [int(c) for c in sys.argv[2].split(",")], sys.argv[3]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        seen = sum(1 for _ in open(log)) if os.path.exists(log) else 0
        code = codes[min(seen, len(codes) - 1)]
        with open(log, "a") as f:
            f.write(json.dumps({"path": self.path, "code": code}) + "\n")
        self.send_response(code)
        self.end_headers()
    def log_message(self, *args):
        pass
http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
'

failures=0

run_case() {
  local codes=$1 want_exit=$2 want_requests=$3
  shift 3
  local work port server rc requests leaked
  work="$(mktemp -d)"
  port=$((20000 + RANDOM % 20000))
  python3 -c "${mock_server}" "${port}" "${codes}" "${work}/requests" &
  server=$!
  sleep 0.5

  env INSTANCE_ID='999?callback_token=testtoken0123456789' \
    APPBOX_CALLBACK_BASE="http://127.0.0.1:${port}" \
    APPBOX_CALLBACK_RETRY_DELAY=1 \
    "$@" "${helper}" >"${work}/output" 2>&1
  rc=$?

  kill "${server}" 2>/dev/null
  wait "${server}" 2>/dev/null
  requests=$(cat "${work}/requests" 2>/dev/null | wc -l | tr -d ' ')
  leaked=$(grep -c testtoken "${work}/output")

  if [ "${rc}" = "${want_exit}" ] && [ "${requests}" = "${want_requests}" ] && [ "${leaked}" = 0 ]; then
    echo "ok   codes=${codes} exit=${rc} requests=${requests}"
  else
    echo "FAIL codes=${codes} exit=${rc}/${want_exit} requests=${requests}/${want_requests} token_logged=${leaked}"
    sed 's/^/     /' "${work}/output"
    failures=$((failures + 1))
  fi
  rm -rf "${work}"
}

run_case 200 0 1
run_case 401 1 1
run_case 404 1 1
run_case 503,502,200 0 3
run_case 429,408,204 0 3
run_case 500,401 1 2
run_case 200 0 0 SKIP_APPBOX_CALLBACK=1

exit "${failures}"
