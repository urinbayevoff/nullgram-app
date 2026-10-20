"""Tepegram's own pieces, drawn as Telegram for Windows Phone drew them
(Evgeny Nadymov's app, GPL-2.0; its look, not its code): round avatars with
initials on eight colours, chats as rows with the name large and light, the
last message small and grey, a round badge; messages as square boxes with a
small corner on the sender's side, white for theirs and dark grey for ours;
a channel's posts as cards across the page with how many saw them. Sizes are
the app's, at 0.75 (its pages were 480 wide, ours are 360 points)."""
import sys
import time
from datetime import datetime

from PySide6.QtCore import QPoint, QPointF, QRectF, Qt, Signal
from PySide6.QtGui import (QBrush, QColor, QFontMetricsF, QImage, QPainter, QPainterPath, QPen, QPixmap,
                           QRegion)
from PySide6.QtWidgets import QSizePolicy, QVBoxLayout, QWidget

import ztos
from ztos import FONT_REGULAR, FONT_SEMIBOLD, FONT_SEMILIGHT, _font, _Pressable

GREY = QColor(153, 153, 153)
CHROME = QColor(0x1f, 0x1f, 0x1f)	# the app bar's and a card's grey
PAGE_W = 360 - 2 * ztos.MARGIN		# pages are 360 points wide on every screen
FONT_BOLD = ["Segoe WP Bold", "Segoe UI Bold", "Selawik Bold", "Selawik Semibold", "Open Sans Bold", "sans-serif"]

# the placeholders' colours (its App.xaml), picked by the id
PLACEHOLDERS = [0x0050ef, 0x00bcd4, 0x00aa08, 0xf0a30a, 0xf472d0, 0xaa00ff, 0xfa6800, 0xfbc02d]
# messages (its MessageControl.xaml, dark theme)
THEIRS, THEIRS_TEXT, THEIRS_SUBTLE = QColor("#ffffff"), QColor("#000000"), QColor("#93989d")
OURS, OURS_TEXT, OURS_SUBTLE = QColor("#2b2b2b"), QColor("#ffffff"), QColor("#a0a0a0")
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
	return QColor(PLACEHOLDERS[abs(chat_id) % len(PLACEHOLDERS)])


def short_count(n: int) -> str:
	"""Views as a channel shows them: 950, 12.4K, 1.2M."""
	if n < 1000:
		return str(n)
	if n < 1000000:
		return f"{n / 1000:.1f}".rstrip("0").rstrip(".") + "K"
	return f"{n / 1000000:.1f}".rstrip("0").rstrip(".") + "M"


_photos = {}		# id -> its small picture (a path, then a QImage once drawn)


def set_photo(chat_id: int, path: str):
	_photos[chat_id] = path


def draw_avatar(p: QPainter, x: float, y: float, d: float, chat_id: int, name: str, label_size: float):
	"""A round avatar: the photo if there is one, else initials on a colour."""
	photo = _photos.get(chat_id)
	if isinstance(photo, str):
		image = QImage(photo)
		_photos[chat_id] = photo = image if not image.isNull() else None
	p.save()
	p.setRenderHint(QPainter.Antialiasing, True)
	p.setRenderHint(QPainter.SmoothPixmapTransform, True)
	circle = QPainterPath()
	circle.addEllipse(QRectF(x, y, d, d))
	if photo is not None:
		p.setClipPath(circle)
		p.drawImage(QRectF(x, y, d, d), photo)
	else:
		p.fillPath(circle, tile_color(chat_id))
		p.setPen(QColor("white"))
		p.setFont(_font(FONT_BOLD, label_size))
		p.drawText(QRectF(x, y - 1, d, d), Qt.AlignCenter, initials(name))
	p.restore()


def _tiled_page(widget: QWidget):
	return ztos._ancestor(widget.parentWidget(), TiledPage)


