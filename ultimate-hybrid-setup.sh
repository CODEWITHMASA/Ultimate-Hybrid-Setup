#!/usr/bin/env bash
# MASA EXE Complete Installer & Launcher
# Author: MASA (CODE WITH MASA)
# Purpose: make Windows .exe run on Debian/Ubuntu automatically + GUI + snapshots + Proton-GE + Bottles + watcher service
# Socials: https://t.me/MrMasaOfficial  (opens at end)
# Log: ~/masa-exe-complete.log

set -u
USER_NAME="$(whoami)"
HOME_DIR="$HOME"
LOGFILE="$HOME_DIR/masa-exe-complete.log"
DESKTOP_DIR="${XDG_DESKTOP_DIR:-$HOME_DIR/Desktop}"
DB_DIR="$HOME_DIR/.local/share/masa-wine"
DB_FILE="$DB_DIR/apps.db"           # format: name|exe_path|desktop_path|prefix|sandbox
SNAP_DIR="$HOME_DIR/masa-wine-snapshots"
BIN_DIR="$HOME_DIR/bin"
DOWNLOADS_DIR="${XDG_DOWNLOAD_DIR:-$HOME_DIR/Downloads}"
MAIN_SCRIPT_PATH="$HOME_DIR/masa-exe-complete.sh"  # if saved there
PROTONUP_CMD="$HOME_DIR/.local/bin/protonup"      # pipx/pip user installs may put bin here
BOTTLES_FLATPAK_ID="com.usebottles.bottles"
TELEGRAM_LINK="https://t.me/MrMasaOfficial"
AIO_URL="https://allinoneruntimes.org/files/aio-runtimes_v2.5.0.exe"
AIO_FILE="$DOWNLOADS_DIR/$(basename "$AIO_URL")"
CHROME_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
CHROME_DEB="/tmp/google-chrome-stable_current_amd64.deb"
NOTEPADPP_URL="https://github.com/notepad-plus-plus/notepad-plus-plus/releases/latest/download/npp.8.5.6.Installer.exe"
NOTEPADPP_FILE="$DOWNLOADS_DIR/$(basename "$NOTEPADPP_URL")"

# Socials/branding
APP_TITLE="CODE WITH MASA"
AUTHOR="MASA"
SOCIALS=(
 "Telegram: https://t.me/MrMasaOfficial"
 "Telegram Page: https://t.me/CODEWITHMASA"
 "Telegram Active: https://t.me/+_R91sWmKBacyZTc0"
 "Group: https://t.me/GROUPCODEWITHMASA"
 "Facebook: https://www.facebook.com/CODEWITHMASA"
 "Instagram: https://www.instagram.com/codewithmasa"
 "TikTok: https://www.tiktok.com/@CODEWITHMASA"
 "YouTube: https://www.youtube.com/@CODEWITHMASA"
 "Github: https://github.com/CODEWITHMASA"
 "X: https://x.com/CODEWITHMASA"
 "Website: https://codewithmasa.blogspot.com/"
)

# Make necessary dirs
mkdir -p "$DESKTOP_DIR" "$DB_DIR" "$SNAP_DIR" "$BIN_DIR" "$DOWNLOADS_DIR"
touch "$DB_FILE"
touch "$LOGFILE"

# Logging helpers
timestamp(){ date +"%Y-%m-%d %H:%M:%S"; }
log(){ echo "$(timestamp) [INFO] $*" | tee -a "$LOGFILE"; }
warn(){ echo "$(timestamp) [WARN] $*" | tee -a "$LOGFILE"; }
err(){ echo "$(timestamp) [ERROR] $*" | tee -a "$LOGFILE"; }

# Wrapper that runs commands, logs stderr to logfile, never exits script on failure
try_cmd(){
  log "RUN: $*"
  if "$@" >>"$LOGFILE" 2>&1; then
    log "OK: $*"
    return 0
  else
    warn "FAILED: $*  (see $LOGFILE)"
    return 1
  fi
}

