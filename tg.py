"""Tepegram's link to Telegram, kept off the UI thread.

The UI only sees `Backend`: calls that return at once, and Qt signals that
carry plain dicts back. Everything Telegram does runs in one asyncio loop on
its own thread, so a slow network never holds a frame. This is the one file
to replace when the client moves from Telethon to TDLib: the signals and
the dicts they carry stay the same.

A chat:    {"id", "name", "text", "date", "unread", "out", "kind", "pinned", "muted"}
A message: {"id", "chat", "text", "date", "out", "sender", "media"}
"""
import asyncio
import json
import os
import sys
import threading
from datetime import datetime, timezone

from PySide6.QtCore import QObject, Signal

DATA = os.path.expanduser("~/.local/share/ztos/data/uz.omonullos.tepegram")
VENDOR = os.path.join(DATA, "vendor")

# the phone keeps the libraries compiled next to the app (tools/deploy.sh)
if os.path.isdir(VENDOR) and VENDOR not in sys.path:
	sys.path.insert(0, VENDOR)

from telethon import TelegramClient, events, utils  # noqa: E402
from telethon.errors import (FloodWaitError, PhoneCodeExpiredError, PhoneCodeInvalidError,  # noqa: E402
                             PasswordHashInvalidError, PhoneNumberInvalidError, SessionPasswordNeededError)

# what a message without text shows in the list and in its bubble
MEDIA_UZ = {
	"photo": "Rasm", "video": "Video", "voice": "Ovozli xabar", "audio": "Musiqa", "sticker": "Stiker",
	"gif": "GIF", "document": "Fayl", "contact": "Kontakt", "geo": "Joylashuv", "poll": "So'rovnoma",
	"video_note": "Video xabar", "web": "Havola",
}


def _media(m) -> str:
	if m.media is None:
		return ""
	if m.voice: return "voice"
	if m.video_note: return "video_note"
	if m.sticker: return "sticker"
	if m.gif: return "gif"
	if m.photo: return "photo"
	if m.video: return "video"
	if m.audio: return "audio"
	if m.contact: return "contact"
	if m.geo: return "geo"
	if m.poll: return "poll"
	if m.web_preview: return ""
	if m.document: return "document"
	return ""


def _stamp(d) -> float:
	return d.replace(tzinfo=d.tzinfo or timezone.utc).timestamp() if d else 0.0


def message_dict(m, sender_name: str = "") -> dict:
	media = _media(m)
	return {"id": m.id, "chat": m.chat_id, "text": m.message or "", "date": _stamp(m.date), "out": bool(m.out),
	        "sender": sender_name, "media": media}


def preview(text: str, media: str) -> str:
	"""One line for the chat list: the text, or what kind of message it is."""
	if media and media in MEDIA_UZ:
		return f"[{MEDIA_UZ[media]}] {text}".strip() if text else f"[{MEDIA_UZ[media]}]"
	return " ".join(text.split())


