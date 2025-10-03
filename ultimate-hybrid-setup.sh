#!/usr/bin/env bash
set -euo pipefail

# 🚀 MASA Tool - CODE WITH MASA
# For Ubuntu 24.04 (Full Version with DirectX)

AUTHOR="MASA"
CHANNEL="CODE WITH MASA"
AIO_URL="https://allinoneruntimes.org/files/aio-runtimes_v2.5.0.exe"
AIO_TMP="/tmp/aio-runtimes_v2.5.0.exe"
WINEPREFIX="${WINEPREFIX:-$HOME/.wine}"
FINISH_LINK="https://t.me/MrMasaOfficial"

echo "🔧 [$CHANNEL by $AUTHOR] Starting installation on Ubuntu 24.04..."

# -----------------------------
# 1. Update system
# -----------------------------
sudo apt update && sudo apt upgrade -y
echo "✅ [$CHANNEL] System update complete."

# -----------------------------
# 2. Enable 32-bit architecture
# -----------------------------
sudo dpkg --add-architecture i386
sudo apt update

# -----------------------------
# 3. Add WineHQ repository
# -----------------------------
echo "📦 [$CHANNEL] Adding WineHQ official repo..."
sudo mkdir -pm755 /etc/apt/keyrings
sudo wget -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
sudo wget -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/noble/winehq-noble.sources
sudo apt update

# -----------------------------
# 4. Install Wine + Winetricks
# -----------------------------
echo "🍷 [$CHANNEL] Installing Wine (stable) + Winetricks..."
sudo apt install -y --install-recommends winehq-stable winetricks
echo "✅ [$CHANNEL] Wine + Winetricks installed."

# -----------------------------
# 5. Setup Wine Prefix
# -----------------------------
export WINEPREFIX="$HOME/.wine"
export WINEARCH="win32"
wineboot -u || true
echo "✅ [$CHANNEL] Wine Prefix ready."

# -----------------------------
# 6. Install core runtimes
# -----------------------------
echo "📦 [$CHANNEL] Installing corefonts + vcrun2019 + dotnet48..."
winetricks -q corefonts vcrun2019 dotnet48 || true
echo "✅ [$CHANNEL] Core runtimes installed."

# -----------------------------
# 7. Install DirectX (9,10,11)
# -----------------------------
echo "🎮 [$CHANNEL] Installing DirectX (d3dx9, d3dx10, d3dx11)..."
winetricks -q d3dx9 d3dx10 d3dx11_43 || true
echo "✅ [$CHANNEL] DirectX installed."

# -----------------------------
# 8. Download & run AIO Runtimes
# -----------------------------
echo "⬇️ [$CHANNEL] Downloading AIO Runtimes..."
wget -O "$AIO_TMP" "$AIO_URL"
echo "▶️ [$CHANNEL] Running AIO Runtimes inside Wine..."
wine "$AIO_TMP" &

# -----------------------------
# 9. Reinstall Google Chrome
# -----------------------------
echo "🌐 [$CHANNEL] Reinstalling Google Chrome..."
sudo apt remove -y google-chrome-stable || true
wget -O /tmp/chrome.deb "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
sudo apt install -y /tmp/chrome.deb || sudo apt -f install -y
echo "✅ [$CHANNEL] Google Chrome installed."

# -----------------------------
# 10. Install Telegram
# -----------------------------
echo "💬 [$CHANNEL] Installing Telegram..."
sudo apt install -y telegram-desktop
echo "✅ [$CHANNEL] Telegram installed."

# -----------------------------
# 11. Create Desktop Shortcuts
# -----------------------------
DESKTOP_DIR="$HOME/Desktop"
mkdir -p "$DESKTOP_DIR"

create_desktop_file() {
  local NAME="$1"; local EXEC="$2"; local ICON="$3"; local FILE="$DESKTOP_DIR/${NAME// /_}.desktop"
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
  chmod +x "$FILE"
  echo "🎯 [$CHANNEL] Shortcut for $NAME created on Desktop."
}

create_desktop_file "Google Chrome" "google-chrome-stable %U" "google-chrome"
create_desktop_file "Telegram" "telegram-desktop" "telegram-desktop"

# -----------------------------
# 12. Open final link
# -----------------------------
echo "🚀 [$CHANNEL by $AUTHOR] Installation complete. Opening final link..."
xdg-open "$FINISH_LINK" || true

# -----------------------------
# 13. Final message
# -----------------------------
echo -e "\n✨ Thank you for using $AUTHOR - $CHANNEL ✨"
echo "💡 Follow us on official links:"
echo "Facebook :  https://www.facebook.com/CODEWITHMASA"
echo "Instagram : https://www.instagram.com/codewithmasa"
echo "Tiktok :    https://www.tiktok.com/@CODEWITHMASA"
echo "Youtube :   https://www.youtube.com/@CODEWITHMASA"
echo "Telegram :  https://t.me/CODEWITHMASA"
echo "Github :    https://github.com/CODEWITHMASA"
echo "X :         https://x.com/CODEWITHMASA"
echo "Website :   https://codewithmasa.blogspot.com/"
echo "Group :     https://t.me/GROUPCODEWITHMASA"
