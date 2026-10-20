"""Tepegram next: Telegram the way Telegram-iOS shows it, on Qt Quick + TDLib.

QML draws everything and keeps the state (qml/Store.qml); this file only loads
TDLib and carries its JSON both ways. Rule (next/NOTES.md): no Python on the
render thread and none in the UI thread's hot paths -- TDLib's answers are read
on a thread of our own (ctypes lets the interpreter go while it waits) and
reach QML as queued signals, which QML takes without Python.

  python3 tepegram.py [--test-dc]      (--test-dc: Telegram's test servers, a throwaway account)
"""
import ctypes
import json
import os
import sys
import threading

# letters over 64 px are drawn from outlines every time, uncached; at the S10's 4x that is all of them
os.environ.setdefault("QT_MAX_CACHED_GLYPH_SIZE", "256")

from PySide6.QtCore import Property, QObject, QRectF, Qt, QUrl, Signal, Slot
from PySide6.QtGui import QColor, QGuiApplication, QImage, QPainter, QPainterPath
from PySide6.QtQuick import QQuickImageProvider, QQuickView

HERE = os.path.dirname(os.path.abspath(__file__))
TEST = "--test-dc" in sys.argv
DATA = os.path.expanduser("~/.local/share/ztos/data/uz.omonullos.tepegram.next" + (".test" if TEST else ""))
KEY = os.path.expanduser("~/.local/share/ztos/data/uz.omonullos.tepegram/api.json")	# v0.6's (tools/deploy.sh --key)
LIBS = [os.path.expanduser("~/.local/td/lib/libtdjson.so"), "libtdjson.so"]
VENDOR = os.path.expanduser("~/.local/share/ztos/data/uz.omonullos.tepegram/vendor")	# qrcode
if os.path.isdir(VENDOR):
	sys.path.insert(0, VENDOR)


def _load():
	for path in LIBS:
		try:
			lib = ctypes.CDLL(path)
			break
		except OSError:
			continue
	else:
		raise SystemExit("libtdjson.so not found (" + ", ".join(LIBS) + ")")
	lib.td_create_client_id.restype = ctypes.c_int
	lib.td_send.argtypes = [ctypes.c_int, ctypes.c_char_p]
	lib.td_receive.argtypes = [ctypes.c_double]
	lib.td_receive.restype = ctypes.c_char_p
	lib.td_execute.argtypes = [ctypes.c_char_p]
	lib.td_execute.restype = ctypes.c_char_p
	return lib


class Td(QObject):
	"""One TDLib client. `received` carries each update or answer as TDLib's JSON text."""
	received = Signal(str)

	def __init__(self):
		super().__init__()
		self.lib = _load()
		self.lib.td_execute(json.dumps({"@type": "setLogVerbosityLevel", "new_verbosity_level": 1}).encode())
		self.client = self.lib.td_create_client_id()
		with open(KEY) as f:
			key = json.load(f)
		self._id, self._hash = int(key["id"]), key["hash"]
		os.makedirs(DATA, exist_ok=True)
		threading.Thread(target=self._receive, name="td", daemon=True).start()

	def _receive(self):
		while True:
			r = self.lib.td_receive(10.0)
			if r:
				self.received.emit(r.decode())

	@Slot(str)
	def send(self, request: str):
		self.lib.td_send(self.client, request.encode())

	@Slot(str, result="QVariantList")
	def qr(self, text: str) -> list:
		"""A QR code's rows, each a string of 0 and 1 (QML draws them)."""
		import qrcode
		q = qrcode.QRCode(border=0, error_correction=qrcode.constants.ERROR_CORRECT_M)
		q.add_data(text)
		q.make(fit=True)
		return ["".join("1" if c else "0" for c in row) for row in q.get_matrix()]

	apiId = Property(int, lambda self: self._id, constant=True)
	apiHash = Property(str, lambda self: self._hash, constant=True)
	dataDir = Property(str, lambda self: DATA, constant=True)
	testDc = Property(bool, lambda self: TEST, constant=True)


