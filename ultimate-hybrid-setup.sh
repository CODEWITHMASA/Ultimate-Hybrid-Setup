#!/usr/bin/env bash
set -euo pipefail
# setup-wine-ubuntu2404.sh
# مخصص Ubuntu 24.04 (Noble Numbat)
# يقوم بتثبيت Wine, winetricks, runtimes, إعادة تثبيت Chrome, تثبيت Telegram,
# تنزيل aio-runtimes_v2.5.0.exe وتشغيله عبر wine، وخلق شورتكات على الديسكتوب،
# ثم يفتح الرابط: https://t.me/MrMasaOfficial
#
# Usage: sudo ./setup-wine-ubuntu2404.sh

AIO_URL="https://allinoneruntimes.org/files/aio-runtimes_v2.5.0.exe"
AIO_TMP="/tmp/aio-runtimes_v2.5.0.exe"
WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"
DESKTOP_DIR="${XDG_DESKTOP_DIR:-$HOME/Desktop}"
TELEGRAM_OPEN_AFTER="https://t.me/MrMasaOfficial"

echo "Starting setup for Ubuntu 24.04 (Noble Numbat)."

if [ "$(id -u)" -ne 0 ]; then
  echo "This script should be run with sudo. Re-run with: sudo $0"
  exit 1
fi

apt update
apt upgrade -y

# enable 32-bit architecture
dpkg --add-architecture i386 || true
apt update

# Install required base packages
apt install -y --no-install-recommends \
  software-properties-common wget curl ca-certificates gnupg2 apt-transport-https \
  cabextract p7zip-full unzip gdebi-core xdg-utils

# Try installing Wine from Ubuntu repos first (Ubuntu 24.04 includes recent Wine).
# If that fails, we'll try to add WineHQ repo.
echo "Installing wine packages from Ubuntu repositories..."
if apt -y install wine winetricks wine64 wine32; then
  echo "Installed wine from Ubuntu repo."
else
  echo "Failed to install wine from Ubuntu repo — trying WineHQ repository..."
  # create keyring dir like modern apt-key replacement
  mkdir -p /etc/apt/keyrings
  wget -O- https://dl.winehq.org/wine-builds/winehq.key | gpg --dearmor >/etc/apt/keyrings/winehq-archive.key || true
  # detect codename and add repo
  CODENAME="$(. /etc/os-release && echo ${UBUNTU_CODENAME:-noble})"
  echo "deb [signed-by=/etc/apt/keyrings/winehq-archive.key] https://dl.winehq.org/wine-builds/ubuntu/ ${CODENAME} main" \
    >/etc/apt/sources.list.d/winehq.list
  apt update || true
  apt install -y --install-recommends winehq-stable || apt install -y --install-recommends winehq-devel || apt install -y wine
fi

# Ensure winetricks exists
if ! command -v winetricks >/dev/null 2>&1; then
  echo "Installing winetricks..."
  wget -O /usr/local/bin/winetricks https://raw.githubusercontent.com/Winetricks/winetricks/master/src/winetricks
  chmod +x /usr/local/bin/winetricks
fi

# Create a 32-bit WINEPREFIX for better compatibility (you can change/remove if you prefer 64-bit)
export WINEPREFIX="$WINEPREFIX"
export WINEARCH="win32"
echo "Initializing WINEPREFIX at $WINEPREFIX (WINEARCH=win32). This may take a few seconds..."
sudo -u "$SUDO_USER" env WINEPREFIX="$WINEPREFIX" WINEARCH="$WINEARCH" wineboot -u || true
sleep 2

# Use winetricks to install common runtimes and dlls. Some may open installers/dialogs.
WINETRICKS_CMD="$(command -v winetricks || echo /usr/local/bin/winetricks)"
echo "Running winetricks (may open GUI dialogs)."
# Run as the regular user who invoked sudo so prefix files are owned correctly
sudo -u "$SUDO_USER" env WINEPREFIX="$WINEPREFIX" "$WINETRICKS_CMD" -q corefonts || true
sudo -u "$SUDO_USER" env WINEPREFIX="$WINEPREFIX" "$WINETRICKS_CMD" -q vcrun2015 vcrun2017 vcrun2019 || true