def changed(widget: QWidget):
	"""`widget` shows something new: its page's pictures of it are made again."""
	page = _tiled_page(widget)
	if page is not None:
		page.dirty(widget)


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
	"""A chat: its avatar, its name, the last message, the time and what is unread."""
	H = 66
	AV = 46.5

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
		page = _tiled_page(self)
		if page is not None:
			page.dirty(self)
		else:
			self.content_changed()

	def draw(self, p: QPainter):
		c, w = self.chat, self.width()
		p.setRenderHints(QPainter.Antialiasing | QPainter.TextAntialiasing)
		top = 9.0
		draw_avatar(p, 0, top, self.AV, c["id"], c["name"], 20)
		x = self.AV + 10.5
		unread, muted = c.get("unread", 0), c.get("muted")

		# the time, at the name's foot, small and grey
		stamp = when(c.get("date", 0))
		p.setFont(_font(FONT_SEMIBOLD, 13))
		fs = QFontMetricsF(p.font())
		stamp_w = fs.horizontalAdvance(stamp)
		p.setPen(GREY)
		p.drawText(QPointF(w - stamp_w, top + 22), stamp)

		p.setPen(QColor("white"))
		p.setFont(_font(FONT_SEMILIGHT, 25))
		fm = QFontMetricsF(p.font())
		name = fm.elidedText(c["name"], Qt.ElideRight, w - x - stamp_w - 8)
		p.drawText(QPointF(x, top + 23), name)

		badge_w = 0.0
		if unread:
			label = str(unread) if unread < 1000 else "999+"
			p.setFont(_font(FONT_SEMIBOLD, 12))
			fb = QFontMetricsF(p.font())
			badge_w = max(21.0, fb.horizontalAdvance(label) + 11)
			r = QRectF(w - badge_w, top + 29, badge_w, 21)
			p.setPen(Qt.NoPen)
			p.setBrush(QColor(0x5d, 0x5d, 0x5d) if muted else ztos.accent())
			p.drawRoundedRect(r, 10.5, 10.5)
			p.setPen(QColor("white"))
			p.drawText(r, Qt.AlignCenter, label)

		y = top + 44
		room = w - x - (badge_w + 6 if badge_w else 0)
		if c.get("out"):
			p.setFont(_font(FONT_SEMIBOLD, 15))
			p.setPen(GREY)
			you = "Siz: "
			p.drawText(QPointF(x, y), you)
			x += QFontMetricsF(p.font()).horizontalAdvance(you)
			room -= QFontMetricsF(p.font()).horizontalAdvance(you)
		p.setFont(_font(FONT_REGULAR, 15))
		p.setPen(QColor(220, 220, 220) if unread and not muted else GREY)
		p.drawText(QPointF(x, y), QFontMetricsF(p.font()).elidedText(c.get("text", ""), Qt.ElideRight, room))


class ContactRow(_Pressable):
	"""A contact, as the People hub lists them: the avatar and the name."""
	H = 62

	def __init__(self, contact: dict, on_tap):
		super().__init__()
		self.chat = contact
		self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
		self.setFixedHeight(self.H)
		self.tapped.connect(lambda: on_tap(self.chat))

	def update_chat(self, contact: dict):
		self.chat = contact
		self.redraw()
		changed(self)

	def draw(self, p: QPainter):
		c = self.chat
		p.setRenderHints(QPainter.Antialiasing | QPainter.TextAntialiasing)
		draw_avatar(p, 0, 8, 46.5, c["id"], c["name"], 20)
		x = 46.5 + 10.5
		p.setPen(QColor("white"))
		p.setFont(_font(FONT_SEMILIGHT, 22))
		fm = QFontMetricsF(p.font())
		p.drawText(QPointF(x, 8 + 23 + 6), fm.elidedText(c["name"], Qt.ElideRight, self.width() - x))


