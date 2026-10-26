"""Albums of files and songs (one bubble, one under another, each its caption), a single file between;
a tap on an album's second document brings it down and saves it, on the second song plays it."""
from fake import *

USERS = {2: ("Ali", "Valiyev")}
OPEN = 2
CHATS = [{"id": 2, "title": "Ali Valiyev", "kind": "private", "user": 2, "messages": [
	{"content": text("Hujjatlarni yuboryapman")},
	{"content": document("shartnoma.pdf", 830000), "album": 31},
	{"content": document("ilova-1.docx", 41000, mime="application/msword", caption="Birinchi ilova"), "album": 31},
	{"content": document("hisob-faktura-2026-oktabr.xlsx", 2200000, here=True, mime="application/vnd.ms-excel"), "album": 31},
	{"content": text("Rahmat, oldim"), "out": True},
	{"content": audio("Bahor", "Sherali", 241, name="bahor.mp3"), "album": 32, "out": True},
	{"content": audio("Yor-yor", "Yulduz", 198, name="yor.mp3"), "album": 32, "out": True},
	{"content": audio("Navo", "Ozodbek", 312, name="navo.mp3", caption="Kecha aytgan qo'shiqlarim"), "album": 32, "out": True},
	{"content": document("bitta-fayl.zip", 5600000, mime="application/zip")},
	{"content": document("rasm.pdf", 90000, caption="Oxirgisida izoh, uzunroq: shu yerda vaqt qayerga tushishini ko'ramiz"), "album": 33},
	{"content": document("rasm2.pdf", 91000, caption="Oxirgi izoh"), "album": 33},
]}]
STEPS = [(4.0, "shot", "files-bottom"),
         (4.2, "eval", "list.contentY = list.contentY - 560"), (4.8, "eval", "list.contentY = list.contentY - 560"),
         (5.4, "tap", 160, 240),            # ilova-1.docx
         (6.4, "shot", "files-saved"),
         (6.8, "tap", 100, 488),            # Yor-yor's button
         (7.8, "eval", "page.soundId >> 20"),
         (7.9, "shot", "files-playing"),
         (8.1, "quit")]
