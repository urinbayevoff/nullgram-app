"""A group with most of what a row shows (no spoilers: their dust moves, a shot would differ each time):
names and pictures, a reply, a pinned, formatted and quoting message, a forward, reactions on two lines,
a voice note, a file, a song, an album, the unread bar, days. Shots g1..g6 up from the bottom: compare
them with cmp.py before and after a change to the rows."""
from fake import *

USERS = {2: ("Ali", "Valiyev"), 3: ("Vali", "Aliyev"), 4: ("Gulnora", ""), 5: ("Sardor", "Karimov")}
OPEN = "!-1002"			# (unread: only "!" opens it)
B = lambda o, n: {"@type": "textEntity", "offset": o, "length": n, "type": {"@type": "textEntityTypeBold"}}
L = lambda o, n, u: {"@type": "textEntity", "offset": o, "length": n, "type": {"@type": "textEntityTypeTextUrl", "url": u}}
Q = lambda o, n: {"@type": "textEntity", "offset": o, "length": n, "type": {"@type": "textEntityTypeBlockQuote"}}
msgs = [
	{"content": service("messageChatAddMembers", member_user_ids=[5]), "sender": 2, "date": NOW - 90000},
	{"content": text("Assalomu alaykum hammaga!"), "sender": 2, "date": NOW - 89000},
	{"content": text("Va alaykum assalom. Ertaga soat nechida uchrashamiz? Men o'ndan keyin bo'shman."), "sender": 3, "date": NOW - 88000},
	{"content": text("Soat 11 da bo'ladimi?"), "sender": 3, "date": NOW - 87990, "reply": 1},
	{"content": text("Bo'ladi 👍"), "out": True, "date": NOW - 3600, "reply": 3, "reactions": [("👍", 3), ("❤", 1)]},
	{"content": text("😂"), "sender": 4, "date": NOW - 3500},
	{"content": text("Muhim e'lon: yig'ilish ko'chirildi. Batafsil havolada.", [B(0, 12), L(41, 7, "https://t.me/durov")]),
	 "sender": 2, "date": NOW - 3400, "pinned": True},
	{"content": text("Bu iqtibos ichida turgan gap\nva keyingi qator", [Q(0, 28)]), "sender": 5, "date": NOW - 3300, "edited": True},
	{"content": text("Bu xabar boshqa joydan uzatilgan, o'qib chiqinglar"), "sender": 5, "date": NOW - 3200, "fwd": 3},
	{"content": photo("c", caption="Kechagi tadbirdan bitta rasm"), "sender": 2, "date": NOW - 3100,
	 "reactions": [("🔥", 12), ("👍", 7), ("❤", 5), ("😁", 2), ("🎉", 1)]},
	{"content": voice(12), "sender": 3, "date": NOW - 3000},
	{"content": document("jadval.xlsx", 48000, mime="application/vnd.ms-excel"), "sender": 4, "date": NOW - 2900},
	{"content": audio("Navo", "Sherali", 263), "out": True, "date": NOW - 2800},
	{"content": photo("d"), "sender": 5, "date": NOW - 2700, "album": 9},
	{"content": photo("e"), "sender": 5, "date": NOW - 2699, "album": 9},
	{"content": text("Rahmat, hammasi aniq. Ertaga ko'rishguncha!"), "out": True, "date": NOW - 2600},
	{"content": text("Xayr"), "sender": 2, "date": NOW - 60},
]
CHATS = [{"id": -1002, "title": "Sinov guruhi", "kind": "supergroup", "members": 42, "messages": msgs, "unread": 2}]
STEPS = [(4.0, "shot", "g1")] + [x for k in range(1, 6) for x in [
	(4.0 + k * 0.8 - 0.4, "eval", "list.contentY = list.contentY - 560"), (4.0 + k * 0.8, "shot", "g%d" % (k + 1))]] + [(9.0, "quit")]
