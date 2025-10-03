#!/bin/bash
set -euo pipefail

###############################################################################
# Ultimate Hybrid Setup - Advanced Interactive Edition
# Target: Ubuntu 20.04.6 LTS
# Features:
#  - Install Wine Staging + Winetricks runtimes (DirectX, .NET, VC++)
#  - Optionally install: Chrome, VSCode, Telegram, GIMP, 7zip, Notepad++, Paint.NET
#  - Game stack: DXVK, vkd3d, Lutris, Steam, Proton
#  - Dev stack: Docker, Python, Node, Java, Rust, VSCode extensions
#  - AIO runtimes, WinePrefix backup/restore, Desktop shortcuts
#  - Interactive selection menu
###############################################################################

HOME_DIR="${HOME:-/home/${SUDO_USER:-$(whoami)}}"
TMP_DIR="/tmp/ultimate-advanced-setup"
LOGFILE="$TMP_DIR/log.txt"
DESKTOP_DIR="$HOME_DIR/Desktop"
WINEPREFIX="$HOME_DIR/.wine"

mkdir -p "$TMP_DIR" "$DESKTOP_DIR"
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

echo "===== Ultimate Hybrid Setup (Advanced) ====="
date
echo "Log: $LOGFILE"
echo ""

# Helper: run command with sudo if needed
run_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    bash -c "$*"
  else
    sudo bash -c "$*"
  fi
}

add_desktop_entry() {
  # add_desktop_entry /path/to/file.desktop "content..."
  local path="$1"; shift
  echo "$*" > "$path"
  chmod +x "$path"
  chown "$(id -u):$(id -g)" "$path" || true
}

apt_update_install() {
  run_sudo "DEBIAN_FRONTEND=noninteractive apt update -y"
  run_sudo "DEBIAN_FRONTEND=noninteractive apt install -y $*"
}

# Basic prep
echo "--- Preparing system packages ---"
apt_update_install wget curl gnupg2 ca-certificates software-properties-common gdebi-core p7zip-full cabextract unzip xz-utils apt-transport-https ca-certificates

# Interactive menu
cat <<'EOF'

Select components to install. Enter numbers separated by spaces (e.g.: 1 3 5)
or enter "all" to install everything.

1) Wine Staging + Winetricks (core) - required for Windows apps
2) Full Runtimes (DirectX, .NET, VC++ etc.)
3) Native Apps: Google Chrome, VSCode, Telegram, GIMP, 7zip
4) Windows apps via Wine: Notepad++, Paint.NET, 7-Zip (Windows)
5) AIO Runtimes (runs inside Wine to add many DLLs)
6) Gaming stack: DXVK, vkd3d, Lutris, Steam, Proton
7) Dev stack: Docker, Python, Node.js, Java (OpenJDK), Rust, VSCode extensions
8) Microsoft Office helper (requires local installer - see notes)
9) Backup/Restore WinePrefix tools + cleanups
10) Full run (all of above)

EOF

read -rp "Your choice: " CHOICE

if [[ "$CHOICE" == "all" ]]; then
  CHOICE="1 2 3 4 5 6 7 8 9"
fi

# --- Step 1: Wine Staging install ---
if [[ " $CHOICE " == *" 1 "* ]]; then
  echo "--- Installing Wine Staging & winetricks ---"
  run_sudo "dpkg --add-architecture i386 || true"
  run_sudo "mkdir -pm755 /etc/apt/keyrings || true"
  run_sudo "wget -q -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key || true"
  run_sudo "wget -q -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/focal/winehq-focal.sources || true"
  run_sudo "apt update -y || true"
  # Try install, fix broken if needed
  if ! run_sudo "DEBIAN_FRONTEND=noninteractive apt install --install-recommends -y winehq-staging winetricks libfaudio0 fonts-wine"; then
    echo "Retry apt --fix-broken and reinstall..."
    run_sudo "apt --fix-broken install -y || true"
    run_sudo "DEBIAN_FRONTEND=noninteractive apt install --install-recommends -y winehq-staging winetricks libfaudio0 fonts-wine || true"
  fi

  export WINEPREFIX="$WINEPREFIX"
  mkdir -p "$WINEPREFIX"
  chown -R "$(id -u):$(id -g)" "$WINEPREFIX" || true
  echo "--- initializing wine prefix ---"
  wineboot --init || true
