#!/bin/bash
# Appbox-required password recovery: updates ruTorrent, XML-RPC, and WebDAV basic-auth
# via the same helper as 025-set-passwd.sh.

set -euo pipefail

# shellcheck source=/usr/local/lib/rtorrent-web-auth.sh
source /usr/local/lib/rtorrent-web-auth.sh

NEW_PASSWORD="${1:-}"

if [[ -z "${NEW_PASSWORD}" ]]; then
  echo "Usage: /moduser.sh <new_password>"
  exit 1
fi

RU_USER="${RUTORRENT_USER:-${USERNAME:-}}"
if [[ -z "${RU_USER}" ]]; then
  if [[ -r /passwd/rutorrent.htpasswd ]] && grep -q '^[^#:]\+:' /passwd/rutorrent.htpasswd 2>/dev/null; then
    RU_USER="$(cut -d: -f1 /passwd/rutorrent.htpasswd | head -1)"
  fi
fi

if [[ -z "${RU_USER}" ]]; then
  echo "Could not determine username. Set RUTORRENT_USER or USERNAME, or ensure /passwd/rutorrent.htpasswd exists."
  exit 1
fi

echo "Updating basic-auth credentials for user: ${RU_USER}"
rtorrent_set_basic_auth "${RU_USER}" "${NEW_PASSWORD}"
echo "Password updated for ruTorrent, XML-RPC, and WebDAV."