class Backend(QObject):
	state = Signal(str)		# "connecting", "login", "ready", "offline"
	qr = Signal(str)		# a tg://login URL to show as a QR code
	need = Signal(str)		# "code", "password": what the login asks for next
	login_error = Signal(str)
	me = Signal(object)		# {"name", "phone"}
	chats = Signal(object)		# [chat, ...], pinned first, then newest
	history = Signal(object, object)	# chat id, [message, ...] oldest first
	incoming = Signal(object, object)	# message, the chat's dict as it is now
	sent = Signal(object, object)	# the local id it was shown with, the message as sent
	error = Signal(str)

	def __init__(self):
		super().__init__()
		self.loop = asyncio.new_event_loop()
		self.client = None
		self._phone = ""
		self._qr_task = None
		self._chats = {}
		threading.Thread(target=self._run, name="tepegram-tg", daemon=True).start()

	# ---- plumbing ---------------------------------------------------------

	def _run(self):
		asyncio.set_event_loop(self.loop)
		self.loop.run_forever()

	def _go(self, coro):
		asyncio.run_coroutine_threadsafe(self._guard(coro), self.loop)

	async def _guard(self, coro):
		try:
			await coro
		except FloodWaitError as e:
			self.error.emit(f"Telegram {e.seconds} soniya kutishni so'radi")
		except ConnectionError:
			self.state.emit("offline")
		except Exception as e:  # noqa: BLE001 (the UI shows it, the loop lives on)
			self.error.emit(f"{type(e).__name__}: {e}")

	# ---- what the UI calls -----------------------------------------------

	def start(self):
		self._go(self._start())

	def login_qr(self):
		self._go(self._login_qr())

	def login_phone(self, phone: str):
		self._go(self._login_phone(phone))

	def login_code(self, code: str):
		self._go(self._login_code(code))

	def login_password(self, password: str):
		self._go(self._login_password(password))

	def load_chats(self):
		self._go(self._load_chats())

	def load_history(self, chat_id: int, limit: int = 40):
		self._go(self._load_history(chat_id, limit))

	def send(self, chat_id: int, text: str, local_id: int):
		self._go(self._send(chat_id, text, local_id))

	def read(self, chat_id: int):
		self._go(self._read(chat_id))

	def log_out(self):
		self._go(self._log_out())

	# ---- inside the loop --------------------------------------------------

	async def _start(self):
		self.state.emit("connecting")
		with open(os.path.join(DATA, "api.json")) as f:
			api = json.load(f)
		self.client = TelegramClient(os.path.join(DATA, "tepegram"), int(api["id"]), api["hash"],
		                             device_model="Galaxy S10 5G", system_version="OmonullOS",
		                             app_version="Tepegram 0.1", lang_code="uz", system_lang_code="uz")
		self.client.add_event_handler(self._on_new, events.NewMessage)
		await self.client.connect()
		if await self.client.is_user_authorized():
			await self._ready()
		else:
			self.state.emit("login")

	async def _ready(self):
		u = await self.client.get_me()
		self.me.emit({"name": utils.get_display_name(u), "phone": u.phone or ""})
		self.state.emit("ready")
		await self._load_chats()

	async def _login_qr(self):
		if self._qr_task:
			self._qr_task.cancel()
		self._qr_task = asyncio.current_task()
		qr = await self.client.qr_login()
		while True:
			self.qr.emit(qr.url)
			try:
				await qr.wait(timeout=max(5, (qr.expires - datetime.now(timezone.utc)).total_seconds() - 2))
				break
			except asyncio.TimeoutError:
				await qr.recreate()
			except SessionPasswordNeededError:
				self.need.emit("password")
				return
		await self._ready()

	async def _login_phone(self, phone: str):
		self._phone = phone.replace(" ", "")
		try:
			await self.client.send_code_request(self._phone)
		except PhoneNumberInvalidError:
			self.login_error.emit("Raqam noto'g'ri")
			return
		self.need.emit("code")

	async def _login_code(self, code: str):
		try:
			await self.client.sign_in(self._phone, code.replace(" ", ""))
		except SessionPasswordNeededError:
			self.need.emit("password")
			return
		except (PhoneCodeInvalidError, PhoneCodeExpiredError):
			self.login_error.emit("Kod noto'g'ri yoki eskirgan")
			return
		await self._ready()

	async def _login_password(self, password: str):
		try:
			await self.client.sign_in(password=password)
		except PasswordHashInvalidError:
			self.login_error.emit("Parol noto'g'ri")
			return
		await self._ready()

	def _chat_dict(self, d) -> dict:
		m = d.message
		media = _media(m) if m else ""
		kind = "user" if d.is_user else ("channel" if d.is_channel and not d.is_group else "group")
		muted = bool(d.dialog.notify_settings and d.dialog.notify_settings.mute_until
		             and _stamp(d.dialog.notify_settings.mute_until) > datetime.now(timezone.utc).timestamp())
		return {"id": d.id, "name": d.name or "", "text": preview(m.message or "", media) if m else "",
		        "date": _stamp(m.date) if m else 0.0, "unread": d.unread_count, "out": bool(m and m.out),
		        "kind": kind, "pinned": bool(d.pinned), "muted": muted}

	async def _load_chats(self):
		out = []
		async for d in self.client.iter_dialogs(limit=80, archived=False):
			c = self._chat_dict(d)
			self._chats[c["id"]] = c
			out.append(c)
		self.chats.emit(out)

	async def _load_history(self, chat_id: int, limit: int):
		msgs = await self.client.get_messages(chat_id, limit=limit)
		group = self._chats.get(chat_id, {}).get("kind") == "group"
		out = []
		for m in reversed(msgs):
			name = utils.get_display_name(m.sender) if group and not m.out and m.sender else ""
			out.append(message_dict(m, name))
		self.history.emit(chat_id, out)

	async def _send(self, chat_id: int, text: str, local_id: int):
		m = await self.client.send_message(chat_id, text)
		d = message_dict(m)
		c = self._chats.get(chat_id)
		if c:
			c.update(text=preview(d["text"], ""), date=d["date"], out=True)
		self.sent.emit(local_id, d)

	async def _read(self, chat_id: int):
		await self.client.send_read_acknowledge(chat_id)
		if chat_id in self._chats:
			self._chats[chat_id]["unread"] = 0

	async def _log_out(self):
		await self.client.log_out()
		self._chats.clear()
		self.state.emit("login")

	async def _on_new(self, event):
		m = event.message
		c = self._chats.get(event.chat_id)
		name = ""
		if c is None:
			chat = await event.get_chat()
			c = {"id": event.chat_id, "name": utils.get_display_name(chat), "unread": 0, "pinned": False,
			     "muted": False, "kind": "user" if event.is_private else ("group" if event.is_group else "channel")}
			self._chats[event.chat_id] = c
		if c["kind"] == "group" and not m.out:
			sender = await event.get_sender()
			name = utils.get_display_name(sender) if sender else ""
		d = message_dict(m, name)
		c.update(text=preview(d["text"], d["media"]), date=d["date"], out=d["out"])
		if not m.out:
			c["unread"] = c.get("unread", 0) + 1
		self.incoming.emit(d, dict(c))
