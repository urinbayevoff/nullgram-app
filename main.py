"""Tepegram: a Telegram client for ztOS phones, in the Windows Phone 8.1 look.

Pages are 360 points wide on every screen (the shell scales them), so the
same app fits the Galaxy S10 5G and other phones. Telegram itself runs on
tg.Backend's own thread; this file only draws and reacts to its signals.
"""
import itertools
import os
import sys
import time

# Qt draws letters over 64 pixels from their outlines every time, uncached; at
# the S10's 4x that is all of them (a 21-point name is 84 pixels). Cached they
# draw 4x faster. Read when the first text is drawn, so before anything is.
os.environ.setdefault("QT_MAX_CACHED_GLYPH_SIZE", "256")

from PySide6.QtCore import QPoint, QTimer
from PySide6.QtGui import QGuiApplication
from PySide6.QtCore import Qt

import ztos
from tg import Backend, preview
from views import (Bubble, ChatRow, CompactBar, ContactRow, DayLabel, List, QrView, TiledPage, UnreadLabel,
                   changed, day_title, set_photo, stamp_now)

app = ztos.App()
tg = Backend()
_local_ids = itertools.count(-1, -1)	# ids for bubbles shown before Telegram gives theirs


class Connecting(ztos.Page):
	def __init__(self):
		super().__init__("tepegram")
		self.status = self.text("Telegram'ga ulanmoqda...", 15)

	def shown(self):
		self.busy(True)


class Login(ztos.Page):
	"""Sign in: the QR code to scan from a phone already signed in, or the number and its code."""

	def __init__(self):
		super().__init__("kirish")
		self.text("Asosiy telefoningizdagi Telegram'da: Sozlamalar → Qurilmalar → "
		          "Qurilmani ulash. Keyin shu kodni skanerlang.", 15)
		self.qr = self.add(QrView())
		self.space(8)
		self.entry("raqam bilan kirish", "Telegram yoki SMS orqali kod keladi", lambda: app.push(PhoneLogin()))
		tg.qr.connect(self.qr.set_url)

	def shown(self):
		tg.login_qr()


class PhoneLogin(ztos.Page):
	"""The number, then the code Telegram sends, then the cloud password if there is one."""

	def __init__(self):
		super().__init__("raqam")
		self.stage = "phone"
		self.error = None
		self._build()
		self.bar(ztos.RoundButton("check", "davom", self.go))
		tg.need.connect(self._need)
		tg.login_error.connect(self._error)

	def _build(self):
		self.clear()
		if self.stage == "phone":
			self.text("Telefon raqamingizni xalqaro shaklda kiriting.", 15)
			self.box = self.textbox("telefon raqami", "+998", on_submit=lambda _: self.go())
		elif self.stage == "code":
			self.text("Telegram yuborgan kodni kiriting (boshqa qurilmangizdagi Telegram'ga yoki SMS'ga keladi).", 15)
			self.box = self.textbox("kod", on_submit=lambda _: self.go())
		else:
			self.text("Hisobingizda ikki bosqichli tekshiruv yoqilgan. Bulut parolini kiriting.", 15)
			self.box = self.textbox("parol", password=True, on_submit=lambda _: self.go())
		self.error = self.text("", 14, ztos.accent())

	def go(self):
		value = self.box.text().strip()
		if not value:
			return
		self.busy(True)
		self.error.setText("")
		{"phone": tg.login_phone, "code": tg.login_code, "password": tg.login_password}[self.stage](value)

	def _need(self, what: str):
		self.busy(False)
		self.stage = what
		self._build()

	def _error(self, text: str):
		self.busy(False)
		self.error.setText(text)


