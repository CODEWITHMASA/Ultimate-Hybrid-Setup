#!/usr/bin/env bash
# setup-for-exe-auto-run.sh
# سكربت شامل: يثبّت wine + runtimes، ينشئ wine-run، يربط exe، ويشغّل أي exe يُنزل تلقائياً من Downloads
# مخصص لـ Debian/Ubuntu-based systems. Designed to continue on errors (best-effort).

set -u

# ---------------- CONFIG ----------------
LOGFILE="$HOME/setup-wine-aio.log"
WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"
DESKTOP_DIR="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
BIN_DIR="$HOME/bin"
BACKUP_DIR="$HOME/wine_backups"
DOWNLOADS="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"
DOWNLOADS="${DOWNLOADS/#\~/$HOME}"
AIO_URL="https://allinoneruntimes.org/files/aio-runtimes_v2.5.0.exe"
AIO_FILE="$DOWNLOADS/$(basename "$AIO_URL")"
CHROME_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
CHROME_DEB="/tmp/google-chrome-stable_current_amd64.deb"
NOTEPADPP_URL="https://github.com/notepad-plus-plus/notepad-plus-plus/releases/download/v8.5.6/npp.8.5.6.Installer.exe"
NOTEPADPP_FILE="$DOWNLOADS/$(basename "$NOTEPADPP_URL")"

# Ensure dirs
mkdir -p "$DOWNLOADS" "$DESKTOP_DIR" "$BIN_DIR" "$BACKUP_DIR" "$(dirname "$LOGFILE")"

# Log everything to file and console
exec > >(tee -a "$LOGFILE") 2>&1

timestamp(){ date +"%Y-%m-%d %H:%M:%S"; }
log(){ echo -e "$(timestamp) [INFO] $*"; }
warn(){ echo -e "$(timestamp) [WARN] $*"; }
err(){ echo -e "$(timestamp) [ERROR] $*"; }

# try wrapper (doesn't exit on failure)
try(){
  log "RUN: $*"
  if "$@"; then
    log "OK: $*"
    return 0
  else
    warn "FAILED: $*"
    return 1
  fi
}

have_internet(){
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 8 https://www.google.com/ >/dev/null 2>&1 && return 0 || return 1
  else
    ping -c1 8.8.8.8 >/dev/null 2>&1 && return 0 || return 1
  fi
}

log "=== بدء تنفيذ setup-for-exe-auto-run.sh ==="

# Use sudo when needed
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
    log "سيتم استخدام sudo عندما يلزم."
  else
    warn "أنت لست root ولا يوجد sudo؛ بعض الأوامر قد تفشل."
  fi
fi

# 1) Basic tools + inotify-tools
log "تحديث apt وتثبيت الأدوات الأساسية (بما في ذلك inotify-tools لمراقبة Downloads)"
try $SUDO apt update -y
try $SUDO apt install -y --no-install-recommends wget curl gnupg2 ca-certificates software-properties-common apt-transport-https gdebi-core p7zip-full unzip cabextract xdg-utils zenity inotify-tools

# 2) enable i386
log "إضافة معماريات i386"
try $SUDO dpkg --add-architecture i386 || true

# 3) Add WineHQ repo (best-effort)
log "إضافة مفتاح ومستودع WineHQ (best-effort)"
try wget -qO- https://dl.winehq.org/wine-builds/winehq.key | $SUDO apt-key add - || warn "فشل إضافة مفتاح WineHQ"
UBU_CODENAME=""
if [ -f /etc/os-release ]; then
  . /etc/os-release
  UBU_CODENAME=${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}
fi
if [ -n "$UBU_CODENAME" ]; then
  try echo "deb https://dl.winehq.org/wine-builds/ubuntu/ $UBU_CODENAME main" | $SUDO tee /etc/apt/sources.list.d/winehq.list >/dev/null
else
  warn "لم أتمكن من تحديد اسم التوزيعة؛ قد تحتاج تضيف مستودع Wine يدوياً."
fi
try $SUDO apt update -y || warn "apt update أعطى تحذير/فشل"

# 4) Install Wine (staging preferred) + winetricks
log "محاولة تثبيت Wine (staging → stable → fallback) و winetricks"
if ! try $SUDO apt install -y --install-recommends winehq-staging wine-staging wine64 wine32 winbind winetricks; then
  if ! try $SUDO apt install -y --install-recommends winehq-stable wine-stable wine64 wine32 winbind winetricks; then
    warn "تعذر تثبيت من WineHQ; أحاول تثبيت الحزم الافتراضية"
    try $SUDO apt install -y wine winetricks wine64 wine32 winbind || warn "فشل تثبيت wine تمامًا"
  fi
fi

if ! command -v wine >/dev/null 2>&1; then
  warn "'wine' غير متوفر بعد التثبيت. قد تحتاج تثبيت wine يدوياً."
