#!/bin/sh
# Runs inside the image with no network. PHP's built-in server uses the same
# multipart/form-data parser (main/rfc1867.c) as php-fpm, so a normal upload
# must still populate $_POST and $_FILES after the parser is patched.
set -eu

smoke_dir=$(mktemp -d)
cat > "$smoke_dir/upload.php" <<'PHP'
<?php
echo count($_FILES), ':', $_FILES['f']['size'] ?? -1, ':', $_FILES['f']['error'] ?? -1, ':', $_POST['a'] ?? '';
PHP
printf 'hello' > "$smoke_dir/file.txt"

php85 -S 127.0.0.1:8089 -t "$smoke_dir" >/dev/null 2>&1 &
server_pid=$!
trap 'kill "$server_pid" 2>/dev/null || true; rm -rf "$smoke_dir"' EXIT

attempt=0
until curl -s -o /dev/null http://127.0.0.1:8089/upload.php; do
    attempt=$((attempt + 1))
    [ "$attempt" -lt 40 ] || { echo "PHP built-in server did not start" >&2; exit 1; }
    sleep 0.25
done

result=$(curl -s -F a=b -F "f=@$smoke_dir/file.txt" http://127.0.0.1:8089/upload.php)
if [ "$result" != "1:5:0:b" ]; then
    echo "multipart upload returned '$result', expected '1:5:0:b'" >&2
    exit 1
fi
echo "multipart upload through php85 CLI server ok"
