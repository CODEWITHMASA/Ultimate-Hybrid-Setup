#!/usr/bin/env bash
# setup-wine-aio.sh
# سكربت لإعداد Wine + برامجك المطلوبة
# موجه لأنظمة Debian/Ubuntu

set -u  # نوقف بس لو متغير غير معرف

# --- CONFIG ---
AIO_URL="https://allinoneruntimes.org/files/aio-runtimes_v2.5.0.exe"
AIO_FILE="$HOME/Downloads/$(basename "$AIO_URL")"
CHROME_DEB="/tmp/google-chrome-stable_current_amd64.deb"
NOTEPADPP_URL="https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.5.6/npp.8.5.6.Installer.exe"
NOTEPADPP_FILE="$HOME/Downloads/$(basename "$NOTEPADPP_URL")"
WINEPREFIX_DEFAULT="$HOME/.wine"
DESKTOP_DIR="${XDG_DESKTOP_DIR:-$HOME/Desktop}"

# Logging helpers
info(){ echo -e "\e[34m[INFO]\e[0m $*"; }
warn(){ echo -e "\e[33m[WARN]\e[0m $*"; }

# Function to run commands without stopping the script
try() {
  "$@" || warn "الأمر فشل: $*"
}

# Ensure Desktop exists
mkdir -p "$DESKTOP_DIR"

info "إضافة دعم i386"
try sudo dpkg --add-architecture i386

info "تحديث الحزم وتثبيت متطلبات أساسية"
try sudo apt update
try sudo apt install -y --no-install-recommends software-properties-common wget gnupg2 ca-certificates curl apt-transport-https gdebi-core unzip p7zip-full p7zip-rar cabextract

info "إضافة مستودع WineHQ"
try wget -qO- https://dl.winehq.org/wine-builds/winehq.key | sudo apt-key add -
. /etc/os-release
if [ -n "${UBUNTU_CODENAME:-}" ]; then
  echo "deb https://dl.winehq.org/wine-builds/ubuntu/ $UBUNTU_CODENAME main" | sudo tee /etc/apt/sources.list.d/winehq.list
fi
try sudo apt update

info "تثبيت Wine و winetricks"
try sudo apt install -y --install-recommends winehq-stable wine-stable wine64 wine32 winbind winetricks

info "ضبط WINEPREFIX: $WINEPREFIX_DEFAULT"
export WINEPREFIX="${WINEPREFIX:-$WINEPREFIX_DEFAULT}"
mkdir -p "$WINEPREFIX"
try WINEARCH=win64 wineboot -u

info "تنزيل AIO runtimes"
mkdir -p "$HOME/Downloads"
[ -f "$AIO_FILE" ] || try wget -O "$AIO_FILE" "$AIO_URL"

AIO_DESKTOP="$DESKTOP_DIR/AIO-Runtimes.desktop"
cat > "$AIO_DESKTOP" <<EOF
[Desktop Entry]
Name=AIO Runtimes
Exec=env WINEPREFIX="$WINEPREFIX" wine start /unix "$AIO_FILE"
Type=Application
Terminal=false
Icon=applications-wine
EOF
chmod +x "$AIO_DESKTOP"

info "إزالة Google Chrome (لو موجود) وتنصيبه من جديد"
try sudo apt remove -y google-chrome-stable
try wget -O "$CHROME_DEB" "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
try sudo gdebi -n "$CHROME_DEB"

CHROME_DESKTOP="$DESKTOP_DIR/Google-Chrome-NoSandbox.desktop"
cat > "$CHROME_DESKTOP" <<EOF
[Desktop Entry]
Name=Google Chrome (no-sandbox)
Exec=/usr/bin/google-chrome-stable --no-sandbox %U
Terminal=false
Type=Application
Icon=google-chrome
Categories=Network;WebBrowser;
EOF
chmod +x "$CHROME_DESKTOP"

info "تنزيل Telegram Desktop"
try sudo apt install -y telegram-desktop
TELE_DESKTOP="$DESKTOP_DIR/Telegram-Desktop.desktop"
cat > "$TELE_DESKTOP" <<EOF
[Desktop Entry]
Name=Telegram Desktop
Exec=telegram-desktop %u
Icon=telegram
Type=Application
Terminal=false
Categories=Network;InstantMessaging;
EOF
chmod +x "$TELE_DESKTOP"

info "تنزيل Notepad++"
[ -f "$NOTEPADPP_FILE" ] || try wget -O "$NOTEPADPP_FILE" "$NOTEPADPP_URL"
try env WINEPREFIX="$WINEPREFIX" wine "$NOTEPADPP_FILE"

NPP_DESKTOP="$DESKTOP_DIR/Notepad++.desktop"
cat > "$NPP_DESKTOP" <<EOF
[Desktop Entry]
Name=Notepad++
Exec=env WINEPREFIX="$WINEPREFIX" wine "$NOTEPADPP_FILE"
Type=Application
Terminal=false
Icon=text-x-generic
Categories=Utility;TextEditor;
EOF
chmod +x "$NPP_DESKTOP"

info "تثبيت 7zip (نسخة لينكس)"
try sudo apt install -y p7zip-full p7zip-rar

info "السكربت خلص ✅"
echo "شوف الاختصارات على سطح المكتب: $DESKTOP_DIR"
