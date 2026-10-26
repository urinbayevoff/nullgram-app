"""A message's menu (a long press): N=6 a bubble with room for its actions under it; N=18 one taller than
the screen — its top under the reactions, the actions under it, scrolled to them; a drag shows its
top; a tap off it closes. Shots menu-open, menu-top, menu-shut. Needs GL (desk.py's Xvfb): offscreen
the blur, the lifted bubble and the reactions are not drawn."""
import os
from fake import *

USERS = {2: ("Ali", "Valiyev")}
OPEN = 2
long = " ".join(["Bu juda uzun xabar, menyu qayerga tushishini ko'rish uchun yozilgan."] * int(os.environ.get("N", "18")))
CHATS = [{"id": 2, "title": "Ali Valiyev", "kind": "private", "user": 2, "messages": [
	{"content": text("Salom")}, {"content": text(long)}, {"content": text("Oxirgi")}]}]
STEPS = [(4.0, "hold", 150, 400), (5.4, "shot", "menu-open"),
         (5.6, "drag", 200, 200, 200, 700, 400), (7.3, "shot", "menu-top"),
         (7.5, "tap", 340, 300), (8.3, "shot", "menu-shut"), (8.5, "quit")]
