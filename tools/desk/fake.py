"""A fake TDLib for desk.py: chats and messages made from a scene's short descriptions, answered in
the shapes Store.qml and ChatPage.qml read. A scene builds its messages with text(), photo(), video(),
animation(), voice(), audio(), document(), service(); test pictures (a-f: gradients with a letter,
their minithumbnails), a short video and a voice note are made once in the desk's work folder."""
import base64
import os
import subprocess
import tempfile

ASSETS = os.path.join(tempfile.gettempdir(), "nullgram-desk", "assets")
NOW = 1793000000		# 2026-10-26: a scene's dates go back from here
PICTURES = {"a": (1280, 960, "#ff6a00", "#ee0979"), "b": (960, 1280, "#2193b0", "#6dd5ed"),
            "c": (1280, 720, "#11998e", "#38ef7d"), "d": (1000, 1000, "#8e2de2", "#4a00e0"),
            "e": (720, 1280, "#f7971e", "#ffd200"), "f": (1280, 853, "#c33764", "#1d2671")}
_next_file = [100]


def asset(name):
	"""A test file's path, made the first time it is asked for (a.jpg ... f.jpg, tiny.mp4, v.ogg)."""
	os.makedirs(ASSETS, exist_ok=True)
	path = os.path.join(ASSETS, name)
	if not os.path.exists(path):
		base, ext = os.path.splitext(name)
		if ext in (".jpg", ".mini"):
			_picture(base)
		elif ext == ".mp4":
			subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "testsrc=size=320x240:rate=10",
			                "-t", "1", "-pix_fmt", "yuv420p", path], check=True)
		elif ext == ".ogg":
			subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
			                "-c:a", "libopus", path], check=False)
			if not os.path.exists(path):
				open(path, "wb").write(b"OggS")
	return path


def _picture(name):
	"""A gradient, a white circle, a dark square and the letter: told apart at a glance, blurred or not."""
	from PySide6.QtCore import QBuffer, QByteArray, QIODevice, QRectF, Qt
	from PySide6.QtGui import QColor, QFont, QImage, QLinearGradient, QPainter
	w, h, c1, c2 = PICTURES[name]
	img = QImage(w, h, QImage.Format_RGB32)
	p = QPainter(img)
	g = QLinearGradient(0, 0, w, h)
	g.setColorAt(0, QColor(c1))
	g.setColorAt(1, QColor(c2))
	p.fillRect(0, 0, w, h, g)
	p.setPen(Qt.NoPen)
	p.setBrush(QColor(255, 255, 255, 200))
	p.drawEllipse(QRectF(w * 0.1, h * 0.15, w * 0.3, w * 0.3))
	p.setBrush(QColor(0, 0, 0, 140))
	p.drawRect(QRectF(w * 0.55, h * 0.5, w * 0.35, h * 0.35))
	p.setPen(QColor("white"))
	f = QFont()
	f.setPixelSize(int(h * 0.3))
	f.setBold(True)
	p.setFont(f)
	p.drawText(QRectF(0, 0, w, h), Qt.AlignCenter, name.upper())
	p.end()
	img.save(os.path.join(ASSETS, name + ".jpg"), "JPG", 85)
	mini = img.scaled(40, 40, Qt.KeepAspectRatio, Qt.SmoothTransformation)
	ba = QByteArray()
	buf = QBuffer(ba)
	buf.open(QIODevice.WriteOnly)
	mini.save(buf, "JPG", 60)
	buf.close()
	with open(os.path.join(ASSETS, name + ".mini"), "w") as f:
		f.write("%d %d %s" % (mini.width(), mini.height(), base64.b64encode(bytes(ba)).decode()))


