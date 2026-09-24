#!/usr/bin/with-contenv bash
# shellcheck shell=bash
# Runs after 02-fix-perms (so /passwd exists). Delegates to
# /usr/local/lib/rtorrent-web-auth.sh (shared with /moduser.sh).

set -euo pipefail

# shellcheck source=/usr/local/lib/rtorrent-web-auth.sh
source /usr/local/lib/rtorrent-web-auth.sh

RU_USER="${RUTORRENT_USER:-${USERNAME:-}}"
RU_PASS="${RUTORRENT_PASSWORD:-${PASSWORD:-}}"

if [[ -n "${RU_USER}" && -n "${RU_PASS}" ]]; then
  echo "Configuring HTTP basic auth for ruTorrent, XML-RPC, and WebDAV..."
  rtorrent_set_basic_auth "${RU_USER}" "${RU_PASS}"
else
  echo "No RUTORRENT_USER/USERNAME or password in environment; leaving /passwd as-is (populate manually or leave empty to disable auth)."
fi
