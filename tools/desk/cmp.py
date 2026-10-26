#!/usr/bin/env python3
"""Two folders of desk.py's pictures compared: how many points differ in each (by more than a faint
shade), and beside the new ones a diff-<name>.png with them in red. Exit 1 when any differ.

  python3 tools/desk/cmp.py <before> <after> [names...]      (default: all, but *mid*: caught mid-motion)"""
import os
import sys

os.environ["QT_QPA_PLATFORM"] = "offscreen"
from PySide6.QtGui import QColor, QGuiApplication, QImage, QPainter  # noqa: E402

app = QGuiApplication(sys.argv[:1])
a_dir, b_dir = sys.argv[1], sys.argv[2]
names = sys.argv[3:] or sorted(n for n in os.listdir(a_dir) if n.endswith(".png") and "mid" not in n and not n.startswith("diff-"))
bad = 0
for n in names:
	a, b = QImage(os.path.join(a_dir, n)), QImage(os.path.join(b_dir, n))
	if a.isNull() or b.isNull() or a.size() != b.size():
		print("%-12s missing, or another size" % n)
		bad += 1
		continue
	a = a.convertToFormat(QImage.Format_RGB32)
	b = b.convertToFormat(QImage.Format_RGB32)
	ba, bb = bytes(a.constBits()), bytes(b.constBits())
	if ba == bb:
		print("%-12s same" % n)
		continue
	w, h = a.width(), a.height()
	diff = QImage(a)
	p = QPainter(diff)
	p.fillRect(0, 0, w, h, QColor(255, 255, 255, 170))
	p.end()
	count, box = 0, [w, h, 0, 0]
	for y in range(h):
		ra, rb = ba[y * w * 4:(y + 1) * w * 4], bb[y * w * 4:(y + 1) * w * 4]
		if ra == rb:
			continue
		for x in range(w):
			i = x * 4
			if max(abs(ra[i] - rb[i]), abs(ra[i + 1] - rb[i + 1]), abs(ra[i + 2] - rb[i + 2])) > 24:
				count += 1
				diff.setPixel(x, y, 0xffff0000)
				box = [min(box[0], x), min(box[1], y), max(box[2], x), max(box[3], y)]
	print("%-12s %s" % (n, "%d px differ in %s" % (count, box) if count else "only faintly"))
	if count:
		bad += 1
		diff.save(os.path.join(b_dir, "diff-" + n))
sys.exit(1 if bad else 0)
