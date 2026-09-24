#!/usr/bin/with-contenv sh
# shellcheck shell=sh

echo "Fixing perms..."
mkdir -p /torrents/config/rtorrent \
  /torrents/config/rutorrent \
  /torrents/completed \
  /torrents/downloading \
  /torrents/watch \
  /passwd \
  /etc/nginx/conf.d \
  /etc/rtorrent \
  /var/cache/nginx \
  /var/lib/nginx \
  /var/log/nginx \
  /var/run/nginx \
  /var/run/php-fpm \
  /var/run/rtorrent
chown rtorrent:rtorrent \
  /torrents/config \
  /torrents/config/rtorrent \
  /torrents/config/rutorrent \
  /torrents/completed \
  /torrents/downloading \
  /torrents/watch
chown -R rtorrent:rtorrent \
  /etc/rtorrent \
  /passwd \
  /tpls \
  /var/cache/nginx \
  /var/lib/nginx \
  /var/log/nginx \
  /var/log/php85 \
  /var/run/nginx \
  /var/run/php-fpm \
  /var/run/rtorrent