fi

# 5) Backup old WINEPREFIX
if [ -d "$WINEPREFIX" ]; then
  BACKUP_FILE="$BACKUP_DIR/wineprefix-$(date +%Y%m%d-%H%M%S).tar.gz"
  log "عمل نسخة احتياطية من WINEPREFIX ($WINEPREFIX) إلى $BACKUP_FILE"
  try tar -czf "$BACKUP_FILE" -C "$(dirname "$WINEPREFIX")" "$(basename "$WINEPREFIX")"
else
  log "لا يوجد WINEPREFIX قديم."
fi

# 6) Initialize WINEPREFIX
log "تهيئة WINEPREFIX: $WINEPREFIX"
try mkdir -p "$WINEPREFIX"
try WINEARCH=win64 WINEPREFIX="$WINEPREFIX" wineboot -u || warn "wineboot فشل أو أعطى تحذير"

# 7) Install common runtimes via winetricks (best-effort)
log "محاولة تثبيت runtimes عبر winetricks (corefonts, vcrun*, dotnet48 محاولة، dxvk...)"
try env WINEPREFIX="$WINEPREFIX" winetricks -q corefonts || warn "corefonts failed"
for v in vcrun2005 vcrun2008 vcrun2010 vcrun2012 vcrun2013 vcrun2015 vcrun2017 vcrun2019; do
  try env WINEPREFIX="$WINEPREFIX" winetricks -q "$v" || warn "winetricks $v failed"
done
# dotnet48 (attempt)
try env WINEPREFIX="$WINEPREFIX" winetricks -q dotnet48 || warn "dotnet48 failed (may need manual steps)"
# DirectX/D3DX9 and dxvk
try env WINEPREFIX="$WINEPREFIX" winetricks -q d3dx9_43 directx9 || warn "directx/d3dx may have failed"
try env WINEPREFIX="$WINEPREFIX" winetricks -q dxvk || warn "dxvk installation failed (ensure Vulkan host drivers)"

# ensure wine-gecko & wine-mono via wineboot
try WINEPREFIX="$WINEPREFIX" wineboot -u || true

# 8) Download AIO runtimes and create desktop shortcut
if have_internet; then
  if [ ! -f "$AIO_FILE" ]; then
    log "تنزيل AIO runtimes إلى $AIO_FILE"
    try wget -O "$AIO_FILE" "$AIO_URL" || warn "فشل تنزيل AIO runtimes"
  else
    log "AIO runtimes موجود بالفعل: $AIO_FILE"
  fi
else
  warn "لا يوجد اتصال إنترنت؛ تخطيت تنزيل AIO runtimes."
fi

AIO_DESKTOP="$DESKTOP_DIR/AIO-Runtimes.desktop"
log "إنشاء اختصار AIO على الديسكتوب: $AIO_DESKTOP"
cat > "$AIO_DESKTOP" <<EOF
[Desktop Entry]
Name=AIO Runtimes (Wine)
Comment=Open aio-runtimes with Wine
Exec=env WINEPREFIX="$WINEPREFIX" wine start /unix "$AIO_FILE"
Type=Application
Terminal=false
Icon=applications-wine
Categories=Utility;
EOF
chmod +x "$AIO_DESKTOP" || warn "تعذر جعل اختصار AIO تنفيذياً"

# 9) Reinstall Google Chrome and create no-sandbox shortcut (warning)
log "إزالة Google Chrome (إن وُجد) ثم تنزيل وتثبيت الإصدار الرسمي"
try $SUDO apt remove -y google-chrome-stable || true
if have_internet; then
  try wget -O "$CHROME_DEB" "$CHROME_URL" || warn "فشل تنزيل Chrome .deb"
  if command -v gdebi >/dev/null 2>&1; then
    try $SUDO gdebi -n "$CHROME_DEB" || try $SUDO dpkg -i "$CHROME_DEB" || try $SUDO apt -f install -y
  else
    try $SUDO dpkg -i "$CHROME_DEB" || try $SUDO apt -f install -y
  fi
else
  warn "لا يوجد إنترنت؛ تخطيت تنزيل Chrome."
fi

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
chmod +x "$CHROME_DESKTOP" || warn "تعذر جعل اختصار Chrome تنفيذياً"
warn "تحذير أمني: تشغيل Chrome مع --no-sandbox غير آمن. استخدمه بحذر."

# 10) Install Telegram Desktop (native) and shortcut
log "تثبيت Telegram Desktop (native) عبر apt إن أمكن"
try $SUDO apt install -y telegram-desktop || warn "تثبيت telegram-desktop فشل عبر apt"
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
chmod +x "$TELE_DESKTOP" || warn "تعذر جعل اختصار Telegram تنفيذياً"