# GUI helpers (zenity)
have_zenity(){ command -v zenity >/dev/null 2>&1; }
zen_info(){ if have_zenity; then zenity --info --title="$APP_TITLE" --text="$1"; else log "$1"; fi }
zen_error(){ if have_zenity; then zenity --error --title="$APP_TITLE - Error" --text="$1"; else err "$1"; fi }
zen_question(){ if have_zenity; then zenity --question --title="$APP_TITLE" --text="$1"; return $?; else return 0; fi }
zen_list(){ if have_zenity; then zenity --list --title="$APP_TITLE" --text="$2" --column=Pick --column=Action "$@" ; else echo "$@"; fi }

# Start UI: show branding
display_branding(){
  BRAND_TEXT="Welcome to $APP_TITLE (by $AUTHOR)\n\n"
  for s in "${SOCIALS[@]}"; do BRAND_TEXT+="$s\n"; done
  BRAND_TEXT+="\nThis tool will prepare your system to run Windows .exe files automatically.\nLogs: $LOGFILE"
  if have_zenity; then
    zenity --info --title="$APP_TITLE" --text="$BRAND_TEXT" --width=700 --height=450
  else
    log "$BRAND_TEXT"
  fi
}

# Ensure sudo is available for system installs
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    zen_error "This installer needs sudo to install system packages. Install sudo or run as root."
    exit 1
  fi
fi

display_branding

# 1) Install system dependencies (apt), flatpak, pip3 if missing — best-effort
log "Installing system dependencies (apt) — this may take some time..."
try_cmd $SUDO dpkg --add-architecture i386 || true
try_cmd $SUDO apt update -y
try_cmd $SUDO apt install -y --no-install-recommends wget curl gnupg2 ca-certificates software-properties-common apt-transport-https gdebi-core p7zip-full unzip cabextract xdg-utils zenity inotify-tools python3-pip flatpak || warn "Some apt installs failed; continuing"

# 2) Enable flathub and install Bottles via flatpak (best-effort)
if command -v flatpak >/dev/null 2>&1; then
  if ! flatpak remote-list | grep -q "^flathub"; then
    try_cmd flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo || warn "Failed to add flathub"
  fi
  log "Installing Bottles (flatpak) — recommended"
  try_cmd flatpak install -y flathub $BOTTLES_FLATPAK_ID || warn "Bottles installation via flatpak failed"
else
  warn "Flatpak not available; Bottles not installed."
fi

# 3) Add WineHQ repo (best-effort) and install Wine (staging->stable->fallback)
log "Adding WineHQ repo (best-effort)"
try_cmd wget -qO- https://dl.winehq.org/wine-builds/winehq.key | $SUDO apt-key add - || warn "Could not add WineHQ key"
if [ -f /etc/os-release ]; then
  . /etc/os-release
  CODENAME=${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}
else
  CODENAME=""
fi
if [ -n "$CODENAME" ]; then
  try_cmd echo "deb https://dl.winehq.org/wine-builds/ubuntu/ $CODENAME main" | $SUDO tee /etc/apt/sources.list.d/winehq.list >/dev/null || warn "Failed to write wine repo"
fi
try_cmd $SUDO apt update -y || warn "apt update had issues"

log "Installing Wine (staging preferred)"
if ! try_cmd $SUDO apt install -y --install-recommends winehq-staging wine-staging wine64 wine32 winbind winetricks; then
  if ! try_cmd $SUDO apt install -y --install-recommends winehq-stable wine-stable wine64 wine32 winbind winetricks; then
    warn "WineHQ installs failed; trying distribution wine packages"
    try_cmd $SUDO apt install -y wine winetricks wine64 wine32 winbind || warn "All wine installs failed; continue anyway (Bottles or Proton-GE may provide runtime)"
  fi
fi

# 4) Ensure wine exists (best-effort)
if ! command -v wine >/dev/null 2>&1; then
  warn "wine command not found — some functionality will rely on Bottles or Proton-GE"
fi

# 5) Install winetricks runtime defaults (best-effort)
log "Installing common winetricks runtimes (best-effort)"
if command -v winetricks >/dev/null 2>&1; then
  try_cmd env WINEPREFIX="$HOME_DIR/.wine" winetricks -q corefonts vcrun2015 vcrun2019 || warn "winetricks partial failure"
  try_cmd env WINEPREFIX="$HOME_DIR/.wine" winetricks -q d3dx9_43 directx9 || warn "directx/d3dx issue"
  # dotnet48 may be fragile; try but continue if fails
  try_cmd env WINEPREFIX="$HOME_DIR/.wine" winetricks -q dotnet48 || warn "dotnet48 install failed (may require manual steps)"