class Round(QQuickImageProvider):
	"""image://round/<path>: the picture cut to a circle at the size asked. Qt calls it on its
	image-loading threads (Image.asynchronous), so the UI thread never waits for it."""

	def __init__(self):
		super().__init__(QQuickImageProvider.Image, QQuickImageProvider.ForceAsynchronousImageLoading)

	def requestImage(self, path, size, requested):
		src = QImage(path)
		side = max(requested.width(), requested.height(), 1) if requested.isValid() else min(src.width(), src.height())
		out = QImage(side, side, QImage.Format_ARGB32_Premultiplied)
		out.fill(Qt.transparent)
		if not src.isNull():
			p = QPainter(out)
			p.setRenderHints(QPainter.Antialiasing | QPainter.SmoothPixmapTransform)
			clip = QPainterPath()
			clip.addEllipse(QRectF(0, 0, side, side))
			p.setClipPath(clip)
			big = src.scaled(side, side, Qt.KeepAspectRatioByExpanding, Qt.SmoothTransformation)
			p.drawImage(0, 0, big, (big.width() - side) // 2, (big.height() - side) // 2, side, side)
			p.end()
		return out


class Bubble(QQuickImageProvider):
	"""image://bubble/<in|out>/<top: b|s>/<bottom: t|s>/<rrggbb>/<scale>: a message bubble to stretch
	(BorderImage, borders R and R + TAIL on the tail's side), as Telegram-iOS draws them from
	stretchable images (ChatMessageBubbleImages.swift): big corners, small ones on the side where the
	sender's messages run together, and the tail under the last of a run."""
	R, SMALL, TAIL = 17, 6, 6

	def __init__(self):
		super().__init__(QQuickImageProvider.Image)

	def requestImage(self, key, size, requested):
		side, top, bottom, colour, scale = key.split("/")
		s = float(scale)
		R, r, T = self.R, self.SMALL, self.TAIL
		w, h = T + 2 * R + 2, 2 * R + 2
		img = QImage(int(w * s), int(h * s), QImage.Format_ARGB32_Premultiplied)
		img.fill(Qt.transparent)
		p = QPainter(img)
		p.setRenderHint(QPainter.Antialiasing)
		p.scale(s, s)
		if side == "out":		# drawn as an incoming one, mirrored: the tail on the right
			p.translate(w, 0)
			p.scale(-1, 1)
		rt = R if top == "b" else r		# the sender's side, top
		x0, x1 = T, w
		path = QPainterPath()
		path.moveTo(x0 + rt, 0)
		path.lineTo(x1 - R, 0)
		path.quadTo(x1, 0, x1, R)
		path.lineTo(x1, h - R)
		path.quadTo(x1, h, x1 - R, h)
		if bottom == "t":		# the tail: out of the bottom corner, a point to the side
			path.lineTo(x0 + 10, h)
			path.cubicTo(x0 + 6.5, h, x0 + 3.5, h - 1.2, x0 + 2, h - 2.4)
			path.cubicTo(x0 - 0.5, h - 0.2, x0 - 3.5, h + 0.1, 0, h - 0.3)
			path.cubicTo(x0 - 1.2, h - 2, x0, h - 4.5, x0, h - 9)
		else:
			path.lineTo(x0 + r, h)
			path.quadTo(x0, h, x0, h - r)
		path.lineTo(x0, rt)
		path.quadTo(x0, 0, x0 + rt, 0)
		p.fillPath(path, QColor("#" + colour))
		p.end()
		img.setDevicePixelRatio(s)
		return img


class Wall(QQuickImageProvider):
	"""image://wall/<rrggbb,rrggbb,rrggbb,rrggbb>: Telegram's freeform wallpaper, its four colours
	blended by nearness (weight max(0, 0.9 - d)^4), small: drawn large it stays smooth."""
	AT = ((0.80, 0.10), (0.35, 0.25), (0.20, 0.90), (0.65, 0.75))

	def __init__(self):
		super().__init__(QQuickImageProvider.Image)

	def requestImage(self, colours, size, requested):
		rgb = [tuple(int(c[i:i + 2], 16) for i in (0, 2, 4)) for c in colours.split(",")]
		w, h = 30, 63
		img = QImage(w, h, QImage.Format_RGB32)
		for y in range(h):
			for x in range(w):
				u, v = x / (w - 1), y / (h - 1)
				ws = [max(0.0, 0.9 - ((u - px) ** 2 + (v - py) ** 2) ** 0.5) ** 4 for px, py in self.AT]
				total = sum(ws) or 1.0
				r, g, b = (int(sum(k * c[i] for k, c in zip(ws, rgb)) / total) for i in range(3))
				img.setPixel(x, y, 0xff000000 | (r << 16) | (g << 8) | b)
		return img


def main():
	app = QGuiApplication(sys.argv)
	td = Td()
	view = QQuickView()
	view.setColor("black")
	view.rootContext().setContextProperty("td", td)
	view.engine().addImageProvider("round", Round())
	view.engine().addImageProvider("wall", Wall())
	view.engine().addImageProvider("bubble", Bubble())
	view.setResizeMode(QQuickView.SizeRootObjectToView)
	view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "qml", "Main.qml")))
	if view.status() == QQuickView.Error:
		raise SystemExit("\n".join(e.toString() for e in view.errors()))
	view.showFullScreen()
	sys.exit(app.exec())


if __name__ == "__main__":
	main()
