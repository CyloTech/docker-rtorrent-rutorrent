#!/usr/bin/env bash
# Exercise rootfs/usr/local/bin/appbox-installed-callback against a local mock
# API: retryable statuses back off up to the cap, any other rejection stops
# after one try, and the callback token in INSTANCE_ID never reaches the log.
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
            f.write(json.dumps({
                "path": self.path,
                "code": code,
                "token_header": self.headers.get("X-Cylo-Callback-Token"),
                "authorization": self.headers.get("Authorization"),
            }) + "\n")
        self.send_response(code)
        self.end_headers()
    def log_message(self, *args):
        pass
http.server.HTTPServer(("127.0.0.1", port), Handler).serve_forever()
'

failures=0
work=""
server=""

start_mock() {
  work="$(mktemp -d)"
  port=$((20000 + RANDOM % 20000))
  python3 -c "${mock_server}" "${port}" "$1" "${work}/requests" &
  server=$!
  sleep 0.5
}

stop_mock() {
  kill "${server}" 2>/dev/null
  wait "${server}" 2>/dev/null
}

# run_helper <base-url> [env...]: runs the helper with a hard time limit so a
# regression that retries forever fails the test instead of hanging it.
run_helper() {
  local base=$1
  shift
  timeout "${CASE_TIMEOUT:-30}" env \
    INSTANCE_ID='999?callback_token=testtoken0123456789' \
    APPBOX_CALLBACK_BASE="${base}" \
    APPBOX_CALLBACK_RETRY_DELAY=1 \
    "$@" "${helper}" >"${work}/output" 2>&1
}

check() {
  local name=$1 ok=$2
  if [ "${ok}" = 1 ] && ! grep -q testtoken "${work}/output"; then
    echo "ok   ${name}"
  else
    echo "FAIL ${name}"
    sed 's/^/     /' "${work}/output"
    failures=$((failures + 1))
  fi
  rm -rf "${work}"
}

requests() { cat "${work}/requests" 2>/dev/null | wc -l | tr -d ' '; }

# run_case <codes> <expected-exit> <expected-requests> [env...]
run_case() {
  local codes=$1 want_exit=$2 want_requests=$3 rc ok=0
  shift 3
  start_mock "${codes}"
  run_helper "http://127.0.0.1:${port}" "$@"
  rc=$?
  stop_mock
  [ "${rc}" = "${want_exit}" ] && [ "$(requests)" = "${want_requests}" ] && ok=1
  check "codes=${codes} exit=${rc} requests=$(requests) $*" "${ok}"
}

run_case 200 0 1
run_case 401 1 1
run_case 404 1 1
run_case 503,502,200 0 3
run_case 429,408,204 0 3
run_case 500,401 1 2
run_case 200 0 0 SKIP_APPBOX_CALLBACK=1

# Backoff doubles from the first delay and is clamped to the cap.
start_mock 503,503,503,200
run_helper "http://127.0.0.1:${port}" APPBOX_CALLBACK_MAX_RETRY_DELAY=2
rc=$?
stop_mock
delays=$(grep -o 'retrying in [0-9]*s' "${work}/output" | grep -o '[0-9]*' | tr '\n' ' ')
ok=0; [ "${rc}" = 0 ] && [ "${delays}" = "1 2 2 " ] && ok=1
check "backoff delays=${delays}(want 1 2 2)" "${ok}"

# An invalid first delay falls back to 5s instead of hot-looping.
start_mock 503,200
run_helper "http://127.0.0.1:${port}" APPBOX_CALLBACK_RETRY_DELAY=0
rc=$?
stop_mock
ok=0; [ "${rc}" = 0 ] && grep -q 'retrying in 5s' "${work}/output" && ok=1
check "invalid retry delay falls back to 5s" "${ok}"

# Network errors are retried, not treated as a rejection.
work="$(mktemp -d)"
CASE_TIMEOUT=4 run_helper "http://127.0.0.1:9"
rc=$?
ok=0; [ "${rc}" = 124 ] && [ "$(grep -c 'HTTP 000, retrying' "${work}/output")" -ge 2 ] && ok=1
check "network error keeps retrying (exit=${rc})" "${ok}"

# CALLBACK_TOKEN goes in the header cylo-api reads, not as a Bearer token.
start_mock 200
run_helper "http://127.0.0.1:${port}" CALLBACK_TOKEN=testtokenheader
rc=$?
stop_mock
ok=0
[ "${rc}" = 0 ] && grep -q '"token_header": "testtokenheader"' "${work}/requests" \
  && grep -q '"authorization": null' "${work}/requests" && ok=1
check "CALLBACK_TOKEN sent as X-Cylo-Callback-Token" "${ok}"

exit "${failures}"