else
  warn "winetricks not found; skipping some runtime installs"
fi

# 6) Install or show ProtonUp command instructions (user-friendly)
log "Installing protonup (user-local) for Proton-GE / Wine-GE management (best-effort)"
if command -v pip3 >/dev/null 2>&1; then
  try_cmd pip3 install --user protonup || warn "pip install protonup failed; you can install ProtonUp-Qt GUI manually"
else
  warn "pip3 not found; cannot install protonup automatically"
fi
PROTON_INSTALL_HELP="To install Proton-GE or Wine-GE manually, run (one of the options):\n\n1) Using pip (already attempted):\n   pip3 install --user protonup\n   ~/.local/bin/protonup -i GE-Proton\n\n2) Using pipx (recommended for system cleanliness):\n   python3 -m pip install --user pipx\n   python3 -m pipx ensurepath\n   pipx install protonup\n   pipx run protonup -i GE-Proton\n\n3) Use ProtonUp-Qt AppImage (GUI): https://github.com/ProtonUp/protonup-qt"

log "$PROTON_INSTALL_HELP"

# 7) Install Bottles CLI or instruct user where Bottles is (if flatpak installed)
if command -v flatpak >/dev/null 2>&1 && flatpak list | grep -q "$BOTTLES_FLATPAK_ID"; then
  log "Bottles installed via flatpak; you can open Bottles GUI from your applications menu."
else
  warn "Bottles not installed via flatpak (or flatpak not available). Bottles recommended but optional."
fi

# 8) Download aio-runtimes exe and create desktop shortcut to open with wine
log "Downloading AIO Runtimes (.exe) to Downloads (best-effort)"
if [ ! -f "$AIO_FILE" ]; then
  if try_cmd wget -O "$AIO_FILE" "$AIO_URL"; then
    log "AIO downloaded: $AIO_FILE"
  else
    warn "Failed to download AIO runtimes"
  fi
else
  log "AIO already present: $AIO_FILE"
fi

AIO_DESKTOP="$DESKTOP_DIR/AIO-Runtimes.desktop"
cat > "$AIO_DESKTOP" <<EOF
[Desktop Entry]
Name=AIO Runtimes (Open with Wine)
Comment=Open AIO Runtimes installer with Wine
Exec=env WINEPREFIX="$HOME_DIR/.wine" wine start /unix "$AIO_FILE"
Type=Application
Terminal=false
Icon=applications-wine
Categories=Utility;
EOF
chmod +x "$AIO_DESKTOP" || true

# 9) Reinstall Google Chrome (download .deb) and create no-sandbox shortcut
log "Installing Google Chrome (stable) and creating no-sandbox shortcut (WARNING: insecure)"
try_cmd $SUDO apt remove -y google-chrome-stable || true
if try_cmd wget -O "$CHROME_DEB" "$CHROME_URL"; then
  try_cmd $SUDO gdebi -n "$CHROME_DEB" || try_cmd $SUDO dpkg -i "$CHROME_DEB" || try_cmd $SUDO apt -f install -y
else
  warn "Failed to download Chrome .deb"
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
chmod +x "$CHROME_DESKTOP" || true

# 10) Install Telegram Desktop (native) & create desktop shortcut
log "Installing Telegram Desktop (native if available)"
try_cmd $SUDO apt install -y telegram-desktop || warn "telegram-desktop apt install failed"
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
chmod +x "$TELE_DESKTOP" || true

# 11) Notepad++ via Wine (download installer and run under wine as best-effort)
log "Downloading Notepad++ installer and attempt to run via Wine (best-effort)"
if [ ! -f "$NOTEPADPP_FILE" ]; then
  try_cmd wget -O "$NOTEPADPP_FILE" "$NOTEPADPP_URL" || warn "Failed to download Notepad++ installer"
fi
if [ -f "$NOTEPADPP_FILE" ]; then
  # try silent flags then fallback to interactive
  try_cmd env WINEPREFIX="$HOME_DIR/.wine" wine "$NOTEPADPP_FILE" /S || \
    try_cmd env WINEPREFIX="$HOME_DIR/.wine" wine "$NOTEPADPP_FILE" || warn "Notepad++ installer via wine failed or may require manual GUI interaction"
