#!/bin/sh
# On the phone: a screenshot of what is on the screen now, to /tmp/<name>.png
#   ssh user@phone sh -s <name> < tools/shot.sh
export XDG_RUNTIME_DIR=/run/user/$(id -u)
printf 'screen on\n' > $XDG_RUNTIME_DIR/ztmetro.ctl; sleep 1
WAYLAND_DISPLAY=wayland-0 grim -s ${2:-1} /tmp/${1:-shot}.png
