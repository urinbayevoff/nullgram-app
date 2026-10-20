#!/bin/bash
# Put Tepegram on the phone: its libraries (compiled there once), the API key,
# then the app itself through the ztOS SDK.
#
#   tools/deploy.sh [--libs] [--key]     (the app always; libraries/key when asked or missing)
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
OS=${OMONULLOS:-~/work/OmonullOS}
DEV=${ZTOS_DEVICE:-user@phone}
DATA='$HOME/.local/share/ztos/data/uz.omonullos.tepegram'
KEYFILE=${TG_API_ENV:-$HOME/.config/omonullos/tg-api.env}
libs=0 key=0
for a in "$@"; do case $a in --libs) libs=1;; --key) key=1;; esac; done

have=$(ssh "$DEV" "d=$DATA; [ -f \$d/vendor/VERSIONS ] && cat \$d/vendor/VERSIONS | md5sum | cut -c1-8; [ -f \$d/api.json ] && echo key" || true)
[ -d "$HERE/vendor" ] || python3 "$HERE/tools/vendor.py"
want=$(md5sum < "$HERE/vendor/VERSIONS" | cut -c1-8)
case $have in *"$want"*) ;; *) libs=1;; esac
case $have in *key*) ;; *) key=1;; esac

if [ $libs = 1 ]; then
	echo "libraries -> phone (compiled there)"
	tar cf - -C "$HERE" vendor | ssh "$DEV" "d=$DATA; mkdir -p \$d && rm -rf \$d/vendor.new && mkdir \$d/vendor.new && tar xf - -C \$d/vendor.new --strip-components=1 && python3 -m compileall -q -j 4 \$d/vendor.new && rm -rf \$d/vendor && mv \$d/vendor.new \$d/vendor && du -sh \$d/vendor"
fi
if [ $key = 1 ]; then
	echo "API key -> phone"
	# shellcheck disable=SC1090
	. "$KEYFILE"
	printf '{"id": %s, "hash": "%s"}\n' "$TG_API_ID" "$TG_API_HASH" | \
		ssh "$DEV" "d=$DATA; mkdir -p \$d && umask 077 && cat > \$d/api.json && chmod 600 \$d/api.json"
fi
cd "$HERE" && ZTOS_DEVICE=$DEV "$OS/sdk/bin/ztos-sdk" install