class Bubble(Cached):
	"""One message: a square box, theirs white with a small corner at the top
	left (in a group with the sender's avatar beside it), ours dark grey with
	the corner at the top right; a channel's post a card across the page."""
	PAD, CORNER, GAP = 9.0, 9.0, 6.0
	AV = 34.0

	def __init__(self, msg: dict, kind: str = "user"):
		super().__init__()
		self.msg = msg
		self.kind = kind
		self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
		self._layout()

	def set_msg(self, msg: dict):
		self.msg = msg
		self._layout()
		self.redraw()
		changed(self)

	def _text(self) -> str:
		from tg import MEDIA_UZ
		m = self.msg
		label = f"[{MEDIA_UZ[m['media']]}]" if m.get("media") in MEDIA_UZ else ""
		return "\n".join(t for t in (label, m.get("text", "")) if t) or " "

	def _card(self) -> bool:
		return self.kind == "channel"

	def _avatar(self) -> bool:
		return self.kind == "group" and not self.msg.get("out")

	def _layout(self):
		if self._card():
			self.max_w = PAGE_W
		else:
			self.max_w = min(251.0, PAGE_W - self.CORNER - (self.AV + 6 if self._avatar() else 0))
		inner = self.max_w - 2 * self.PAD
		fm = QFontMetricsF(_font(FONT_REGULAR, 16))
		self.text_rect = fm.boundingRect(QRectF(0, 0, inner, 100000), Qt.TextWordWrap, self._text())
		self.name_h = 20.0 if self.msg.get("sender") else 0.0
		fs = QFontMetricsF(_font(FONT_REGULAR, 12))
		self.foot = self._foot()
		body_w = max(self.text_rect.width(), fs.horizontalAdvance(self.foot) + 4,
		             QFontMetricsF(_font(FONT_SEMIBOLD, 14)).horizontalAdvance(self.msg.get("sender", ""))
		             if self.name_h else 0)
		self.box_w = self.max_w if self._card() else min(self.max_w, body_w + 2 * self.PAD)
		self.box_h = self.name_h + self.text_rect.height() + 20 + 2 * self.PAD - 4
		self.setFixedHeight(int(self.box_h + self.GAP + 0.999))

	def _foot(self) -> str:
		m = self.msg
		t = datetime.fromtimestamp(m["date"]).strftime("%H:%M") if m.get("date") else ""
		if m.get("pending"):
			return "yuborilmoqda..."
		if m.get("failed"):
			return "yuborilmadi"
		if self._card() and m.get("views"):
			return f"{short_count(m['views'])} ko'rdi  ·  {t}"
		if m.get("out"):
			return t + ("  ✓✓" if m.get("read") else "  ✓")
		return t

	def draw(self, p: QPainter):
		m, w = self.msg, self.width()
		out, card = bool(m.get("out")), self._card()
		if card:
			fill, ink, subtle = CHROME, OURS_TEXT, OURS_SUBTLE
		elif out:
			fill, ink, subtle = OURS, OURS_TEXT, OURS_SUBTLE
		else:
			fill, ink, subtle = THEIRS, THEIRS_TEXT, THEIRS_SUBTLE
		if m.get("pending"):
			fill = QColor(fill)
			fill.setAlphaF(0.6)
		y = 0.0
		if card:
			x = 0.0
		elif out:
			x = w - self.CORNER - self.box_w
			corner = QPainterPath(QPointF(x + self.box_w, y + self.CORNER))
			corner.lineTo(x + self.box_w + self.CORNER, y + self.CORNER)
			corner.lineTo(x + self.box_w, y + 2 * self.CORNER)
			corner.closeSubpath()
		else:
			x = self.CORNER + (self.AV + 6 if self._avatar() else 0)
			corner = QPainterPath(QPointF(x, y + self.CORNER))
			corner.lineTo(x - self.CORNER, y + self.CORNER)
			corner.lineTo(x, y + 2 * self.CORNER)
			corner.closeSubpath()
		if self._avatar():
			draw_avatar(p, 0, y, self.AV, m.get("sender_id", 0), m.get("sender", ""), 14)
		p.fillRect(QRectF(x, y, self.box_w, self.box_h), fill)
		if not card:
			p.fillPath(corner, fill)

		ty = y + self.PAD
		if self.name_h:
			p.setPen(tile_color(m.get("sender_id", 0)))
			p.setFont(_font(FONT_SEMIBOLD, 14))
			fm = QFontMetricsF(p.font())
			p.drawText(QPointF(x + self.PAD, ty + fm.ascent() - 2),
			           fm.elidedText(m["sender"], Qt.ElideRight, self.box_w - 2 * self.PAD))
			ty += self.name_h
		p.setPen(ink)
		p.setFont(_font(FONT_REGULAR, 16))
		p.drawText(QRectF(x + self.PAD, ty, self.box_w - 2 * self.PAD + 1, self.text_rect.height() + 2),
		           Qt.TextWordWrap, self._text())
		p.setPen(subtle)
		p.setFont(_font(FONT_REGULAR, 12))
		fm = QFontMetricsF(p.font())
		p.drawText(QPointF(x + self.box_w - self.PAD - fm.horizontalAdvance(self.foot),
		                   y + self.box_h - self.PAD + 2), self.foot)