fi
NPP_DESKTOP="$DESKTOP_DIR/Notepad++.desktop"
cat > "$NPP_DESKTOP" <<EOF
[Desktop Entry]
Name=Notepad++
Exec=env WINEPREFIX="$HOME_DIR/.wine" wine "$NOTEPADPP_FILE"
Terminal=false
Type=Application
Icon=text-x-generic
Categories=Utility;TextEditor;
EOF
chmod +x "$NPP_DESKTOP" || true

# 12) Install 7zip (native)
log "Installing native 7zip (p7zip-full)"
try_cmd $SUDO apt install -y p7zip-full p7zip-rar || warn "p7zip install failed"

# 13) Create global wine-run wrapper to run any .exe easily
WRAPPER="$BIN_DIR/wine-run"
log "Creating wine-run wrapper: $WRAPPER"
cat > "$WRAPPER" <<'EOF'
#!/usr/bin/env bash
WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"
export WINEPREFIX
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
      env WINEPREFIX="$WINEPREFIX" wine start /unix "$f_expanded" >/dev/null 2>&1 &
      sleep 0.2
    else
      echo "File not found: $f_expanded"
    fi
  done
fi
EOF
chmod +x "$WRAPPER" || true

# 14) Create "Open with Wine (MASA)" desktop entry used to handle double-click .exe
OPEN_WINE_DESKTOP="$DB_DIR/open-with-wine-masa.desktop"
cat > "$OPEN_WINE_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Name=Open with Wine (MASA)
Exec=$MAIN_SCRIPT_PATH %f
Icon=applications-wine
MimeType=application/x-ms-dos-executable;application/x-msdos-program;application/x-executable;
NoDisplay=false
Categories=Utility;
EOF
chmod +x "$OPEN_WINE_DESKTOP" || true
cp -f "$OPEN_WINE_DESKTOP" "$HOME_DIR/.local/share/applications/" 2>/dev/null || true
try_cmd update-desktop-database "$HOME_DIR/.local/share/applications" || true

# Set xdg-mime defaults (best-effort)
try_cmd xdg-mime default "$(basename "$OPEN_WINE_DESKTOP")" application/x-ms-dos-executable || warn "xdg-mime set failed (app .desktop)"
try_cmd xdg-mime default "$(basename "$OPEN_WINE_DESKTOP")" application/x-msdos-program || warn "xdg-mime set failed"
try_cmd xdg-mime default "$(basename "$OPEN_WINE_DESKTOP")" application/x-executable || warn "xdg-mime set failed"

# 15) DB utilities
db_add(){
  local name="$1"; local exe="$2"; local desktop="$3"; local prefix="$4"; local sandbox="$5"
  echo "${name}|${exe}|${desktop}|${prefix}|${sandbox}" >> "$DB_FILE"
  log "DB add: $name | $exe | $desktop | $prefix | $sandbox"
}
db_list(){
  awk -F'|' '{print NR":"$1":"$2":"$4":"$5}' "$DB_FILE"
}

# 16) Snapshot helpers
snapshot_prefix(){
  local prefix="$1"
  if [ -d "$prefix" ]; then
    local snap="$SNAP_DIR/$(basename "$prefix")-snapshot-$(date +%Y%m%d-%H%M%S).tar.gz"
    try_cmd tar -czf "$snap" -C "$(dirname "$prefix")" "$(basename "$prefix")" && log "Snapshot created: $snap"
  else
    warn "Prefix not found for snapshot: $prefix"
  fi
}
list_snapshots(){ ls -1 "$SNAP_DIR" 2>/dev/null || true; }
restore_snapshot(){
  local snap="$1"
  if [ -f "$SNAP_DIR/$snap" ]; then
    # Extract into parent of prefix (best-effort)
    try_cmd tar -xzf "$SNAP_DIR/$snap" -C "$HOME_DIR" && log "Restored snapshot: $snap" || warn "Restore failed for $snap"
  else
    warn "Snapshot file not found: $snap"
  fi
}