fi

# --- Step 2: Full runtimes via winetricks ---
if [[ " $CHOICE " == *" 2 "* ]]; then
  echo "--- Installing Winetricks runtimes (DirectX, .NET, VC++) ---"
  # order matters for dotnet, we attempt sequence; some may open GUI
  WINETRICKS_LIST=(
    corefonts allfonts wine-mono
    # VC++
    vcrun6 vcrun6sp6 vcrun2005 vcrun2008 vcrun2010 vcrun2012 vcrun2013 vcrun2015 vcrun2017 vcrun2019 msvcp140 mfc140
    # DirectX family
    directx9 d3dx9 d3dx10 d3dx11 dxvk xact_jun2010
    # .NET frameworks (install progressively)
    dotnet20 dotnet35 dotnet40 dotnet45 dotnet48 dotnet462
    # other helpful libs
    msxml6 gdiplus windowscodecs riched20 riched30 fontsmooth=rgb jre8 ie8
  )
  for pkg in "${WINETRICKS_LIST[@]}"; do
    echo "winetricks -> $pkg"
    # use -q when possible
    if [[ "$pkg" == dotnet* ]]; then
      # try quiet install; may need GUI
      WINEPREFIX="$WINEPREFIX" winetricks -q "$pkg" || {
        echo "Warning: $pkg may require GUI interaction. Attempting non-interactive fallback..."
        WINEPREFIX="$WINEPREFIX" winetricks -q "$pkg" || echo "Skipping $pkg."
      }
    else
      WINEPREFIX="$WINEPREFIX" winetricks -q "$pkg" || echo "Warning: $pkg failed or needs input; continuing..."
    fi
  done
fi

# --- Step 3: Native Linux apps ---
if [[ " $CHOICE " == *" 3 "* ]]; then
  echo "--- Installing native apps: Chrome, VSCode, Telegram, GIMP, 7zip ---"
  # Chrome
  TMP_CHROME="$TMP_DIR/google-chrome.deb"
  wget -q -O "$TMP_CHROME" "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" || true
  run_sudo "DEBIAN_FRONTEND=noninteractive apt install -y '$TMP_CHROME' || (dpkg -i '$TMP_CHROME' || true; apt --fix-broken install -y || true)" || true
  rm -f "$TMP_CHROME"
  add_desktop_entry "$DESKTOP_DIR/google-chrome-no-sandbox.desktop" "[Desktop Entry]
Version=1.0
Name=Google Chrome (no-sandbox)
Comment=Google Chrome
Exec=google-chrome --no-sandbox %U
Terminal=false
Type=Application
Icon=google-chrome
Categories=Network;WebBrowser;
StartupNotify=true
"

  # VSCode
  TMP_VSCODE="$TMP_DIR/vscode.deb"
  wget -q -O "$TMP_VSCODE" "https://update.code.visualstudio.com/latest/linux-deb-x64/stable" || true
  run_sudo "DEBIAN_FRONTEND=noninteractive apt install -y '$TMP_VSCODE' || (dpkg -i '$TMP_VSCODE' || true; apt --fix-broken install -y || true)" || true
  rm -f "$TMP_VSCODE"
  add_desktop_entry "$DESKTOP_DIR/visual-studio-code.desktop" "[Desktop Entry]
Version=1.0
Name=Visual Studio Code
Comment=Code Editing
Exec=code --no-sandbox %F
Terminal=false
Type=Application
Icon=code
Categories=Development;IDE;
StartupNotify=true
"

  # Telegram
  run_sudo "add-apt-repository -y universe || true"
  run_sudo "DEBIAN_FRONTEND=noninteractive apt update -y || true"
  if ! run_sudo "DEBIAN_FRONTEND=noninteractive apt install -y telegram-desktop"; then
    run_sudo "snap install telegram-desktop || true"
  fi
  add_desktop_entry "$DESKTOP_DIR/telegram-desktop.desktop" "[Desktop Entry]
Version=1.0
Name=Telegram Desktop
Comment=Telegram Desktop Messenger
Exec=telegram-desktop %U
Terminal=false
Type=Application
Icon=telegram
Categories=Network;InstantMessaging;
StartupNotify=true
"

  # GIMP & 7zip/unrar
  apt_update_install gimp p7zip-full p7zip-rar unrar || true