def media_file(path, here=True, size=None):
	"""TDLib's file: here (downloaded) or not yet (downloadFile brings it)."""
	_next_file[0] += 1
	n = size if size is not None else (os.path.getsize(path) if os.path.exists(path) else 12345)
	return {"@type": "file", "id": _next_file[0], "size": n, "expected_size": n,
	        "local": {"@type": "localFile", "path": path if here else "", "can_be_downloaded": True,
	                  "is_downloading_active": False, "is_downloading_completed": here,
	                  "downloaded_size": n if here else 0, "downloaded_prefix_size": n if here else 0},
	        "remote": {"@type": "remoteFile", "id": "r%d" % _next_file[0], "is_uploading_active": False,
	                   "is_uploading_completed": True, "uploaded_size": n},
	        "_path": path}


def mini(name):
	with open(asset(name + ".mini")) as f:
		w, h, data = f.read().split(" ", 2)
	return {"@type": "minithumbnail", "width": int(w), "height": int(h), "data": data}


def ft(text="", entities=None):
	return {"@type": "formattedText", "text": text, "entities": entities or []}


# ---- contents ---------------------------------------------------------------------------------
def service(kind, **fields):
	d = {"@type": kind}
	d.update(fields)
	return d


def text(t, entities=None):
	return {"@type": "messageText", "text": ft(t, entities)}


def photo(name, spoiler=False, caption="", here=True):
	w, h = PICTURES[name][:2]
	return {"@type": "messagePhoto", "has_spoiler": spoiler, "show_caption_above_media": False, "is_secret": False,
	        "caption": ft(caption),
	        "photo": {"@type": "photo", "has_stickers": False, "minithumbnail": mini(name),
	                  "sizes": [{"@type": "photoSize", "type": "x", "width": w, "height": h,
	                             "photo": media_file(asset(name + ".jpg"), here), "progressive_sizes": []}]}}


def video(name, spoiler=False, caption="", here=False, w=1280, h=720, dur=14):
	return {"@type": "messageVideo", "has_spoiler": spoiler, "show_caption_above_media": False, "is_secret": False,
	        "caption": ft(caption), "alternative_videos": [], "storyboards": [], "cover": None, "start_timestamp": 0,
	        "video": {"@type": "video", "duration": dur, "width": w, "height": h, "file_name": "clip.mp4",
	                  "mime_type": "video/mp4", "has_stickers": False, "supports_streaming": True,
	                  "minithumbnail": mini(name),
	                  "thumbnail": {"@type": "thumbnail", "format": {"@type": "thumbnailFormatJpeg"}, "width": 320,
	                                "height": 180, "file": media_file(asset(name + ".jpg"))},
	                  "video": media_file(asset("tiny.mp4"), here, 4200000)}}


def animation(name, spoiler=False, caption="", here=True):
	return {"@type": "messageAnimation", "has_spoiler": spoiler, "show_caption_above_media": False, "is_secret": False,
	        "caption": ft(caption),
	        "animation": {"@type": "animation", "duration": 1, "width": 320, "height": 240, "file_name": "a.mp4",
	                      "mime_type": "video/mp4", "has_stickers": False, "minithumbnail": mini(name),
	                      "thumbnail": {"@type": "thumbnail", "format": {"@type": "thumbnailFormatJpeg"}, "width": 320,
	                                    "height": 240, "file": media_file(asset(name + ".jpg"))},
	                      "animation": media_file(asset("tiny.mp4"), here)}}


def voice(dur=7, here=True, caption=""):
	wave = "AAAAAAAAAMBCGEaUUmlLWlLSlKVKKSVnznIhxYyNjnW7m1GmpZglWCYhSqIBAA=="
	return {"@type": "messageVoiceNote", "caption": ft(caption), "is_listened": False,
	        "voice_note": {"@type": "voiceNote", "duration": dur, "waveform": wave, "mime_type": "audio/ogg",
	                       "speech_recognition_result": None, "voice": media_file(asset("v.ogg"), here)}}


