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

from PySide6.QtCore import QEvent, QPoint, QPointF, QRectF, Qt, Signal
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
# chat themes: the first is Telegram for WP's dark one (its MessageControl.xaml: square
# boxes on black); the others are as other Telegrams have them, a wallpaper of four
# colours blended ("freeform", fixed to the screen, the messages float over it) and
# round bubbles. theirs, ours, a channel's card: (fill, text, small text)
THEMES = [
	{"id": "qora", "name": "qora", "wall": None, "round": 0,
	 "theirs": ("#ffffff", "#000000", "#93989d"), "ours": ("#2b2b2b", "#ffffff", "#a0a0a0"),
	 "card": ("#1f1f1f", "#ffffff", "#a0a0a0")},
	{"id": "tun", "name": "tun", "wall": ("#0e1621", "#13202e", "#0c141d", "#112030"), "round": 12,
	 "theirs": ("#182533", "#ffffff", "#6d7f8f"), "ours": ("#2b5278", "#ffffff", "#7da8d3")},
	{"id": "binafsha", "name": "binafsha", "wall": ("#2a1650", "#47226e", "#1c1440", "#3a1d63"), "round": 12,
	 "theirs": ("#2a2142", "#ffffff", "#8e84a8"), "ours": ("#6b3fb8", "#ffffff", "#c9b3ef")},
	{"id": "okean", "name": "okean", "wall": ("#0b3a52", "#0f5e6e", "#08304a", "#136b78"), "round": 12,
	 "theirs": ("#17323f", "#ffffff", "#7b97a3"), "ours": ("#1d7584", "#ffffff", "#a5dbe3")},
	{"id": "shaftoli", "name": "shaftoli", "wall": ("#fec496", "#dd6cb9", "#962fbf", "#4f5bd5"), "round": 12,
	 "theirs": ("#ffffff", "#000000", "#a1aab3"), "ours": ("#ffe6f4", "#000000", "#c27aa5")},
	{"id": "yashil", "name": "kunduzgi yashil", "wall": ("#dbddbb", "#6ba587", "#d5d88d", "#88b884"), "round": 12,
	 "theirs": ("#ffffff", "#000000", "#a1aab3"), "ours": ("#effedd", "#000000", "#5fae6f")},
]
THEME = THEMES[0]
WEEK = ["du", "se", "ch", "pa", "ju", "sh", "ya"]
MONTHS = ["yanvar", "fevral", "mart", "aprel", "may", "iyun", "iyul", "avgust", "sentabr", "oktabr",
          "noyabr", "dekabr"]


def set_theme(theme_id: str):
	global THEME
	THEME = next((t for t in THEMES if t["id"] == theme_id), THEMES[0])


def colors(which: str, theme: dict = None) -> tuple:
	"""A theme's (fill, text, small text) for "theirs", "ours" or "card" as QColors."""
	t = theme or THEME
	return tuple(QColor(c) for c in t.get(which) or t["theirs"])


# where the four colours are (Telegram's freeform gradient: the first of each pair it turns between)
_WALL_AT = ((0.80, 0.10), (0.35, 0.25), (0.20, 0.90), (0.65, 0.75))
_walls = {}


def wallpaper(wall: tuple, w: int = 60, h: int = 126) -> QImage:
	"""The four colours blended by nearness, small (it is smooth: drawn large it stays smooth)."""
	key = (wall, w, h)
	if key not in _walls:
		cols = [QColor(c) for c in wall]
		rgb = [(c.red(), c.green(), c.blue()) for c in cols]
		img = QImage(w, h, QImage.Format_RGB32)
		for y in range(h):
			v = y / max(1, h - 1)
			for x in range(w):
				u = x / max(1, w - 1)
				ws = [max(0.0, 0.9 - ((u - px) ** 2 + (v - py) ** 2) ** 0.5) ** 4 for px, py in _WALL_AT]
				total = sum(ws) or 1.0
				r = sum(k * c[0] for k, c in zip(ws, rgb)) / total
				g = sum(k * c[1] for k, c in zip(ws, rgb)) / total
				b = sum(k * c[2] for k, c in zip(ws, rgb)) / total
				img.setPixel(x, y, 0xff000000 | (int(r) << 16) | (int(g) << 8) | int(b))
		_walls[key] = img
	return _walls[key]


