"""Groups with rights taken away: OPEN=-2001 text barred (the field locked), -2002 nothing (the bar),
-2003 voice notes barred (the mic dim), -2004 only voice notes (📎 dim). A tap on the field, 📎, the mic."""
import os
from fake import *

USERS = {2: ("Ali", "Valiyev")}
OPEN = int(os.environ.get("OPEN", "-2001"))
msgs = [{"content": text("Bu guruhda faqat rasm va fayl yuboriladi"), "sender": 2}]
NOTEXT = {"can_send_basic_messages": False}
NOTHING = {k: False for k in ["can_send_basic_messages", "can_send_audios", "can_send_documents", "can_send_photos",
                              "can_send_videos", "can_send_video_notes", "can_send_voice_notes", "can_send_polls",
                              "can_send_other_messages"]}
CHATS = [{"id": -2001, "title": "Faqat media", "kind": "supergroup", "permissions": NOTEXT, "messages": msgs},
         {"id": -2002, "title": "Hech narsa", "kind": "supergroup", "permissions": NOTHING, "messages": msgs},
         {"id": -2003, "title": "Ovozsiz", "kind": "supergroup", "permissions": {"can_send_voice_notes": False}, "messages": msgs},
         {"id": -2004, "title": "Faqat ovoz", "kind": "supergroup", "permissions": dict(NOTHING, can_send_voice_notes=True), "messages": msgs}]
STEPS = [(3.8, "shot", "perm-a"),
         (4.0, "tap", 180, 735), (4.4, "shot", "perm-field"),
         (5.0, "hold", 330, 735), (5.6, "shot", "perm-mic"),
         (6.4, "tap", 30, 735), (6.8, "shot", "perm-clip"),
         (7.0, "quit")]
