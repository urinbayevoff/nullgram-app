"""A private chat with media of every kind: spoilers (a photo, a video, two of an album, a GIF), a voice
note, a song, a file; a tap blows the photo's spoiler off. Its shots: bottom, top, blown."""
from fake import *

USERS = {2: ("Ali", "Valiyev")}
OPEN = 2
CHATS = [{"id": 2, "title": "Ali Valiyev", "kind": "private", "user": 2, "messages": [
	{"content": text("Salom! Rasmlarni ko'rdingmi?")},
	{"content": photo("a", spoiler=True)},
	{"content": video("c", spoiler=True, caption="Spoilerli video")},
	{"content": photo("b", caption="Oddiy rasm")},
	{"content": voice(), "out": True},
	{"content": audio()},
	{"content": document()},
	{"content": photo("d", spoiler=True), "album": 77, "out": True},
	{"content": photo("e"), "album": 77, "out": True},
	{"content": photo("f", spoiler=True, caption="Albom"), "album": 77, "out": True},
	{"content": animation("a", spoiler=True)},
	{"content": text("Oxirgi xabar")},
]}]
STEPS = [(4.0, "shot", "media-bottom"),
         (4.2, "eval", "list.positionViewAtEnd()"),
         (5.0, "shot", "media-top"),
         (5.2, "tap", 147, 270),            # the photo's spoiler
         (6.2, "shot", "media-blown"),
         (6.4, "quit")]
