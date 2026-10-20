"""The bottom bar as iOS 26 draws it, "liquid glass": capsules and circles
that float over the list, the list moving under them blurred and bent at
their rims. Shapes, sizes and tints are Telegram for iOS's (TabBarComponent,
GlassBackgroundComponent; GPL-2.0, its look, not its code): a bar 56 tall
with an inset of 4, the selected tab in a lighter lens, a round search
button as tall as the bar beside it, 8 between them; a dark grey tint and a
thin bright rim. The icons are our own (Apple's are for Apple's systems).

The blur costs next to nothing: each tile of the list (views.TiledPage)
leaves a copy of itself at a sixteenth of the points, blurred, and the glass
is that copy, drawn back large -- in strips half a point tall, each strip as
wide as the shape is at that height (so the shape is round) and taken from a
little further out the nearer it is to the rim (so the rim bends what is
under it, as a lens does). The same strips are GPU quads while the list
moves and QPainter calls while it is still, so the two look the same."""
import math

from PySide6.QtCore import QEvent, QPoint, QPointF, QRect, QRectF, Qt
from PySide6.QtGui import QColor, QFontMetricsF, QImage, QLinearGradient, QPainter, QPainterPath, QPalette, QPen, \
	QPixmap, QRegion
from PySide6.QtWidgets import QWidget

import ztos
from ztos import FONT_REGULAR, FONT_SEMIBOLD, _font

TINT = QColor(40, 40, 44, 110)		# the panel's dark grey (Telegram's 0.11 white over black), see-through
LENS = QColor(255, 255, 255, 28)		# under the selected tab
LENS_PRESSED = QColor(255, 255, 255, 54)
STEP = 0.5				# a strip's height, points (drawn on the CPU)
BANDS = 14				# trapezoids a shape is cut into (drawn on the GPU)
BEND = 0.45				# how much further out the rim takes what it shows


def icon(p: QPainter, name: str, cx: float, cy: float, size: float, color: QColor, filled: bool = False):
	"""Our own line icons, `size` across, about (cx, cy)."""
	s = size / 2
	p.save()
	p.translate(cx, cy)
	pen = QPen(color, size / 13, Qt.SolidLine, Qt.RoundCap, Qt.RoundJoin)
	p.setPen(pen)
	p.setBrush(color if filled else Qt.NoBrush)
	path = QPainterPath()
	if name == "chats":		# a speech bubble with its tail at the lower left
		path.addRoundedRect(QRectF(-s, -s * 0.82, 2 * s, s * 1.5), s * 0.62, s * 0.62)
		tail = QPainterPath(QPointF(-s * 0.55, s * 0.5))
		tail.lineTo(-s * 0.85, s * 0.95)
		tail.lineTo(-s * 0.1, s * 0.62)
		path = path.united(tail)
	elif name == "contacts":	# a head and shoulders
		path.addEllipse(QPointF(0, -s * 0.38), s * 0.42, s * 0.42)
		body = QPainterPath(QPointF(-s * 0.85, s * 0.9))
		body.cubicTo(-s * 0.85, s * 0.15, s * 0.85, s * 0.15, s * 0.85, s * 0.9)
		body.closeSubpath()
		path.addPath(body)
	elif name == "settings":	# a gear: eight teeth around a ring
		gear = QPainterPath()
		for k in range(16):
			a = math.pi * 2 * k / 16
			r = s * (0.95 if k % 2 == 0 else 0.72)
			for da in (-0.17, 0.17):
				pt = QPointF(r * math.cos(a + da), r * math.sin(a + da))
				gear.moveTo(pt) if k == 0 and da < 0 else gear.lineTo(pt)
		gear.closeSubpath()
		path.addPath(gear)
		hole = QPainterPath()
		hole.addEllipse(QPointF(0, 0), s * 0.3, s * 0.3)
		if filled:
			path = path.subtracted(hole)
		else:
			path.addPath(hole)
	elif name == "search":
		path.addEllipse(QPointF(-s * 0.15, -s * 0.15), s * 0.62, s * 0.62)
		path.moveTo(s * 0.32, s * 0.32)
		path.lineTo(s * 0.85, s * 0.85)
	elif name == "up":		# send, as iOS draws it: an arrow up
		path.moveTo(0, s * 0.8)
		path.lineTo(0, -s * 0.75)
		path.moveTo(-s * 0.62, -s * 0.15)
		path.lineTo(0, -s * 0.8)
		path.lineTo(s * 0.62, -s * 0.15)
	elif name == "down":
		path.moveTo(0, -s * 0.8)
		path.lineTo(0, s * 0.75)
		path.moveTo(-s * 0.62, s * 0.15)
		path.lineTo(0, s * 0.8)
		path.lineTo(s * 0.62, s * 0.15)
	elif name == "refresh":
		r = QRectF(-s * 0.75, -s * 0.75, s * 1.5, s * 1.5)
		path.arcMoveTo(r, 70)
		path.arcTo(r, 70, 290)
		path.moveTo(s * 0.05, -s * 1.0)
		path.lineTo(s * 0.32, -s * 0.72)
		path.lineTo(s * 0.02, -s * 0.45)
	if name in ("search", "up", "down", "refresh"):
		p.setBrush(Qt.NoBrush)
	p.drawPath(path)
	p.restore()


