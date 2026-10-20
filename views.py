"""Tepegram's own pieces, drawn the Windows Phone 8.1 way: square avatars in
the accent's family, chats as rows of the People hub, messages as the
Messaging app's speech bubbles (received ones in the accent with the tail at
the top, sent ones darker with the tail at the bottom)."""
import sys
import time
from datetime import datetime

from PySide6.QtCore import QPoint, QPointF, QRectF, Qt
from PySide6.QtGui import QColor, QFontMetricsF, QImage, QPainter, QPainterPath, QPixmap, QRegion
from PySide6.QtWidgets import QSizePolicy, QVBoxLayout, QWidget

import ztos
from ztos import FONT_REGULAR, FONT_SEMIBOLD, FONT_SEMILIGHT, _font, _Pressable

GREY = QColor(153, 153, 153)
PAGE_W = 360 - 2 * ztos.MARGIN		# pages are 360 points wide on every screen

# avatar squares: the Windows Phone accents, picked by the chat's id
TILES = [0xa4c400, 0x60a917, 0x008a00, 0x00aba9, 0x1ba1e2, 0x0050ef, 0x6a00ff, 0xaa00ff,
         0xd80073, 0xa20025, 0xe51400, 0xfa6800, 0xf0a30a, 0x825a2c, 0x647687, 0x76608a]
WEEK = ["du", "se", "ch", "pa", "ju", "sh", "ya"]
MONTHS = ["yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avgust", "sentabr", "oktabr",
          "noyabr", "dekabr"]


def when(stamp: float) -> str:
	"""The chat list's time: today a clock, this week a day, before that a date."""
	if not stamp:
		return ""
	d, now = datetime.fromtimestamp(stamp), datetime.now()
	if d.date() == now.date():
		return d.strftime("%H:%M")
	if (now.date() - d.date()).days < 7:
		return WEEK[d.weekday()]
	return d.strftime("%d.%m.%y")


def day_title(stamp: float) -> str:
	d, now = datetime.fromtimestamp(stamp), datetime.now()
	days = (now.date() - d.date()).days
	if days == 0:
		return "bugun"
	if days == 1:
		return "kecha"
	return f"{d.day} {MONTHS[d.month - 1]}" + ("" if d.year == now.year else f" {d.year}")


def initials(name: str) -> str:
	parts = [p for p in name.split() if p[:1].isalnum()]
	return "".join(p[0] for p in parts[:2]).upper() or "?"


def tile_color(chat_id: int) -> QColor:
	return QColor(TILES[abs(chat_id) % len(TILES)])


class Cached(QWidget):
	"""A widget drawn once into a picture at the screen's resolution, and a
	repaint only copies it (text at 4x is the costly part). Subclasses draw()
	and call redraw() when what they show changes."""
	_cache = None

	def draw(self, p: QPainter):
		pass

	def redraw(self):
		self._cache = None
		self.update()

	def paintEvent(self, event):
		ratio = self.devicePixelRatioF()
		size = self.size() * ratio
		if self._cache is None or self._cache.size() != size:
			self._cache = QPixmap(size)
			self._cache.setDevicePixelRatio(ratio)
			self._cache.fill(Qt.transparent)
			q = QPainter(self._cache)
			q.setRenderHints(QPainter.Antialiasing | QPainter.TextAntialiasing)
			self.draw(q)
			q.end()
		p = QPainter(self)
		p.drawPixmap(0, 0, self._cache)
		p.end()


class List(QWidget):
	"""Rows that come and go inside a ztos.Page."""

	def __init__(self):
		super().__init__()
		self.box = QVBoxLayout(self)
		self.box.setContentsMargins(0, 0, 0, 0)
		self.box.setSpacing(0)

	def clear(self):
		while self.box.count():
			w = self.box.takeAt(0).widget()
			if w:
				w.deleteLater()

	def add(self, widget: QWidget, at: int = -1) -> QWidget:
		self.box.insertWidget(at, widget)
		return widget

	def rows(self) -> list:
		return [self.box.itemAt(i).widget() for i in range(self.box.count())]