# 11) Notepad++ via Wine (try silent flags then interactive)
log "تنزيل Notepad++ installer إلى $NOTEPADPP_FILE"
if have_internet; then
  [ -f "$NOTEPADPP_FILE" ] || try wget -O "$NOTEPADPP_FILE" "$NOTEPADPP_URL" || warn "فشل تنزيل Notepad++"
else
  warn "لا يوجد إنترنت؛ تخطيت تنزيل Notepad++"
fi

if [ -f "$NOTEPADPP_FILE" ]; then
  log "محاولة تثبيت Notepad++ عبر wine بصمت (best-effort)"
  try env WINEPREFIX="$WINEPREFIX" wine "$NOTEPADPP_FILE" /S || \
  try env WINEPREFIX="$WINEPREFIX" wine "$NOTEPADPP_FILE" /SILENT || \
  try env WINEPREFIX="$WINEPREFIX" wine "$NOTEPADPP_FILE" || warn "Notepad++ installer فشل أو قد يحتاج تفاعل"
else
  warn "ملف Notepad++ غير متاح."
fi

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
chmod +x "$NPP_DESKTOP" || warn "تعذر جعل اختصار Notepad++ تنفيذياً"

# 12) Install native 7zip (p7zip)
log "تثبيت 7zip (p7zip-full)"
try $SUDO apt install -y p7zip-full p7zip-rar || warn "فشل تثبيت p7zip"

# 13) Create wine-run wrapper to run any .exe
WRAPPER="$BIN_DIR/wine-run"
log "إنشاء wrapper لتشغيل أي ملف .exe: $WRAPPER"
cat > "$WRAPPER" <<'EOF'
#!/usr/bin/env bash
# wine-run : run any .exe using configured WINEPREFIX
WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"
export WINEPREFIX

# If no args, open file chooser if zenity exists
if [ $# -eq 0 ]; then
  if command -v zenity >/dev/null 2>&1; then
    FILE="$(zenity --file-selection --title='Select a .exe to run with Wine' --file-filter='*.exe')"
    [ -n "$FILE" ] || exit 0
    exec env WINEPREFIX="$WINEPREFIX" wine start /unix "$FILE"
  else
    echo "Usage: wine-run /path/to/file.exe"
    exit 1
  fi
else
  for f in "$@"; do
    f_expanded="${f/#\~/$HOME}"
    if [ -f "$f_expanded" ]; then
      echo "Running with Wine: $f_expanded"
      env WINEPREFIX="$WINEPREFIX" wine start /unix "$f_expanded" >/dev/null 2>&1 &
      sleep 0.2
    else
      echo "File not found: $f_expanded"
    fi
  done
fi
EOF
chmod +x "$WRAPPER" || warn "تعذر جعل wrapper تنفيذياً"

# 14) Create desktop entry "Open with Wine" and register .exe mime association
APP_DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$APP_DESKTOP_DIR"
OPEN_WINE_DESKTOP="$APP_DESKTOP_DIR/open-with-wine.desktop"
log "إنشاء Desktop Entry لربط امتدادات .exe: $OPEN_WINE_DESKTOP"
cat > "$OPEN_WINE_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Open with Wine
Exec=$WRAPPER %f
Icon=applications-wine
MimeType=application/x-ms-dos-executable;application/x-msdos-program;application/x-executable;
NoDisplay=false
Categories=Utility;
EOF
chmod +x "$OPEN_WINE_DESKTOP" || warn "تعذر جعل open-with-wine.desktop تنفيذياً"

log "تحديث desktop database و محاولة تعيين الإفتتاح الافتراضي لملفات exe"
try update-desktop-database "$APP_DESKTOP_DIR" || warn "update-desktop-database غير متاح"
try xdg-mime default open-with-wine.desktop application/x-ms-dos-executable || warn "xdg-mime failed for application/x-ms-dos-executable"
try xdg-mime default open-with-wine.desktop application/x-msdos-program || warn "xdg-mime failed for application/x-msdos-program"
try xdg-mime default open-with-wine.desktop application/x-executable || warn "xdg-mime failed for application/x-executable"
try cp "$OPEN_WINE_DESKTOP" "$DESKTOP_DIR/Open with Wine.desktop" || warn "تعذر نسخ .desktop إلى الديسكتوب"

# 15) Create watcher script to auto-run new .exe files in Downloads
WATCHER="$BIN_DIR/wine-exe-watcher.sh"
log "إنشاء سكربت المراقبة: $WATCHER (يشغل أي .exe ينزل إلى $DOWNLOADS تلقائياً)"
cat > "$WATCHER" <<'EOF'
#!/usr/bin/env bash
# wine-exe-watcher.sh
# يراقب مجلد Downloads لأي ملفات .exe جديدة ويشغّلها عبر wine-run
DOWNLOADS_DIR="${DOWNLOADS_DIR:-$HOME/Downloads}"
WRAPPER_PATH="${WRAPPER_PATH:-$HOME/bin/wine-run}"
DESKTOP_DIR="${DESKTOP_DIR:-$HOME/Desktop}"

# ensure inotifywait is available
if ! command -v inotifywait >/dev/null 2>&1; then
  echo "inotifywait not found; please install inotify-tools"
  exit 1
fi

# function to create desktop shortcut for the exe
create_shortcut(){
  exe="$1"
  base="$(basename "$exe")"
  name="${base%.*}"
  desktopfile="$DESKTOP_DIR/${name}_Wine.desktop"
  cat > "$desktopfile" <<EOD
[Desktop Entry]
Name=${name} (Wine)
Exec=${WRAPPER_PATH} "${exe}"
Terminal=false
Type=Application
Icon=applications-wine
Categories=Utility;
EOD
  chmod +x "$desktopfile" 2>/dev/null || true
  echo "Created desktop shortcut: $desktopfile"
}

echo "Watching $DOWNLOADS_DIR for new .exe files..."
# watch for CLOSE_WRITE (finished downloads) and MOVED_TO events
inotifywait -m -e close_write -e moved_to --format '%w%f' "$DOWNLOADS_DIR" | while read -r FILE; do
  # only process .exe (case-insensitive)
  case "${FILE,,}" in
    *.exe)
      echo "Detected EXE: $FILE"
      # small delay to ensure download finished fully
      sleep 0.5
      # make executable bit (not required but useful)
      chmod +x "$FILE" 2>/dev/null || true
      # create shortcut
      create_shortcut "$FILE"
      # run with wine-run
      if [ -x "$WRAPPER_PATH" ]; then
        echo "Launching with wine-run: $FILE"
        "$WRAPPER_PATH" "$FILE" &
      else
        echo "wine-run wrapper not found at $WRAPPER_PATH"
      fi
      ;;
    *) ;;
  esac
