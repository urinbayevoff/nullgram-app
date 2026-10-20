#!/bin/sh
# On the phone: a tap at x y (points, 360×760), or with a third argument a swipe to x2 y2
#   ssh user@phone sh -s 180 400 < tools/tap.sh
export XDG_RUNTIME_DIR=/run/user/$(id -u)
C=$XDG_RUNTIME_DIR/ztmetro.ctl
s() { printf '%s\n' "$*" > $C; }
s down 1 $1 $2
if [ -n "${3:-}" ]; then
	n=8; i=1
	while [ $i -le $n ]; do
		s move 1 $(( $1 + ($3 - $1) * i / n )) $(( $2 + ($4 - $2) * i / n )); sleep 0.016; i=$((i + 1))
	done
else
	sleep 0.08
fi
s up 1
