#!/usr/bin/env bash
# setup-wine-aio.sh
# سكربت لإعداد Wine + تنزيل AIO runtimes و Chrome (مع --no-sandbox) و Telegram و Notepad++ و 7zip
# موجه لأنظمة Debian/Ubuntu (اختبره أولاً في VM إذا أمكن)
set -euo pipefail

# --- CONFIG ---
AIO_URL="https://allinoneruntimes.org/files/aio-runtimes_v2.5.0.exe"
AIO_FILE="$HOME/Downloads/$(basename "$AIO_URL")"
CHROME_DEB="/tmp/google-chrome-stable_current_amd64.deb"
NOTEPADPP_URL="https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.5.6/npp.8.5.6.Installer.exe"
NOTEPADPP_FILE="$HOME/Downloads/$(basename "$NOTEPADPP_URL")"
WINEPREFIX_DEFAULT="$HOME/.wine"
DESKTOP_DIR="${XDG_DESKTOP_DIR:-$HOME/Desktop}"

# Helper for logging
info(){ echo -e "\e[34m[INFO]\e[0m $*"; }
warn(){ echo -e "\e[33m[WARN]\e[0m $*"; }
err(){ echo -e "\e[31m[ERROR]\e[0m $*"; exit 1; }

if [ "$(id -u)" -ne 0 ]; then
  warn "يُفضّل تشغيل هذا السكربت بصلاحيات root (sudo). سأستمر لكن قد يُطلب منك sudo أثناء التشغيل."
fi

# Detect apt-based
if ! command -v apt >/dev/null 2>&1; then
  err "هذا السكربت مخصّص لـ Debian/Ubuntu-based systems (يستخدم apt)."
fi

# Ensure Desktop exists
mkdir -p "$DESKTOP_DIR"

info "إضافة دعم المعمارية i386"
dpkg --add-architecture i386 || true

info "تحديث الحزم الأساسية وتثبيت متطلبات"
apt update
apt install -y --no-install-recommends software-properties-common wget gnupg2 ca-certificates curl apt-transport-https gdebi-core unzip p7zip-full p7zip-rar cabextract

# --- Add WineHQ repo ---
info "إضافة مستودع WineHQ"
wget -qO- https://dl.winehq.org/wine-builds/winehq.key | apt-key add - || true
# Add repository for Ubuntu releases (uses generic ubuntu codename)
. /etc/os-release
if [ -z "${UBUNTU_CODENAME:-}" ]; then
  # fallback: try lsb_release
  UBUNTU_CODENAME=$(lsb_release -sc 2>/dev/null || echo "")
fi
if [ -z "$UBUNTU_CODENAME" ]; then
  warn "لم أتمكن من تحديد معرف التوزيعة تلقائيًا — سأواصل لكن قد يفشل إضافة repo."
else
  echo "deb https://dl.winehq.org/wine-builds/ubuntu/ $UBUNTU_CODENAME main" > /etc/apt/sources.list.d/winehq.list
fi

apt update || true

info "تثبيت Wine (stable) و wine32 و winetricks"
# try to install winehq-stable, otherwise winehq-devel, otherwise fallback to wine
apt install -y --install-recommends winehq-stable wine-stable wine64 wine32 winbind winetricks || \
apt install -y --install-recommends winehq-devel wine-devel wine64 wine32 winbind winetricks || \
apt install -y wine winetricks wine64 wine32 || err "فشل تثبيت Wine. افحص المخرجات أعلاه."

info "ضبط WINEPREFIX (افتراضي: $WINEPREFIX_DEFAULT) وإنشاء prefix أولي"
export WINEPREFIX="${WINEPREFIX:-$WINEPREFIX_DEFAULT}"
mkdir -p "$WINEPREFIX"
# initialize prefix (this may download gecko/mono)
WINEARCH=win64 wineboot -u || true

# Install common runtimes using winetricks (non-interactive)
info "تثبيت حزم Windows runtime شائعة عبر winetricks (corefonts, vcrun2015, vcrun2019)..."
export WINETRICKS_QUIET=1
winetricks -q corefonts vcrun2015 vcrun2019 || warn "winetricks فشل في بعض الحزم — قد تحتاج تنفيذها يدوياً."

# --- Download AIO Runtimes EXE ---
info "تنزيل AIO Runtimes: $AIO_URL"
mkdir -p "$HOME/Downloads"
if [ ! -f "$AIO_FILE" ]; then
  wget -O "$AIO_FILE" "$AIO_URL" || warn "فشل تنزيل AIO runtimes — تأكد من الاتصال أو الرابط."
else
  info "AIO runtimes موجود بالفعل في $AIO_FILE"
fi

