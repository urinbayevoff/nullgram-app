"""«Tanlash» in group.py's chat: picked by the menu's way, one more, scrolled, off. Shots p1..p5 (*mid*:
caught mid-motion, cmp.py leaves them out)."""
from group import USERS, OPEN, CHATS

STEPS = [(4.0, "eval", "page.startPicking([messages.get(2).msgId])"),
         (4.1, "shot", "p0-mid"),
         (5.0, "shot", "p1"),
         (5.2, "eval", "page.pick([messages.get(4).msgId])"),
         (5.6, "shot", "p2"),
         (5.8, "eval", "list.contentY = list.contentY - 560"),
         (6.4, "shot", "p3"),
         (6.6, "eval", "page.stopPicking()"),
         (6.75, "shot", "p4-mid"),
         (7.5, "shot", "p5"),
         (7.7, "quit")]