class DayLabel(Cached):
	"""A day's name between messages."""

	def __init__(self, stamp: float):
		super().__init__()
		self.text = day_title(stamp)
		self.setFixedHeight(34)

	def draw(self, p: QPainter):
		p.setPen(GREY)
		p.setFont(_font(FONT_SEMIBOLD, 13))
		p.drawText(QRectF(0, 4, self.width(), 26), Qt.AlignHCenter | Qt.AlignVCenter, self.text)


class UnreadLabel(Cached):
	"""Where the unread messages start."""

	def __init__(self, count: int):
		super().__init__()
		self.count = count
		self.setFixedHeight(36)

	def draw(self, p: QPainter):
		p.fillRect(QRectF(0, 6, self.width(), 24), CHROME)
		p.setPen(ztos.accent())
		p.setFont(_font(FONT_SEMIBOLD, 13))
		p.drawText(QRectF(0, 6, self.width(), 24), Qt.AlignCenter,
		           f"{self.count} ta o'qilmagan xabar" if self.count else "o'qilmagan xabarlar")


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
		# for glass over the list (glass.GlassBar): each tile small, then blurred
		self.glass = []
		self._small = {}
		self._blur = {}
		self.glass_gen = 0

	def _key(self, i: int):
		return (id(self), "tile", i)

	# the blurred copies
	SMALL = 4		# points a pixel
	BLUR_MARGIN = 16	# pixels of the tiles either side, so the blur has no seams

	def _shrink(self, i: int, image: QImage):
		w = max(1, round(image.width() / image.devicePixelRatio() / self.SMALL))
		h = max(1, round(image.height() / image.devicePixelRatio() / self.SMALL))
		# (a quarter first, the quick way: what is lost there the blur would lose)
		quick = image.scaled(w * 4, h * 4, Qt.IgnoreAspectRatio, Qt.FastTransformation)
		small = quick.scaled(w, h, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
		small.setDevicePixelRatio(1.0)
		self._small[i] = small
		for j in (i - 1, i, i + 1):
			if j in self._small:
				self._blur_tile(j)
		self.glass_gen += 1
		if not self._gl_on:
			for bar in self.glass:
				bar.update()

	def _blur_tile(self, i: int):
		"""Tile i's small copy blurred (about 16 points), with its neighbours'
		edges under and over it, so the blur runs on across the seam."""
		small = self._small[i]
		w, h, m = small.width(), small.height(), self.BLUR_MARGIN
		col = QImage(w, h + 2 * m, QImage.Format_RGBA8888_Premultiplied)
		col.fill(QColor("black"))
		p = QPainter(col)
		above, below = self._small.get(i - 1), self._small.get(i + 1)
		if above is not None:
			p.drawImage(QPoint(0, m - above.height()), above)
		p.drawImage(QPoint(0, m), small)
		if below is not None:
			p.drawImage(QPoint(0, m + h), below)
		p.end()
		# down twice and up twice, each time smoothed: close to a gaussian
		cw, ch = col.width(), col.height()
		sizes = [(max(1, cw // 2), max(1, ch // 2)), (max(1, cw // 4), max(1, ch // 4))]
		img = col
		for sw, sh in sizes:
			img = img.scaled(sw, sh, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
		for sw, sh in [sizes[0], (cw, ch)]:
			img = img.scaled(sw, sh, Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
		blurred = img.copy(0, m, w, h)
		self._blur[i] = blurred
		layer = ztos._layer_of(self)
		if layer is not None:
			layer.upload((id(self), "blur", i), blurred)

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
		t15 = time.perf_counter()
		if self.glass:
			self._shrink(i, image)
		t2 = time.perf_counter()
		self._tiles[i], self._tile_h[i] = "ok", h
		self._prints[i] = self._print(top, h)
		if ztos._profiling:
			print(f"tepegram tile {i}: render {(t1 - t0) * 1000:.0f} upload {(t15 - t1) * 1000:.0f} glass {(t2 - t15) * 1000:.0f} "
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
			layer.drop((id(self), "blur", i))
			self._tiles.pop(i)
			self._prints.pop(i, None)
			self._small.pop(i, None)
			self._blur.pop(i, None)
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
		for bar in self.glass:
			bar.gpu_prepare(layer)
			bar.gpu_where(self)
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
		for bar in self.glass:
			if bar.isVisible():
				quads += bar.gpu_quads(self, s, layer)
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
