#!/usr/bin/with-contenv bash
# shellcheck shell=bash

rm -rf /tmp/*

RUTORRENT_USER="${RUTORRENT_USER:-${USERNAME:-rtorrent}}"

# Detect major version upgrade from old Appbox ruTorrent
# Note: 03-config.sh backs up legacy Appbox .rtorrent.rc to .rtorrent.rc.bak
# So we check both the current file and the backup
OLD_APPBOX_DETECTED=false
for rc_file in /torrents/config/rtorrent/.rtorrent.rc /torrents/config/rtorrent/.rtorrent.rc.bak; do
  if [ -f "$rc_file" ] && grep -q "Appbox ruTorrent" "$rc_file" 2>/dev/null; then
    OLD_APPBOX_DETECTED=true
    # Copy the old config if not already done
    if [ ! -f /torrents/config/rtorrent/.rtorrent.rc.old ]; then
      cp "$rc_file" /torrents/config/rtorrent/.rtorrent.rc.old
      echo "Backed up old Appbox config to .rtorrent.rc.old"
    fi
    break
  fi
done

# Also detect by presence of old user settings path (more reliable)
if [ -d "/torrents/config/rutorrent/users/${RUTORRENT_USER}/settings" ]; then
  OLD_APPBOX_DETECTED=true
fi

# Also detect by presence of html/ directory (old ruTorrent location)
if [ -d "/torrents/config/rutorrent/html" ]; then
  OLD_APPBOX_DETECTED=true
fi

if [ "$OLD_APPBOX_DETECTED" = true ]; then
  echo "=============================================="
  echo "UPGRADE DETECTED: Old Appbox ruTorrent"
  echo "=============================================="
  echo ""
  echo "The old version used rTorrent 0.9.6 with different session format."
  echo ""
  echo "IMPORTANT: Your completed torrents may show '/downloading' as directory"
  echo "even though data is still in '/completed'. This is due to session format"
  echo "differences between rTorrent 0.9.6 and 0.15.7."
  echo ""
  echo "TO FIX THIS:"
  echo "  1. In ruTorrent, select affected torrents"
  echo "  2. Right-click -> Set Download Directory -> /torrents/completed"
  echo "  3. Right-click -> Force Recheck"
  echo ""
  echo "Or simply remove and re-add the torrent (data won't be deleted)."
  echo "=============================================="
  echo ""
fi

mkdir -p /torrents/config/autodl

chown rtorrent:rtorrent \
  /torrents/config/autodl

# Migrate autodl-irssi config from old location to new location
# Old location: /torrents/config/autodl-irssi/autodl/
# New location: /torrents/config/autodl/
if [ -d /torrents/config/autodl-irssi/autodl ] && [ ! -L /torrents/config/autodl-irssi/autodl ]; then
  echo "Autodl-irssi config directory found, migrating to new location..."
  
  # Extract existing port/password from user's config BEFORE moving
  if [ -f /torrents/config/autodl-irssi/autodl/autodl.cfg ]; then
    AUTODL_PORT=$(grep "gui-server-port" /torrents/config/autodl-irssi/autodl/autodl.cfg 2>/dev/null | awk '{print $3}' | tr -d '\r')
    AUTODL_PASS=$(grep "gui-server-password" /torrents/config/autodl-irssi/autodl/autodl.cfg 2>/dev/null | awk '{print $3}' | tr -d '\r')
    echo "  Preserving existing autodl port: ${AUTODL_PORT:-not set}"
  fi
  
  # Move files to new location
  mv /torrents/config/autodl-irssi/autodl/* /torrents/config/autodl 2>/dev/null || true
  rm -rf /torrents/config/autodl-irssi/autodl
  
  # Create symlink for backward compatibility (allows downgrade to work)
  mkdir -p /torrents/config/autodl-irssi
  ln -sf /torrents/config/autodl /torrents/config/autodl-irssi/autodl
  echo "  Created backward-compatible symlink for downgrade support"
  
  # If we extracted port/password, ensure they're set in the new location
  # Otherwise use defaults
  if [ -n "${AUTODL_PORT}" ] && [ "${AUTODL_PORT}" != "0" ]; then
    sed -i "/gui-server-port/ c\gui-server-port = ${AUTODL_PORT}" /torrents/config/autodl/autodl.cfg
  else
    AUTODL_PORT=36001
    sed -i "/gui-server-port/ c\gui-server-port = ${AUTODL_PORT}" /torrents/config/autodl/autodl.cfg
  fi
  
  if [ -n "${AUTODL_PASS}" ] && [ "${AUTODL_PASS}" != "" ]; then
    sed -i "/gui-server-password/ c\gui-server-password = ${AUTODL_PASS}" /torrents/config/autodl/autodl.cfg
  else
    # Generate a random password for security
    AUTODL_PASS=$(head /dev/urandom | tr -dc 'a-zA-Z0-9' | head -c 16)
    sed -i "/gui-server-password/ c\gui-server-password = ${AUTODL_PASS}" /torrents/config/autodl/autodl.cfg
  fi
  
  # Update the autodl-rutorrent plugin conf.php to match
  AUTODL_CONF="/var/www/rutorrent/plugins/autodl-rutorrent/conf.php"
  if [ -f "${AUTODL_CONF}" ]; then
    sed -i "s/\$autodlPort = [0-9]*;/\$autodlPort = ${AUTODL_PORT};/" "${AUTODL_CONF}"
    sed -i "s/\$autodlPassword = \"[^\"]*\";/\$autodlPassword = \"${AUTODL_PASS}\";/" "${AUTODL_CONF}"
    echo "  Updated autodl-rutorrent plugin conf.php with preserved settings"
  fi
fi

# Ensure backward-compatible symlink exists even if migration already happened
if [ -d /torrents/config/autodl ] && [ ! -e /torrents/config/autodl-irssi/autodl ]; then
  mkdir -p /torrents/config/autodl-irssi
  ln -sf /torrents/config/autodl /torrents/config/autodl-irssi/autodl
fi

# Handle session directory compatibility (old: session/, new: .session/)
# IMPORTANT: Do NOT move files - this can corrupt session data between rTorrent versions
# Instead, create symlinks so both paths work
echo "Setting up session directory compatibility..."
echo "  Checking /torrents/config/rtorrent/session: $(ls -la /torrents/config/rtorrent/session 2>&1 | head -1)"
echo "  Checking /torrents/config/rtorrent/.session: $(ls -la /torrents/config/rtorrent/.session 2>&1 | head -1)"

if [ -d /torrents/config/rtorrent/session ] && [ ! -L /torrents/config/rtorrent/session ]; then
  # Old 'session/' directory exists as real directory - keep it, symlink .session to it
  if [ "$(ls -A /torrents/config/rtorrent/session 2>/dev/null)" ]; then
    echo "  Found session/ directory with files"
    # Remove .session if it exists (symlink or empty dir) to recreate it
    if [ -L /torrents/config/rtorrent/.session ]; then
      echo "  Removing existing .session symlink"
      rm -f /torrents/config/rtorrent/.session
    elif [ -d /torrents/config/rtorrent/.session ]; then
      if [ ! "$(ls -A /torrents/config/rtorrent/.session 2>/dev/null)" ]; then
        echo "  Removing empty .session directory"
        rm -rf /torrents/config/rtorrent/.session
      else
        echo "  WARNING: .session has files but session/ also has files - keeping both"
      fi
    fi
    if [ ! -e /torrents/config/rtorrent/.session ]; then
      ln -sf session /torrents/config/rtorrent/.session
      echo "  Created symlink: .session -> session"
    fi
  else
    # Empty old directory - remove it and create .session
    echo "  Found empty session/ directory, switching to .session/"
    rm -rf /torrents/config/rtorrent/session
    mkdir -p /torrents/config/rtorrent/.session
    ln -sf .session /torrents/config/rtorrent/session
    echo "  Created symlink: session -> .session"
  fi
elif [ -d /torrents/config/rtorrent/.session ] && [ ! -L /torrents/config/rtorrent/.session ]; then
  # Only .session exists as real directory - create session symlink for compatibility
  echo "  Found .session/ directory, creating session symlink"
  if [ -e /torrents/config/rtorrent/session ]; then
  rm -rf /torrents/config/rtorrent/session
  fi
  ln -sf .session /torrents/config/rtorrent/session
  echo "  Created symlink: session -> .session"
else
  # Neither exists - create .session and symlink
  echo "  No session directory found, creating .session/"
  mkdir -p /torrents/config/rtorrent/.session
  ln -sf .session /torrents/config/rtorrent/session 2>/dev/null || true
  echo "  Created symlink: session -> .session"
fi

# Verify session directory setup
echo "Session directory verification:"
if [ -L /torrents/config/rtorrent/.session ]; then
  echo "  .session: symlink -> $(readlink /torrents/config/rtorrent/.session)"
elif [ -d /torrents/config/rtorrent/.session ]; then
  echo "  .session: directory"
else
  echo "  .session: not found"
fi
if [ -L /torrents/config/rtorrent/session ]; then
  echo "  session: symlink -> $(readlink /torrents/config/rtorrent/session)"
elif [ -d /torrents/config/rtorrent/session ]; then
  echo "  session: directory"
else
  echo "  session: not found"
fi
SESSION_FILES=$(ls /torrents/config/rtorrent/.session/*.torrent 2>/dev/null | wc -l)
echo "  Torrent files in session: ${SESSION_FILES}"

# If we're upgrading from old Appbox, show session file info
if [ "$OLD_APPBOX_DETECTED" = true ] && [ "$SESSION_FILES" -gt 0 ]; then
  echo ""
  echo "Session files found from previous installation:"
  for f in /torrents/config/rtorrent/.session/*.rtorrent; do
    if [ -f "$f" ]; then
      HASH=$(basename "$f" .torrent.rtorrent)
      # Extract directory from session file (bencode format)
      DIR=$(cat "$f" 2>/dev/null | tr -d '\0' | grep -oP 'directory\d+:\K[^0-9]+' | head -1)
      echo "  $HASH: $DIR"
    fi
  done 2>/dev/null || true
  echo ""
fi

chown -R rtorrent:rtorrent /torrents/config/rtorrent/.session 2>/dev/null || true
chown -R rtorrent:rtorrent /torrents/config/rtorrent/session 2>/dev/null || true

echo "Setting up autodl configuration..."
mkdir -p /home/rtorrent/.autodl

if [ ! -f /torrents/config/autodl/autodl.cfg ]; then
  # No config exists yet - use the default from image
  if [ -f /home/rtorrent/.autodl/autodl.cfg ]; then
    echo "  Moving default autodl.cfg to persistent storage..."
  mv /home/rtorrent/.autodl/autodl.cfg /torrents/config/autodl/autodl.cfg
  fi
fi

# Ensure symlink exists for autodl to find the config
  ln -sf /torrents/config/autodl/autodl.cfg /home/rtorrent/.autodl/autodl.cfg

# Sync autodl-rutorrent plugin conf.php with existing autodl.cfg settings
if [ -f /torrents/config/autodl/autodl.cfg ]; then
  AUTODL_PORT=$(grep "gui-server-port" /torrents/config/autodl/autodl.cfg 2>/dev/null | awk '{print $3}' | tr -d '\r')
  AUTODL_PASS=$(grep "gui-server-password" /torrents/config/autodl/autodl.cfg 2>/dev/null | awk '{print $3}' | tr -d '\r')
  
  AUTODL_CONF="/var/www/rutorrent/plugins/autodl-rutorrent/conf.php"
  if [ -f "${AUTODL_CONF}" ] && [ -n "${AUTODL_PORT}" ] && [ -n "${AUTODL_PASS}" ]; then
    sed -i "s/\$autodlPort = [0-9]*;/\$autodlPort = ${AUTODL_PORT};/" "${AUTODL_CONF}"
    sed -i "s/\$autodlPassword = \"[^\"]*\";/\$autodlPassword = \"${AUTODL_PASS}\";/" "${AUTODL_CONF}"
    echo "  Synced autodl-rutorrent plugin with port ${AUTODL_PORT}"
  fi
fi

# Ensure user settings and torrents directories exist with proper permissions
mkdir -p /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings
mkdir -p /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/torrents
chown -R rtorrent:rtorrent /torrents/config/rutorrent/share/users/${RUTORRENT_USER}
chmod 770 /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/torrents

# Migrate settings from old path (/users/) to new path (/share/users/) if needed
OLD_SETTINGS_PATH="/torrents/config/rutorrent/users/${RUTORRENT_USER}/settings"
NEW_SETTINGS_PATH="/torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings"
if [ -d "${OLD_SETTINGS_PATH}" ]; then
  echo "Found old settings directory, migrating to new location..."
  for file in "${OLD_SETTINGS_PATH}"/*.dat; do
    if [ -f "$file" ]; then
      filename=$(basename "$file")
      new_file="${NEW_SETTINGS_PATH}/${filename}"
      
      if [ ! -f "${new_file}" ]; then
        # New file doesn't exist - copy from old
        echo "  Migrating ${filename}..."
        cp "$file" "${new_file}"
      elif [ "$file" -nt "${new_file}" ]; then
        # Old file is newer - copy from old
        echo "  Updating ${filename} (old version is newer)..."
        cp "$file" "${new_file}"
      elif [ "${filename}" = "autotools.dat" ]; then
        # Special handling for autotools.dat:
        # If old has enable_move=1 and new has enable_move=0, use old settings
        # This preserves user's explicit choice to enable automove
        old_move=$(grep -o 'enable_move";s:[0-9]*:"[01]"' "$file" | grep -o '"[01]"' | tr -d '"')
        new_move=$(grep -o 'enable_move";s:[0-9]*:"[01]"' "${new_file}" | grep -o '"[01]"' | tr -d '"')
        if [ "${old_move}" = "1" ] && [ "${new_move}" = "0" ]; then
          echo "  Restoring ${filename} (old had automove enabled, new has it disabled)..."
          cp "$file" "${new_file}"
        fi
      fi
    fi
  done
  chown -R rtorrent:rtorrent "${NEW_SETTINGS_PATH}"
fi

# ruTorrent's RSS plugin stores feed subscriptions under profilePath/rss/cache.
# Old Appbox used profilePath=/torrents/config/rutorrent; this image uses
# profilePath=/torrents/config/rutorrent/share. Keep both paths pointed at the
# same data so upgrades and downgrades preserve RSS feeds.
OLD_RSS_PATH="/torrents/config/rutorrent/rss"
NEW_RSS_PATH="/torrents/config/rutorrent/share/rss"
if [ -e "${OLD_RSS_PATH}" ] && [ ! -L "${OLD_RSS_PATH}" ]; then
  echo "Found old RSS profile directory, migrating to shared profile path..."
  mkdir -p "${NEW_RSS_PATH}"

  if [ -d "${OLD_RSS_PATH}" ]; then
    for file in "${OLD_RSS_PATH}"/cache/*; do
      if [ -f "$file" ]; then
        filename=$(basename "$file")
        new_file="${NEW_RSS_PATH}/cache/${filename}"
        mkdir -p "${NEW_RSS_PATH}/cache"

        if [ ! -f "${new_file}" ]; then
          echo "  Migrating RSS cache ${filename}..."
          cp -a "$file" "${new_file}"
        elif [ "$file" -nt "${new_file}" ]; then
          echo "  Updating RSS cache ${filename} from old profile..."
          cp -a "${new_file}" "${new_file}.bak"
          cp -a "$file" "${new_file}"
        fi
      fi
    done

    backup_path="${OLD_RSS_PATH}.pre-share-migration"
    if [ ! -e "${backup_path}" ]; then
      mv "${OLD_RSS_PATH}" "${backup_path}"
      echo "  Backed up old RSS directory to ${backup_path}"
    else
      rm -rf "${OLD_RSS_PATH}"
    fi
  else
    rm -f "${OLD_RSS_PATH}"
  fi
fi

mkdir -p "${NEW_RSS_PATH}/cache"
if [ ! -e "${OLD_RSS_PATH}" ]; then
  ln -sf "share/rss" "${OLD_RSS_PATH}"
  echo "Created RSS downgrade compatibility symlink: ${OLD_RSS_PATH} -> share/rss"
fi
chown -R rtorrent:rtorrent "${NEW_RSS_PATH}"

if [ ! -f "/torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/theme.dat" ]; then
    echo "Adding theme.dat..."
    echo 'O:6:"rTheme":3:{s:4:"hash";s:9:"theme.dat";s:8:"modified";b:0;s:7:"current";s:6:"appbox";}' > /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/theme.dat
fi

# autotools.dat - check old path first, then template
OLD_AUTOTOOLS="${OLD_SETTINGS_PATH}/autotools.dat"
NEW_AUTOTOOLS="${NEW_SETTINGS_PATH}/autotools.dat"
if [ ! -f "${NEW_AUTOTOOLS}" ]; then
  if [ -f "${OLD_AUTOTOOLS}" ]; then
    echo "Copying autotools.dat from old settings..."
    cp "${OLD_AUTOTOOLS}" "${NEW_AUTOTOOLS}"
  else
    echo "Adding autotools.dat from template..."
    cp /tpls/autotools.dat "${NEW_AUTOTOOLS}"
  fi
elif ! grep -q '/watch' "${NEW_AUTOTOOLS}"; then
  # Corrupted or incomplete file - restore from old or template
  if [ -f "${OLD_AUTOTOOLS}" ]; then
    echo "Restoring autotools.dat from old settings (current is corrupted)..."
    cp "${OLD_AUTOTOOLS}" "${NEW_AUTOTOOLS}"
  else
    echo "Restoring autotools.dat from template (current is corrupted)..."
    cp /tpls/autotools.dat "${NEW_AUTOTOOLS}"
  fi
fi

# WebUISettings.dat
if [ ! -f /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/WebUISettings.dat ]; then
  echo "Adding WebUISettings.dat..."
  cp /tpls/WebUISettings.dat /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/WebUISettings.dat
elif ! grep -q '"webui.ignore_timeouts":1' /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/WebUISettings.dat; then
  echo "Adding WebUISettings.dat..."
  cp /tpls/WebUISettings.dat /torrents/config/rutorrent/share/users/${RUTORRENT_USER}/settings/WebUISettings.dat
fi

# Only create rtorrent symlink if RUTORRENT_USER is different from rtorrent
# This avoids duplicate user directories that cause autotools to register twice
if [ "${RUTORRENT_USER}" != "rtorrent" ]; then
  # If /torrents/config/rutorrent/share/users/rtorrent is a directory (not symlink), remove it
  if [ -d /torrents/config/rutorrent/share/users/rtorrent ] && [ ! -L /torrents/config/rutorrent/share/users/rtorrent ]; then
    echo "Removing old rtorrent directory (using ${RUTORRENT_USER} instead)..."
  rm -rf /torrents/config/rutorrent/share/users/rtorrent
fi
  # Note: We intentionally do NOT create a symlink to avoid autotools registering twice
fi

chown -R rtorrent:rtorrent /torrents/config/rutorrent/share/users/${RUTORRENT_USER}
# Only chown rtorrent symlink if it exists
if [ -e /torrents/config/rutorrent/share/users/rtorrent ]; then
chown rtorrent:rtorrent /torrents/config/rutorrent/share/users/rtorrent
fi

chown -R rtorrent:rtorrent /torrents/config/autodl
chown -R rtorrent:rtorrent /home/rtorrent/.autodl

# Ensure irssi directory exists with correct permissions
# TLS is handled by patched AutoConnector.pm (-notls flag when SSL disabled)
mkdir -p /home/rtorrent/.irssi
chown -R rtorrent:rtorrent /home/rtorrent/.irssi

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
ln -sf /var/www/rutorrent/plugins/filemanager-share/share.php /var/www/rutorrent/no-auth/share.php

# Configure filemanager-share plugin with encryption key and endpoint
if [ -f /var/www/rutorrent/plugins/filemanager-share/conf.php ]; then
  # Generate a random key if not set
  FLM_SHARE_KEY=${RU_FLM_SHARE_KEY:-$(head -c 32 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 32)}
  FLM_SHARE_ENDPOINT="${EXTERNAL_DOMAIN}/no-auth/share.php"
  
  # Create a custom conf.php with the key and endpoint
  cat > /var/www/rutorrent/plugins/filemanager-share/conf.php <<EOFCONF
<?php
\$conf['duration'] = \$_ENV['RU_FLM_SHARE_MAX_DURATION'] ?? 24;
\$conf['links'] = \$_ENV['RU_FLM_SHARE_MAX_LINKS'] ?? 0;

return [
    'limits' => \$conf,
    'require_password' => false,
    'endpoint' => '${FLM_SHARE_ENDPOINT}',
    'key' => '${FLM_SHARE_KEY}',
    'remove_share_on_file_delete' => false,
    'purge_expired_shares' => true
];
EOFCONF
  chown rtorrent:rtorrent /var/www/rutorrent/plugins/filemanager-share/conf.php
fi
sed -i "s/true/false/g" /var/www/rutorrent/plugins/_getdir/conf.php

# Disable unnecessary plugins
echo "Disabling cpuload plugin..."
if [ -f /var/www/rutorrent/conf/plugins.ini ]; then
  if ! grep -q "\[cpuload\]" /var/www/rutorrent/conf/plugins.ini; then
    echo "" >> /var/www/rutorrent/conf/plugins.ini
    echo "[cpuload]" >> /var/www/rutorrent/conf/plugins.ini
    echo "enabled = no" >> /var/www/rutorrent/conf/plugins.ini
  fi
fi

if [ -z "${INSTANCE_ID:-}" ]; then
  exit 0
fi

callback_installed() {
  if [ "${SKIP_APPBOX_CALLBACK:-0}" = "1" ]; then
    return 0
  fi

  CALLBACK_BASE="${APPBOX_CALLBACK_BASE:-https://api.cylo.net}"
  callback_headers=(
    -H "Accept: application/json"
    -H "Content-Type:application/json"
  )
  if [ -n "${CALLBACK_TOKEN:-}" ]; then
    callback_headers+=(-H "Authorization: Bearer ${CALLBACK_TOKEN}")
  fi
  until curl -fsS -o /dev/null \
    "${callback_headers[@]}" \
    -X POST "${CALLBACK_BASE}/v1/apps/installed/${INSTANCE_ID}"; do
    sleep 5
  done
}

if [ ! -f /etc/app_configured ]; then
  touch /etc/app_configured
  callback_installed
fi