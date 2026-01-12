#!/usr/bin/with-contenv bash
# shellcheck shell=bash

rm -rf /tmp/*

mkdir -p /torrents/config/autodl

chown rtorrent:rtorrent \
  /torrents/config/autodl

if [ -d /torrents/config/autodl-irssi/autodl ]; then
  echo "Autodl-irssi config directory found, moving to new location..."
  mv /torrents/config/autodl-irssi/autodl/* /torrents/config/autodl
  rm -rf /torrents/config/autodl-irssi

  sed -i "/gui-server-port/ c\gui-server-port = 36001" /torrents/config/autodl/autodl.cfg
  sed -i "/gui-server-password/ c\gui-server-password = 123456789" /torrents/config/autodl/autodl.cfg
fi

if [ -d /torrents/config/rtorrent/session ]; then
  echo "Session directory found, moving to new location..."
  mv /torrents/config/rtorrent/session/* /torrents/config/rtorrent/.session/
  rm -rf /torrents/config/rtorrent/session
fi

echo "Symlinking autodl autodl.cfg file..."
if [ ! -f /torrents/config/autodl/autodl.cfg ]; then
  mv /home/rtorrent/.autodl/autodl.cfg /torrents/config/autodl/autodl.cfg
  ln -sf /torrents/config/autodl/autodl.cfg /home/rtorrent/.autodl/autodl.cfg
fi

if [ ! -f /etc/app_configured ]; then
    echo "Adding theme.dat..."
    echo 'O:6:"rTheme":3:{s:4:"hash";s:9:"theme.dat";s:8:"modified";b:0;s:7:"current";s:13:"club-QuickBox";}' > /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/theme.dat
fi

if [ ! -f /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/autotools.dat ]; then
  echo "Adding autotools.dat..."
  cp /tpls/autotools.dat /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/autotools.dat
elif ! grep -q '/watch' /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/autotools.dat; then
  echo "Adding autotools.dat..."
  cp /tpls/autotools.dat /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/autotools.dat
fi

# WebUISettings.dat
if [ ! -f /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/WebUISettings.dat ]; then
  echo "Adding WebUISettings.dat..."
  cp /tpls/WebUISettings.dat /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/WebUISettings.dat
elif ! grep -q '"webui.ignore_timeouts":1' /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/WebUISettings.dat; then
  echo "Adding WebUISettings.dat..."
  cp /tpls/WebUISettings.dat /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/WebUISettings.dat
fi

# If /torrents/config/rutorrent/share/users/rtorrent is a directory and not a symlink, convert it to a symlink
if [ -d /torrents/config/rutorrent/share/users/rtorrent ]; then
  echo "Converting rtorrent directory to a symlink..."
  rm -rf /torrents/config/rutorrent/share/users/rtorrent
  ln -s /torrents/config/rutorrent/share/users/${RUTORRENT_USER} /torrents/config/rutorrent/share/users/rtorrent
fi

if [ ! -d /torrents/config/rutorrent/share/users/rtorrent ]; then
  echo "Creating symlink for rtorrent directory..."
  ln -s /torrents/config/rutorrent/share/users/${RUTORRENT_USER} /torrents/config/rutorrent/share/users/rtorrent
fi

chown -R rtorrent:rtorrent /torrents/config/rutorrent/share/users/${RUTORRENT_USER}
chown rtorrent:rtorrent /torrents/config/rutorrent/share/users/rtorrent

chown -R rtorrent:rtorrent /torrents/config/autodl
chown -R rtorrent:rtorrent /home/rtorrent/.autodl

mkdir -p /etc/services.d/irssi
cat > /etc/services.d/irssi/run <<EOL
#!/usr/bin/with-contenv bash
export HOME=/home/rtorrent
export PWD=/home/rtorrent
export TERM=xterm

if [ ! -d "/detach_sess" ]; then
mkdir -p /detach_sess
fi

if [ -f "/detach_sess/.irssi" ]; then
  rm -f /detach_sess/.irssi || true
  sleep 1s
fi

dtach -n /detach_sess/.irssi s6-setuidgid ${PUID}:${PGID} /usr/bin/irssi --home=/home/rtorrent/.irssi 1>/dev/null
sleep 1
EOL
chmod +x /etc/services.d/irssi/run

cat > /etc/services.d/irssi/run <<EOL
#!/usr/bin/with-contenv sh
export HOME=/home/rtorrent
export PWD=/home/rtorrent
export TERM=xterm

# Log that the script started
echo "Starting irssi service"

# Ensure the /detach_sess directory exists
mkdir -p /detach_sess
echo "Ensured /detach_sess directory exists"

while true; do
    # Check if irssi is already running in dtach
    if pgrep -f "dtach -n /detach_sess/.irssi" > /dev/null; then
        echo "Irssi is already running, waiting..."
        sleep 60  # Check again in 60 seconds
        continue
    fi

    # If no dtach session is found, clean up and start a new one
    if [ -e /detach_sess/.irssi ]; then
        rm -f /detach_sess/.irssi
        echo "Removed old session file if it existed"
    fi

    # Start irssi inside dtach
    dtach -n /detach_sess/.irssi s6-setuidgid ${PUID}:${PGID} /usr/bin/irssi --home=/home/rtorrent/.irssi
    echo "Started irssi in dtach"

    # Monitor the dtach session
    while pgrep -f "dtach -n /detach_sess/.irssi" > /dev/null; do
        sleep 5
    done

    echo "Irssi process ended, restarting..."
done
EOL

mkdir -p /etc/services.d/rtcheck
cat > /etc/services.d/rtcheck/run <<EOL
#!/usr/bin/execlineb -P
with-contenv
s6-setuidgid ${PUID}:${PGID}
/usr/local/bin/rtcheck
EOL
chmod +x /etc/services.d/rtcheck/run

mkdir -p /var/www/rutorrent/no-auth
ln -s /var/www/rutorrent/plugins/filemanager-share/share.php /var/www/rutorrent/no-auth/share.php
sed -i "/^\$downloadpath/ c\\\$downloadpath = '${EXTERNAL_DOMAIN}/noauth/share.php';" /var/www/rutorrent/plugins/filemanager-share/conf.php
sed -i "s/true/false/g" /var/www/rutorrent/plugins/_getdir/conf.php

if [ ! -f /etc/app_configured ]; then
    touch /etc/app_configured

    until curl -i -H "Accept: application/json" -H "Content-Type:application/json" -X POST "https://api.cylo.io/v1/apps/installed/${INSTANCE_ID}" | grep -q '200'
        do
        sleep 5
    done
fi