# Try several dotnet versions (these can be large and may require interaction)
sudo -u "$SUDO_USER" env WINEPREFIX="$WINEPREFIX" "$WINETRICKS_CMD" -q dotnet40 || true
sudo -u "$SUDO_USER" env WINEPREFIX="$WINEPREFIX" "$WINETRICKS_CMD" -q dotnet45 || true
# dotnet48 may be heavy; include but allow failure
sudo -u "$SUDO_USER" env WINEPREFIX="$WINEPREFIX" "$WINETRICKS_CMD" -q dotnet48 || true

# Additional helpful components
sudo -u "$SUDO_USER" env WINEPREFIX="$WINEPREFIX" "$WINETRICKS_CMD" -q gdiplus ie8 msxml6 comctl32 riched20 || true

# Download the AIO runtimes exe and run via wine as the regular user
echo "Downloading AIO runtimes from $AIO_URL ..."
wget -O "$AIO_TMP" "$AIO_URL" || echo "Warning: could not download $AIO_URL -- check network."

if [ -f "$AIO_TMP" ]; then
  echo "Running $AIO_TMP with wine (as $SUDO_USER)..."
  # run in background as user so GUI can appear in their session
  sudo -u "$SUDO_USER" env WINEPREFIX="$WINEPREFIX" DISPLAY="${DISPLAY:-:0}" wine "$AIO_TMP" &
  sleep 5
else
  echo "AIO runtimes file not present; skipping running it."
fi

# Remove Google Chrome if present, then download and install latest .deb
if dpkg -l | grep -qi google-chrome; then
  echo "Removing existing Google Chrome..."
  apt remove -y google-chrome-stable || true
fi

CHROME_DEB_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
CHROME_TMP="/tmp/google-chrome-stable_current_amd64.deb"
wget -O "$CHROME_TMP" "$CHROME_DEB_URL" || true
if [ -f "$CHROME_TMP" ]; then
  echo "Installing Google Chrome..."
  gdebi -n "$CHROME_TMP" || dpkg -i "$CHROME_TMP" || apt -f install -y
fi

# Install Telegram (prefer apt, fallback to snap)
if apt-cache policy telegram-desktop | grep -q Candidate; then
  apt install -y telegram-desktop || true
else
  if command -v snap >/dev/null 2>&1; then
    snap install telegram-desktop || true
  else
    apt install -y telegram-desktop || true
  fi
fi

# Create desktop shortcuts (for the invoking user)
USER_HOME="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
USER_DESKTOP="$USER_HOME/Desktop"
mkdir -p "$USER_DESKTOP"
chown "$SUDO_USER":"$SUDO_USER" "$USER_DESKTOP"

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
  echo "Created desktop shortcut: $FILE"
}

# determine chrome path for Exec
CHROME_PATH="$(command -v google-chrome-stable || command -v google-chrome || true)"
if [ -n "$CHROME_PATH" ]; then
  create_desktop_file "Google Chrome" "$CHROME_PATH %U" "google-chrome"
fi

TELEGRAM_PATH="$(command -v telegram-desktop || true)"
if [ -n "$TELEGRAM_PATH" ]; then
  create_desktop_file "Telegram" "$TELEGRAM_PATH" "telegram-desktop"
fi

# Add a "CODE WITH MASA" desktop file with your social links (opens website)
# Replace the Exec target if you want it to open Telegram page instead
CODE_LINK="https://codewithmasa.blogspot.com/"
create_desktop_file "CODE WITH MASA" "xdg-open $CODE_LINK" "internet-messenger"

# Final note and open the requested Telegram link
echo "Setup finished. Opening the requested Telegram link: $TELEGRAM_OPEN_AFTER"
# Open as the regular user so it opens in their GUI session
sudo -u "$SUDO_USER" env DISPLAY="${DISPLAY:-:0}" xdg-open "$TELEGRAM_OPEN_AFTER" || true

echo "All done. If any installers (especially dotnet) opened GUI windows, please follow their instructions."
