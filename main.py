"""Tepegram: a Telegram client for ztOS phones, in the Windows Phone 8.1 look.

Pages are 360 points wide on every screen (the shell scales them), so the
same app fits the Galaxy S10 5G and other phones. Telegram itself runs on
tg.Backend's own thread; this file only draws and reacts to its signals.
"""
import itertools

from PySide6.QtCore import QTimer
from PySide6.QtGui import QGuiApplication
from PySide6.QtCore import Qt

import ztos
from tg import Backend, preview
from views import Bubble, ChatRow, DayLabel, List, QrView, stamp_now

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


class Chats(ztos.Page):
	"""Every chat, pinned first then newest, as in the People hub's list."""

	def __init__(self):
		super().__init__("chatlar")
		self.chat_list = self.add(List())
		self.rows = {}
		self.bar(ztos.RoundButton("refresh", "yangilash", self.refresh),
		         ztos.RoundButton("settings", "sozlamalar", lambda: app.push(Settings())))
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
		known = self.rows
		self.rows = {}
		self.chat_list.clear()
		for c in chats:
			self.rows[c["id"]] = self.chat_list.add(ChatRow(c, open_chat))
		known.clear()
		update_tile()

	def _incoming(self, msg: dict, chat: dict):
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


class Chat(ztos.Page):
	"""One conversation: bubbles, newest at the bottom, and a box to write in."""

	def __init__(self, chat: dict):
		super().__init__(chat["name"])
		self.chat = chat
		self.ids = {}
		self.last_day = None
		self.bubbles = self.add(List())
		self.box = self.textbox("", placeholder="xabar yozing", on_submit=lambda _: self.send())
		self.bar(ztos.RoundButton("send", "yuborish", self.send))
		tg.history.connect(self._history)
		tg.incoming.connect(self._incoming)
		tg.sent.connect(self._sent)

	def shown(self):
		self.busy(True)
		tg.load_history(self.chat["id"])
		if self.chat.get("unread"):
			tg.read(self.chat["id"])
			self.chat["unread"] = 0
			row = chats.rows.get(self.chat["id"])
			if row:
				row.update_chat(self.chat)
			update_tile()

	def _day(self, stamp: float):
		from views import day_title
		day = day_title(stamp)
		if day != self.last_day:
			self.last_day = day
			self.bubbles.add(DayLabel(stamp))

	def _add(self, m: dict):
		if m["id"] in self.ids:
			self.ids[m["id"]].set_msg(m)
			return
		self._day(m["date"])
		self.ids[m["id"]] = self.bubbles.add(Bubble(m))

	def _bottom(self):
		QTimer.singleShot(30, lambda: self.scroll_to(10 ** 7))

	def _history(self, chat_id: int, msgs: list):
		if chat_id != self.chat["id"]:
			return
		self.busy(False)
		self.bubbles.clear()
		self.ids, self.last_day = {}, None
		for m in msgs:
			self._add(m)
		self._bottom()

	def _incoming(self, m: dict, chat: dict):
		if m["chat"] != self.chat["id"]:
			return
		self._add(m)
		self._bottom()
		if not m["out"] and app.page is self and active():
			tg.read(self.chat["id"])

	def send(self):
		text = self.box.text().strip()
		if not text:
			return
		self.box.set_text("")
		local = next(_local_ids)
		self._add({"id": local, "chat": self.chat["id"], "text": text, "date": stamp_now(), "out": True,
		           "sender": "", "media": "", "pending": True})
		self._bottom()
		ztos.haptic("tick")
		tg.send(self.chat["id"], text, local)

	def _sent(self, local: int, m: dict):
		bubble = self.ids.pop(local, None)
		if bubble is None:
			return
		bubble.set_msg(m)
		self.ids[m["id"]] = bubble

	def back(self) -> bool:
		for sig, slot in ((tg.history, self._history), (tg.incoming, self._incoming), (tg.sent, self._sent)):
			sig.disconnect(slot)
		return super().back()


class Settings(ztos.Page):
	def __init__(self):
		super().__init__("sozlamalar")
		self.account = self.entry(me.get("name", ""), me.get("phone", "") and "+" + me["phone"])
		self.space(8)
		self.entry("chiqish", "bu telefonda Telegram'dan chiqish", self.log_out)
		self.section("TEPEGRAM 0.1")
		self.text("Telegram uchun norasmiy ilova. Telethon (MIT) asosida.", 13)

	def log_out(self):
		def done(i):
			if i == 0:
				tg.log_out()
		ztos.message("chiqish", "Bu telefonda Telegram hisobingizdan chiqasizmi?", ("chiqish", "bekor"), done)


me = {}
chats = Chats()


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
	elif state == "ready" and app.page is not chats:
		app.replace(chats)
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
tg.error.connect(lambda text: ztos.notify("Tepegram", text))
tg.start()
app.run(Connecting())