class GlassBar(QWidget):
	"""Shapes along the foot of `host` (a page, or a pivot of pages), over its
	list. `parts` from left to right:
	  ("tabs", [(icon, word, on_tap), ...])   a capsule of tabs, one selected
	  ("circle", icon, on_tap[, lit])         a round button (filled with the accent while lit())
	  ("field", ztos.TextBox)                 a capsule to write in
	  ("space",)                              room between them
	tabs, field and space share what is left of the width.

	The bar is a strip across the whole foot and paints all of it (outside
	the shapes, the list itself as it is there): so nothing under it repaints
	when it does (a cursor blinking, a tab pressed), which would count as a
	change of the list."""
	FOOT = 8.0		# under the shapes
	SIDE = 12.0
	GAP = 8.0
	INSET = 4.0

	def __init__(self, host: QWidget, parts: list, height: float = 64.0, page=None):
		super().__init__(host)
		self.host = host
		self.parts = list(parts)
		self.h = height
		self.page_of = page or (lambda: host)		# the TiledPage under it now
		self.selected = 0
		self.pressed = None		# (part index, tab index)
		self.setAttribute(Qt.WA_OpaquePaintEvent)
		self._cache = None
		self._cache_key = None
		self._over = None		# the shapes' tint, rims and icons, transparent around them
		self._over_key = None
		self._over_gen = 0
		self._gpu_key = None
		self._still_key = None
		self._bands = None
		self._gl_at = None
		for part in self.parts:
			if part[0] == "field":
				self._own_field(part[1])
		host.installEventFilter(self)
		self._place()
		self.show()
		self.raise_()

	# where it is
	def space(self) -> int:
		"""What the list keeps free at its foot, to come out from under the bar."""
		return int(self.h + self.FOOT + 10)

	def eventFilter(self, obj, event):
		if obj is self.host and event.type() == QEvent.Resize:
			self._place()
		return False

	def _place(self):
		hh = int(math.ceil(self.h + self.FOOT))
		self.setGeometry(0, self.host.height() - hh, self.host.width(), hh)
		self._layout()
		self.raise_()

	def _layout(self):
		w = float(self.width())
		fixed = sum(self.h for p in self.parts if p[0] == "circle")
		flex = [p for p in self.parts if p[0] in ("tabs", "field", "space")]
		room = w - 2 * self.SIDE - fixed - self.GAP * (len(self.parts) - 1)
		x = self.SIDE
		self.shapes = []		# (part index, rect, radius)
		for i, part in enumerate(self.parts):
			pw = self.h if part[0] == "circle" else room / max(1, len(flex))
			if part[0] != "space":
				self.shapes.append((i, QRectF(x, 0, pw, self.h), self.h / 2))
				if part[0] == "field":
					part[1].setGeometry(QRect(round(x + 6), round((self.h - 40) / 2), round(pw - 12), 40))
			x += pw + self.GAP
		self._bands = None
		self._over = None
		self.update()

	def _own_field(self, box):
		box.setParent(self)
		f = box.field
		f.setStyleSheet("QLineEdit, QLineEdit:focus { background: transparent; color: white; border: none;"
		                " padding: 0px 10px; font-size: 17px; selection-background-color: %s; }" % ztos.accent().name())
		pal = f.palette()
		pal.setColor(QPalette.PlaceholderText, QColor(255, 255, 255, 110))
		f.setPalette(pal)
		f.textChanged.connect(lambda _: self._restyle())
		box.show()

	def _restyle(self):
		self._over = None
		self.update()

	def select(self, i: int):
		if i != self.selected:
			self.selected = i
			self._restyle()

	# the bands
	def bands(self) -> list:
		"""Each shape cut across into BANDS trapezoids, evenly by the angle
		round its ends (thin where the rim turns fast): (y0, y1, left and
		right at y0, at y1; whence: x0, x1, y0, y1). The whence is further out
		near the rim: the bend."""
		if self._bands is None:
			out = []
			for _, rect, r in self.shapes:
				cy, cx = rect.center().y(), rect.center().x()

				def at(y):
					dy = min(r, max(-r, y - cy))
					half = math.sqrt(max(0.0, r * r - dy * dy))
					return rect.left() + r - half, rect.right() - r + half

				def whence(y):
					d = (y - cy) / r
					return cy + (y - cy) * (1 + BEND * d ** 4)

				ys = [cy - r * math.cos(math.pi * k / BANDS) for k in range(BANDS + 1)]
				for y0, y1 in zip(ys, ys[1:]):
					l0, r0 = at(y0)
					l1, r1 = at(y1)
					ml, mr = at((y0 + y1) / 2)
					grow = 1 + BEND * 0.5 * (1.0 - (mr - ml - rect.width() + 2 * r) / (2 * r))
					out.append((y0, y1, l0, r0, l1, r1, cx - (cx - ml) * grow, cx + (mr - cx) * grow,
					            whence(y0), whence(y1)))
			self._bands = out
		return self._bands

	def _offset(self, page) -> QPointF:
		"""Where the bar's (0, 0) is on the page's list, at scroll 0."""
		win = self.window()
		at = self.mapTo(win, QPoint(0, 0)) - page.viewport.mapTo(win, QPoint(0, 0))
		return QPointF(at.x(), at.y())

	def _pieces(self, page, scroll: float, o: QPointF):
		"""The bands as they fall on the blurred tiles (one cut in two where it
		crosses from one tile to the next): (tile, y0, y1, l0, r0, l1, r1, u0, u1, v0, v1)."""
		blur = page._blur
		if not blur:
			return
		vw = float(page.viewport.width())
		T = page.TILE
		heights = page._tile_h
		top = o.y() + scroll
		for y0, y1, l0, r0, l1, r1, s0, s1, w0, w1 in self.bands():
			u0, u1 = (o.x() + s0) / vw, (o.x() + s1) / vw
			b0, b1 = top + w0, top + w1
			while b1 - b0 > 1e-3:
				j = int(b0 // T)
				end = min(b1, (j + 1) * T)
				f = (end - b0) / (b1 - b0)
				y = y0 + (y1 - y0) * f
				l, r = l0 + (l1 - l0) * f, r0 + (r1 - r0) * f
				th = heights.get(j)
				if b0 >= 0 and th and j in blur:
					yield j, y0, y, l0, r0, l, r, u0, u1, (b0 - j * T) / th, (end - j * T) / th
				b0, y0, l0, r0 = end, y, l, r

	def _paint_strips(self, p: QPainter, page, scroll: float):
		"""The bands on the CPU: in strips STEP tall, each as wide as its band is there."""
		p.setRenderHint(QPainter.SmoothPixmapTransform, True)
		blur = page._blur
		for j, y0, y1, l0, r0, l1, r1, u0, u1, v0, v1 in self._pieces(page, scroll, self._offset(page)):
			img = blur[j]
			W, H = img.width(), img.height()
			y = y0
			while y < y1 - 1e-3:
				h = min(STEP, y1 - y)
				f = (y + h / 2 - y0) / (y1 - y0)
				l, r = l0 + (l1 - l0) * f, r0 + (r1 - r0) * f
				v = v0 + (v1 - v0) * f
				p.drawImage(QRectF(l, y, r - l, h), img, QRectF(u0 * W, v * H - 0.25, (u1 - u0) * W, 0.5))
				y += h

	# the shapes' own look
	def _paint_over(self, p: QPainter):
		p.setRenderHints(QPainter.Antialiasing | QPainter.TextAntialiasing)
		for i, rect, r in self.shapes:
			part = self.parts[i]
			path = QPainterPath()
			path.addRoundedRect(rect, r, r)
			p.fillPath(path, TINT)
			# the rim: bright at the top, faint at the foot
			g = QLinearGradient(rect.topLeft(), rect.bottomLeft())
			g.setColorAt(0.0, QColor(255, 255, 255, 120))
			g.setColorAt(0.5, QColor(255, 255, 255, 30))
			g.setColorAt(1.0, QColor(255, 255, 255, 70))
			p.setPen(QPen(g, 1.0))
			p.setBrush(Qt.NoBrush)
			p.drawRoundedRect(rect.adjusted(0.5, 0.5, -0.5, -0.5), r - 0.5, r - 0.5)
			pressed = self.pressed is not None and self.pressed[0] == i
			if part[0] == "tabs":
				self._paint_tabs(p, i, rect)
			elif part[0] == "circle":
				lit = len(part) > 3 and part[3]()
				if lit or pressed:
					p.setPen(Qt.NoPen)
					p.setBrush(ztos.accent().lighter(130) if lit and pressed else ztos.accent() if lit
					           else LENS_PRESSED)
					p.drawEllipse(rect.adjusted(3, 3, -3, -3))
				icon(p, part[1], rect.center().x(), rect.center().y(), self.h * 0.42, QColor("white"))

	def _tab_rects(self, rect: QRectF, n: int) -> list:
		inner = rect.adjusted(self.INSET, self.INSET, -self.INSET, -self.INSET)
		w = inner.width() / n
		return [QRectF(inner.left() + k * w, inner.top(), w, inner.height()) for k in range(n)]

	def _paint_tabs(self, p: QPainter, i: int, rect: QRectF):
		tabs = self.parts[i][1]
		rects = self._tab_rects(rect, len(tabs))
		pressed = self.pressed[1] if self.pressed is not None and self.pressed[0] == i else -1
		for k, (name, word, _) in enumerate(tabs):
			t = rects[k]
			on = k == self.selected
			if on or k == pressed:
				p.setPen(Qt.NoPen)
				p.setBrush(LENS_PRESSED if k == pressed else LENS)
				p.drawRoundedRect(t, t.height() / 2, t.height() / 2)
			color = ztos.accent() if on else QColor("white")
			icon(p, name, t.center().x(), t.top() + t.height() * 0.40, t.height() * 0.46, color, on)
			p.setPen(color)
			p.setFont(_font(FONT_SEMIBOLD, 10.5))
			p.drawText(QRectF(t.left(), t.bottom() - 19, t.width(), 14), Qt.AlignHCenter | Qt.AlignVCenter, word)

	def _overlay(self) -> QImage:
		"""The shapes' tint, rims and icons at the screen's resolution, transparent around them."""
		ratio = self.devicePixelRatioF()
		lit = tuple(bool(p[3]()) for p in self.parts if p[0] == "circle" and len(p) > 3)
		key = (self.size(), ratio, self.selected, self.pressed, lit)
		if self._over is None or self._over_key != key:
			img = QImage(max(1, round(self.width() * ratio)), max(1, round(self.height() * ratio)),
			             QImage.Format_RGBA8888_Premultiplied)
			img.setDevicePixelRatio(ratio)
			img.fill(Qt.transparent)
			p = QPainter(img)
			self._paint_over(p)
			p.end()
			self._over, self._over_key = img, key
			self._over_gen += 1
		return self._over

	def _children(self, p: QPainter):
		"""The boxes to write in, as they are now (for a picture of the bar)."""
		for part in self.parts:
			if part[0] == "field" and part[1].isVisible():
				box = part[1]
				box.render(p, box.pos(), QRegion(), QWidget.RenderFlag.DrawChildren)

	# still: the widget
	def paintEvent(self, event):
		page = self.page_of()
		scroll = getattr(page, "_scroll", 0.0)
		ratio = self.devicePixelRatioF()
		self._overlay()
		key = (id(page), round(scroll * ratio), getattr(page, "glass_gen", 0), self.size(), ratio, self._over_gen)
		if self._cache is None or self._cache_key != key:
			self._cache = self._compose(page, scroll, ratio, opaque=True)
			self._cache_key = key
		p = QPainter(self)
		p.drawPixmap(0, 0, self._cache)
		p.end()

	def _compose(self, page, scroll: float, ratio: float, opaque: bool, children: bool = False):
		if opaque:
			img = QPixmap(max(1, round(self.width() * ratio)), max(1, round(self.height() * ratio)))
			img.setDevicePixelRatio(ratio)
			img.fill(QColor("black"))
		else:
			img = QImage(max(1, round(self.width() * ratio)), max(1, round(self.height() * ratio)),
			             QImage.Format_RGBA8888_Premultiplied)
			img.setDevicePixelRatio(ratio)
			img.fill(Qt.transparent)
		p = QPainter(img)
		if opaque and hasattr(page, "body"):
			# the list as it is under the strip, sharp (its paints are ours, not changes of it)
			o = self._offset(page)
			top = round(o.y() + scroll)
			ztos._drawing_pictures += 1
			try:
				page.body.render(p, QPoint(0, 0), QRegion(round(o.x()), top, self.width(), self.height()),
				                 QWidget.RenderFlag.DrawChildren | QWidget.RenderFlag.DrawWindowBackground)
			finally:
				ztos._drawing_pictures -= 1
		if hasattr(page, "_blur"):
			if opaque:
				# under the shapes only the blur
				clip = QPainterPath()
				for _, rect, r in self.shapes:
					clip.addRoundedRect(rect, r, r)
				p.save()
				p.setClipPath(clip)
				p.fillRect(self.rect(), QColor("black"))
				p.restore()
			self._paint_strips(p, page, scroll)
		p.drawImage(QPointF(0, 0), self._overlay())
		if children:
			self._children(p)
		p.end()
		return img

	# moving: GPU quads
	def gpu_prepare(self, layer):
		"""Before a motion: the shapes' look (and what is written in them) on the GPU."""
		over = self._overlay()
		texts = tuple(p[1].text() for p in self.parts if p[0] == "field")
		key = (self._over_gen, texts)
		if self._gpu_key == key and layer.has((id(self), "over")):
			return
		img = QImage(over)
		if texts:
			p = QPainter(img)
			self._children(p)
			p.end()
		layer.upload((id(self), "over"), img)
		self._gpu_key = key

	def gpu_where(self, page):
		"""Where it is in the window and on the page's list: worked out once a motion."""
		at = self.mapTo(self.window(), QPoint(0, 0))
		self._gl_at = (float(at.x()), float(at.y()), self._offset(page))

	def gpu_quads(self, page, scroll: float, layer) -> list:
		from ztos._gl import Quad
		if self._gl_at is None:
			self.gpu_where(page)
		ox, oy, o = self._gl_at
		quads = []
		has = layer.has
		pid = id(page)
		for j, y0, y1, l0, r0, l1, r1, u0, u1, v0, v1 in self._pieces(page, scroll, o):
			key = (pid, "blur", j)
			if has(key):
				quads.append(Quad(key, QRectF(u0, v0, u1 - u0, v1 - v0),
				                  ((ox + l0, oy + y0, 1.0), (ox + r0, oy + y0, 1.0),
				                   (ox + l1, oy + y1, 1.0), (ox + r1, oy + y1, 1.0))))
		if has((id(self), "over")):
			quads.append(Quad.rect((id(self), "over"), ztos._WHOLE, ox, oy, float(self.width()), float(self.height())))
		return quads

	def still_quads(self, layer) -> list:
		"""The bar as one picture, for a motion that is not of the list under
		it (a pivot's tabs sliding): its glass stays as it was."""
		from ztos._gl import Quad
		page = self.page_of()
		scroll = getattr(page, "_scroll", 0.0)
		ratio = self.devicePixelRatioF()
		self._overlay()
		key = (id(page), round(scroll * ratio), getattr(page, "glass_gen", 0), self._over_gen,
		       tuple(p[1].text() for p in self.parts if p[0] == "field"))
		if self._still_key != key or not layer.has((id(self), "still")):
			layer.upload((id(self), "still"), self._compose(page, scroll, ratio, opaque=False, children=True))
			self._still_key = key
		at = self.mapTo(self.window(), QPoint(0, 0))
		return [Quad.rect((id(self), "still"), ztos._WHOLE, float(at.x()), float(at.y()),
		                  float(self.width()), float(self.height()))]

	# touch
	def _hit(self, pos: QPointF):
		for i, rect, r in self.shapes:
			if rect.adjusted(-4, -6, 4, 6).contains(pos):
				part = self.parts[i]
				if part[0] == "tabs":
					for k, t in enumerate(self._tab_rects(rect, len(part[1]))):
						if t.left() - 4 <= pos.x() < t.right() + 4:
							return i, k
					return None
				return i, -1
		return None

	def mousePressEvent(self, event):
		hit = self._hit(event.position())
		if hit is not None and self.parts[hit[0]][0] in ("tabs", "circle"):
			self.pressed = hit
			self._restyle()

	def mouseReleaseEvent(self, event):
		hit, was = self._hit(event.position()), self.pressed
		self.pressed = None
		self._restyle()
		if was is None or hit != was:
			return
		part = self.parts[hit[0]]
		ztos.haptic("tap")
		if part[0] == "tabs":
			part[1][hit[1]][2]()
		elif part[0] == "circle":
			part[2]()