class ChatRow(_Pressable):
	"""A chat: its square, its name, the last message, the time and what is unread."""
	H = 76

	def __init__(self, chat: dict, on_tap, on_hold=None):
		super().__init__()
		self.chat = chat
		self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
		self.setFixedHeight(self.H)
		self.tapped.connect(lambda: on_tap(self.chat))
		if on_hold:
			self.held.connect(lambda: on_hold(self.chat))

	def update_chat(self, chat: dict):
		self.chat = chat
		self.redraw()
		page = ztos._ancestor(self.parentWidget(), TiledPage)
		if page is not None:
			page.dirty(self)
		else:
			self.content_changed()

	def draw(self, p: QPainter):
		c, w = self.chat, self.width()
		p.setRenderHints(QPainter.Antialiasing | QPainter.TextAntialiasing)
		side, top = 56, 8
		p.fillRect(QRectF(0, top, side, side), tile_color(c["id"]))
		p.setPen(QColor("white"))
		p.setFont(_font(FONT_SEMILIGHT, 22))
		p.drawText(QRectF(0, top, side, side), Qt.AlignCenter, initials(c["name"]))

		x = side + 12
		unread = c.get("unread", 0)
		stamp = when(c.get("date", 0))
		p.setFont(_font(FONT_REGULAR, 12))
		fm_small = QFontMetricsF(p.font())
		stamp_w = fm_small.horizontalAdvance(stamp)
		p.setPen(ztos.accent() if unread and not c.get("muted") else GREY)
		p.drawText(QPointF(w - stamp_w, top + 14), stamp)

		p.setPen(QColor("white"))
		p.setFont(_font(FONT_SEMILIGHT, 21))
		fm = QFontMetricsF(p.font())
		name = fm.elidedText(c["name"], Qt.ElideRight, w - x - stamp_w - 8)
		p.drawText(QPointF(x, top + fm.ascent() - 2), name)

		badge_w = 0.0
		if unread:
			label = str(unread) if unread < 1000 else "999+"
			p.setFont(_font(FONT_SEMIBOLD, 12))
			fb = QFontMetricsF(p.font())
			badge_w = max(22.0, fb.horizontalAdvance(label) + 12)
			r = QRectF(w - badge_w, top + 32, badge_w, 22)
			p.fillRect(r, GREY.darker(160) if c.get("muted") else ztos.accent())
			p.setPen(QColor("white"))
			p.drawText(r, Qt.AlignCenter, label)

		text = ("Siz: " if c.get("out") else "") + c.get("text", "")
		p.setFont(_font(FONT_REGULAR, 14))
		fm2 = QFontMetricsF(p.font())
		p.setPen(QColor(230, 230, 230) if unread else GREY)
		p.drawText(QPointF(x, top + 44), fm2.elidedText(text, Qt.ElideRight, w - x - badge_w - 8))