# 17) Handle a double-clicked .exe (script invoked with a file path)
handle_opened_exe(){
  local file="$1"
  # strip file:// if present
  file="${file#file://}"
  file="${file/#\~/$HOME_DIR}"
  log "User opened: $file"
  if [ ! -f "$file" ]; then
    zen_error "File not found: $file"
    return 1
  fi

  # Build program name:
  pname="$(basename "$file")"
  pname="${pname%.*}"

  # Show choices to user (Zenity). Default to Run if zenity missing.
  if have_zenity; then
    CHOICE=$(zenity --list --title="$APP_TITLE - Open EXE" --text="What do you want to do with:\n$pname" --radiolist --column Pick --column Action TRUE "Run now (base prefix)" FALSE "Install & create shortcut (new prefix)" FALSE "Run in sandbox (isolate)" --width=600 --height=300) || CHOICE="Run now (base prefix)"
  else
    CHOICE="Run now (base prefix)"
  fi

  case "$CHOICE" in
    "Install & create shortcut (new prefix)")
      # prompt app name
      if have_zenity; then
        APPNAME=$(zenity --entry --title="Install $pname" --text="Application name for shortcuts:" --entry-text="$pname") || APPNAME="$pname"
      else
        APPNAME="$pname"
      fi
      # create prefix
      PREFIX="$HOME_DIR/.wine-prefixes/${APPNAME// /_}"
      mkdir -p "$PREFIX"
      snapshot_prefix "$PREFIX"   # snapshot before install
      try_cmd WINEARCH=win64 WINEPREFIX="$PREFIX" wineboot -u || warn "wineboot new prefix may have issues"
      try_cmd env WINEPREFIX="$PREFIX" wine "$file" || warn "Running installer for $APPNAME may have failed"
      # create desktop entry
      DESKTOP_PATH="$DESKTOP_DIR/${APPNAME}.desktop"
      cat > "$DESKTOP_PATH" <<EOF
[Desktop Entry]
Name=$APPNAME
Exec=env WINEPREFIX="$PREFIX" wine start /unix "$file"
Terminal=false
Type=Application
Icon=applications-wine
Categories=Utility;
EOF
      chmod +x "$DESKTOP_PATH" || true
      db_add "$APPNAME" "$file" "$DESKTOP_PATH" "$PREFIX" "no"
      zen_info "Installed $APPNAME (shortcut created on Desktop)."
      ;;
    "Run in sandbox (isolate)")
      # create sandbox prefix and run with firejail or bubblewrap if available
      PREFIX="$HOME_DIR/.wine-sandbox/$(basename "$file" .exe)-$(date +%s)"
      mkdir -p "$PREFIX"
      snapshot_prefix "$PREFIX"
      try_cmd WINEARCH=win64 WINEPREFIX="$PREFIX" wineboot -u || warn "wineboot sandbox prefix may have issues"
      if command -v firejail >/dev/null 2>&1; then
        try_cmd firejail --quiet --private="$PREFIX" env WINEPREFIX="$PREFIX" wine start /unix "$file" || warn "firejail run failed, fallback to normal wine"
      elif command -v bwrap >/dev/null 2>&1; then
        try_cmd bwrap --unshare-all --new-session --bind "$PREFIX" "$PREFIX" --dev /dev --proc /proc env WINEPREFIX="$PREFIX" wine start /unix "$file" || warn "bubblewrap run failed, fallback"
      else
        warn "No sandbox available; running plain wine"
        try_cmd env WINEPREFIX="$PREFIX" wine start /unix "$file" || warn "wine run failed"
      fi
      # create shortcut entry
      DESKTOP_PATH="$DESKTOP_DIR/${pname}-sandbox.desktop"
      cat > "$DESKTOP_PATH" <<EOF
[Desktop Entry]
Name=${pname} (sandbox)
Exec=env WINEPREFIX="$PREFIX" wine start /unix "$file"
Terminal=false
Type=Application
Icon=applications-wine
Categories=Utility;
EOF
      chmod +x "$DESKTOP_PATH" || true
      db_add "${pname}-sandbox" "$file" "$DESKTOP_PATH" "$PREFIX" "yes"
      zen_info "Running $pname in sandbox. Shortcut created on Desktop."
      ;;
    *)
      # Run now using base prefix
      try_cmd env WINEPREFIX="$HOME_DIR/.wine" wine start /unix "$file" || warn "Failed to run $file with base prefix"
      zen_info "Launched $(basename "$file") (base prefix)."
      ;;
  esac
}