fi

# --- Step 4: Windows apps via Wine ---
if [[ " $CHOICE " == *" 4 "* ]]; then
  echo "--- Installing Windows apps via Wine: Notepad++, Paint.NET (attempt), 7-Zip (Windows) ---"
  # Notepad++ via winetricks or installer
  WINEPREFIX="$WINEPREFIX" winetricks -q notepad++ || {
    NPP_URL="https://github.com/notepad-plus-plus/notepad-plus-plus/releases/latest/download/npp.Installer.x64.exe"
    wget -q -O "$TMP_DIR/npp_installer.exe" "$NPP_URL" || true
    [ -f "$TMP_DIR/npp_installer.exe" ] && wine "$TMP_DIR/npp_installer.exe" /S || echo "Notepad++ installer may need GUI."
    rm -f "$TMP_DIR/npp_installer.exe"
  }

  # 7-zip windows
  WINEPREFIX="$WINEPREFIX" winetricks -q 7zip || {
    echo "Skipping wine 7zip if not available."
  }

  # Paint.NET: often needs dotnet and GUI; attempt if dotnet installed
  if wine --version >/dev/null 2>&1; then
    echo "Attempting Paint.NET (may require manual steps)..."
    # user can place installer in TMP_DIR/paintnet.exe for automatic install attempt
    if [ -f "$TMP_DIR/paintnet_installer.exe" ]; then
      wine "$TMP_DIR/paintnet_installer.exe" || echo "Paint.NET installer returned non-zero (may require GUI)."
    else
      echo "No local Paint.NET installer found. To auto-install, place installer at $TMP_DIR/paintnet_installer.exe and re-run this step."
    fi
  fi
fi

# --- Step 5: AIO Runtimes ---
if [[ " $CHOICE " == *" 5 "* ]]; then
  echo "--- Downloading & running AIO Runtimes (inside Wine) ---"
  AIO_URL="https://allinoneruntimes.org/files/aio-runtimes_v2.5.0.exe"
  wget -q -O "$TMP_DIR/aio-runtimes.exe" "$AIO_URL" || true
  if [ -f "$TMP_DIR/aio-runtimes.exe" ]; then
    wine "$TMP_DIR/aio-runtimes.exe" || echo "AIO installer may require GUI; continuing..."
    rm -f "$TMP_DIR/aio-runtimes.exe"
  else
    echo "AIO download failed; skipped."
  fi
fi

# --- Step 6: Gaming stack: DXVK, VKD3D, Lutris, Steam, Proton ---
if [[ " $CHOICE " == *" 6 "* ]]; then
  echo "--- Installing gaming stack (DXVK, vkd3d, Lutris, Steam) ---"
  # DXVK via winetricks
  WINEPREFIX="$WINEPREFIX" winetricks -q dxvk || echo "dxvk install returned non-zero; continuing..."
  # try vkd3d from apt if available
  run_sudo "apt update -y || true"
  run_sudo "apt install -y vkd3d-proton || run_sudo 'apt install -y vkd3d-tools' || true"

  # Lutris
  run_sudo "add-apt-repository -y ppa:lutris-team/lutris || true"
  run_sudo "apt update -y || true"
  run_sudo "DEBIAN_FRONTEND=noninteractive apt install -y lutris || true"

  # Steam (native)
  run_sudo "DEBIAN_FRONTEND=noninteractive apt install -y software-properties-common || true"
  run_sudo "add-apt-repository -y multiverse || true"
  run_sudo "apt update -y || true"
  run_sudo "DEBIAN_FRONTEND=noninteractive apt install -y steam || run_sudo 'apt install -y flatpak && flatpak install flathub com.valvesoftware.Steam -y' || true"

  echo "Note: Proton versions managed inside Steam; Lutris can manage Wine prefixes per-game."
fi

