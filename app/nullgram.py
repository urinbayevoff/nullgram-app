"""Nullgram: Telegram the way Telegram-iOS shows it, on Qt Quick + TDLib.

QML draws everything and keeps the state (qml/Store.qml); this file only loads
TDLib and carries its JSON both ways. Rule (NOTES.md): no Python on the
render thread and none in the UI thread's hot paths -- TDLib's answers are read
on a thread of our own (ctypes lets the interpreter go while it waits) and
reach QML as queued signals, which QML takes without Python.

  python3 nullgram.py [--test-dc]      (--test-dc: Telegram's test servers, a throwaway account;
                                       NULLGRAM_TEST_PHONE=99966XYYYY signs in there by itself)
"""
import base64
import ctypes
import json
import hashlib
import os
import shutil
import subprocess
import sys
import threading

# letters over 64 px are drawn from outlines every time, uncached; at the S10's 4x that is all of them
os.environ.setdefault("QT_MAX_CACHED_GLYPH_SIZE", "256")

from PySide6.QtCore import Property, QObject, QRectF, Qt, QUrl, Signal, Slot
from PySide6.QtGui import QColor, QGuiApplication, QImage, QImageReader, QPainter, QPainterPath
from PySide6.QtQuick import QQuickImageProvider, QQuickView

