#!/usr/bin/env python3
"""On the phone: a throwaway account on Telegram's test servers, to test Nullgram with chats
of our own (unread ones, long ones) and never touch the owner's.

  python3 tdtest.py <data dir> <phone 99966XYYYY> me
  python3 tdtest.py <data dir> <phone> send <their phone> <count> [text]

Test numbers sign in with the code X five times (X: the number's 6th digit). The API key is
Nullgram's (its data dir's api.json)."""
import ctypes
import json
import os
import sys
import time

KEY = os.path.expanduser("~/.local/share/ztos/data/uz.omonullos.nullgram/api.json")
td = ctypes.CDLL(os.path.expanduser("~/.local/td/lib/libtdjson.so"))
td.td_create_client_id.restype = ctypes.c_int
td.td_send.argtypes = [ctypes.c_int, ctypes.c_char_p]
td.td_receive.argtypes = [ctypes.c_double]
td.td_receive.restype = ctypes.c_char_p
td.td_execute.argtypes = [ctypes.c_char_p]
td.td_execute(json.dumps({"@type": "setLogVerbosityLevel", "new_verbosity_level": 0}).encode())

data, phone, cmd, args = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
client = td.td_create_client_id()
seq = 0


def send(req):
	global seq
	seq += 1
	req["@extra"] = str(seq)
	td.td_send(client, json.dumps(req).encode())
	return str(seq)


def call(req, timeout=30):
	"""a request's answer (updates on the way are looked at for the sign-in)"""
	extra = send(req)
	end = time.time() + timeout
	while time.time() < end:
		u = poll(1.0)
		if u and u.get("@extra") == extra:
			return u
	raise SystemExit("no answer to " + req["@type"])


state = None


def poll(t):
	global state
	r = td.td_receive(t)
	if not r:
		return None
	u = json.loads(r)
	if u["@type"] == "updateAuthorizationState":
		state = u["authorization_state"]["@type"]
		key = json.load(open(KEY))
		if state == "authorizationStateWaitTdlibParameters":
			send({"@type": "setTdlibParameters", "use_test_dc": True, "database_directory": data + "/db",
			      "files_directory": data + "/files", "use_message_database": True, "use_chat_info_database": True,
			      "api_id": int(key["id"]), "api_hash": key["hash"], "system_language_code": "uz",
			      "device_model": "Nullgram test", "application_version": "0.1"})
		elif state == "authorizationStateWaitPhoneNumber":
			send({"@type": "setAuthenticationPhoneNumber", "phone_number": phone})
		elif state == "authorizationStateWaitCode":
			send({"@type": "checkAuthenticationCode", "code": phone[5] * 5})
		elif state == "authorizationStateWaitRegistration":
			send({"@type": "registerUser", "first_name": "Test " + phone[-4:], "last_name": ""})
	return u


os.makedirs(data, exist_ok=True)
send({"@type": "getOption", "name": "version"})
end = time.time() + 60
while state != "authorizationStateReady" and time.time() < end:
	poll(1.0)
if state != "authorizationStateReady":
	raise SystemExit("not signed in: " + str(state))

if cmd == "me":
	me = call({"@type": "getMe"})
	print(me["id"], me.get("phone_number"), me["first_name"])
elif cmd == "send":
	them, n = args[0], int(args[1])
	text = args[2] if len(args) > 2 else "Sinov xabari"
	r = call({"@type": "importContacts", "contacts": [{"@type": "importedContact", "phone_number": them,
	                                                     "first_name": "Sinov", "last_name": ""}]})
	uid = r["user_ids"][0]
	if not uid:
		raise SystemExit(them + " is not on the test servers")
	chat = call({"@type": "createPrivateChat", "user_id": uid, "force": False})
	for i in range(1, n + 1):
		call({"@type": "sendMessage", "chat_id": chat["id"],
		      "input_message_content": {"@type": "inputMessageText",
		                                "text": {"@type": "formattedText", "text": "%s %d" % (text, i)}}})
		time.sleep(0.15)
	time.sleep(2)		# (the last ones leave)
	print("sent", n, "to", them, "chat", chat["id"])
send({"@type": "close"})		# the database is let go cleanly
end = time.time() + 10
while state != "authorizationStateClosed" and time.time() < end:
	poll(0.5)