# 18) Create Launcher (Zenity GUI) to list installed apps and snapshot manager
LAUNCHER_PATH="$BIN_DIR/masa-wine-launcher"
cat > "$LAUNCHER_PATH" <<'EOF'
#!/usr/bin/env bash
DB="$HOME/.local/share/masa-wine/apps.db"
SNAP="$HOME/masa-wine-snapshots"
ZENITY="$(command -v zenity || true)"
if [ ! -f "$DB" ] || [ ! -s "$DB" ]; then
  if [ -n "$ZENITY" ]; then
    zenity --info --title="CODE WITH MASA" --text="No installed Windows apps registered yet."
    exit 0
  else
    echo "No apps registered."
    exit 0
  fi
fi
mapfile -t entries < "$DB"
choices=()
for i in "${!entries[@]}"; do
  name="$(echo "${entries[$i]}" | cut -d'|' -f1)"
  choices+=("$((i+1))" "$name")
done
sel="$(zenity --list --title="Wine Apps Launcher (CODE WITH MASA)" --column=ID --column=App "${choices[@]}" --height=400 --width=600 --print-column=1)" || exit 0
idx=$((sel-1))
entry="${entries[$idx]}"
exe="$(echo "$entry" | cut -d'|' -f2)"
prefix="$(echo "$entry" | cut -d'|' -f4)"
sandbox="$(echo "$entry" | cut -d'|' -f5)"
action="$(zenity --list --title="Action" --radiolist --column Pick --column Action TRUE run "Run" FALSE snapshot "Create Snapshot of prefix" FALSE restore "Restore Snapshot" FALSE remove "Remove entry (DB only)")" || exit 0
case "$action" in
  run)
    if [ "$sandbox" = "yes" ]; then
      if command -v firejail >/dev/null 2>&1; then
        firejail --quiet --private="$prefix" env WINEPREFIX="$prefix" wine start /unix "$exe" &
      elif command -v bwrap >/dev/null 2>&1; then
        bwrap --unshare-all --new-session --bind "$prefix" "$prefix" --dev /dev --proc /proc env WINEPREFIX="$prefix" wine start /unix "$exe" &
      else
        env WINEPREFIX="$prefix" wine start /unix "$exe" &
      fi
    else
      env WINEPREFIX="$prefix" wine start /unix "$exe" &
    fi
    ;;
  snapshot)
    name="$(basename "$prefix")-snapshot-$(date +%Y%m%d-%H%M%S)"
    tar -czf "$SNAP/$name.tar.gz" -C "$(dirname "$prefix")" "$(basename "$prefix")" && zenity --info --text="Snapshot created: $name" || zenity --error --text="Snapshot failed"
    ;;
  restore)
    snaps=( $(ls -1 "$SNAP" 2>/dev/null) )
    if [ ${#snaps[@]} -eq 0 ]; then zenity --info --text="No snapshots found"; exit 0; fi
    selsnap="$(zenity --list --title='Choose snapshot' --column=Snap "${snaps[@]}" --height=400 --width=600 --print-column=1)" || exit 0
    tar -xzf "$SNAP/$selsnap" -C "$HOME" && zenity --info --text="Restored $selsnap" || zenity --error --text="Restore failed"
    ;;
  remove)
    grep -vF "$entry" "$DB" > "${DB}.tmp" && mv "${DB}.tmp" "$DB" && zenity --info --text="Removed entry (DB only). Files left."
    ;;
  *) ;;
esac
EOF
chmod +x "$LAUNCHER_PATH" || true

# Create Desktop shortcut for launcher
LAUNCHER_DESKTOP="$DESKTOP_DIR/Wine-Apps-Launcher.desktop"
cat > "$LAUNCHER_DESKTOP" <<EOF
[Desktop Entry]
Name=Wine Apps Launcher (CODE WITH MASA)
Exec=$LAUNCHER_PATH
Terminal=false
Type=Application
Icon=applications-wine
Categories=Utility;
EOF
chmod +x "$LAUNCHER_DESKTOP" || true

