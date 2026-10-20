#!/bin/sh
# Tepegram next on the phone: copy next/app over and start it there (fullscreen under ztmetro).
#   next/run.sh [--test-dc]        (stop it: ssh user@phone pkill -f tepegram-next/tepegram.py)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DEV=${ZTOS_DEVICE:-user@phone}
tar cf - -C "$HERE/app" --exclude=__pycache__ . | ssh "$DEV" 'rm -rf ~/tepegram-next && mkdir ~/tepegram-next && tar xf - -C ~/tepegram-next'
ssh "$DEV" "pkill -f '[t]epegram-next/tepegram.py'; export XDG_RUNTIME_DIR=/run/user/\$(id -u) WAYLAND_DISPLAY=wayland-0 QT_QPA_PLATFORM=wayland; \
	TEPEGRAM_TEST_PHONE=${TEPEGRAM_TEST_PHONE:-} nohup python3 ~/tepegram-next/tepegram.py $* > /tmp/tepegram-next.log 2>&1 & sleep 3; tail -5 /tmp/tepegram-next.log"
