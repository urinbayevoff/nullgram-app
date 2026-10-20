# Nullgram

Our own Telegram client for the OmonullOS phone (Galaxy S10 5G first): Qt Quick for the screen,
TDLib underneath, Telegram-iOS's motion and look. «null» in the phone's app list.

- `app/` — the app: `nullgram.py` loads TDLib and carries its JSON; `qml/` draws and keeps the state.
- `./install.sh [--key]` — put it on the phone (`ZTOS_DEVICE`, default `user@phone`).
- `./run.sh [--test-dc]` — install and start it from here; log in `/tmp/nullgram.log` on the phone.
- `NOTES.md` — what was learnt from Telegram-iOS and the owner's iPhone videos; `STATUS.md` — where things stand.
- `archive/v0.6/` — the first version (Python ztOS SDK + Telethon, "Tepegram"), kept for reference.

Needs TDLib on the phone at `~/.local/td/lib/libtdjson.so` (built there, 1.8.68) and PySide6.
