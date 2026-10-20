"""Tepegram's own pieces, drawn the Windows Phone 8.1 way: square avatars in
the accent's family, chats as rows of the People hub, messages as the
Messaging app's speech bubbles (received ones in the accent with the tail at
the top, sent ones darker with the tail at the bottom)."""
import time
from datetime import datetime

from PySide6.QtCore import QPointF, QRectF, Qt
from PySide6.QtGui import QColor, QFontMetricsF, QPainter, QPainterPath
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


class Bubble(QWidget):
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
		self.update()

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

	def paintEvent(self, event):
		m, w = self.msg, self.width()
		p = QPainter(self)
		p.setRenderHints(QPainter.Antialiasing | QPainter.TextAntialiasing)
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
		p.end()


class DayLabel(QWidget):
	"""A day's name between bubbles."""

	def __init__(self, stamp: float):
		super().__init__()
		self.text = day_title(stamp)
		self.setFixedHeight(34)

	def paintEvent(self, event):
		p = QPainter(self)
		p.setRenderHints(QPainter.TextAntialiasing)
		p.setPen(GREY)
		p.setFont(_font(FONT_REGULAR, 13))
		p.drawText(QRectF(0, 4, self.width(), 26), Qt.AlignLeft | Qt.AlignVCenter, self.text)
		p.end()


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
