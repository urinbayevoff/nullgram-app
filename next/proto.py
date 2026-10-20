"""Runs proto.qml; at exit prints which thread drew and the gaps between frames
while something moved (frames more than 100 ms apart start a new run).
--busy: the UI thread's Python busy 30 ms of every 40 (as building bubbles is) -- the motion should not care.
--secs N: quit after N seconds.
--busythread: the same Python work on a thread of its own (the UI thread runs no Python).
--auto: push or pop the chat every second, no touch needed."""
import sys
import threading
import time

from PySide6.QtCore import Qt, QTimer, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQuick import QQuickView

app = QGuiApplication(sys.argv)
view = QQuickView()
view.setResizeMode(QQuickView.SizeRootObjectToView)
view.setSource(QUrl.fromLocalFile(__file__.replace("proto.py", "proto.qml")))
view.showFullScreen()

swaps, drew = [], set()
main = threading.get_ident()
# on the render thread itself (direct): the times are when frames were really drawn. But the
# callbacks are Python, so they wait for the GIL: --qt leaves timing to Qt's own log
# (QT_LOGGING_RULES=qt.scenegraph.time.renderloop=true QT_FORCE_STDERR_LOGGING=1)
if "--qt" not in sys.argv:
	view.frameSwapped.connect(lambda: swaps.append(time.perf_counter()), Qt.DirectConnection)
	view.beforeRendering.connect(lambda: drew.add("main" if threading.get_ident() == main else "render thread"),
	                             Qt.DirectConnection)


def report():
	print("drawn on:", ", ".join(sorted(drew)) or "?", file=sys.stderr)
	runs, run = [], []
	for a, b in zip(swaps, swaps[1:]):
		gap = (b - a) * 1000
		if gap > 100:
			if len(run) > 5:
				runs.append(run)
			run = []
		else:
			run.append(gap)
	if len(run) > 5:
		runs.append(run)
	for r in runs:
		r2 = sorted(r)
		print(f"moved {len(r) + 1} frames in {sum(r):.0f} ms: {1000 * len(r) / sum(r):.0f} fps, "
		      f"median {r2[len(r2) // 2]:.1f} ms, worst {r2[-1]:.1f} ms, over 20 ms: {sum(g > 20 for g in r)}",
		      file=sys.stderr, flush=True)


app.aboutToQuit.connect(report)
if "--secs" in sys.argv:
	QTimer.singleShot(int(float(sys.argv[sys.argv.index("--secs") + 1]) * 1000), app.quit)

if "--busy" in sys.argv:
	def hog():
		end = time.perf_counter() + 0.03
		while time.perf_counter() < end:
			pass
	busy = QTimer()
	busy.timeout.connect(hog)
	busy.start(40)
if "--busythread" in sys.argv:
	def hogs():
		while True:
			end = time.perf_counter() + 0.03
			while time.perf_counter() < end:
				pass
			time.sleep(0.01)
	threading.Thread(target=hogs, daemon=True).start()
if "--auto" in sys.argv:
	auto = QTimer()
	auto.timeout.connect(lambda: view.rootObject().toggle())
	auto.start(1000)
sys.exit(app.exec())