# --- Step 7: Dev stack: Docker, Python, Node, Java, Rust, VSCode extensions ---
if [[ " $CHOICE " == *" 7 "* ]]; then
  echo "--- Installing dev stack (Docker, Python, Node, OpenJDK, Rust) ---"
  # Docker
  run_sudo "apt remove -y docker docker-engine docker.io containerd runc || true"
  run_sudo "apt update -y || true"
  run_sudo "apt install -y ca-certificates curl gnupg lsb-release || true"
  run_sudo "mkdir -p /etc/apt/keyrings || true"
  run_sudo "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || true"
  run_sudo "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu focal stable\" > /etc/apt/sources.list.d/docker.list || true"
  run_sudo "apt update -y || true"
  run_sudo "DEBIAN_FRONTEND=noninteractive apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || true"
  echo "Adding user to docker group..."
  run_sudo "usermod -aG docker $(id -un) || true"

  # Python
  apt_update_install python3 python3-pip python3-venv || true

  # Node.js (LTS)
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - || true
  run_sudo "DEBIAN_FRONTEND=noninteractive apt install -y nodejs || true"

  # Java (OpenJDK)
  apt_update_install openjdk-11-jdk || true

  # Rust (rustup)
  if ! command -v rustc >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || true
    export PATH="$HOME/.cargo/bin:$PATH"
  fi

  # VSCode extensions (optional list)
  echo "Installing recommended VSCode extensions..."
  if command -v code >/dev/null 2>&1 ; then
    code --install-extension ms-python.python --force || true
    code --install-extension ms-vscode.cpptools --force || true
    code --install-extension ms-azuretools.vscode-docker --force || true
    code --install-extension eamodio.gitlens --force || true
  fi
fi

# --- Step 8: MS Office helper ---
if [[ " $CHOICE " == *" 8 "* ]]; then
  echo "--- Microsoft Office helper ---"
  echo "To install Office, place the installer (e.g. Office2010.exe or ISO content) in: $TMP_DIR/office_installer.exe"
  if [ -f "$TMP_DIR/office_installer.exe" ]; then
    echo "Found local Office installer, attempting install (may require GUI & license):"
    wine "$TMP_DIR/office_installer.exe" || echo "Office installer returned non-zero; may need manual interaction."
  else
    echo "No local Office installer present. Place it at $TMP_DIR/office_installer.exe and re-run the script or run manually."
  fi
fi

# --- Step 9: Backup/Restore & Clean tools ---
if [[ " $CHOICE " == *" 9 "* ]]; then
  echo "--- Backup/Restore & Cleanup tools ---"
  echo "1) Backup current WinePrefix"
  echo "2) Restore WinePrefix from latest backup (if exists)"
  echo "3) Clean temporary files"
  read -rp "Choose 1 (backup), 2 (restore), 3 (clean) or anything else to skip: " backup_choice
  if [[ "$backup_choice" == "1" ]]; then
    echo "Creating backup..."
    tar -cJf "$TMP_DIR/wine-backup-$(date +%Y%m%d%H%M%S).tar.xz" -C "$HOME_DIR" ".wine" || echo "Backup failed."
    echo "Backup created in $TMP_DIR."
  elif [[ "$backup_choice" == "2" ]]; then
    latest="$(ls -1t $TMP_DIR/wine-backup-*.tar.xz 2>/dev/null | head -n1 || true)"
    if [ -n "$latest" ]; then
      echo "Restoring from $latest ..."
      rm -rf "$HOME_DIR/.wine" || true
      tar -xJf "$latest" -C "$HOME_DIR" || echo "Restore failed."
      echo "Restore complete."
    else
      echo "No backup found in $TMP_DIR."
    fi
  elif [[ "$backup_choice" == "3" ]]; then
    echo "Cleaning tmp dir..."
    rm -rf "$TMP_DIR/*" || true
    echo "Cleaned."
  else
    echo "Skipping backup/restore/clean."
  fi
fi

# Finalization
echo "--- Final config: winecfg (may open GUI) ---"
winecfg || true

echo ""
echo "===== Setup finished ====="
echo "Log saved to: $LOGFILE"
echo "If any installers required GUI (e.g. some dotnet versions), re-run those winetricks steps manually or follow prompts."
echo "Tips:"
echo " - To install Office, put the installer in $TMP_DIR/office_installer.exe and run 'wine $TMP_DIR/office_installer.exe'"
echo " - Use Lutris to manage per-game Wine prefixes and Proton compatibility."
echo ""
date