class Chats(TiledPage):
	"""Every chat, pinned first then newest.

	New messages (channels send many) are gathered and put on the list together,
	every 1.5 s at most and only while it is still: each one moves a row, and a
	moved row means tiles drawn again."""

	def __init__(self):
		super().__init__("chatlar")
		self.chat_list = self.add(List())
		self.rows = {}
		self._waiting = {}
		self._apply = QTimer(self, singleShot=True, interval=1500)
		self._apply.timeout.connect(self._apply_waiting)
		tg.chats.connect(self._chats)
		tg.incoming.connect(self._incoming)
		tg.sent.connect(lambda _local, m: self._touch(m["chat"]))

	def shown(self):
		if not self.rows:
			self.busy(True)

	def refresh(self):
		self.busy(True)
		tg.load_chats()

	def _chats(self, chats: list):
		self.busy(False)
		self.rows = {}
		self.chat_list.clear()
		for c in chats:
			self.rows[c["id"]] = self.chat_list.add(ChatRow(c, open_chat))
		update_tile()

	def _incoming(self, msg: dict, chat: dict):
		self._waiting.pop(chat["id"], None)
		self._waiting[chat["id"]] = chat		# (newest last)
		if not self._apply.isActive():
			self._apply.start()

	def _apply_waiting(self):
		if self._gl_on or self._flinging() or ztos._animating():
			self._apply.start()
			return
		waiting, self._waiting = self._waiting, {}
		for chat in waiting.values():
			row = self.rows.get(chat["id"])
			if row is None:
				row = ChatRow(chat, open_chat)
				self.rows[chat["id"]] = row
			else:
				row.update_chat(chat)
			self._to_top(row)
		update_tile()

	def _touch(self, chat_id: int):
		row = self.rows.get(chat_id)
		if row:
			row.update_chat(tg._chats.get(chat_id, row.chat))
			self._to_top(row)

	def _to_top(self, row):
		# newest under the pinned ones
		pinned = sum(1 for r in self.chat_list.rows() if r is not row and r.chat.get("pinned"))
		if row.chat.get("pinned"):
			return
		self.chat_list.box.removeWidget(row)
		self.chat_list.add(row, pinned)


class Contacts(TiledPage):
	"""Everyone in the address book who is on Telegram, by name."""

	def __init__(self):
		super().__init__("kontaktlar")
		self.people = self.add(List())
		self.rows = {}
		tg.contacts.connect(self._contacts)

	def shown(self):
		if not self.rows:
			self.busy(True)
			tg.load_contacts()

	def _contacts(self, people: list):
		self.busy(False)
		self.people.clear()
		self.rows = {c["id"]: self.people.add(ContactRow(c, open_chat)) for c in people}


