# shellcheck shell=bash
# Shared by cont-init (`00-set-passwd.sh`, `025-set-passwd.sh`) and `/moduser.sh`.
# Keep ruTorrent, XML-RPC, and WebDAV basic-auth in sync.

rtorrent_set_basic_auth() {
  local ru_user="$1" ru_pass="$2"

  if [[ -z "${ru_user}" || -z "${ru_pass}" ]]; then
    echo "rtorrent_set_basic_auth: username and password are required" >&2
    return 1
  fi

  install -d -o rtorrent -g rtorrent /passwd

  local tmp
  tmp="$(mktemp)"
  if ! htpasswd -Bbn "${ru_user}" "${ru_pass}" > "${tmp}"; then
    rm -f "${tmp}"
    return 1
  fi

  install -m 644 -o rtorrent -g rtorrent "${tmp}" /passwd/rpc.htpasswd
  install -m 644 -o rtorrent -g rtorrent "${tmp}" /passwd/rutorrent.htpasswd
  install -m 644 -o rtorrent -g rtorrent "${tmp}" /passwd/webdav.htpasswd
  rm -f "${tmp}"
}