done
EOF

# Replace placeholders with actual values
sed -i "s|\${DOWNLOADS_DIR:-\$HOME/Downloads}|$DOWNLOADS|g" "$WATCHER"
sed -i "s|\${WRAPPER_PATH:-\$HOME/bin/wine-run}|$WRAPPER|g" "$WATCHER"
sed -i "s|\${DESKTOP_DIR:-\$HOME/Desktop}|$DESKTOP_DIR|g" "$WATCHER"

chmod +x "$WATCHER" || warn "تعذر جعل watcher تنفيذياً"

# 16) Install watcher as systemd --user service if possible, else run via nohup
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_NAME="wine-exe-watcher.service"
SERVICE_PATH="$SYSTEMD_USER_DIR/$SERVICE_NAME"
TIMER_NAME="wine-exe-watcher.path"  # not using path unit; we'll use simple service
if command -v systemctl >/dev/null 2>&1 && systemctl --user >/dev/null 2>&1; then
  log "إعداد systemd --user service لتشغيل المراقب تلقائياً عند تسجيل الدخول (best-effort)"
  mkdir -p "$SYSTEMD_USER_DIR"
  cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=Wine EXE Watcher (auto-run .exe in Downloads)

[Service]
Type=simple
ExecStart=$WATCHER
Restart=always
RestartSec=5

[Install]
WantedBy=default.target
EOF
  chmod 644 "$SERVICE_PATH"
  # Reload user daemon and enable+start
  try systemctl --user daemon-reload
  try systemctl --user enable --now "$SERVICE_NAME" || warn "تعذر تفعيل أو تشغيل خدمة systemd-user (قد تحتاج جلسة systemd-user)"
else
  warn "systemd --user غير متاح؛ سأشغّل watcher في الخلفية عبر nohup (سيعمل خلال الجلسة الحالية فقط)."
  # start watcher in background via nohup
  try nohup "$WATCHER" >/dev/null 2>&1 &
fi

# 17) Final summary
log "=== انتهى السكربت: ملخص سريع ==="
log "WINEPREFIX: $WINEPREFIX"
log "Wrapper: $WRAPPER"
log "Watcher: $WATCHER"
log "Downloads monitored: $DOWNLOADS"
log "Desktop shortcuts تُنشأ تلقائياً عند تنزيل .exe"
log "Logs: $LOGFILE"
warn "ملاحظة أخيرة: المراقب سيشغّل أي .exe جديد في $DOWNLOADS تلقائياً. إذا لم يعمل ملف معين، شوف $LOGFILE وبلغني باسم الملف والمخرجات."

echo
log "لو عايز أضيف: تجاهل بعض الملفات (مثلاً ملفات التحديث المؤقتة .part) أو تأخير أطول قبل التشغيل أو قاعدة فلاتر أكثر تعقيداً — أعدّل السكربت لك فورًا."
