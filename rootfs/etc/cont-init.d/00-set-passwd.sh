#!/usr/bin/with-contenv bash
# shellcheck shell=bash

htpasswd -Bbn "${RUTORRENT_USER}" "${RUTORRENT_PASSWORD}" > /passwd/webdav.htpasswd
htpasswd -Bbn "${RUTORRENT_USER}" "${RUTORRENT_PASSWORD}" > /passwd/rutorrent.htpasswd
htpasswd -Bbn "${RUTORRENT_USER}" "${RUTORRENT_PASSWORD}" > /passwd/rpc.htpasswd