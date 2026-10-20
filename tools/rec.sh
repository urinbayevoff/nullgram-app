#!/bin/sh
# On the phone: what is on the screen through the shell's own recorder (glReadPixels, a quarter of
# the pixels) -- grim fails while an app keeps drawing (a GIF, a video). The newest frame of
# MS ms (default 300) to /tmp/<name>.png.   ssh user@phone sh -s <name> [ms] < tools/rec.sh
export XDG_RUNTIME_DIR=/run/user/$(id -u)
C=$XDG_RUNTIME_DIR/ztmetro.ctl
rm -rf /tmp/ztrec; mkdir -p /tmp/ztrec
printf 'screen on\n' > $C; sleep 0.5
printf 'record %s\n' "${2:-300}" > $C; sleep $(( ${2:-300} / 1000 + 1 ))
f=$(ls /tmp/ztrec/*.ppm 2>/dev/null | tail -1)
[ -n "$f" ] && ffmpeg -loglevel error -y -i "$f" /tmp/${1:-rec}.png && echo "$(ls /tmp/ztrec | wc -l) frames"
