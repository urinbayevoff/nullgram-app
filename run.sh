#!/bin/sh
# Nullgram on the phone, started from here: install it, stop the one running, start it again.
#   ./run.sh [--test-dc]        (log: ssh user@phone tail -f /tmp/nullgram.log)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DEV=${ZTOS_DEVICE:-user@phone}
"$HERE/install.sh"
ssh "$DEV" sh -s "$*" "${NULLGRAM_TEST_PHONE:-}" <<'S'
pkill -f '[n]ullgram/nullgram.py'; sleep 0.5
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0 NULLGRAM_TEST_PHONE=$2
setsid -f $HOME/.local/share/ztos/apps/uz.omonullos.nullgram $1 < /dev/null
sleep 3; tail -5 /tmp/nullgram.log
S