class Bubble(Cached):
	"""One message, as the Messaging app draws it."""
	PAD, TAIL, GAP = 10, 10, 6

	def __init__(self, msg: dict):
		super().__init__()
		self.msg = msg
		self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
		self._layout()

	def set_msg(self, msg: dict):
		self.msg = msg
		self._layout()
		self.redraw()
		page = ztos._ancestor(self.parentWidget(), TiledPage)
		if page is not None:
			page.dirty(self)

	def _text(self) -> str:
		from tg import MEDIA_UZ
		m = self.msg
		label = f"[{MEDIA_UZ[m['media']]}]" if m.get("media") in MEDIA_UZ else ""
		return "\n".join(t for t in (label, m.get("text", "")) if t) or " "

	def _layout(self):
		self.max_w = PAGE_W * 0.8
		inner = self.max_w - 2 * self.PAD
		fm = QFontMetricsF(_font(FONT_REGULAR, 15))
		self.text_rect = fm.boundingRect(QRectF(0, 0, inner, 100000), Qt.TextWordWrap, self._text())
		self.name_h = 18.0 if self.msg.get("sender") else 0.0
		fs = QFontMetricsF(_font(FONT_REGULAR, 11))
		self.foot = self._foot()
		body_w = max(self.text_rect.width(), fs.horizontalAdvance(self.foot) + 4,
		             QFontMetricsF(_font(FONT_SEMIBOLD, 12)).horizontalAdvance(self.msg.get("sender", "")) if self.name_h else 0)
		self.box_w = min(self.max_w, body_w + 2 * self.PAD)
		self.box_h = self.name_h + self.text_rect.height() + 18 + 2 * self.PAD - 4
		self.setFixedHeight(int(self.box_h + self.TAIL + self.GAP + 0.999))

	def _foot(self) -> str:
		m = self.msg
		t = datetime.fromtimestamp(m["date"]).strftime("%H:%M") if m.get("date") else ""
		if m.get("pending"):
			return "yuborilmoqda..."
		if m.get("failed"):
			return "yuborilmadi"
		return t

	def draw(self, p: QPainter):
		m, w = self.msg, self.width()
		color = ztos.accent()
		out = m.get("out")
		if out:
			color = color.darker(155)
			x, y = w - self.box_w, 0.0
			tail = QPainterPath(QPointF(w - 2 * self.TAIL, y + self.box_h - 0.5))
			tail.lineTo(w, y + self.box_h + self.TAIL)
			tail.lineTo(w, y + self.box_h - 0.5)
		else:
			x, y = 0.0, float(self.TAIL)
			tail = QPainterPath(QPointF(0, 0))
			tail.lineTo(2 * self.TAIL, y + 0.5)
			tail.lineTo(0, y + 0.5)
		if m.get("pending"):
			color.setAlphaF(0.6)
		p.fillRect(QRectF(x, y, self.box_w, self.box_h), color)
		p.fillPath(tail, color)

		ty = y + self.PAD
		if self.name_h:
			p.setPen(QColor(255, 255, 255, 200))
			p.setFont(_font(FONT_SEMIBOLD, 12))
			fm = QFontMetricsF(p.font())
			p.drawText(QPointF(x + self.PAD, ty + fm.ascent()),
			           fm.elidedText(m["sender"], Qt.ElideRight, self.box_w - 2 * self.PAD))
			ty += self.name_h
		p.setPen(QColor("white"))
		p.setFont(_font(FONT_REGULAR, 15))
		p.drawText(QRectF(x + self.PAD, ty, self.box_w - 2 * self.PAD + 1, self.text_rect.height() + 2),
		           Qt.TextWordWrap, self._text())
		p.setPen(QColor(255, 255, 255, 170))
		p.setFont(_font(FONT_REGULAR, 11))
		fm = QFontMetricsF(p.font())
		p.drawText(QPointF(x + self.box_w - self.PAD - fm.horizontalAdvance(self.foot),
		                   y + self.box_h - self.PAD + 2), self.foot)


class DayLabel(Cached):
	"""A day's name between bubbles."""

	def __init__(self, stamp: float):
		super().__init__()
		self.text = day_title(stamp)
		self.setFixedHeight(34)

	def draw(self, p: QPainter):
		p.setPen(GREY)
		p.setFont(_font(FONT_REGULAR, 13))
		p.drawText(QRectF(0, 4, self.width(), 26), Qt.AlignLeft | Qt.AlignVCenter, self.text)


class QrView(QWidget):
	"""A tg://login link as a QR code: black modules on a white square."""

	def __init__(self, side: int = 236):
		super().__init__()
		self.side = side
		self.matrix = None
		self.setFixedHeight(side + 8)

	def set_url(self, url: str):
		import qrcode
		q = qrcode.QRCode(border=2, error_correction=qrcode.constants.ERROR_CORRECT_M)
		q.add_data(url)
		q.make(fit=True)
		self.matrix = q.get_matrix()
		self.update()

	def paintEvent(self, event):
		p = QPainter(self)
		x0 = 0.0
		p.fillRect(QRectF(x0, 4, self.side, self.side), QColor("white"))
		if self.matrix:
			n = len(self.matrix)
			cell = self.side / n
			for r, row in enumerate(self.matrix):
				for c, on in enumerate(row):
					if on:
						p.fillRect(QRectF(x0 + c * cell, 4 + r * cell, cell + 0.4, cell + 0.4), QColor("black"))
		else:
			p.setPen(GREY)
			p.setFont(_font(FONT_REGULAR, 13))
			p.drawText(QRectF(x0, 4, self.side, self.side), Qt.AlignCenter, "QR kod tayyorlanmoqda...")
		p.end()


