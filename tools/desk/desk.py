#!/usr/bin/env python3
"""Nullgram on the desk, without the phone: the app's own QML (app/qml/Main.qml) and nullgram.py's
pictures, over a fake TDLib (fake.py) that answers from chats a scene describes, offscreen; what it
draws saved as pictures, taps and drags sent as a finger's.

  python3 tools/desk/desk.py tools/desk/scenes/media.py /tmp/out [--scale 2]

Needs PySide6 with its add-ons (QtMultimedia), ffmpeg for the test video and voice note. A scene is a
module with CHATS, USERS, OPEN (the chat to open, as NULLGRAM_OPEN), RECENT (the phone's files for the
attach sheet, as nullgram.py's recent()) and STEPS: (seconds, what, ...) —
("shot", name), ("tap", x, y), ("hold", x, y), ("drag", x1, y1, x2, y2, ms), ("eval", js) in the top
page's scope (its ids: list, messages, viewer...), ("call", fn(view, root, world)), ("quit",). Points
are the page's (360 × 760). NULLGRAM_APP=<dir>: another app/ (an older one, to compare: cmp.py).

What it is not: the phone's speed (an x86 core, software GL), its fonts, a real video playing."""
import importlib.util
import json
import os
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.abspath(os.environ.get("NULLGRAM_APP", os.path.join(HERE, "..", "..", "app")))
WORK = os.path.join(tempfile.gettempdir(), "nullgram-desk")
sys.path.insert(0, APP)
sys.path.insert(0, HERE)

scale = sys.argv[sys.argv.index("--scale") + 1] if "--scale" in sys.argv else "2"
os.environ["QT_QPA_PLATFORM"] = "offscreen"
os.environ["QT_SCALE_FACTOR"] = scale
os.environ["QSG_USE_SIMPLE_ANIMATION_DRIVER"] = "1"		# (as nullgram.py: animations by the clock)
for d in ("run", "home"):
	os.makedirs(os.path.join(WORK, d), exist_ok=True)
os.environ["XDG_RUNTIME_DIR"] = os.path.join(WORK, "run")
os.environ["HOME"] = os.path.join(WORK, "home")		# its settings and caches: not the real ones

from PySide6.QtCore import Property, QElapsedTimer, QEvent, QObject, QPoint, QPointF, Qt, QTimer, QUrl, Signal, Slot  # noqa: E402
from PySide6.QtGui import QGuiApplication, QMouseEvent  # noqa: E402
from PySide6.QtQml import QQmlEngine, QQmlExpression  # noqa: E402
from PySide6.QtQuick import QQuickView  # noqa: E402

import nullgram  # noqa: E402	(the app's own picture providers and Ink)
import fake  # noqa: E402


class Osk(QObject):
	"""No keyboard."""
	changed = Signal()

	@Slot()
	def hide(self):
		pass

	h = Property(int, lambda self: 0, notify=changed)
	ms = Property(int, lambda self: 200, notify=changed)


class Td(QObject):
	"""nullgram.py's Td, its requests answered by the fake (queued, as TDLib's thread would)."""
	received = Signal(str)

	def __init__(self, world, open_id):
		super().__init__()
		self.world = world
		self._open = str(open_id)

	def start(self):
		for u in self.world.startup():
			self.received.emit(json.dumps(u))

	@Slot(str)
	def send(self, request):
		for answer in self.world.answer(json.loads(request)):
			QTimer.singleShot(0, lambda a=answer: self.received.emit(json.dumps(a)))

	@Slot(str, result="QVariantList")
	def qr(self, text):
		return []

	@Slot(str, str, result=str)
	def save(self, path, name):
		return os.path.join(WORK, name)

	@Slot(result="QVariantList")
	def recent(self):
		return self.world.recent

	@Slot(str, result="QVariantMap")
	def probe(self, path):
		return {"duration": 3, "width": 640, "height": 360}

	@Slot(str, result="QVariantMap")
	def voice(self, path):
		return {"duration": 1, "waveform": ""}

	@Slot(str, str)
	def notify(self, title, body):
		print("desk: banner", title, "|", body, flush=True)

	@Slot(str, "QVariantList", int)
	def tile(self, title, lines, count):
		pass

	@Slot(result=str)
	def voicePath(self):
		return os.path.join(WORK, "v.ogg")

	apiId = Property(int, lambda self: 1, constant=True)
	apiHash = Property(str, lambda self: "x", constant=True)
	dataDir = Property(str, lambda self: os.path.join(WORK, "data"), constant=True)
	testDc = Property(bool, lambda self: False, constant=True)
	devOpen = Property(str, lambda self: self._open, constant=True)
	devSay = Property(str, lambda self: "", constant=True)
	devFind = Property(str, lambda self: "", constant=True)
	testPhone = Property(str, lambda self: "", constant=True)


