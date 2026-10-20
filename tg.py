"""Tepegram's link to Telegram, kept off the UI thread.

The UI only sees `Backend`: calls that return at once, and Qt signals that
carry plain dicts back. Everything Telegram does runs in one asyncio loop on
its own thread, so a slow network never holds a frame. This is the one file
to replace when the client moves from Telethon to TDLib: the signals and
the dicts they carry stay the same.

A chat:    {"id", "name", "text", "date", "unread", "out", "kind", "pinned", "muted", "photo"}
A message: {"id", "chat", "text", "date", "out", "sender", "sender_id", "media", "views", "read"}
A contact: {"id", "name", "phone", "photo", "kind": "user"}

"photo" is the profile photo's id (0: none); its small picture comes by the
`avatar` signal once it is on disk (AVATARS/<chat id>_<photo id>.jpg).
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
AVATARS = os.path.join(DATA, "avatars")

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


def message_dict(m, sender_name: str = "", read_out: int = 0) -> dict:
	media = _media(m)
	return {"id": m.id, "chat": m.chat_id, "text": m.message or "", "date": _stamp(m.date), "out": bool(m.out),
	        "sender": sender_name, "sender_id": m.sender_id or 0, "media": media, "views": m.views or 0,
	        "read": bool(m.out and m.id <= read_out)}


def photo_id(entity) -> int:
	photo = getattr(entity, "photo", None)
	return getattr(photo, "photo_id", 0) or 0


def avatar_path(chat_id: int, photo: int) -> str:
	return os.path.join(AVATARS, f"{chat_id}_{photo}.jpg")


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
	history = Signal(object, object, object)	# chat id, [message, ...] oldest first, {"first_unread", "newer"}
	older = Signal(object, object, object)	# chat id, [message, ...] oldest first, more before them?
	newer = Signal(object, object, object)	# chat id, [message, ...] oldest first, more after them?
	read_out = Signal(object, object)	# chat id, the newest of our messages they have read
	avatar = Signal(object, object)	# chat (or user) id, the small picture's path
	contacts = Signal(object)	# [contact, ...] by name
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
		self._entities = {}		# id -> the user, group or channel (for photos)
		self._read_in, self._read_out = {}, {}	# id -> the newest message read, theirs and ours
		self._avatar_task = None
		self._avatar_queue = []
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

	def load_older(self, chat_id: int, before_id: int, limit: int = 30):
		self._go(self._load_older(chat_id, before_id, limit))

	def load_newer(self, chat_id: int, after_id: int, limit: int = 30):
		self._go(self._load_newer(chat_id, after_id, limit))

	def load_contacts(self):
		self._go(self._load_contacts())

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
		                             app_version="Tepegram 0.2", lang_code="uz", system_lang_code="uz")
		self.client.add_event_handler(self._on_new, events.NewMessage)
		self.client.add_event_handler(self._on_read, events.MessageRead(inbox=False))
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
		self._entities[d.id] = d.entity
		self._read_in[d.id] = getattr(d.dialog, "read_inbox_max_id", 0) or 0
		self._read_out[d.id] = getattr(d.dialog, "read_outbox_max_id", 0) or 0
		return {"id": d.id, "name": d.name or "", "text": preview(m.message or "", media) if m else "",
		        "date": _stamp(m.date) if m else 0.0, "unread": d.unread_count, "out": bool(m and m.out),
		        "kind": kind, "pinned": bool(d.pinned), "muted": muted, "photo": photo_id(d.entity)}

	async def _load_chats(self):
		out = []
		async for d in self.client.iter_dialogs(limit=80, archived=False):
			c = self._chat_dict(d)
			self._chats[c["id"]] = c
			out.append(c)
		self.chats.emit(out)
		self._fetch_avatars([(c["id"], c["photo"]) for c in out])

	def _fetch_avatars(self, wanted: list):
		"""The small profile pictures, one at a time, those already on disk at
		once: (id, photo id) pairs, in the order they are shown."""
		os.makedirs(AVATARS, exist_ok=True)
		missing = []
		for chat_id, photo in wanted:
			if not photo:
				continue
			path = avatar_path(chat_id, photo)
			if os.path.exists(path):
				self.avatar.emit(chat_id, path)
			else:
				missing.append((chat_id, photo))
		# the newest wish first, each once
		self._avatar_queue = missing + [w for w in self._avatar_queue if w not in missing]
		if missing and (self._avatar_task is None or self._avatar_task.done()):
			self._avatar_task = asyncio.ensure_future(self._download_avatars())

	async def _download_avatars(self):
		while self._avatar_queue:
			chat_id, photo = self._avatar_queue.pop(0)
			entity = self._entities.get(chat_id)
			if entity is None:
				continue
			path = avatar_path(chat_id, photo)
			try:
				got = await self.client.download_profile_photo(entity, file=path + ".part", download_big=False)
			except FloodWaitError as e:
				await asyncio.sleep(e.seconds + 1)
				continue
			except Exception:  # noqa: BLE001 (no picture is fine: the initials stay)
				continue
			if got:
				os.replace(got, path)
				self.avatar.emit(chat_id, path)

	async def _messages(self, chat_id: int, msgs) -> list:
		"""Oldest first, as dicts: senders' names in groups."""
		group = self._chats.get(chat_id, {}).get("kind") == "group"
		read_out = self._read_out.get(chat_id, 0)
		out, people = [], {}
		for m in sorted(msgs, key=lambda m: m.id):
			name = ""
			if group and not m.out and m.sender:
				name = utils.get_display_name(m.sender)
				people[m.sender_id] = (m.sender_id, photo_id(m.sender))
				self._entities.setdefault(m.sender_id, m.sender)
			out.append(message_dict(m, name, read_out))
		if people:
			self._fetch_avatars(list(people.values()))
		return out

	async def _load_history(self, chat_id: int, limit: int):
		"""The newest messages; or, with some unread, a few read ones and the
		unread after them, so the chat opens where it was left."""
		unread = self._chats.get(chat_id, {}).get("unread", 0)
		read_in = self._read_in.get(chat_id, 0)
		if unread and read_in:
			before = await self.client.get_messages(chat_id, limit=10, max_id=read_in + 1)
			after = await self.client.get_messages(chat_id, limit=limit, min_id=read_in, reverse=True)
			msgs = await self._messages(chat_id, list(before) + list(after))
			first = next((m["id"] for m in msgs if m["id"] > read_in and not m["out"]), 0)
			self.history.emit(chat_id, msgs, {"first_unread": first, "newer": len(after) >= limit})
			return
		msgs = await self.client.get_messages(chat_id, limit=limit)
		self.history.emit(chat_id, await self._messages(chat_id, msgs), {"first_unread": 0, "newer": False})

	async def _load_older(self, chat_id: int, before_id: int, limit: int):
		msgs = await self.client.get_messages(chat_id, limit=limit, max_id=before_id)
		self.older.emit(chat_id, await self._messages(chat_id, msgs), len(msgs) >= limit)

	async def _load_newer(self, chat_id: int, after_id: int, limit: int):
		msgs = await self.client.get_messages(chat_id, limit=limit, min_id=after_id, reverse=True)
		self.newer.emit(chat_id, await self._messages(chat_id, msgs), len(msgs) >= limit)

	async def _load_contacts(self):
		from telethon.tl.functions.contacts import GetContactsRequest
		result = await self.client(GetContactsRequest(hash=0))
		out = []
		for u in result.users:
			if u.deleted or u.bot:
				continue
			self._entities[u.id] = u
			out.append({"id": u.id, "name": utils.get_display_name(u) or (u.phone or ""), "phone": u.phone or "",
			            "photo": photo_id(u), "kind": "user"})
		out.sort(key=lambda c: c["name"].lower())
		self.contacts.emit(out)
		self._fetch_avatars([(c["id"], c["photo"]) for c in out])

	async def _on_read(self, event):
		self._read_out[event.chat_id] = max(self._read_out.get(event.chat_id, 0), event.max_id)
		self.read_out.emit(event.chat_id, event.max_id)

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
		self._read_in[chat_id] = 0	# all of it (the next unread one sets it again)

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
			     "muted": False, "kind": "user" if event.is_private else ("group" if event.is_group else "channel"),
			     "photo": photo_id(chat)}
			self._chats[event.chat_id] = c
			self._entities[event.chat_id] = chat
			self._fetch_avatars([(c["id"], c["photo"])])
		if c["kind"] == "group" and not m.out:
			sender = await event.get_sender()
			name = utils.get_display_name(sender) if sender else ""
			if sender is not None and m.sender_id not in self._entities:
				self._entities[m.sender_id] = sender
				self._fetch_avatars([(m.sender_id, photo_id(sender))])
		d = message_dict(m, name)
		c.update(text=preview(d["text"], d["media"]), date=d["date"], out=d["out"])
		if not m.out:
			if not c.get("unread"):
				self._read_in[event.chat_id] = m.id - 1	# read up to the one before this
			c["unread"] = c.get("unread", 0) + 1
		self.incoming.emit(d, dict(c))
