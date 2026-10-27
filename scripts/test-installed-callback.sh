#!/usr/bin/env bash
# Exercise rootfs/usr/local/bin/appbox-installed-callback against a local mock
# API: retryable statuses back off up to the cap, any other rejection stops
# after one try, the callback token in INSTANCE_ID never reaches the log, and
# neither token is on curl's command line. APPBOX_CALLBACK_HELPER tests
# another copy of the helper (the release gate tests the one in the image).
set -u

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
helper="${APPBOX_CALLBACK_HELPER:-${repo_root}/rootfs/usr/local/bin/appbox-installed-callback}"

mock_server='
import http.server, json, os, sys, time
port, codes, log = int(sys.argv[1]), [int(c) for c in sys.argv[2].split(",")], sys.argv[3]
class Handler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        seen = sum(1 for _ in open(log)) if os.path.exists(log) else 0
        code = codes[min(seen, len(codes) - 1)]
        if code < 0:
            # A negative code answers -code after 3s, so the test can inspect
            # the running curl process.
            time.sleep(3)
            code = -code
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

# The full INSTANCE_ID, query token included, reaches the API path.
start_mock 200
run_helper "http://127.0.0.1:${port}"
rc=$?
stop_mock
ok=0
[ "${rc}" = 0 ] && grep -q '"path": "/v1/apps/installed/999?callback_token=testtoken0123456789"' "${work}/requests" && ok=1
check "INSTANCE_ID query token reaches the API path" "${ok}"

# Quotes and backslashes in the token survive curl's config syntax.
start_mock 200
run_helper "http://127.0.0.1:${port}" 'CALLBACK_TOKEN=tok"en\x'
rc=$?
stop_mock
ok=0
[ "${rc}" = 0 ] && grep -qF '"token_header": "tok\"en\\x"' "${work}/requests" && ok=1
check "CALLBACK_TOKEN with quote and backslash sent unchanged" "${ok}"

# Neither token appears on any process's command line while curl runs
# (Linux /proc only).
if [ -d /proc/self ]; then
  start_mock -200
  # Export the tokens (shell builtins) instead of run_helper's `env VAR=...`,
  # which would itself put them on a command line.
  (
    export INSTANCE_ID='999?callback_token=testtoken0123456789' \
      CALLBACK_TOKEN=testtokenheader \
      APPBOX_CALLBACK_BASE="http://127.0.0.1:${port}" \
      APPBOX_CALLBACK_RETRY_DELAY=1
    exec timeout 30 "${helper}"
  ) >"${work}/output" 2>&1 &
  helper_pid=$!
  seen_curl=0
  leaked=0
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    sleep 0.2
    for cmdline in /proc/[0-9]*/cmdline; do
      args=$(tr '\0' ' ' < "${cmdline}" 2>/dev/null) || continue
      case "${args}" in
        *testtoken*) leaked=1 ;;
      esac
      case "${args}" in
        curl\ *) seen_curl=1 ;;
      esac
    done
  done
  wait "${helper_pid}"
  rc=$?
  stop_mock
  ok=0
  [ "${rc}" = 0 ] && [ "${seen_curl}" = 1 ] && [ "${leaked}" = 0 ] && ok=1
  check "tokens not on the command line (curl seen=${seen_curl}, leaked=${leaked})" "${ok}"
fi

exit "${failures}"