def main():
	app = QGuiApplication(sys.argv[:1])		# (first: a scene's test pictures are drawn as it loads)
	sys.path.insert(0, os.path.dirname(os.path.abspath(sys.argv[1])))		# (a scene may take another's chats)
	spec = importlib.util.spec_from_file_location("scene", sys.argv[1])
	scene = importlib.util.module_from_spec(spec)
	spec.loader.exec_module(scene)
	out = sys.argv[2]
	os.makedirs(out, exist_ok=True)

	world = fake.World(scene)
	td = Td(world, scene.OPEN)
	view = QQuickView()
	view.setColor("black")
	ctx = view.rootContext()
	ctx.setContextProperty("td", td)
	osk = Osk()
	ctx.setContextProperty("osk", osk)
	ink = nullgram.Ink()
	ctx.setContextProperty("ink", ink)
	imagers = nullgram.Imager()
	eng = view.engine()
	for kind in ("round", "pic", "thumb"):
		eng.addImageProvider(kind, nullgram.Asked(imagers, kind))
	eng.addImageProvider("wall", nullgram.Wall())
	eng.addImageProvider("bubble", nullgram.Bubble())
	eng.addImageProvider("dust", nullgram.Dust())
	view.setResizeMode(QQuickView.SizeRootObjectToView)
	view.resize(360, 760)
	view.setSource(QUrl.fromLocalFile(os.path.join(APP, "qml", "Main.qml")))
	if view.status() == QQuickView.Error:
		for e in view.errors():
			print("desk: QML error:", e.toString(), flush=True)
		sys.exit(1)
	view.show()
	td.start()
	root = view.rootObject()

	clock = QElapsedTimer()
	clock.start()

	def finger(kind, x, y, buttons):
		g = view.mapToGlobal(QPoint(int(x), int(y)))
		e = QMouseEvent(kind, QPointF(x, y), QPointF(g), Qt.LeftButton, buttons, Qt.NoModifier)
		e.setTimestamp(clock.elapsed() + 1000)		# (all at 0, every second press is a double click: its tap lost)
		QGuiApplication.sendEvent(view, e)

	def page_scope():
		"""The top page and the context its own ids are in (its document's: a child's, not its own)."""
		page = root.property("topPage")
		outer = QQmlEngine.contextForObject(page)
		for ch in page.findChildren(QObject):
			c = QQmlEngine.contextForObject(ch)
			if c is not None and c != outer and c.parentContext() is not None:
				return page, c
		return page, outer or view.rootContext()

	def run(step):
		what = step[1]
		if what == "shot":
			path = os.path.join(out, step[2] + ".png")
			view.grabWindow().save(path)
			print("desk: shot", path, flush=True)
		elif what in ("tap", "hold"):
			x, y = step[2], step[3]
			finger(QEvent.MouseButtonPress, x, y, Qt.LeftButton)
			QTimer.singleShot(60 if what == "tap" else 700, lambda: finger(QEvent.MouseButtonRelease, x, y, Qt.NoButton))
		elif what == "drag":
			x1, y1, x2, y2, ms = step[2:7]
			n = max(2, int(ms / 16))
			finger(QEvent.MouseButtonPress, x1, y1, Qt.LeftButton)
			for k in range(1, n + 1):
				QTimer.singleShot(16 * k, lambda k=k: finger(QEvent.MouseMove, x1 + (x2 - x1) * k / n, y1 + (y2 - y1) * k / n, Qt.LeftButton))
			QTimer.singleShot(16 * n + 16, lambda: finger(QEvent.MouseButtonRelease, x2, y2, Qt.NoButton))
		elif what == "eval":
			page, c = page_scope()
			e = QQmlExpression(c, page, step[2])
			v = e.evaluate()
			if e.hasError():
				print("desk: eval error:", e.error().toString(), flush=True)
			else:
				print("desk: eval", " ".join(step[2].split())[:60], "->", v[0] if isinstance(v, tuple) else v, flush=True)
		elif what == "call":
			step[2](view, root, world)
		elif what == "quit":
			app.quit()

	for step in scene.STEPS:
		QTimer.singleShot(int(step[0] * 1000), lambda s=step: run(s))
	code = app.exec()
	sys.stdout.flush()
	os._exit(code)


if __name__ == "__main__":
	main()