class Chat(TiledPage):
	"""One conversation, newest at the bottom, and a box to write in under it
	that stays put (off the list, so its cursor is not a change of it). With
	unread messages it opens where they start. Older ones come when the list
	stops near its top, newer ones (if it opened among the unread) near its foot."""
	NEAR = 600		# points from an end

	def __init__(self, chat: dict):
		super().__init__(chat["name"])
		self.chat = chat
		self.kind = chat.get("kind", "user")
		self.ids = {}
		self.bubbles = self.add(List())
		self.more_before = self.more_after = False
		self.asking = False
		self._shift = 0
		self._stick = False		# kept at the bottom as the list grows
		self.box = ztos.TextBox(placeholder="xabar yozing" if self.kind != "channel" else "kanal")
		self.box.submitted.connect(lambda _: self.send())
		self.box.setContentsMargins(ztos.MARGIN, 6, ztos.MARGIN, 6)
		self.layout().addWidget(self.box)
		if self.kind == "channel":
			self.box.hide()
		self.app_bar_compact = CompactBar(
			[("send", "yuborish", self.send)] if self.kind != "channel" else [("refresh", "yangilash", self.reload)],
			[("eng pastga", self.to_bottom)])
		self.layout().addWidget(self.app_bar_compact)
		for sig, slot in self._links():
			sig.connect(slot)

	def _links(self):
		return ((tg.history, self._history), (tg.older, self._older), (tg.newer, self._newer),
		        (tg.incoming, self._incoming), (tg.sent, self._sent), (tg.read_out, self._read_out),
		        (tg.avatar, self._avatar))

	def shown(self):
		self.reload()

	def reload(self):
		self.busy(True)
		tg.load_history(self.chat["id"])

	def _mark_read(self):
		if self.chat.get("unread"):
			tg.read(self.chat["id"])
			self.chat["unread"] = 0
			row = chats.rows.get(self.chat["id"])
			if row:
				row.update_chat(self.chat)
			update_tile()

	# building the list
	def _widgets(self, msgs: list, last_day=None, first_unread=0, unread=0) -> list:
		"""Bubbles for `msgs` (oldest first), with the days between them."""
		out = []
		for m in msgs:
			if m["id"] == first_unread:
				out.append(UnreadLabel(unread))
			day = day_title(m["date"])
			if day != last_day:
				last_day = day
				out.append(DayLabel(m["date"]))
			b = Bubble(m, self.kind)
			self.ids[m["id"]] = b
			out.append(b)
		return out

	def _ends(self):
		bubbles = [w for w in self.bubbles.rows() if isinstance(w, Bubble) and w.msg["id"] > 0]
		return (bubbles[0].msg["id"], bubbles[-1].msg["id"]) if bubbles else (0, 0)

	def _last_day(self):
		days = [w for w in self.bubbles.rows() if isinstance(w, DayLabel)]
		return days[-1].text if days else None

	def _history(self, chat_id: int, msgs: list, info: dict):
		if chat_id != self.chat["id"]:
			return
		self.busy(False)
		t = time.perf_counter()
		self.bubbles.clear()
		self.ids = {}
		first = info.get("first_unread", 0)
		widgets = self._widgets(msgs, None, first, self.chat.get("unread", 0))
		for w in widgets:
			self.bubbles.add(w)
		self.more_before, self.more_after = len(msgs) >= 10, info.get("newer", False)
		label = next((w for w in widgets if isinstance(w, UnreadLabel)), None)
		if label is not None:
			self._stick = False
			QTimer.singleShot(0, lambda: self._fit() or self.scroll_to(label.mapTo(self.body, QPoint(0, 0)).y() - 8))
		else:
			self.to_bottom()
		if not self.more_after:
			self._mark_read()
		if ztos._profiling:
			print(f"tepegram history: {len(msgs)} messages built in {(time.perf_counter() - t) * 1000:.0f} ms",
			      file=sys.stderr, flush=True)

	def _older(self, chat_id: int, msgs: list, more: bool):
		if chat_id != self.chat["id"]:
			return
		self.asking = False
		self.more_before = more
		known = [m for m in msgs if m["id"] not in self.ids]
		if not known:
			return
		widgets = self._widgets(known)
		rows = self.bubbles.rows()
		# the day the old ones end on may be the one the list starts with
		if rows and isinstance(rows[0], DayLabel) and rows[0].text == day_title(known[-1]["date"]):
			self._shift -= rows[0].height()
			self.bubbles.box.removeWidget(rows[0])
			rows[0].deleteLater()
		for k, w in enumerate(widgets):
			self.bubbles.add(w, k)
			self._shift += w.height()
		self._stick = False

	def _newer(self, chat_id: int, msgs: list, more: bool):
		if chat_id != self.chat["id"]:
			return
		self.asking = False
		self.more_after = more
		for w in self._widgets([m for m in msgs if m["id"] not in self.ids], self._last_day()):
			self.bubbles.add(w)
		if not more:
			self._mark_read()

	def _fit(self):
		super()._fit()
		if self._shift:		# older ones came in above: what was on the screen stays there
			shift, self._shift = self._shift, 0
			self._set(min(self._scroll + shift, self._max()))
		elif self._stick:
			self._set(self._max())

	def to_bottom(self):
		if self.more_after:	# among the unread: the newest instead
			self.reload_newest()
			return
		self._stick = True
		QTimer.singleShot(0, lambda: self.scroll_to(10 ** 7))

	def reload_newest(self):
		self.chat["unread"] = 0
		self.more_after = False
		self.reload()

	def _gl_end(self):
		was = self._gl_on
		super()._gl_end()
		if was:
			self._stick = self._scroll >= self._max() - 4
			self._more()

	def _more(self):
		"""Stopped near an end: what lies past it."""
		if self.asking:
			return
		first, last = self._ends()
		if self.more_before and first and self._scroll < self.NEAR:
			self.asking = True
			tg.load_older(self.chat["id"], first)
		elif self.more_after and last and self._scroll > self._max() - self.NEAR:
			self.asking = True
			tg.load_newer(self.chat["id"], last)

	# live
	def _incoming(self, m: dict, chat: dict):
		if m["chat"] != self.chat["id"] or self.more_after or m["id"] in self.ids:
			return
		for w in self._widgets([m], self._last_day()):
			self.bubbles.add(w)
		if self._stick or m["out"]:
			self.to_bottom()
		if not m["out"] and app.page is self and active():
			tg.read(self.chat["id"])

	def send(self):
		text = self.box.text().strip()
		if not text:
			return
		self.box.set_text("")
		local = next(_local_ids)
		m = {"id": local, "chat": self.chat["id"], "text": text, "date": stamp_now(), "out": True,
		     "sender": "", "sender_id": 0, "media": "", "views": 0, "read": False, "pending": True}
		if self.more_after:
			self.reload_newest()
		for w in self._widgets([m], self._last_day()):
			self.bubbles.add(w)
		self.to_bottom()
		ztos.haptic("tick")
		tg.send(self.chat["id"], text, local)

	def _sent(self, local: int, m: dict):
		bubble = self.ids.pop(local, None)
		if bubble is None:
			return
		bubble.set_msg(m)
		self.ids[m["id"]] = bubble

	def _read_out(self, chat_id: int, max_id: int):
		if chat_id != self.chat["id"]:
			return
		for mid, b in self.ids.items():
			if b.msg.get("out") and not b.msg.get("read") and 0 < mid <= max_id:
				b.set_msg(dict(b.msg, read=True))

	def _avatar(self, user_id: int, path: str):
		for b in self.ids.values():
			if b.msg.get("sender_id") == user_id and b._avatar():
				b.redraw()
				changed(b)

	def back(self) -> bool:
		for sig, slot in self._links():
			sig.disconnect(slot)
		return super().back()