# 19) Create Downloads watcher script
WATCHER_SCRIPT="$BIN_DIR/masa-watcher.sh"
cat > "$WATCHER_SCRIPT" <<'EOF'
#!/usr/bin/env bash
DOWNLOADS="${DOWNLOADS_DIR:-$HOME/Downloads}"
MAIN="$MAIN_SCRIPT_PATH"
if ! command -v inotifywait >/dev/null 2>&1; then
  echo "inotifywait missing"
  exit 1
fi
inotifywait -m -e close_write -e moved_to --format '%w%f' "$DOWNLOADS" | while read -r FILE; do
  case "${FILE,,}" in
    *.exe)
      sleep 0.5
      # launch main script to handle file (xdg-open style)
      if [ -x "$MAIN" ]; then
        "$MAIN" "$FILE" &
      fi
      ;;
    *) ;;
  esac
done
EOF
# Replace placeholders
sed -i "s|\$MAIN_SCRIPT_PATH|$MAIN_SCRIPT_PATH|g" "$WATCHER_SCRIPT"
sed -i "s|\${DOWNLOADS_DIR:-\$HOME/Downloads}|$DOWNLOADS_DIR|g" "$WATCHER_SCRIPT"
chmod +x "$WATCHER_SCRIPT" || true

# 20) Install watcher as systemd --user service and enable linger (best-effort)
SYSTEMD_USER_DIR="$HOME_DIR/.config/systemd/user"
SERVICE_NAME="masa-exe-watcher.service"
SERVICE_PATH="$SYSTEMD_USER_DIR/$SERVICE_NAME"
mkdir -p "$SYSTEMD_USER_DIR"
cat > "$SERVICE_PATH" <<EOF
[Unit]
Description=MASA EXE Auto Launcher (watch Downloads for .exe)

[Service]
Type=simple
ExecStart=$WATCHER_SCRIPT
Restart=always
RestartSec=5
Environment=DISPLAY=$DISPLAY
Environment=XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR

[Install]
WantedBy=default.target
EOF
chmod 644 "$SERVICE_PATH" || true

# Reload, enable and start user service
if command -v systemctl >/dev/null 2>&1 && systemctl --user >/dev/null 2>&1; then
  try_cmd systemctl --user daemon-reload
  try_cmd systemctl --user enable --now "$SERVICE_NAME" || warn "Enabling systemd user service failed (you may need to loginctl enable-linger $USER or re-login)."
else
  warn "systemd --user not available; watcher will be started in background for this session"
  try_cmd nohup "$WATCHER_SCRIPT" >/dev/null 2>&1 &
fi

# 21) Enable linger automatically (so user services run after logout) — needs sudo
if try_cmd $SUDO loginctl enable-linger "$USER_NAME"; then
  log "Enabled linger for $USER_NAME"
else
  warn "Failed to enable linger automatically. To enable manually run: sudo loginctl enable-linger $USER_NAME"
fi

# 22) Provide Proton-GE commands (ready-to-run) to the user (no terminal requirement)
PROTON_HELP="Proton-GE installation commands (pick one):\n\nOption A (pip3 user-install):\n  pip3 install --user protonup\n  ~/.local/bin/protonup -i GE-Proton\n\nOption B (pipx, recommended):\n  python3 -m pip install --user pipx\n  python3 -m pipx ensurepath\n  pipx install protonup\n  pipx run protonup -i GE-Proton\n\nOption C (GUI): ProtonUp-Qt AppImage: https://github.com/ProtonUp/protonup-qt\n\nAfter installing Proton-GE, you can configure Bottles/Steam to use the GE runner."
log "$PROTON_HELP"
if have_zenity; then
  zenity --info --title="$APP_TITLE - Proton-GE" --text="$PROTON_HELP" --width=700
fi

# 23) Final UI message, open Telegram contact
zen_info "Setup finished. MASA tools are ready.\nOpen the MASA Launcher from your Desktop: 'Wine Apps Launcher (CODE WITH MASA)'.\nLogs: $LOGFILE"
# Open the telegram contact link
if command -v xdg-open >/dev/null 2>&1; then
  xdg-open "$TELEGRAM_LINK" >/dev/null 2>&1 || log "xdg-open failed to open $TELEGRAM_LINK"
fi

# If script was called with file(s), handle them
if [ "$#" -ge 1 ]; then
  for f in "$@"; do
    handle_opened_exe "$f"
  done
fi

exit 0
