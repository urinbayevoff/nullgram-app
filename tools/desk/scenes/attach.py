"""The attach sheet (📎): OPEN=2 a private chat — a picture and the video picked, ⋯, «Spoyler bilan
yashirish» (both blurred under dust), sent (the log shows has_spoiler); OPEN=-3001 a group barring
pictures (a tap on one says so, a video is picked); OPEN=-3002 a group barring media but not files
(it opens on Fayllar; Galereya says why it is empty)."""
import os
from fake import *

USERS = {2: ("Ali", "Valiyev")}
OPEN = int(os.environ.get("OPEN", "2"))
RECENT = [{"path": asset(n + ".jpg"), "name": n + ".jpg", "size": 240000, "kind": "photo", "w": w, "h": h}
          for n, (w, h) in (("a", (1280, 960)), ("b", (960, 1280)))]
RECENT.insert(2, {"path": asset("tiny.mp4"), "name": "tiny.mp4", "size": 30000, "kind": "video", "w": 0, "h": 0})
RECENT += [{"path": asset("c.jpg"), "name": "c.jpg", "size": 180000, "kind": "photo", "w": 1280, "h": 720},
           {"path": asset("v.ogg"), "name": "hisobot.ogg", "size": 9000, "kind": "audio", "w": 0, "h": 0}]
msgs = [{"content": text("Rasmlarni yubor")}]
MEDIA = {k: False for k in ["can_send_photos", "can_send_videos"]}
CHATS = [{"id": 2, "title": "Ali Valiyev", "kind": "private", "user": 2, "messages": msgs},
         {"id": -3001, "title": "Rasmsiz", "kind": "supergroup", "permissions": {"can_send_photos": False}, "messages": msgs},
         {"id": -3002, "title": "Mediasiz", "kind": "supergroup", "permissions": MEDIA, "messages": msgs}]
# the sheet: its top at 274, cells of 120 from y 334; ⋯ at the top right, its menu under it
if OPEN == 2:
	STEPS = [(3.8, "tap", 30, 735), (4.8, "tap", 60, 394), (5.4, "tap", 300, 394), (6.0, "shot", "attach-picked"),
	         (6.2, "tap", 335, 305), (6.8, "shot", "attach-menu"),
	         (7.0, "tap", 200, 449), (7.8, "shot", "attach-veiled"),
	         (8.0, "tap", 180, 719), (8.8, "shot", "attach-sent"), (9.0, "quit")]
elif OPEN == -3001:
	STEPS = [(3.8, "tap", 30, 735), (4.8, "tap", 60, 394), (5.2, "shot", "attach-nophoto"),
	         (5.6, "tap", 300, 394), (6.2, "shot", "attach-novideo-picked"), (6.4, "quit")]
else:
	STEPS = [(3.8, "tap", 30, 735), (4.8, "shot", "attach-files"),
	         (5.0, "tap", 140, 308), (5.6, "shot", "attach-nomedia"), (5.8, "quit")]
