#!/usr/bin/with-contenv bash
# shellcheck shell=bash

set -euo pipefail

# shellcheck source=/usr/local/lib/rtorrent-web-auth.sh
source /usr/local/lib/rtorrent-web-auth.sh

RU_USER="${RUTORRENT_USER:-${USERNAME:-}}"
RU_PASS="${RUTORRENT_PASSWORD:-${PASSWORD:-}}"

if [[ -n "${RU_USER}" && -n "${RU_PASS}" ]]; then
  rtorrent_set_basic_auth "${RU_USER}" "${RU_PASS}"
fi