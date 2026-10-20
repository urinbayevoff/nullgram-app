#!/bin/sh
# Nullgram on the phone, started from here: install it, stop the one running, start it again.
#   ./run.sh [--test-dc]        (NULLGRAM_OPEN=<chat id>: open that chat; log: ssh user@phone tail -f /tmp/nullgram.log)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DEV=${ZTOS_DEVICE:-user@phone}
"$HERE/install.sh"
# (as variables: ssh joins its arguments with spaces, an empty one would vanish)
ssh "$DEV" "A='$*' T='${NULLGRAM_TEST_PHONE:-}' O='${NULLGRAM_OPEN:-}' sh -s" <<'S'
pkill -f '[n]ullgram/nullgram.py'; sleep 0.5
export XDG_RUNTIME_DIR=/run/user/$(id -u) WAYLAND_DISPLAY=wayland-0 NULLGRAM_TEST_PHONE=$T NULLGRAM_OPEN=$O
setsid -f $HOME/.local/share/ztos/apps/uz.omonullos.nullgram $A < /dev/null
sleep 3; tail -5 /tmp/nullgram.log
S
