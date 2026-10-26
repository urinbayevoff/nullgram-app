"""A channel we read: views, comments rows, ↪ beside the posts, an album, a video, a long post, the
sound capsule. Shots c1..c5 up from the bottom (compare with cmp.py)."""
from fake import *

USERS = {2: ("Ali", "Valiyev")}
OPEN = -1003
msgs = [
	{"content": service("messageSupergroupChatCreate", title="Yangiliklar"), "date": NOW - 200000},
	{"content": text("Kanalimizga xush kelibsiz! Bu yerda eng so'nggi yangiliklar."), "date": NOW - 190000, "views": 1520, "comments": 0},
	{"content": photo("a", caption="Bugungi rasm: shahar markazi"), "date": NOW - 7200, "views": 12345, "comments": 14,
	 "reactions": [("👍", 120), ("🔥", 45)]},
	{"content": photo("b"), "date": NOW - 3600, "views": 980, "comments": 3, "album": 5},
	{"content": photo("f", caption="Albom izohi"), "date": NOW - 3599, "views": 980, "comments": 3, "album": 5},
	{"content": video("c", caption="Qisqa video"), "date": NOW - 1800, "views": 2400000, "comments": -1},
	{"content": text("Uzun post: " + "so'z " * 60), "date": NOW - 600, "views": 77, "edited": True},
]
CHATS = [{"id": -1003, "title": "Yangiliklar", "kind": "channel", "members": 5400, "messages": msgs}]
STEPS = [(4.0, "shot", "c1")] + [x for k in range(1, 5) for x in [
	(4.0 + k * 0.8 - 0.4, "eval", "list.contentY = list.contentY - 560"), (4.0 + k * 0.8, "shot", "c%d" % (k + 1))]] + [(8.0, "quit")]