class Settings(ztos.Page):
	def __init__(self):
		super().__init__("sozlamalar")
		self.account = self.entry(me.get("name", ""), me.get("phone", "") and "+" + me["phone"])
		self.space(8)
		self.entry("chiqish", "bu telefonda Telegram'dan chiqish", self.log_out)
		self.section("TEPEGRAM 0.2")
		self.text("Telegram uchun norasmiy ilova. Telethon (MIT) asosida.", 13)

	def log_out(self):
		def done(i):
			if i == 0:
				tg.log_out()
		ztos.message("chiqish", "Bu telefonda Telegram hisobingizdan chiqasizmi?", ("chiqish", "bekor"), done)


me = {}
chats = Chats()
contacts = Contacts()
home = ztos.Pivot([chats, contacts])
home.layout().addWidget(CompactBar(
	[("refresh", "yangilash", chats.refresh), ("search", "qidirish", lambda: ztos.notify("Tepegram", "qidiruv hali yo'q"))],
	[("sozlamalar", lambda: app.push(Settings()))]))


def on_avatar(chat_id: int, path: str):
	set_photo(chat_id, path)
	for rows in (chats.rows, contacts.rows):
		row = rows.get(chat_id)
		if row is not None:
			row.update_chat(row.chat)


def active() -> bool:
	return QGuiApplication.applicationState() == Qt.ApplicationActive


def open_chat(chat: dict):
	app.push(Chat(chat))


def update_tile():
	unread = [r.chat for r in chats.rows.values() if r.chat.get("unread") and not r.chat.get("muted")]
	total = sum(c["unread"] for c in unread)
	if total:
		lines = [f"{c['name']}: {c.get('text', '')}" for c in sorted(unread, key=lambda c: -c.get("date", 0))[:3]]
		ztos.tile_update("tepegram", lines, total)
	else:
		ztos.tile_clear()


def on_state(state: str):
	if state == "login":
		app.replace(Login())
	elif state == "ready" and app.page is not home:
		app.replace(home)
	elif state == "offline":
		ztos.notify("Tepegram", "Internet yo'q, ulanish tiklanishini kutyapman")


def on_incoming(m: dict, chat: dict):
	page = app.page
	here = isinstance(page, Chat) and page.chat["id"] == chat["id"] and active()
	if not m["out"] and not chat.get("muted") and not here:
		ztos.notify(chat["name"], (m["sender"] + ": " if m["sender"] else "") + preview(m["text"], m["media"]))


tg.state.connect(on_state)
tg.me.connect(me.update)
tg.incoming.connect(on_incoming)
tg.avatar.connect(on_avatar)
tg.error.connect(lambda text: ztos.notify("Tepegram", text))
tg.start()
app.run(Connecting())
