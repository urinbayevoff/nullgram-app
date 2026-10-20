#!/bin/sh
# On the phone: wake it, open Tepegram (profiler on), fling the chat list up and
# down; the app logs each motion's frames ("tepegram moved") and the profile.
#   ssh user@phone sh -s < tools/measure.sh [chat]   ("chat": also open the top chat and fling there)
export XDG_RUNTIME_DIR=/run/user/$(id -u)
C=$XDG_RUNTIME_DIR/ztmetro.ctl
A=$HOME/.local/share/ztos/apps/uz.omonullos.tepegram
LOG=$HOME/.local/share/ztos/data/uz.omonullos.tepegram/measure.log
s() { printf '%s\n' "$*" > $C; }
mkdir -p ~/.config/ztos; touch ~/.config/ztos/profile
s "screen on"; sleep 1
s down 9 180 620; for y in 540 460 380 300 220 160; do s move 9 180 $y; sleep 0.016; done; s up 9; sleep 1.5
pkill -f "apps/[u]z.omonullos.tepegram"; sleep 1
s launch $A; sleep 12
# a fling: finger from y0 to y1 in n steps of 16 ms
fling() { s down 1 180 $1; i=1; while [ $i -le $3 ]; do s move 1 180 $(( $1 + ($2 - $1) * i / $3 )); sleep 0.016; i=$((i + 1)); done; s up 1; }
frames() { rm -rf /tmp/ztrec; s "record $1"; sleep $(( $1 / 1000 + 1 )); }
for k in 1 2 3; do
	fling 600 200 8; sleep 2.2
done
for k in 1 2 3; do
	fling 200 650 8; sleep 2.2
done
for k in 1 2 3 4 5 6; do fling 550 350 12; done; sleep 1
sleep 2
if [ "$1" = chat ]; then
	fling 250 650 6; sleep 2
	echo "open chat $(date +%T.%N | cut -c1-12)"; s down 1 180 170; sleep 0.08; s up 1; sleep 6
	for k in 1 2 3; do fling 250 650 8; sleep 2; done
	for k in 1 2 3; do fling 650 250 8; sleep 2; done
	s down 1 60 740; sleep 0.08; s up 1; sleep 1
fi
rm -f ~/.config/ztos/profile
echo MEASURE-DONE