def stamp_now() -> float:
	return time.time()


class TiledPage(ztos.Page):
	"""A page whose list moves on the GPU as tiles 384 points tall, not as the
	SDK's one picture: the one picture is at most 8192 pixels (2048 points at
	the S10's 4x), so a long list fell off it onto the CPU (10 frames a second),
	and it was drawn again whole (250-400 ms) every time the list stopped. Here
	a tile is drawn only when it changed (checked against its print, as the SDK
	does), nearest first, while nothing moves; the nearest MOST stay on the GPU."""
	TILE = 384
	MOST = 14

	def __init__(self, *args, **kwargs):
		super().__init__(*args, **kwargs)
		self._tiles = {}	# index -> "ok" | "suspect" (to check against its print) | "stale"
		self._tile_h = {}
		self._prints = {}
		self._gl_idle.setInterval(60)

	def _key(self, i: int):
		return (id(self), "tile", i)

	def _count(self) -> int:
		return max(1, -(-self.body.height() // self.TILE))

	def _view_tiles(self, scroll: float) -> range:
		view = self.viewport.height()
		first = max(0, int(max(0.0, scroll) // self.TILE))
		last = min(self._count() - 1, int((max(0.0, scroll) + view - 1) // self.TILE))
		return range(first, last + 1)

	# what changed
	def _changed(self, explicit: bool = False):
		if self._quiet or (not explicit and (ztos._drawing_pictures or ztos._now() < ztos._settle_until)):
			return
		self._version += 1
		self._suspect()

	def _suspect(self):
		for i, state in self._tiles.items():
			if state == "ok":
				self._tiles[i] = "suspect"
		if not self._gl_on:
			self._gl_idle.start()

	def _verify(self):
		self._suspect()

	def dirty(self, widget: QWidget):
		"""`widget` (on this list) shows something new: its tiles are drawn again."""
		y = widget.mapTo(self.body, QPoint(0, 0)).y()
		for i in range(max(0, y // self.TILE), (y + widget.height()) // self.TILE + 1):
			if i in self._tiles:
				self._tiles[i] = "stale"
		if not self._gl_on:
			self._gl_idle.start()

	# drawing tiles
	def _render(self, i: int):
		t0 = time.perf_counter()
		layer = ztos._layer_of(self)
		ratio = self.devicePixelRatioF()
		w, top = self.viewport.width(), i * self.TILE
		h = max(1, min(self.TILE, self.body.height() - top))
		# (in the layer's own format: the upload then does not convert it)
		image = QImage(max(1, round(w * ratio)), round(h * ratio), QImage.Format_RGBA8888_Premultiplied)
		image.setDevicePixelRatio(ratio)
		image.fill(QColor("black"))
		self._quiet = True
		ztos._drawing_pictures += 1
		try:
			self.body.render(image, QPoint(0, 0), QRegion(0, top, w, h),
			                 QWidget.RenderFlag.DrawChildren | QWidget.RenderFlag.DrawWindowBackground)
		finally:
			ztos._drawing_pictures -= 1
			self._quiet = False
		t1 = time.perf_counter()
		layer.upload(self._key(i), image)
		t2 = time.perf_counter()
		self._tiles[i], self._tile_h[i] = "ok", h
		self._prints[i] = self._print(top, h)
		if ztos._profiling:
			print(f"tepegram tile {i}: render {(t1 - t0) * 1000:.0f} upload {(t2 - t1) * 1000:.0f} "
			      f"print {(time.perf_counter() - t2) * 1000:.0f} ms{' (moving)' if self._gl_on else ''}",
			      file=sys.stderr, flush=True)

	def _fresh(self, i: int) -> bool:
		"""Tile i is right (checked against its print if in doubt)."""
		state = self._tiles.get(i)
		if state == "ok":
			return True
		if state == "suspect" and self._tile_h.get(i) == max(1, min(self.TILE, self.body.height() - i * self.TILE)):
			if self._print(i * self.TILE, self._tile_h[i]) == self._prints.get(i):
				self._tiles[i] = "ok"
				return True
		return False

	def _ensure(self, scroll: float):
		for i in self._view_tiles(scroll):
			if not self._fresh(i):
				self._render(i)

	def _nearest(self) -> list:
		here = max(0.0, self._scroll) // self.TILE
		return sorted(range(self._count()), key=lambda i: abs(i - here))[:self.MOST]

	def _gl_prepare(self, force: bool = False):
		"""Idle work, one tile a turn: the nearest one not right is drawn again."""
		layer = ztos._layer_of(self)
		if layer is None or not self.scrolls or self._max() <= 0 or not self.isVisible() or self._gl_on:
			return
		if ztos._animating():
			self._gl_idle.start()
			return
		keep = self._nearest()
		for i in [i for i in self._tiles if i not in keep]:
			layer.drop(self._key(i))
			self._tiles.pop(i)
			self._prints.pop(i, None)
		for i in keep:
			if not self._fresh(i):
				self._render(i)
				self._gl_idle.start()
				return

	# moving on the GPU
	def _gl_covers(self, scroll: float) -> bool:
		return True

	def _gl_begin(self):
		layer = ztos._layer_of(self)
		if self._gl_on or layer is None or not self.scrolls or self._max() <= 0:
			return
		self._gl_idle.stop()
		self._ensure(self._scroll)
		self._gl_on = True
		ztos._solid(layer, ("sys", "black"), QColor("black"))
		at = self.viewport.mapTo(self.window(), QPoint(0, 0))
		self._gl_ox, self._gl_oy = float(at.x()), float(at.y())
		# the widgets stay where they are under the layer (not moved, so not
		# painted; and still able to draw a tile that is needed on the way)
		layer.begin((id(self), "scroll"), self.window().rect(), self._gl_quads)
		self._frames, self._moving_since = 0, time.perf_counter()

	def _gl_quads(self) -> list:
		from ztos._gl import Quad
		layer = ztos._layer_of(self)
		w, view, s = float(self.viewport.width()), float(self.viewport.height()), self._scroll
		self._frames = getattr(self, "_frames", 0) + 1
		quads = [Quad.rect(("sys", "black"), ztos._WHOLE, self._gl_ox, self._gl_oy, w, view)]
		if layer is None:
			return quads
		for i in self._view_tiles(s):
			th = self._tile_h.get(i)
			if not th or not layer.has(self._key(i)):
				continue
			t0 = i * self.TILE
			c0, c1 = max(float(t0), s), min(float(t0 + th), s + view)
			if c1 > c0:
				quads.append(Quad.rect(self._key(i), QRectF(0, (c0 - t0) / th, 1, (c1 - c0) / th),
				                       self._gl_ox, self._gl_oy + c0 - s, w, c1 - c0))
		return quads

	def _set(self, scroll: float):
		if self._gl_on:
			self._scroll = scroll
			self._ensure(scroll)
			ztos._layer_of(self).update()
			return
		super()._set(scroll)

	def _gl_end(self):
		if not self._gl_on:
			return
		self._gl_on = False
		self._quiet = True
		self.body.move(0, -round(self._scroll))
		self.viewport.repaint()
		self._quiet = False
		# a change while it moved may not have reached a tile: they are checked
		self._suspect()
		if ztos._profiling:
			ms = (time.perf_counter() - self._moving_since) * 1000
			print(f"tepegram moved: {self._frames} frames in {ms:.0f} ms = {self._frames * 1000 / max(1, ms):.0f} fps",
			      file=sys.stderr, flush=True)
		layer = ztos._layer_of(self)
		if layer is not None:
			layer.end((id(self), "scroll"))
			ztos._settle()
