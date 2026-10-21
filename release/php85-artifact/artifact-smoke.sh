#!/bin/sh
# Runs as root inside a throwaway alpine:3.24 container started by
# verify-artifact.sh, with the extracted artifact at /artifact (read-only)
# and network access for Alpine's own dependency packages.
#
# Usage: artifact-smoke.sh <expected-php-version> <expected-package-version>
set -eu
php_version=$1
package_version=$2
repo=/artifact/packages/community
index=$repo/x86_64/APKINDEX.tar.gz

# Trust the artifact key in this throwaway container only. Alpine's index
# still has the older php85, so the artifact's packages win on version.
cp /artifact/keys/*.rsa.pub /etc/apk/keys/

echo "-- signatures"
for apk_file in "$repo"/x86_64/*.apk; do
    apk verify "$apk_file" >/dev/null || { echo "signature check failed: $apk_file" >&2; exit 1; }
done
echo "$(ls "$repo"/x86_64/*.apk | wc -l) packages verify against the artifact key"

echo "-- install every runtime package from the artifact"
packages=$(tar -xzOf "$index" APKINDEX | sed -n 's/^P://p' | grep -v -E -- '-(dbg|doc|dev)$' | sort)
# shellcheck disable=SC2086
apk add -q --no-cache --repository "$repo" $packages apache2 curl fcgi >/dev/null
installed=$(apk info -v | grep -E '^php85(-[a-z0-9_]+)*-[0-9]' | sort)
echo "$installed" | sed -E 's/^php85(-[a-z0-9_]+)*-//' | sort -u > /tmp/php85-versions
[ "$(cat /tmp/php85-versions)" = "$package_version" ] \
    || { echo "installed php85 versions: $(tr '\n' ' ' < /tmp/php85-versions), expected $package_version" >&2; exit 1; }
echo "$(echo "$installed" | wc -l) php85 packages installed, all $package_version"

echo "-- versions and modules"
[ "$(php85 -r 'echo PHP_VERSION;')" = "$php_version" ] || { php85 -v >&2; exit 1; }
[ "$(php-fpm85 -v | head -n 1 | awk '{print $2}')" = "$php_version" ] || { php-fpm85 -v >&2; exit 1; }
[ "$(php-cgi85 -v | head -n 1 | awk '{print $2}')" = "$php_version" ] || { php-cgi85 -v >&2; exit 1; }
php85 -m > /tmp/modules 2> /tmp/modules.err
if [ -s /tmp/modules.err ] || grep -q -i -E 'warning|unable to load' /tmp/modules; then
    cat /tmp/modules.err /tmp/modules >&2
    exit 1
fi
echo "php85 $php_version, $(grep -c -v -E '^\[|^$' /tmp/modules) modules load without warnings"

echo "-- configuration tests"
php-fpm85 -t 2>&1 | tail -n 1
httpd -t 2>&1 | tail -n 1
httpd -M 2>/dev/null | grep -q php_module || { echo "mod_php85 not loaded by apache2" >&2; exit 1; }

docroot=$(mktemp -d)
cat > "$docroot/upload.php" <<'PHP'
<?php
echo PHP_VERSION, '|', php_sapi_name(), '|', count($_FILES), '|', $_FILES['f']['size'] ?? -1, '|', $_FILES['f']['error'] ?? -1, '|', $_POST['a'] ?? '';
PHP
chmod 755 "$docroot"
chmod 644 "$docroot/upload.php"
printf 'hello' > /tmp/file.txt

echo "-- multipart through the CLI server"
php85 -S 127.0.0.1:8089 -t "$docroot" >/dev/null 2>&1 &
attempt=0
until curl -s -o /dev/null http://127.0.0.1:8089/upload.php; do
    attempt=$((attempt + 1)); [ "$attempt" -lt 40 ] || { echo "CLI server did not start" >&2; exit 1; }; sleep 0.25
done
result=$(curl -s -F a=b -F f=@/tmp/file.txt http://127.0.0.1:8089/upload.php)
[ "$result" = "$php_version|cli-server|1|5|0|b" ] || { echo "CLI server multipart returned '$result'" >&2; exit 1; }
echo "$result"

echo "-- multipart through php-fpm (FastCGI)"
sed -i 's|^listen = .*|listen = 127.0.0.1:9085|' /etc/php85/php-fpm.d/www.conf
php-fpm85 -D
boundary=gate$$
printf -- '--%s\r\nContent-Disposition: form-data; name="a"\r\n\r\nb\r\n--%s\r\nContent-Disposition: form-data; name="f"; filename="x.txt"\r\nContent-Type: text/plain\r\n\r\nhello\r\n--%s--\r\n' \
    "$boundary" "$boundary" "$boundary" > /tmp/body
attempt=0
until result=$(REQUEST_METHOD=POST CONTENT_TYPE="multipart/form-data; boundary=$boundary" \
        CONTENT_LENGTH=$(wc -c < /tmp/body) SCRIPT_FILENAME="$docroot/upload.php" \
        SCRIPT_NAME=/upload.php REQUEST_URI=/upload.php SERVER_PROTOCOL=HTTP/1.1 GATEWAY_INTERFACE=CGI/1.1 \
        cgi-fcgi -bind -connect 127.0.0.1:9085 < /tmp/body 2>/dev/null); do
    attempt=$((attempt + 1)); [ "$attempt" -lt 40 ] || { echo "php-fpm did not answer" >&2; exit 1; }; sleep 0.25
done
result=$(printf '%s' "$result" | tr -d '\r' | sed '1,/^$/d')
[ "$result" = "$php_version|fpm-fcgi|1|5|0|b" ] || { echo "php-fpm multipart returned '$result'" >&2; exit 1; }
echo "$result"

echo "-- multipart through apache2 + mod_php85"
sed -i "s|^DocumentRoot .*|DocumentRoot \"$docroot\"|; s|<Directory \"/var/www/localhost/htdocs\">|<Directory \"$docroot\">|; s|^Listen .*|Listen 127.0.0.1:8090|" /etc/apache2/httpd.conf
httpd -t 2>&1 | tail -n 1
httpd -k start
attempt=0
until curl -s -o /dev/null http://127.0.0.1:8090/upload.php; do
    attempt=$((attempt + 1)); [ "$attempt" -lt 40 ] || { echo "apache2 did not start" >&2; exit 1; }; sleep 0.25
done
result=$(curl -s -F a=b -F f=@/tmp/file.txt http://127.0.0.1:8090/upload.php)
[ "$result" = "$php_version|apache2handler|1|5|0|b" ] || { echo "apache2 multipart returned '$result'" >&2; exit 1; }
echo "$result"
echo "artifact smoke test passed"
