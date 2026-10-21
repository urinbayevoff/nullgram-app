#!/usr/bin/env python3
"""On the phone: flicks through the shell's ctl at a finger's pace (a move every 8 ms, not a shell's
sleep), then how the app's frames went (NULLGRAM_FPS=0 in its log: every frame).

  ssh phone-usb python3 - [n] [log] < tools/flick.py

n flicks up then n down (default 8). Prints, for the drags and for the glides after them apart,
the frames dropped (over 28 ms) and the time lost, and how unevenly the rest came: a fair measure
of the stutter a hand would feel (flicks sent through ssh came at uneven times, frames waited)."""
import os
import sys
import time

n = int(sys.argv[1]) if len(sys.argv) > 1 else 8
log = sys.argv[2] if len(sys.argv) > 2 else "/tmp/nullgram.log"
ctl = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid()), "ztmetro.ctl")


def say(line):
	with open(ctl, "w") as f:
		f.write(line + "\n")


def flick(y0, y1, steps=12):
	say("down 1 180 %d" % y0)
	for i in range(1, steps + 1):
		time.sleep(0.008)
		say("move 1 180 %d" % (y0 + (y1 - y0) * i // steps))
	say("up 1")


say("screen on")
time.sleep(0.5)
start = time.monotonic()
phases = []        # (drag from, glide from, glide to)
for k in range(2 * n):
	a = time.monotonic()
	flick(250, 650) if k < n else flick(650, 250)
	b = time.monotonic()
	time.sleep(1.2)
	phases.append((a, b, time.monotonic()))
time.sleep(0.2)

frames = []
for line in open(log, errors="replace"):
	if line.startswith("nullgram: frame "):
		p = line.split()
		ms, at = float(p[2]), float(p[5])
		if at >= start:
			frames.append((at, ms))

for name, lo, hi in (("drag", 0, 1), ("glide", 1, 2)):
	got = [ms for ph in phases for at, ms in frames
	       if ph[lo] + (0.05 if lo == 1 else 0) <= at < ph[hi] and ms < 400]
	drops = sorted((ms for ms in got if ms > 28), reverse=True)
	# uneven: how far the frames stray from 16.7 ms, the drops left out (the clock's animation
	# driver ticks unevenly; what moves then moves unevenly on an even screen)
	even = [ms for ms in got if ms <= 28]
	jitter = (sum((ms - 16.7) ** 2 for ms in even) / max(len(even), 1)) ** 0.5
	print("%-5s frames %4d, dropped %3d (%.1f%%) lost %5.0f ms, jitter %.1f ms, worst %s" % (
		name, len(got), len(drops), 100.0 * len(drops) / max(len(got), 1), sum(ms - 16.7 for ms in drops),
		jitter, " ".join("%.0f" % w for w in drops[:6])))
