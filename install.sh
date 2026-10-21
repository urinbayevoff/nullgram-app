#!/bin/sh
# Nullgram on the phone as an app: app/ goes to ~/nullgram (with qrcode beside it), a starter to
# ztOS's apps, a .desktop entry ("null" in the app list), the API key once, and the shell is told.
#   ./install.sh [--key]       (--key: write the API key again; ./run.sh installs and starts it from here)
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DEV=${ZTOS_DEVICE:-user@phone}
KEYFILE=${TG_API_ENV:-$HOME/.config/omonullos/tg-api.env}
ID=uz.omonullos.nullgram
DATA='$HOME/.local/share/ztos/data/'$ID

# qrcode for the sign-in QR: pure Python, kept here (vendor/ is not in git)
if [ ! -d "$HERE/vendor/qrcode" ]; then
	mkdir -p "$HERE/vendor"
	cp -r "$HERE/archive/v0.6/vendor/qrcode" "$HERE/vendor/" 2>/dev/null ||
		python3 -m pip install -q --no-deps --target "$HERE/vendor" qrcode==8.2
fi
tar cf - -C "$HERE" --exclude=__pycache__ --exclude='*.dist-info' app vendor icon.svg | ssh "$DEV" \
	'rm -rf ~/nullgram.new && mkdir ~/nullgram.new && tar xf - -C ~/nullgram.new && mv ~/nullgram.new/vendor ~/nullgram.new/app/ &&
	 mv ~/nullgram.new/icon.svg ~/nullgram.new/app/ && rm -rf ~/nullgram && mv ~/nullgram.new/app ~/nullgram && rm -rf ~/nullgram.new'

if [ "${1:-}" = --key ] || ! ssh "$DEV" "[ -f $DATA/api.json ]"; then
	echo "API key -> phone"
	# shellcheck disable=SC1090
	. "$KEYFILE"
	printf '{"id": %s, "hash": "%s"}\n' "$TG_API_ID" "$TG_API_HASH" | \
		ssh "$DEV" "d=$DATA; mkdir -p \$d && umask 077 && cat > \$d/api.json && chmod 600 \$d/api.json"
fi

ssh "$DEV" sh -s "$ID" <<'S'
set -e
ID=$1 a=$HOME/.local/share/ztos/apps/$1 i=$HOME/.local/share/icons/hicolor/scalable/apps/$1.svg
mkdir -p "$(dirname "$a")" "$(dirname "$i")" ~/.local/share/applications
cp ~/nullgram/icon.svg "$i"
cat > "$a" <<'E'
#!/bin/sh
# one at a time: a second tap brings the running one back (hidden when it was closed: SIGUSR1 shows it)
pid=$(pgrep -f '[n]ullgram/nullgram.py') && { kill -USR1 $pid; exit 0; }
export QT_QPA_PLATFORM=wayland QT_FORCE_STDERR_LOGGING=1	# started by the shell, Qt would log to journald
exec python3 "$HOME/nullgram/nullgram.py" "$@" > /tmp/nullgram.log 2>&1
E
chmod 755 "$a"
cat > ~/.local/share/applications/$ID.desktop <<E
[Desktop Entry]
Type=Application
Name=null
Comment=Nullgram: Telegram, Qt Quick + TDLib
Exec=$a
Icon=$i
Terminal=false
StartupWMClass=ztos.$ID
Categories=Network;
X-ZtOS-Id=$ID
E
ctl=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ztmetro.ctl
[ -p "$ctl" ] && timeout 2 sh -c 'printf "apps\n" > "$1"' _ "$ctl" || true
echo "installed $ID"
S
