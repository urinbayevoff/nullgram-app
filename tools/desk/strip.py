#!/usr/bin/env python3
"""desk.py's pictures side by side in one, smaller (K=0.5 by default): a sequence, or before and after.

  K=0.4 python3 tools/desk/strip.py <out.png> <a.png> <b.png> ..."""
import os
import sys

os.environ["QT_QPA_PLATFORM"] = "offscreen"
from PySide6.QtGui import QGuiApplication, QImage, QPainter  # noqa: E402

app = QGuiApplication(sys.argv[:1])
imgs = [QImage(p) for p in sys.argv[2:]]
w = sum(i.width() for i in imgs) + 16 * (len(imgs) - 1)
h = max(i.height() for i in imgs)
out = QImage(w, h, QImage.Format_RGB32)
out.fill(0xffffff)
p = QPainter(out)
x = 0
for i in imgs:
	p.drawImage(x, 0, i)
	x += i.width() + 16
p.end()
k = float(os.environ.get("K", "0.5"))
out.scaled(int(w * k), int(h * k)).save(sys.argv[1])
