# Tepegram

Telegram uchun norasmiy ilova: ztOS telefonlar (OmonullOS, Galaxy S10 5G) uchun,
Windows Phone 8.1 ko'rinishida. ztOS SDK (Python + PySide6, GPU bilan chiziladi)
ustida yozilgan; sahifalar 360 nuqta kenglikda, shell ekranga moslaydi — boshqa
telefonlarga ham shu yo'l bilan o'tadi.

| fayl | nima |
|---|---|
| `main.py` | sahifalar: ulanish, kirish (QR / raqam + kod + parol), chatlar, chat, qidiruv, sozlamalar |
| `views.py` | o'z vidjetlarimiz (Telegram for WP ko'rinishi): ChatRow, ContactRow, Bubble, QrView; `TiledPage` — ro'yxat GPU'da plitkalar bilan (+ har plitkaning xira kichik nusxasi) |
| `glass.py` | `GlassBar` — "liquid glass" panel (iOS Telegram o'lchamlari), pastda yoki tepada: tablar, doira tugmalar, yozish maydoni, sarlavha kapsulasi, avatar |
| `tg.py` | Telegram bilan aloqa: `Backend` (o'z oqimida asyncio, Qt signallari dict tashiydi) — TDLib'ga o'tganda faqat shu fayl almashadi |
| `tools/vendor.py` | Telethon, rsa, pyasn1, qrcode, pyaes ni PyPI'dan (sha256 bilan) `vendor/` ga |
| `tools/measure.sh`, `tools/shot.sh` | telefonda: aylantirib kadr/s o'lchash, skrinshot |
| `tools/deploy.sh` | telefonga: kutubxonalar (u yerda compileall), API kaliti, ilova (`ztos-sdk install`) |

## Telefonga qo'yish

```
tools/deploy.sh            # kerak bo'lsa --libs / --key
```

Kerak: OmonullOS repo (`$OMONULLOS`, default `~/work/OmonullOS`, undagi `sdk/bin/ztos-sdk`),
`ssh phone` (Cloudflare tunnel), API kaliti `~/.config/omonullos/tg-api.env`
(`TG_API_ID=`, `TG_API_HASH=`; repo'ga kirmaydi). Telefonda: `~/.local/share/ztos/data/uz.omonullos.tepegram/`
(`vendor/`, `api.json`, `tepegram.session`). Log: `ztos-sdk logs` (ilova papkasidan).

Holat va keyingi qadamlar: o'sha paytdagi STATUS.md (endi repoda yo'q).