# Create desktop shortcut to open the AIO EXE with wine
AIO_DESKTOP="$DESKTOP_DIR/AIO-Runtimes.desktop"
info "إنشاء اختصار على الديسكتوب لفتح AIO runtimes عبر wine: $AIO_DESKTOP"
cat > "$AIO_DESKTOP" <<EOF
[Desktop Entry]
Name=AIO Runtimes (open with Wine)
Comment=Open aio-runtimes with Wine
Exec=env WINEPREFIX="$WINEPREFIX" wine start /unix "$AIO_FILE"
Type=Application
Terminal=false
Icon=applications-wine
Categories=Utility;
EOF
chmod +x "$AIO_DESKTOP"

# --- Reinstall Google Chrome and create desktop shortcut without sandbox ---
info "إزالة Google Chrome (إن وُجد)"
apt remove -y google-chrome-stable || true
rm -f "$CHROME_DEB"

info "تنزيل أحدث Google Chrome (.deb) وتثبيته"
# official google chrome stable .deb URL
CHROME_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
wget -O "$CHROME_DEB" "$CHROME_URL" || warn "فشل تنزيل Chrome .deb — قد تكون المشكلة في الشبكة."
gdebi -n "$CHROME_DEB" || dpkg -i "$CHROME_DEB" || apt -f install -y

# Create desktop shortcut that launches Chrome without sandbox (WARNING)
CHROME_DESKTOP="$DESKTOP_DIR/Google-Chrome-NoSandbox.desktop"
info "إنشاء اختصار Chrome على الديسكتوب مع --no-sandbox (غير آمن)."
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

warn "تنبيه أمني: تشغيل Google Chrome مع --no-sandbox يعطل آليات الأمان الأساسية ويجعل المتصفح عرضة للاستغلال. لا تقم بذلك إلا إذا كنت تفهم المخاطر."

# --- Install Telegram Desktop (native if available) ---
info "تثبيت Telegram Desktop (native) إن أمكن"
apt install -y telegram-desktop || warn "قد لا يكون telegram-desktop متوفرًا عبر apt على هذه النسخة — يمكنك تثبيته يدوياً من الموقع الرسمي أو من snap/flatpak."

# Create desktop shortcut (system will usually already have one), but ensure one exists
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

# --- Notepad++ (Windows) via Wine ---
info "تنزيل وتثبيت Notepad++ عبر Wine (إذا لم يكن موجودًا)"
if [ ! -f "$NOTEPADPP_FILE" ]; then
  wget -O "$NOTEPADPP_FILE" "$NOTEPADPP_URL" || warn "فشل تنزيل Notepad++ installer."
fi

info "تشغيل مثبت Notepad++ باستخدام wine (سيظهر واجهة التثبيت، قد يطلب تفاعلاً)"
env WINEPREFIX="$WINEPREFIX" wine "$NOTEPADPP_FILE" || warn "قد يفشل تشغيل مثبت Notepad++ عبر wine أو يتطلب تفاعل."

# Create a desktop link that launches the Notepad++ installer via wine (كما طلبت اختصار لفتحه بـ wine)
NPP_DESKTOP="$DESKTOP_DIR/Notepad++ (installer).desktop"
cat > "$NPP_DESKTOP" <<EOF
[Desktop Entry]
Name=Notepad++ (open installer with Wine)
Exec=env WINEPREFIX="$WINEPREFIX" wine "$NOTEPADPP_FILE"
Type=Application
Terminal=false
Icon=text-x-generic
Categories=Utility;TextEditor;
EOF
chmod +x "$NPP_DESKTOP"

# --- 7zip (p7zip) installation (native) ---
info "تثبيت 7zip (p7zip-full)"
apt install -y p7zip-full p7zip-rar || warn "فشل تثبيت p7zip via apt."

# Optionally download 7-Zip Windows portable (if user wants Windows version under wine)
# You can uncomment below if you want the Windows 7-Zip:
# wget -O "$HOME/Downloads/7z2201-x64.exe" "https://www.7-zip.org/a/7z2201-x64.exe"

info "اكتملت معظم الخطوات. بعض مثبتات Windows (مثل Notepad++ أو AIO runtimes) تتطلّب تفاعل أثناء التثبيت؛ السكربت شغّل المثبّتات عبر wine لكن لا يمكن إتمام تثبيت GUI تلقائيًا بالكامل هنا."

echo
info "ملاحظات أخيرة:"
echo "- ملف AIO runtimes موجود في: $AIO_FILE"
echo "- اختصارات على الديسكتوب:"
ls -1 "$DESKTOP_DIR" | grep -E "AIO-Runtimes|Google-Chrome-NoSandbox|Telegram-Desktop|Notepad\+\+" || true
echo
info "إذا أردت أضيف خطوات تلقائية لتثبيت التطبيقات داخل wine (مثلاً تثبيت Notepad++ تلقائيًا أو تثبيت dotnet محدد عبر winetricks)، أخبرني وسأحدّث السكربت لعمل ذلك (مع تحذيرات حول الوقت والمساحة والاعتماديات)."