def bubble_path(rect: QRectF, r: float, small: str) -> QPainterPath:
	"""A box with round corners, the one at `small` ("tl", "tr" or "") less round (where its tail would be)."""
	rad = {k: (3.0 if k == small else r) for k in ("tl", "tr", "br", "bl")}
	x0, y0, x1, y1 = rect.left(), rect.top(), rect.right(), rect.bottom()
	path = QPainterPath(QPointF(x0 + rad["tl"], y0))
	path.lineTo(x1 - rad["tr"], y0)
	path.arcTo(QRectF(x1 - 2 * rad["tr"], y0, 2 * rad["tr"], 2 * rad["tr"]), 90, -90)
	path.lineTo(x1, y1 - rad["br"])
	path.arcTo(QRectF(x1 - 2 * rad["br"], y1 - 2 * rad["br"], 2 * rad["br"], 2 * rad["br"]), 0, -90)
	path.lineTo(x0 + rad["bl"], y1)
	path.arcTo(QRectF(x0, y1 - 2 * rad["bl"], 2 * rad["bl"], 2 * rad["bl"]), 270, -90)
	path.lineTo(x0, y0 + rad["tl"])
	path.arcTo(QRectF(x0, y0, 2 * rad["tl"], 2 * rad["tl"]), 180, -90)
	path.closeSubpath()
	return path


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
	the corner at the top right; a channel's post a card across the page. In
	a round theme (THEME["round"]) the box is round, the corner a less round one."""
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
		self.side = 0.0 if THEME["round"] else self.CORNER		# room for the corner
		if self._card():
			self.max_w = PAGE_W
		else:
			self.max_w = min(251.0 + self.CORNER - self.side, PAGE_W - self.side - (self.AV + 6 if self._avatar() else 0))
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
		fill, ink, subtle = colors("card" if card else "ours" if out else "theirs")
		if m.get("pending"):
			fill.setAlphaF(0.6)
		y, r = 0.0, THEME["round"]
		if card:
			x = 0.0
		elif out:
			x = w - self.side - self.box_w
		else:
			x = self.side + (self.AV + 6 if self._avatar() else 0)
		if self._avatar():
			draw_avatar(p, 0, y, self.AV, m.get("sender_id", 0), m.get("sender", ""), 14)
		box = QRectF(x, y, self.box_w, self.box_h)
		if r:
			p.fillPath(bubble_path(box, r, "" if card else "tr" if out else "tl"), fill)
		else:
			p.fillRect(box, fill)
			if not card:
				if out:
					corner = QPainterPath(QPointF(x + self.box_w, y + self.CORNER))
					corner.lineTo(x + self.box_w + self.CORNER, y + self.CORNER)
					corner.lineTo(x + self.box_w, y + 2 * self.CORNER)
				else:
					corner = QPainterPath(QPointF(x, y + self.CORNER))
					corner.lineTo(x - self.CORNER, y + self.CORNER)
					corner.lineTo(x, y + 2 * self.CORNER)
				corner.closeSubpath()
				p.fillPath(corner, fill)

		ty = y + self.PAD
		if self.name_h:
			name = tile_color(m.get("sender_id", 0))
			p.setPen(name.lighter(150) if fill.lightness() < 128 else name)
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
		p.setFont(_font(FONT_SEMIBOLD, 13))
		if THEME["wall"]:	# a pill that reads on any wallpaper
			w = QFontMetricsF(p.font()).horizontalAdvance(self.text) + 20
			pill = QRectF((self.width() - w) / 2, 6, w, 22)
			p.setPen(Qt.NoPen)
			p.setBrush(QColor(0, 0, 0, 80))
			p.drawRoundedRect(pill, 11, 11)
			p.setPen(QColor("white"))
		else:
			p.setPen(GREY)
		p.drawText(QRectF(0, 4, self.width(), 26), Qt.AlignHCenter | Qt.AlignVCenter, self.text)


class UnreadLabel(Cached):
	"""Where the unread messages start."""

	def __init__(self, count: int):
		super().__init__()
		self.count = count
		self.setFixedHeight(36)

	def draw(self, p: QPainter):
		p.fillRect(QRectF(0, 6, self.width(), 24), QColor(0, 0, 0, 110) if THEME["wall"] else CHROME)
		p.setPen(ztos.accent().lighter(130) if THEME["wall"] else ztos.accent())
		p.setFont(_font(FONT_SEMIBOLD, 13))
		p.drawText(QRectF(0, 6, self.width(), 24), Qt.AlignCenter,
		           f"{self.count} ta o'qilmagan xabar" if self.count else "o'qilmagan xabarlar")


class ThemeRow(_Pressable):
	"""A chat theme to pick: a small picture of a chat in it, and its name."""
	H = 98

	def __init__(self, theme: dict, on_tap):
		super().__init__()
		self.theme = theme
		self.setSizePolicy(QSizePolicy.Expanding, QSizePolicy.Fixed)
		self.setFixedHeight(self.H)
		self.tapped.connect(lambda: on_tap(self.theme))

	def draw(self, p: QPainter):
		t = self.theme
		p.setRenderHints(QPainter.Antialiasing | QPainter.TextAntialiasing | QPainter.SmoothPixmapTransform)
		pic = QRectF(0, 8, 64, self.H - 16)
		frame = QPainterPath()
		frame.addRoundedRect(pic, 8, 8)
		p.save()
		p.setClipPath(frame)
		if t["wall"]:
			p.drawImage(pic, wallpaper(t["wall"], 24, 40))
		else:
			p.fillRect(pic, QColor("black"))
		r = t["round"]
		for which, x, y, w in (("theirs", 6, 18, 38), ("ours", 20, 42, 38), ("theirs", 6, 62, 30)):
			fill = colors(which, t)[0]
			box = QRectF(pic.left() + x, pic.top() + y - 8, w, 16)
			if r:
				p.fillPath(bubble_path(box, 6, "tr" if which == "ours" else "tl"), fill)
			else:
				p.fillRect(box, fill)
		p.restore()
		p.setPen(QPen(QColor(255, 255, 255, 60), 1))
		p.setBrush(Qt.NoBrush)
		p.drawPath(frame)
		x = pic.right() + 16
		on = t is THEME
		p.setPen(QColor("white"))
		p.setFont(_font(FONT_SEMILIGHT, 25))
		p.drawText(QPointF(x, self.H / 2 + 4), t["name"])
		p.setFont(_font(FONT_REGULAR, 14))
		p.setPen(ztos.accent() if on else GREY)
		p.drawText(QPointF(x, self.H / 2 + 26), "tanlangan" if on else "Windows Phone" if not t["wall"] else
		           "yumaloq pufakchalar, rangli fon")


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
		# a chat theme's wallpaper, fixed behind the list (see set_wallpaper)
		self.wallpaper = None
		self._wall = self._wall_key = None
		self._wall_gen = self._wall_up = 0

	def set_wallpaper(self, wall):
		"""Four colours (views.THEMES) blended behind the list, which is see-through over them."""
		self.wallpaper = wall
		if wall:
			self.body.setStyleSheet("#ztosBody { background: transparent; }")
			self.viewport.installEventFilter(self)

	def wall_image(self) -> QImage:
		"""The wallpaper as large as the viewport, a pixel a point (drawn larger it stays smooth)."""
		size = self.viewport.size()
		key = (self.wallpaper, size.width(), size.height())
		if self._wall_key != key:
			self._wall = wallpaper(self.wallpaper).scaled(max(1, size.width()), max(1, size.height()),
			                                              Qt.IgnoreAspectRatio, Qt.SmoothTransformation)
			self._wall_key = key
			self._wall_gen += 1
		return self._wall

	def eventFilter(self, obj, event):
		if obj is self.viewport and self.wallpaper and event.type() == QEvent.Paint:
			p = QPainter(self.viewport)
			p.setRenderHint(QPainter.SmoothPixmapTransform, True)
			p.drawImage(QRectF(self.viewport.rect()), self.wall_image())
			p.end()
			return True
		return super().eventFilter(obj, event)

	def _clear(self) -> QColor:
		return QColor(Qt.transparent) if self.wallpaper else QColor("black")

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
		col.fill(self._clear())
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
		image.fill(self._clear())
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
		if self.wallpaper:
			self.wall_image()
			if self._wall_up != self._wall_gen or not layer.has((id(self), "wall")):
				layer.upload((id(self), "wall"), self._wall)
				self._wall_up = self._wall_gen
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
		if self.wallpaper and layer.has((id(self), "wall")):
			quads.append(Quad.rect((id(self), "wall"), ztos._WHOLE, self._gl_ox, self._gl_oy, w, view))
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
