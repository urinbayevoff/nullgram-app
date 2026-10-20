#!/bin/sh
# On the phone: screen on and the lock screen swiped away (in an app the swipe
# only moves its list a little).
#   ssh user@phone sh -s < tools/wake.sh
export XDG_RUNTIME_DIR=/run/user/$(id -u)
C=$XDG_RUNTIME_DIR/ztmetro.ctl
s() { printf '%s\n' "$*" > $C; }
s "screen on"; sleep 1
s down 9 180 620; for y in 540 460 380 300 220 160; do s move 9 180 $y; sleep 0.016; done; s up 9; sleep 1.5
