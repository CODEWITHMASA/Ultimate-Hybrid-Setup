#!/usr/bin/env bash
set -euo pipefail

# 🚀 أداة MASA - CODE WITH MASA
# خاص بـ Ubuntu 24.04

AUTHOR="MASA"
CHANNEL="CODE WITH MASA"
AIO_URL="https://allinoneruntimes.org/files/aio-runtimes_v2.5.0.exe"
AIO_TMP="/tmp/aio-runtimes_v2.5.0.exe"
WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"
DESKTOP_DIR="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
FINISH_LINK="https://t.me/MrMasaOfficial"

echo "🔧 [$CHANNEL by $AUTHOR] بدء التثبيت على Ubuntu 24.04..."

# تحديث النظام
apt update && apt upgrade -y
echo "✅ [$CHANNEL] تحديث النظام اكتمل."

# تمكين معمارية 32bit
dpkg --add-architecture i386 || true
apt update

# تثبيت الحزم الأساسية
apt install -y --no-install-recommends \
  software-properties-common wget curl ca-certificates gnupg2 apt-transport-https \
  cabextract p7zip-full unzip gdebi-core xdg-utils

# تثبيت Wine و winetricks
echo "🍷 [$CHANNEL] جاري تثبيت Wine + Winetricks..."
apt install -y wine64 wine32 winetricks
echo "✅ [$CHANNEL] Wine و Winetricks تم تثبيتهم."

# إعداد Wine Prefix
export WINEPREFIX="$WINEPREFIX"
export WINEARCH="win32"
sudo -u "$SUDO_USER" env WINEPREFIX="$WINEPREFIX" WINEARCH="$WINEARCH" wineboot -u || true
echo "✅ [$CHANNEL] Wine Prefix جاهز."

# تثبيت runtimes عبر winetricks
echo "📦 [$CHANNEL] تثبيت corefonts + vcrun + dotnet..."
sudo -u "$SUDO_USER" env WINEPREFIX="$WINEPREFIX" winetricks -q corefonts vcrun2019 dotnet48 || true
echo "✅ [$CHANNEL] تم تثبيت المكتبات الأساسية."

# تحميل aio runtimes
echo "⬇️ [$CHANNEL] تحميل AIO Runtimes..."
wget -O "$AIO_TMP" "$AIO_URL"
echo "▶️ [$CHANNEL] تشغيل AIO Runtimes عبر Wine..."
sudo -u "$SUDO_USER" env WINEPREFIX="$WINEPREFIX" DISPLAY="${DISPLAY:-:0}" wine "$AIO_TMP" &

# إزالة وتثبيت Google Chrome
echo "🌐 [$CHANNEL] إعادة تثبيت Google Chrome..."
apt remove -y google-chrome-stable || true
wget -O /tmp/chrome.deb "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
gdebi -n /tmp/chrome.deb || apt -f install -y
echo "✅ [$CHANNEL] Google Chrome جاهز."

# تثبيت Telegram
echo "💬 [$CHANNEL] تثبيت Telegram..."
apt install -y telegram-desktop || snap install telegram-desktop
echo "✅ [$CHANNEL] Telegram جاهز."

# إنشاء شورتكات على سطح المكتب
USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
USER_DESKTOP="$USER_HOME/Desktop"
mkdir -p "$USER_DESKTOP"

create_desktop_file() {
  local NAME="$1"; local EXEC="$2"; local ICON="$3"; local FILE="$USER_DESKTOP/${NAME// /_}.desktop"
  cat > "$FILE" <<EOF
[Desktop Entry]
Name=$NAME
Comment=$NAME
Exec=$EXEC
Terminal=false
Type=Application
Icon=$ICON
Categories=Utility;
StartupNotify=true
EOF
  chown "$SUDO_USER":"$SUDO_USER" "$FILE"
  chmod +x "$FILE"
  echo "🎯 [$CHANNEL] شورتكات $NAME جاهز على سطح المكتب."
}

create_desktop_file "Google Chrome" "google-chrome-stable %U" "google-chrome"
create_desktop_file "Telegram" "telegram-desktop" "telegram-desktop"

# فتح الرابط النهائي
echo "🚀 [$CHANNEL by $AUTHOR] التثبيت اكتمل. جاري فتح الرابط النهائي..."
sudo -u "$SUDO_USER" env DISPLAY="${DISPLAY:-:0}" xdg-open "$FINISH_LINK" || true

# رسالة ختامية
echo -e "\n✨ شكراً لاستخدامك أداة $AUTHOR - $CHANNEL ✨"
echo "💡 تابعنا على الروابط الرسمية:"
echo "Facebook :  https://www.facebook.com/CODEWITHMASA"
echo "Instagram : https://www.instagram.com/codewithmasa"
echo "Tiktok :    https://www.tiktok.com/@CODEWITHMASA"
echo "Youtube :   https://www.youtube.com/@CODEWITHMASA"
echo "Telegram :  https://t.me/CODEWITHMASA"
echo "Github :    https://github.com/CODEWITHMASA"
echo "X :         https://x.com/CODEWITHMASA"
echo "Website :   https://codewithmasa.blogspot.com/"
echo "Group :     https://t.me/GROUPCODEWITHMASA"