HERE = os.path.dirname(os.path.abspath(__file__))
TEST = "--test-dc" in sys.argv
DATA = os.path.expanduser("~/.local/share/ztos/data/uz.omonullos.nullgram" + (".test" if TEST else ""))
KEY = os.path.expanduser("~/.local/share/ztos/data/uz.omonullos.nullgram/api.json")	# install.sh --key
LIBS = [os.path.expanduser("~/.local/td/lib/libtdjson.so"), "libtdjson.so"]
VENDOR = os.path.join(HERE, "vendor")	# qrcode (install.sh)
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

	def start(self):
		"""Once QML listens: a signal sent before anyone is connected is lost, and with it
		TDLib's first update (asking for the parameters) -- the app would wait on a blank page."""
		threading.Thread(target=self._receive, name="td", daemon=True).start()
		# TDLib starts the client on its first request; until then no updates come
		self.send(json.dumps({"@type": "getOption", "name": "version"}))

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

	@Slot(str, str, result=str)
	def save(self, path: str, name: str) -> str:
		"""A downloaded file copied to ~/Downloads under its own name (a number added when that is
		taken): where it went, or "" when it could not be."""
		out = os.path.expanduser("~/Downloads")
		os.makedirs(out, exist_ok=True)
		base, ext = os.path.splitext(os.path.basename(name or path))
		to = os.path.join(out, base + ext)
		n = 1
		while os.path.exists(to):
			n += 1
			to = os.path.join(out, "%s (%d)%s" % (base, n, ext))
		try:
			shutil.copyfile(path, to)
		except OSError:
			return ""
		return to

	@Slot(result="QVariantList")
	def recent(self) -> list:
		"""The phone's own files to send, newest first: {path, name, size, kind (photo, video, audio,
		file), w, h}. Only from the user's folders, a level or two down -- not the app's own."""
		roots = ["~/Pictures", "~/Rasmlar", "~/Videos", "~/Music", "~/Downloads", "~/Documents", "~/DCIM"]
		found = []
		for root in roots:
			root = os.path.expanduser(root)
			for top, dirs, names in os.walk(root):
				if top.count(os.sep) - root.count(os.sep) >= 2:
					dirs[:] = []
				dirs[:] = [d for d in dirs if not d.startswith(".")]
				for n in names:
					f = os.path.join(top, n)
					if n.startswith(".") or not os.path.isfile(f):
						continue
					found.append((os.path.getmtime(f), f))
		found.sort(reverse=True)
		out = []
		for _, f in found[:300]:
			ext = os.path.splitext(f)[1].lower()
			kind = PHOTO.get(ext) or VIDEO.get(ext) or AUDIO.get(ext) or "file"
			w = h = 0
			if kind == "photo":
				size = QImageReader(f).size()
				w, h = size.width(), size.height()
			out.append({"path": f, "name": os.path.basename(f), "size": os.path.getsize(f), "kind": kind, "w": w, "h": h})
		return out

	@Slot(str, result="QVariantMap")
	def probe(self, path: str) -> dict:
		"""A video's or a sound's length (seconds), width and height, by ffprobe."""
		try:
			r = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries",
			                    "stream=width,height:format=duration", "-of", "json", path],
			                   capture_output=True, text=True, timeout=10)
			j = json.loads(r.stdout or "{}")
		except (OSError, ValueError, subprocess.TimeoutExpired):
			return {"duration": 0, "width": 0, "height": 0}
		st = (j.get("streams") or [{}])[0]
		return {"duration": int(float(j.get("format", {}).get("duration", 0)) + 0.5),
		        "width": st.get("width", 0), "height": st.get("height", 0)}

	@Slot(str, result="QVariantMap")
	def voice(self, path: str) -> dict:
		"""A voice note's length and Telegram's waveform for it: 100 loudness values of 5 bits,
		packed low bit first (base64), as Telegram-iOS makes it (audioWaveform in its encoder)."""
		try:
			pcm = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", "8000", "-f", "s16le", "-"],
			                     capture_output=True, timeout=20).stdout
		except (OSError, subprocess.TimeoutExpired):
			pcm = b""
		samples = memoryview(pcm).cast("h") if len(pcm) >= 2 else []
		n = len(samples)
		peaks = []
		for k in range(100):
			part = samples[k * n // 100:(k + 1) * n // 100]
			peaks.append(max((abs(v) for v in part), default=0))
		top = max(peaks) or 1
		bits = 0
		value = 0
		out = bytearray()
		for p in peaks:
			value |= (min(31, p * 31 // top)) << bits
			bits += 5
			while bits >= 8:
				out.append(value & 0xff)
				value >>= 8
				bits -= 8
		if bits:
			out.append(value & 0xff)
		return {"duration": max(1, round(n / 8000)), "waveform": base64.b64encode(bytes(out)).decode()}

	@Slot(result=str)
	def voicePath(self) -> str:
		"""Where the next voice note is recorded."""
		d = os.path.join(DATA, "voice")
		os.makedirs(d, exist_ok=True)
		return os.path.join(d, "%d.ogg" % (len(os.listdir(d)) + 1))

	apiId = Property(int, lambda self: self._id, constant=True)
	apiHash = Property(str, lambda self: self._hash, constant=True)
	dataDir = Property(str, lambda self: DATA, constant=True)
	testDc = Property(bool, lambda self: TEST, constant=True)
	# on the test servers only: sign in by itself with this number (99966XYYYY, the code is X five times)
	# for testing from the PC: open this chat (its id) once the chats are there (run.sh passes it on)
	devOpen = Property(str, lambda self: os.environ.get("NULLGRAM_OPEN", ""), constant=True)
	# and send it these lines, one message each (only with NULLGRAM_OPEN)
	devSay = Property(str, lambda self: os.environ.get("NULLGRAM_SAY", ""), constant=True)
	testPhone = Property(str, lambda self: os.environ.get("NULLGRAM_TEST_PHONE", "") if TEST else "", constant=True)


PHOTO = dict.fromkeys([".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp"], "photo")
VIDEO = dict.fromkeys([".mp4", ".mov", ".mkv", ".webm", ".avi", ".m4v"], "video")
AUDIO = dict.fromkeys([".mp3", ".ogg", ".oga", ".opus", ".m4a", ".flac", ".wav", ".aac"], "audio")


class Thumb(QQuickImageProvider):
	"""image://thumb/<path>: a still of a video file (a frame half a second in, by ffmpeg, kept in
	the cache), or the picture itself; for the attach sheet. On Qt's image-loading threads."""

	def __init__(self):
		super().__init__(QQuickImageProvider.Image, QQuickImageProvider.ForceAsynchronousImageLoading)
		self.cache = os.path.expanduser("~/.cache/nullgram/thumbs")
		os.makedirs(self.cache, exist_ok=True)

	def requestImage(self, path, size, requested):
		src = path
		if os.path.splitext(path)[1].lower() in VIDEO:
			st = os.stat(path)
			key = hashlib.sha1(("%s %d %d" % (path, st.st_size, st.st_mtime)).encode()).hexdigest()
			src = os.path.join(self.cache, key + ".jpg")
			if not os.path.exists(src):
				subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", "0.5", "-i", path, "-frames:v", "1",
				                "-vf", "scale=320:-2", src], timeout=20)
		r = QImageReader(src)
		r.setAutoTransform(True)
		if requested.isValid() and requested.width() > 0:
			full = r.size()
			if full.isValid() and full.width() > 0:
				k = max(requested.width() / full.width(), requested.height() / max(full.height(), 1))
				if k < 1:
					r.setScaledSize(full * k)
		img = r.read()
		return img if not img.isNull() else QImage(1, 1, QImage.Format_ARGB32_Premultiplied)


class Round(QQuickImageProvider):
	"""image://round/<path>: the picture cut to a circle at the size asked. Qt calls it on its
	image-loading threads (Image.asynchronous), so the UI thread never waits for it."""

	def __init__(self):
		super().__init__(QQuickImageProvider.Image, QQuickImageProvider.ForceAsynchronousImageLoading)

	def requestImage(self, path, size, requested):
		src = QImage(path.removeprefix("file://"))
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


class Pic(QQuickImageProvider):
	"""image://pic/<radius>/<width>/<path> (or .../mini/<base64>): a message's picture at the size
	asked, cut to the middle, its corners rounded (radius 0: none; -1: a circle). `width` is the
	item's in points, so the radius scales with the pixels asked. `mini` is Telegram's tiny blurred
	preview, there before the picture is. On Qt's image-loading threads."""

	def __init__(self):
		super().__init__(QQuickImageProvider.Image, QQuickImageProvider.ForceAsynchronousImageLoading)

	def requestImage(self, key, size, requested):
		radius, width, rest = key.split("/", 2)
		if rest.startswith("mini/"):
			src = QImage.fromData(base64.b64decode(rest[5:]))
		else:
			src = QImage(rest)
		if requested.isValid() and requested.width() > 0 and requested.height() > 0:
			w, h = requested.width(), requested.height()
		else:
			w, h = max(src.width(), 1), max(src.height(), 1)
		out = QImage(w, h, QImage.Format_ARGB32_Premultiplied)
		out.fill(Qt.transparent)
		if src.isNull():
			return out
		k = w / max(float(width), 1.0)
		r = float(radius)
		p = QPainter(out)
		p.setRenderHints(QPainter.Antialiasing | QPainter.SmoothPixmapTransform)
		if r:
			clip = QPainterPath()
			if r < 0:
				clip.addEllipse(QRectF(0, 0, w, h))
			else:
				clip.addRoundedRect(QRectF(0, 0, w, h), r * k, r * k)
			p.setClipPath(clip)
		big = src.scaled(w, h, Qt.KeepAspectRatioByExpanding, Qt.SmoothTransformation)
		p.drawImage(0, 0, big, (big.width() - w) // 2, (big.height() - h) // 2, w, h)
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
		# left at device pixel ratio 1: BorderImage on the GPU takes its borders in the picture's
		# pixels and draws them that many points big whatever the ratio, so QML draws it `scale`
		# times bigger and scales the item down (ChatPage.qml)
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
	app.setOrganizationName("OmonullOS")
	app.setApplicationName("Nullgram")
	app.setDesktopFileName("ztos.uz.omonullos.nullgram")	# the shell knows its window by this (install.sh)
	td = Td()
	view = QQuickView()
	view.setColor("black")
	view.rootContext().setContextProperty("td", td)
	view.engine().addImageProvider("round", Round())
	view.engine().addImageProvider("wall", Wall())
	view.engine().addImageProvider("bubble", Bubble())
	view.engine().addImageProvider("pic", Pic())
	view.engine().addImageProvider("thumb", Thumb())
	view.setResizeMode(QQuickView.SizeRootObjectToView)
	view.setSource(QUrl.fromLocalFile(os.path.join(HERE, "qml", "Main.qml")))
	if view.status() == QQuickView.Error:
		raise SystemExit("\n".join(e.toString() for e in view.errors()))
	td.start()
	view.showFullScreen()
	sys.exit(app.exec())


if __name__ == "__main__":
	main()
