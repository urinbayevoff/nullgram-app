# Nullgram

A Telegram client for Linux phones, written from scratch: **TDLib** underneath, **Qt Quick**
(PySide6) on screen, and Telegram-iOS's motion and look on top. The interface is in Uzbek.

It is built for OmonullOS, a Linux phone OS running on the Galaxy S10 5G, where it shows up as
«null» in the app list. Nullgram is young and still changes every day.

## What it does

- Sign in with a QR code or with a phone number, its code and the cloud password
- Chat list with folders, search and contacts
- Groups and channels: replies, quotes, reactions, pinned messages, comments, join requests,
  and the permissions a group's admins set
- Photos, videos, albums, files, songs and voice notes; the photo viewer; spoiler media
- The attach sheet, forwarding, a context menu with reactions, picking several messages
- Settings: profile, appearance, devices, storage

The motion follows Telegram-iOS closely. Its springs and timings were read from the Telegram-iOS
source and checked frame by frame against screen recordings of the iPhone app. The numbers and how
they were measured are in [NOTES.md](NOTES.md).

## Layout

- `app/nullgram.py` loads TDLib (`libtdjson`) and passes its JSON to the QML side.
- `app/qml/` draws the screens and keeps the app's state (`Store.qml`).
- `tools/desk/` is a test bench that runs without a phone. It renders the app's own QML over a fake
  TDLib that answers from scripted scenes (`tools/desk/scenes/`), offscreen. It saves screenshots,
  replays taps, holds and drags, and `cmp.py` compares two runs pixel by pixel.
- `archive/v0.6/` is the first version (Python + Telethon, "Tepegram"), kept for reference.

## Running it

You need TDLib (built at `~/.local/td/lib/libtdjson.so`; 1.8.68 is the version tested) and PySide6.
You also need your own Telegram API ID and hash from https://my.telegram.org. They go in
`~/.config/omonullos/tg-api.env` as `TG_API_ID=` and `TG_API_HASH=` and are never committed.

```sh
./install.sh [--key]     # copy the app to the phone over ssh (ZTOS_DEVICE=user@host)
./run.sh [--test-dc]     # install and start it; log: /tmp/nullgram.log on the phone
```

Test bench (needs PySide6 with QtMultimedia and ffmpeg; Xvfb is optional, for GL rendering):

```sh
python3 tools/desk/desk.py tools/desk/scenes/media.py /tmp/out
```

## License

GPL-2.0. See [LICENSE](LICENSE). TDLib is under the Boost Software License, and Telegram-iOS,
whose behaviour Nullgram follows, is under GPL-2.0.
