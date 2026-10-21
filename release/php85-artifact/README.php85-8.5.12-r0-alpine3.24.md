# php-artifacts: php85 8.5.12-r0 for Alpine 3.24 (x86_64)

Image: `repo.cylo.net/php-artifacts:php85-8.5.12-r0-alpine3.24` (FROM scratch;
nothing runs from it). Pin it by digest and mount or copy from it.

Alpine's v3.24 community index still had php85 8.5.11-r0 when PHP 8.5.12 was
released on 21 October 2026 (CVE-2026-109618 / GHSA-w8hw-w9fx-j79w and
CVE-2026-109619 / GHSA-6wmf-4rv5-p3rp, multipart/form-data parsing; Alpine's
APKBUILD secfixes comment lists GHSA-7875-c8px-7q5f for the second CVE, php-src's
advisory is GHSA-6wmf-4rv5-p3rp). These are
Alpine's own php85 packages, built by us from Alpine's APKBUILD and signed
with our own key.

## Contents

- `/packages/community/x86_64/*.apk` and `APKINDEX.tar.gz`: an apk repository
  of all 63 php85 subpackages, version 8.5.12-r0. The index and every
  package are signed with the key below.
- `/keys/cylo-php85-20261021161817.rsa.pub`: the public signing key
  (RSA 4096; SHA-256 of the DER public key
  `87291a8f5b8aad9a7a8cd4c3a1338a55e6e45779629f9069c1e512633dd70a71`).
  The private key is not in this image. It is kept only on the builder
  (`/home/appbox/php-artifact-keys/`, mode 700) and in the release operator's
  scratch copy.
- `/SHA256SUMS`: SHA-256 of every file under `/packages` and `/keys`.
- `/build-info.txt`, `/build-environment-packages.txt`: the build container's
  Alpine release, apk-tools, and every installed package (makedepends
  included) at build time.

## Provenance

