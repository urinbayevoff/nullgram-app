"""A busy group of 300 (texts, photos, voice notes, files, videos, reactions): what a row makes
(objects, by kind) and how long the list takes positioned through end to end (ms, made anew as it
goes), a few times. Only to compare a change with what was before, on the same machine."""
import random
from fake import *

random.seed(7)
USERS = {2: ("Ali", "Valiyev"), 3: ("Vali", "Aliyev"), 4: ("Gulnora", ""), 5: ("Sardor", "Karimov"), 6: ("Malika", "")}
OPEN = -1001
words = ("salom qalesan bugun ertaga uchrashamiz albatta rahmat yaxshi ish bor edi kecha bozorga bordim narxlar "
         "qimmat bo'libdi shunaqa gaplar endi nima qilamiz hammasi joyida xavotir olma telefon qil").split()


def sentence(n):
	return " ".join(random.choice(words) for _ in range(n)).capitalize()


msgs = []
for k in range(300):
	r = random.random()
	m = {"sender": random.choice([2, 3, 4, 5, 6]), "out": random.random() < 0.2}
	if r < 0.55:
		m["content"] = text(sentence(random.choice([2, 4, 8, 15, 30])))
	elif r < 0.62:
		m["content"] = text(sentence(6), [{"@type": "textEntity", "offset": 0, "length": 5, "type": {"@type": "textEntityTypeBold"}}])
	elif r < 0.75:
		m["content"] = photo(random.choice("abcdef"), caption=sentence(5) if random.random() < 0.4 else "")
	elif r < 0.82:
		m["content"] = voice(random.randint(2, 40))
	elif r < 0.87:
		m["content"] = document("fayl%d.pdf" % k)
	elif r < 0.90:
		m["content"] = video(random.choice("abcdef"))
	else:
		m["content"] = text(sentence(3))
	if random.random() < 0.15:
		m["reactions"] = [("👍", random.randint(1, 9))] + ([("❤", 2)] if random.random() < 0.3 else [])
	msgs.append(m)
CHATS = [{"id": -1001, "title": "Katta guruh", "kind": "supergroup", "members": 250, "messages": msgs}]


def count(view, root, world):
	"""Objects each row made (the QObjects under it), by kind: least, most, mean."""
	from PySide6.QtQuick import QQuickItem
	page = root.property("topPage")
	lv = max([o for o in page.findChildren(QQuickItem) if o.inherits("QQuickListView")], key=lambda o: o.property("count") or 0)

	def total(o):
		return 1 + sum(total(c) for c in o.children())
	by = {}
	for c in lv.property("contentItem").childItems():
		if c.property("msgId") is not None:
			by.setdefault(c.property("picKind") or c.property("rowKind") or "text", []).append(total(c))
	print("desk: objects a row:", {k: (min(v), max(v), round(sum(v) / len(v))) for k, v in by.items()}, flush=True)


THROUGH = """(function () {
	const t0 = Date.now()
	for (let k = 0; k < list.count; k += 2) { list.positionViewAtIndex(k, ListView.Beginning); list.forceLayout() }
	return Date.now() - t0
})()"""
STEPS = [(3.5 + 0.35 * k, "eval", "page.older()") for k in range(10)] + [
	(7.5, "eval", "messages.count"), (7.6, "call", count),
	(7.7, "eval", "list.positionViewAtEnd()"), (8.0, "call", count), (8.2, "eval", "list.positionViewAtBeginning()")] + [
	(9.0 + 1.5 * k, "eval", THROUGH) for k in range(8)] + [(21.5, "quit")]