def audio(title="Qo'shiq", performer="Ijrochi", dur=215, here=False, caption="", name="song.mp3"):
	return {"@type": "messageAudio", "caption": ft(caption),
	        "audio": {"@type": "audio", "duration": dur, "title": title, "performer": performer, "file_name": name,
	                  "mime_type": "audio/mpeg", "album_cover_minithumbnail": None, "album_cover_thumbnail": None,
	                  "external_album_covers": [], "audio": media_file(asset("v.ogg"), here, 5300000)}}


def document(name="hisobot.pdf", size=1200000, here=False, caption="", mime="application/pdf"):
	return {"@type": "messageDocument", "caption": ft(caption),
	        "document": {"@type": "document", "file_name": name, "mime_type": mime, "minithumbnail": None,
	                     "thumbnail": None, "document": media_file(asset("a.jpg"), here, size)}}


# ---- the world --------------------------------------------------------------------------------
class World:
	"""scene.CHATS: [{ id, title, kind (private, group, supergroup, channel), user (a private chat's), status
	(a group's: our chatMemberStatus*), permissions (over all allowed), members, unread (how many of the newest),
	messages: [{ content, out, sender, date, album, reply (the index of the one it answers), fwd (from a user),
	edited, pinned, views, comments, reactions: [(emoji, n)] }] }]; scene.USERS: { id: (first, last) }; we are 1."""

	KINDS = {"searchMessagesFilterPhotoAndVideo": ("messagePhoto", "messageVideo"),
	         "searchMessagesFilterDocument": ("messageDocument",), "searchMessagesFilterAudio": ("messageAudio",),
	         "searchMessagesFilterVoiceNote": ("messageVoiceNote",), "searchMessagesFilterUrl": ()}

	def __init__(self, scene):
		self.me = {"@type": "user", "id": 1, "first_name": "Uzim", "last_name": "", "usernames": None,
		           "status": {"@type": "userStatusOnline", "expires": NOW + 999999}, "type": {"@type": "userTypeRegular"},
		           "profile_photo": None, "is_premium": False, "phone_number": "998900000000"}
		self.users = {1: self.me}
		for uid, (first, last) in getattr(scene, "USERS", {}).items():
			self.users[uid] = {"@type": "user", "id": uid, "first_name": first, "last_name": last, "usernames": None,
			                   "status": {"@type": "userStatusRecently"}, "type": {"@type": "userTypeRegular"},
			                   "profile_photo": None, "is_premium": False}
		self.chats = {}
		self.messages = {}		# chat id -> its messages, newest first
		self.groups = []
		self.files = {}
		for c in scene.CHATS:
			self._chat(c)

	def _register(self, v):
		if isinstance(v, dict):
			if v.get("@type") == "file":
				self.files[v["id"]] = v
			for x in v.values():
				self._register(x)
		elif isinstance(v, list):
			for x in v:
				self._register(x)

	def _chat(self, c):
		kind = c.get("kind", "private")
		cid = c["id"]
		status = c.get("status", {"@type": "chatMemberStatusMember"})
		if kind == "private":
			t = {"@type": "chatTypePrivate", "user_id": c["user"]}
		elif kind == "group":
			t = {"@type": "chatTypeBasicGroup", "basic_group_id": abs(cid)}
			self.groups.append({"@type": "updateBasicGroup", "basic_group": {
				"@type": "basicGroup", "id": abs(cid), "member_count": c.get("members", 5), "status": status, "is_active": True}})
		else:
			sid = abs(cid) % 1000000000
			t = {"@type": "chatTypeSupergroup", "supergroup_id": sid, "is_channel": kind == "channel"}
			self.groups.append({"@type": "updateSupergroup", "supergroup": {
				"@type": "supergroup", "id": sid, "member_count": c.get("members", 120), "is_channel": kind == "channel",
				"status": status, "has_linked_chat": False}})
		perms = {"@type": "chatPermissions", "can_send_basic_messages": True, "can_send_audios": True,
		         "can_send_documents": True, "can_send_photos": True, "can_send_videos": True,
		         "can_send_video_notes": True, "can_send_voice_notes": True, "can_send_polls": True,
		         "can_send_other_messages": True, "can_add_link_previews": True, "can_change_info": False,
		         "can_invite_users": True, "can_pin_messages": False, "can_create_topics": False}
		perms.update(c.get("permissions", {}))
		msgs = []
		for k, m in enumerate(c.get("messages", [])):
			mid = (k + 1) << 20
			out = m.get("out", False)
			sender = {"@type": "messageSenderUser", "user_id": 1 if out else m.get("sender", c.get("user", 2))}
			if kind == "channel":
				sender = {"@type": "messageSenderChat", "chat_id": cid}
			msg = {"@type": "message", "id": mid, "chat_id": cid, "sender_id": sender, "is_outgoing": out,
			       "date": m.get("date", NOW - 3600 + k * 60), "edit_date": 0, "content": m["content"],
			       "interaction_info": None, "reply_to": None, "forward_info": None,
			       "media_album_id": str(m.get("album", 0)), "is_channel_post": kind == "channel",
			       "is_pinned": bool(m.get("pinned")), "sending_state": None, "topic_id": None, "can_be_saved": True,
			       "has_timestamped_media": False, "contains_unread_mention": False, "author_signature": ""}
			if m.get("reply") is not None:
				msg["reply_to"] = {"@type": "messageReplyToMessage", "chat_id": cid, "message_id": (m["reply"] + 1) << 20,
				                   "quote": None, "origin": None, "origin_send_date": 0, "content": None}
			if m.get("fwd"):
				msg["forward_info"] = {"@type": "messageForwardInfo", "date": NOW - 86400, "source": None,
				                       "public_service_announcement_type": "",
				                       "origin": {"@type": "messageOriginUser", "sender_user_id": m["fwd"]}}
			if m.get("edited"):
				msg["edit_date"] = msg["date"] + 30
			if m.get("views") or m.get("comments") is not None or m.get("reactions"):
				msg["interaction_info"] = {
					"@type": "messageInteractionInfo", "view_count": m.get("views", 0), "forward_count": 0,
					"reply_info": {"@type": "messageReplyInfo", "reply_count": m["comments"]} if m.get("comments") is not None else None,
					"reactions": {"@type": "messageReactions", "reactions": [
						{"@type": "messageReaction", "type": {"@type": "reactionTypeEmoji", "emoji": e},
						 "total_count": n, "is_chosen": False} for e, n in m.get("reactions", [])]}}
			msgs.append(msg)
		msgs.sort(key=lambda m: -m["id"])
		self._register(msgs)
		self.messages[cid] = msgs
		unread = c.get("unread", 0)
		self.chats[cid] = {"@type": "chat", "id": cid, "type": t, "title": c["title"], "photo": None,
		                   "permissions": perms, "last_message": msgs[0] if msgs else None,
		                   "positions": [{"@type": "chatPosition", "list": {"@type": "chatListMain"},
		                                  "order": str(9000 - len(self.chats)), "is_pinned": False}],
		                   "unread_count": unread, "last_read_inbox_message_id": msgs[unread]["id"] if msgs else 0,
		                   "last_read_outbox_message_id": msgs[0]["id"] if msgs else 0,
		                   "notification_settings": {"@type": "chatNotificationSettings", "mute_for": 0},
		                   "draft_message": None, "is_translatable": False, "message_auto_delete_time": 0,
		                   "pending_join_requests": None}

	def startup(self):
		"""What TDLib says first: who is who, the chats, then that we are in."""
		for u in self.users.values():
			yield {"@type": "updateUser", "user": u}
		yield from self.groups
		for c in self.chats.values():
			yield {"@type": "updateNewChat", "chat": c}
		yield {"@type": "updateAuthorizationState", "authorization_state": {"@type": "authorizationStateReady"}}

	def filtered(self, chat_id, f):
		msgs = self.messages.get(chat_id, [])
		return [m for m in msgs if m["content"]["@type"] in self.KINDS[f]] if f in self.KINDS else msgs

	def answer(self, req):
		"""The answers to a request (and the updates it brings), as TDLib would send them."""
		t = req["@type"]
		extra = req.get("@extra")
		out = []

		def reply(obj):
			if extra is not None:
				out.append(dict(obj, **{"@extra": extra}))

		if t == "getMe":
			reply(self.me)
		elif t in ("getChatHistory", "getMessageThreadHistory"):
			msgs = self.messages.get(req["chat_id"], [])
			frm, off, lim = req.get("from_message_id", 0), req.get("offset", 0), req.get("limit", 30)
			start = 0
			if frm:		# older than from_message_id; a negative offset: that many newer too (it among them)
				start = next((i for i, m in enumerate(msgs) if m["id"] < frm), len(msgs))
				if off < 0:
					start = max(0, start + off)
			reply({"@type": "messages", "total_count": len(msgs), "messages": msgs[start:start + lim]})
		elif t == "getMessage":
			m = next((m for m in self.messages.get(req["chat_id"], []) if m["id"] == req["message_id"]), None)
			reply(m or {"@type": "error", "code": 404, "message": "Not Found"})
		elif t == "downloadFile":
			f = self.files.get(req["file_id"])
			if f:
				f["local"].update(is_downloading_completed=True, path=f["_path"], downloaded_size=f["size"])
				reply(f)
				out.append({"@type": "updateFile", "file": f})
			else:
				reply({"@type": "error", "code": 404, "message": "no file"})
		elif t == "getMessageProperties":
			reply({"@type": "messageProperties", "can_be_copied": True, "can_be_deleted_for_all_users": True,
			       "can_be_deleted_only_for_self": True, "can_be_edited": False, "can_be_forwarded": True,
			       "can_be_pinned": False, "can_be_replied": True, "can_be_saved": True, "can_get_link": False,
			       "can_report_chat": False})
		elif t == "getMessageAvailableReactions":
			reply({"@type": "availableReactions", "recent_reactions": [], "popular_reactions": [],
			       "allow_custom_emoji": False, "are_tags": False, "top_reactions": [
			           {"@type": "availableReaction", "type": {"@type": "reactionTypeEmoji", "emoji": e}, "needs_premium": False}
			           for e in ["👍", "❤", "🔥", "😁"]]})
		elif t == "getChatPinnedMessage":
			reply({"@type": "error", "code": 404, "message": "Not Found"})
		elif t == "getChatMessageCount":
			reply({"@type": "count", "count": len(self.filtered(req["chat_id"], (req.get("filter") or {}).get("@type", "")))})
		elif t == "searchChatMessages":
			msgs = self.filtered(req["chat_id"], (req.get("filter") or {}).get("@type", ""))
			q = req.get("query", "").lower()
			if q:
				msgs = [m for m in msgs if q in (m["content"].get("text") or m["content"].get("caption") or {}).get("text", "").lower()]
			reply({"@type": "foundChatMessages", "total_count": len(msgs), "messages": msgs[:req.get("limit", 50)],
			       "next_from_message_id": 0})
		elif t in ("getSupergroupFullInfo", "getBasicGroupFullInfo"):
			reply({"@type": "supergroupFullInfo", "member_count": 120, "members": []})
		elif t == "deleteMessages":
			ids = req["message_ids"]
			self.messages[req["chat_id"]] = [m for m in self.messages[req["chat_id"]] if m["id"] not in ids]
			reply({"@type": "ok"})
			out.append({"@type": "updateDeleteMessages", "chat_id": req["chat_id"], "message_ids": ids,
			            "is_permanent": True, "from_cache": False})
		else:
			reply({"@type": "ok"})
		return out