- Source: `https://www.php.net/distributions/php-8.5.12.tar.xz`
  - SHA-256 `08bc2eba2a588654ade1357174aa646b761556c862dda0678345ee29ed481209`
    (matches php.net's releases JSON)
  - SHA-512 `0a6615373cb4842a3e99632e0903f062f89410ffdc63fc754218ac64de7263119df3af2ec2570457fdc1c3108e5eecd9569dd3bab2769d8d280361bd5e25025b`
    (matches the APKBUILD)
  - `php-8.5.12.tar.xz.asc`: good signature from
    `D95C 03BC 702B E951 5344 AE33 74E4 4BC9 0677 01A5` (Daniel Scherzer, a
    PHP 8.5 release manager listed on https://www.php.net/gpg-keys.php)
- Recipe: aports `community/php85` at commit
  `0161a10b0614476c3a2f6247c5c7903ecdef903e` ("community/php85: disable
  oom_rfc1867 tests needing shared extensions", MR !110201 for 3.24-stable).
  It is 3.24-stable's `f169399075e263e1dbf5cdc1843726562cd113c3`
  ("community/php85: security upgrade to 8.5.12", pkgver 8.5.12, pkgrel 0)
  plus two lines in `disabled-tests.list`:
  `tests/basic/oom_rfc1867_mb_encoding.phpt` and
  `tests/basic/oom_rfc1867_upload_progress.phpt`. Both are new 8.5.12 tests
  that start `php-cgi -n`, so the shared mbstring/session extensions are not
  loaded and the requests stay under the memory limit the tests expect to
  hit. Our first build failed on exactly these two tests before that commit
  existed. The APKBUILD, patches and every other source checksum are
  unchanged from Alpine.
- Build: `release/php85-artifact/build-in-alpine.sh` (abuild 3.17.0-r0, clang
  22.1.3, `abuild deps` then `abuild` as an unprivileged `abuild` group user)
  in `alpine@sha256:294b683cb724975bec92580e1e685676bd4b50bda910ddb8c51d4cabeaec77e6`
  (alpine:3.24, 3.24.2), started by `release/php85-artifact/node-build.sh` on
  cylo07.ata.ams3.nl.cylo.net in a throwaway container with
  `--cpu-shares 256`, from docker-rtorrent-rutorrent commit
  `57528d9b0b5b88cab7b019f48ea229f6e8825129`.
- PHP test suite (`check()`, 48 workers): 20801 tests, 19933 passed,
  0 failed, 857 skipped, 9 expected failures, 2 warned (XFAIL tests that
  passed: `sapi/phpdbg/tests/watch_006.phpt`,
  `sapi/fpm/tests/log-bwd-multiple-msgs-stdout-stderr.phpt`).
- Gate before push: `release/php85-artifact/verify-artifact.sh` (contents and
  SHA256SUMS, signature of every package, install of every runtime
  subpackage in alpine:3.24, all modules load, `php-fpm85 -t`, `httpd -t`,
  multipart upload through the CLI server, php-fpm and apache2 + mod_php85,
  registry tag absent).

## Use

Upgrade only the php85 packages an image already has, from this repository
alone (no network, its own key directory, nothing added to `/etc/apk/keys`):

```dockerfile
ARG PHP85_ARTIFACT=repo.cylo.net/php-artifacts@sha256:<digest>
FROM ${PHP85_ARTIFACT} AS php85-artifact
FROM <base image pinned by digest>
RUN --mount=type=bind,from=php85-artifact,source=/,target=/run/php85-artifact \
    apk --no-cache --no-network --repositories-file /dev/null \
        --repository /run/php85-artifact/packages/community \
        --keys-dir /run/php85-artifact/keys \
        upgrade $(apk info | grep -E '^php85(-|$)')
```

The packages link against Alpine 3.24 libraries by soname, as Alpine's own
build does. An install that needs a library the base image lacks fails
rather than fetching it.

## Packages (SHA-256)

```text
37347b3d5695866638b35bf7f66e9329ce546515ab66421c29b9b334a0d2e971  APKINDEX.tar.gz
eb9fd2af65ff00e26db312205259c10dcf09a5a07acbba0f9393864534c963d6  php85-8.5.12-r0.apk
a8b52f28a5936fb053cfddee0d5195a3f7083f7b51095724f4254742789b8364  php85-apache2-8.5.12-r0.apk
f8955699de46f829c41d2324374fbbe35b0de3813940ddc5a32c2a5d8b8c84f4  php85-bcmath-8.5.12-r0.apk
524622fdc7ab61638a47441190ce3d4d5fa58152d55389699ab7f9a7d0f845e7  php85-bz2-8.5.12-r0.apk
fa41d07520a2079059b006bb1c805e2a096cf8a093e713f038dca28748eb1b54  php85-calendar-8.5.12-r0.apk
cbb8fc2c86dc10a1fe79bc979d0f97961fcb69903d09f7cb86dcc99b1cfa8f1c  php85-cgi-8.5.12-r0.apk
25534aec4507ed89e08af547173e37ec40e67acae8dcfb3f4306831035b61c93  php85-common-8.5.12-r0.apk
48af8329646b6c030b55edfe957db9534c25a81a5165dc56cc912979abedf289  php85-ctype-8.5.12-r0.apk
d73b42779457677e54268a14adb9a80fc0a88f8cfcbe67f8ed6ea8446c326c9b  php85-curl-8.5.12-r0.apk
a4b74b578fd9d38520ae8228cab761636b9a582105277395607caee2941b92e3  php85-dba-8.5.12-r0.apk
6fad973e9eef191397535250883dad5015810553861fe3a7bdf919e9f9cd82e0  php85-dbg-8.5.12-r0.apk
6a65034d9a3a6c94c1d817a1435d5adc58367c6044ccec961df295b6702803ba  php85-dev-8.5.12-r0.apk
5cc26bf2f48bb40c2dc8feea126500e9eb54cc220dc1e8bb5e68dee6a3dacb86  php85-doc-8.5.12-r0.apk
3ddb513ccdbe791868541b189451a0f636ed06400ec371fb8e96d44eb146d807  php85-dom-8.5.12-r0.apk
cc52187b6ba1905555d6119beacae444b1d93afa22d4028e5f3982ad518e53c3  php85-embed-8.5.12-r0.apk
1d2855759478417a86626609c72e4f1cd5ddc620d62747577e23392f51e24c54  php85-enchant-8.5.12-r0.apk
e0e4a2e57498f6d26b09b973f425ec9892646e50be43b30183f02bd537b98c9d  php85-exif-8.5.12-r0.apk
49704e2c8fb4bfb3b5591a3fbcddba12ccd612e874d8a622d7d6de711bff982b  php85-ffi-8.5.12-r0.apk
9135d02a1a9e109390d05dec826cf00311a44cb54e5947043ae249834b28535a  php85-fileinfo-8.5.12-r0.apk
fc2e663db0b42672f28a35b033eb6e91aab41513c0bf94a1bd9cb266c024fbb5  php85-fpm-8.5.12-r0.apk
a28db4ec6ab82edfde2721b7e1ee0da6798499577f891cb18495fbcb63968e10  php85-ftp-8.5.12-r0.apk
8629b881b8a27121d465244ad1df4b6c45d3f844d7f2f9cbcf6eeba832e2751d  php85-gd-8.5.12-r0.apk
84a7f2d7deca4e45ca33ba66b8052eb167e30be0401c5ad24cc00d8b0f4a2e3b  php85-gettext-8.5.12-r0.apk
81f0ee4071a28055c416f2a4b541d1232151e1d95e5a792eb40bb96ed0140443  php85-gmp-8.5.12-r0.apk
a2637e01244de749a089f390af5a483b2a2bf2bf4a99f1a4e3bf82469f5fa95b  php85-iconv-8.5.12-r0.apk
3f6cdef665a67577427d061f7dcf49488c7484197d9918d595aa41b29704addc  php85-intl-8.5.12-r0.apk
7fab389942991af89991ee65f4e3c573663b9f8e5a3f6211bef0a9768b951441  php85-ldap-8.5.12-r0.apk
73c8924c67e6fada6b243366bfc53b6c21dd6d60ca5d0ac5ad548891190a9b61  php85-litespeed-8.5.12-r0.apk
b778583c5e4157a910b576b938a3796b71aab9cf39c59d58380c63cd80dbc3a1  php85-mbstring-8.5.12-r0.apk
531f3fe4c26e854c8393ebac0b8fa428e35451221acda75f36f0403f321b44b4  php85-mysqli-8.5.12-r0.apk
2ef4535e6227095069d23ca98fa5f23ff444df2ab2de9d687f5be44422f5fd8b  php85-mysqlnd-8.5.12-r0.apk
20138eda0e204d314c8bfb31ec1a5509fe6a69b9b118154c1665b40bc507e401  php85-odbc-8.5.12-r0.apk
b08c0a84b253443c23e718d9dd944e530c2b24eca179ccffdecf20a00ea2cbca  php85-openssl-8.5.12-r0.apk
91948cfaac0b7acc8f2f70e20bff60e836fd8eaf7975fbe6e9cadce08c3397ea  php85-pcntl-8.5.12-r0.apk
7c1de026dbb1ac33302f56492337421ed37a1d6b141840d310ca5c60f61f923f  php85-pdo-8.5.12-r0.apk
e3ec0e1a0d2be1c12ee15c120b84bdbf5240723515f11a12de0465c8805a77ec  php85-pdo_dblib-8.5.12-r0.apk
be506d13dc8ca876b4fc29d4dc81b9557084c147abdf15816a50e68dc1619fd6  php85-pdo_mysql-8.5.12-r0.apk
309bb302f3fe036a58e36800f4921d4f01adbbb1acd0f213fca1ce69dbb7bb07  php85-pdo_odbc-8.5.12-r0.apk
f53f347525bf1d570596a6035c98df620c6f05c3ad264b0fb6cc807777bbcee3  php85-pdo_pgsql-8.5.12-r0.apk
863363e7417009914ba688259aeb7e4453fd5c80f2abfa98e5e581b1a63925ac  php85-pdo_sqlite-8.5.12-r0.apk
fe7509e05ed5f5d4136ed041e8c11a0b21b2d729bfddca5be8028e92554f1a13  php85-pear-8.5.12-r0.apk
cca6c46eac1d7edf3403ce19d928538fafd6d44cacc85cc772c607bee5defbed  php85-pgsql-8.5.12-r0.apk
9605f1dd1e0ba8535cd23811b68a2c428f8ad408dd82e5d2d15d27c9cf5d3aa5  php85-phar-8.5.12-r0.apk
94870a1329355f512c3c4cab0f2475928de7ae1fa92cd541b15ddca2a524db5c  php85-phpdbg-8.5.12-r0.apk
747a69049cd117009d66ad9d672b5435d78ff0275c7f719d7ee9193d4f31bdd7  php85-posix-8.5.12-r0.apk
be2d551f01823b050e83258830da754b893c202af5af53084bdbcac99fb01031  php85-session-8.5.12-r0.apk
929ac71750eee5b9a13cafb0e2fc8366ec454b3315b1eff52c57d06969d9cc70  php85-shmop-8.5.12-r0.apk
bf3f3f20bf0feaf1ff0d619e47182e7fec3906e2c8e5c5c84834e000df5d0416  php85-simplexml-8.5.12-r0.apk
eadce576153784826363c691d927aa21c759a3649acfcf28f1feb1db4948a3c5  php85-snmp-8.5.12-r0.apk
be9913e8f72d094ee29f96eb8905282b1855f70d0c20f0d2f29c56ee59f86522  php85-soap-8.5.12-r0.apk
179e8dbee6aabbb32fca6c8fc3579cd4d4bb9e9bd7b9a29aeb08c097feff363b  php85-sockets-8.5.12-r0.apk
e276539054fad00fde7f8cb45afed3bef5ae69efdff3c9dfe04c118c65443038  php85-sodium-8.5.12-r0.apk
fa564ac12ae59b4d5b4935e7cc17acd7a4061aa5aea9814da75a89a28f560c13  php85-sqlite3-8.5.12-r0.apk
d43bbbe79522e75a4d2529e97521492dab7dedae0eb521de209aae5ffb848764  php85-sysvmsg-8.5.12-r0.apk
f8e8bfdc2cacb67c713e9adf962dcd8924ca990e7c70916b51fca760e4f24f1a  php85-sysvsem-8.5.12-r0.apk
492fe274ee65052132320033f294849bd87ddfe9b2adbbc37e6a5c3289ef2d68  php85-sysvshm-8.5.12-r0.apk
a9d45df7dff62fefb6fc5aecd7cb47442e87fe371243ccf900fde6793e8b2f62  php85-tidy-8.5.12-r0.apk
50a2b85915f71f63d052f2b3f74b7988863a681163b211eb2913f706d0573327  php85-tokenizer-8.5.12-r0.apk
f12e285b5bcf868060420e32b297aad7479cf9b0ce87363952a8354463c83bb8  php85-xml-8.5.12-r0.apk
45d4202dea9a7b809c5bb9693b2ad522740a3a99af138657c31edcc7ec782cfe  php85-xmlreader-8.5.12-r0.apk
1fccd744076d6ab71568a79a9c468abb709999c884976f757f638ad1796de16f  php85-xmlwriter-8.5.12-r0.apk
4bdf4480b53ab59850717aabc565b1478cd2ca98c3457af709b9ab5a5ddf712f  php85-xsl-8.5.12-r0.apk
d69a2377747c916995c4844a5b5cba0dcede0b3225fa3b21ddcab08686b1d83f  php85-zip-8.5.12-r0.apk
```
