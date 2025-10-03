#!/bin/bash
set -euo pipefail

# ultimate-advanced-with-gui-office.sh
# Advanced Interactive Ultimate Hybrid Setup (with whiptail UI, Office auto-install, per-prefix resource-limited launchers)
# Target: Ubuntu 20.04.6 LTS
# Usage:
#   chmod +x ultimate-advanced-with-gui-office.sh
#   ./ultimate-advanced-with-gui-office.sh

HOME_DIR="${HOME:-/home/${SUDO_USER:-$(whoami)}}"
TMP_DIR="/tmp/ultimate-advanced-setup"
LOGFILE="$TMP_DIR/log.txt"
DESKTOP_DIR="$HOME_DIR/Desktop"
WINEPREFIX_BASE="$HOME_DIR/.wine"   # default base prefix; script can create more
mkdir -p "$TMP_DIR" "$DESKTOP_DIR"
touch "$LOGFILE"
exec > >(tee -a "$LOGFILE") 2>&1

echo "===== Ultimate Advanced Setup (GUI + Office Auto + Per-Prefix Launchers) ====="
date
echo ""

# helper: run with sudo if required
run_sudo() {
  if [ "$(id -u)" -eq 0 ]; then
    bash -c "$*"
  else
    sudo bash -c "$*"
  fi
}

add_desktop_entry() {
  # add_desktop_entry /path/file.desktop "content..."
  local path="$1"; shift
  echo "$*" > "$path"
  chmod +x "$path"
  chown "$(id -u):$(id -g)" "$path" || true
}

apt_update_install() {
  run_sudo "DEBIAN_FRONTEND=noninteractive apt update -y"
  run_sudo "DEBIAN_FRONTEND=noninteractive apt install -y $*"
}

# Ensure whiptail (for textual UI)
if ! command -v whiptail >/dev/null 2>&1; then
  echo "Installing whiptail for UI..."
  apt_update_install whiptail || true
fi

# Simple UI: main choices
OPTIONS=$(whiptail --title "Ultimate Hybrid Setup" --checklist \
  "اختر المكونات التي تريد تثبيتها (استخدم المسافة للاختيار، Enter للتأكيد):" 20 80 12 \
  "wine" "Wine Staging + winetricks (أساسي)" ON \
  "runtimes" "Full runtimes (DirectX, .NET, VC++)" ON \
  "nativeapps" "Native apps (Chrome, VSCode, Telegram, GIMP, 7zip)" ON \
  "winapps" "Windows apps via Wine (Notepad++, Paint.NET...)" ON \
  "aio" "AIO Runtimes (داخل Wine)" ON \
  "gaming" "Gaming stack (DXVK, vkd3d, Lutris, Steam)" ON \
  "dev" "Dev stack (Docker, Python, Node, Java, Rust, VSCode ext)" ON \
  "office" "Microsoft Office auto-install helper (إذا وضعت الملف في $TMP_DIR)" OFF \
  "prefix-tools" "إنشاء per-prefix launcher (CPU/RAM limits)" ON \
  3>&1 1>&2 2>&3)

# Transform OPTIONS into array with items
# whiptail returns quoted items like: "wine" "runtimes" ...
read -r -a CHOICES <<<"$OPTIONS"

echo "You chose: ${CHOICES[*]}"

# --- Step A: basic prep packages ---
echo "--- Installing base packages ---"
apt_update_install wget curl gnupg2 ca-certificates software-properties-common gdebi-core p7zip-full cabextract unzip xz-utils apt-transport-https ca-certificates libgl1 libgl1-mesa-dri

# --- Wine installation ---
if [[ " ${CHOICES[*]} " == *" wine "* ]]; then
  echo "--- Installing Wine Staging & winetricks ---"
  run_sudo "dpkg --add-architecture i386 || true"
  run_sudo "mkdir -pm755 /etc/apt/keyrings || true"
  run_sudo "wget -q -O /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key || true"
  run_sudo "wget -q -NP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/focal/winehq-focal.sources || true"
  run_sudo "apt update -y || true"
  if ! run_sudo "DEBIAN_FRONTEND=noninteractive apt install --install-recommends -y winehq-staging winetricks libfaudio0 fonts-wine"; then
    echo "Retrying apt fix broken..."
    run_sudo "apt --fix-broken install -y || true"
    run_sudo "DEBIAN_FRONTEND=noninteractive apt install --install-recommends -y winehq-staging winetricks libfaudio0 fonts-wine || true"
  fi
  export WINEPREFIX="$WINEPREFIX_BASE"
  mkdir -p "$WINEPREFIX"
  chown -R "$(id -u):$(id -g)" "$WINEPREFIX" || true
  echo "--- wineboot init ---"
  wineboot --init || true
fi

# --- Full runtimes via winetricks ---
if [[ " ${CHOICES[*]} " == *" runtimes "* ]]; then
  echo "--- Installing Winetricks runtimes (DirectX, .NET, VC++) ---"
  WINETRICKS_LIST=(
    corefonts allfonts wine-mono
    vcrun6 vcrun6sp6 vcrun2005 vcrun2008 vcrun2010 vcrun2012 vcrun2013 vcrun2015 vcrun2017 vcrun2019 msvcp140 mfc140
    directx9 d3dx9 d3dx10 d3dx11 dxvk xact_jun2010
    dotnet20 dotnet35 dotnet40 dotnet45 dotnet48 dotnet462
    msxml6 gdiplus windowscodecs riched20 riched30 fontsmooth=rgb jre8 ie8
  )
  for pkg in "${WINETRICKS_LIST[@]}"; do
    echo "-> winetricks $pkg"
    if [[ "$pkg" == dotnet* ]]; then
      WINEPREFIX="$WINEPREFIX_BASE" winetricks -q "$pkg" || {
        echo "Warning: $pkg may require GUI; attempted non-interactive install failed; continuing..."
      }
    else
      WINEPREFIX="$WINEPREFIX_BASE" winetricks -q "$pkg" || echo "Warning: $pkg failed or needed input; continuing..."
    fi
  done
fi

# --- Native Linux apps ---
if [[ " ${CHOICES[*]} " == *" nativeapps "* ]]; then
  echo "--- Installing native apps (Chrome, VSCode, Telegram, GIMP, 7zip) ---"
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

  # GIMP & 7zip
  apt_update_install gimp p7zip-full p7zip-rar unrar || true
fi

# --- Windows apps via Wine ---
if [[ " ${CHOICES[*]} " == *" winapps "* ]]; then
  echo "--- Installing Windows apps via Wine (Notepad++, optionally Paint.NET) ---"
  # Notepad++
  WINEPREFIX="$WINEPREFIX_BASE" winetricks -q notepad++ || {
    echo "winetricks notepad++ failed or not available, trying direct installer..."
    NPP_URL="https://github.com/notepad-plus-plus/notepad-plus-plus/releases/latest/download/npp.Installer.x64.exe"
    wget -q -O "$TMP_DIR/npp_installer.exe" "$NPP_URL" || true
    [ -f "$TMP_DIR/npp_installer.exe" ] && wine "$TMP_DIR/npp_installer.exe" /S || echo "Notepad++ installer may require GUI."
    rm -f "$TMP_DIR/npp_installer.exe"
  }
  # Create desktop entry for Notepad++
  add_desktop_entry "$DESKTOP_DIR/notepad-plus-plus.desktop" "[Desktop Entry]
Version=1.0
Name=Notepad++
Comment=Notepad++ via Wine
Exec=env WINEPREFIX=$WINEPREFIX_BASE wine 'C:\\\\Program Files\\\\Notepad++\\\\notepad++.exe'
Terminal=false
Type=Application
Icon=notepad-plus-plus
Categories=Development;TextEditor;
StartupNotify=true
"
fi

# --- AIO Runtimes ---
if [[ " ${CHOICES[*]} " == *" aio "* ]]; then
  echo "--- Running AIO Runtimes inside Wine ---"
  AIO_URL="https://allinoneruntimes.org/files/aio-runtimes_v2.5.0.exe"
  wget -q -O "$TMP_DIR/aio-runtimes.exe" "$AIO_URL" || true
  if [ -f "$TMP_DIR/aio-runtimes.exe" ]; then
    wine "$TMP_DIR/aio-runtimes.exe" || echo "AIO installer may require GUI input; continuing..."
    rm -f "$TMP_DIR/aio-runtimes.exe"
  else
    echo "AIO not downloaded; skipped."
  fi
fi

# --- Gaming stack ---
if [[ " ${CHOICES[*]} " == *" gaming "* ]]; then
  echo "--- Installing Gaming stack: DXVK, vkd3d, Lutris, Steam ---"
  WINEPREFIX="$WINEPREFIX_BASE" winetricks -q dxvk || echo "dxvk attempt failed; continuing..."
  run_sudo "apt update -y || true"
  run_sudo "apt install -y vkd3d-proton || run_sudo 'apt install -y vkd3d-tools' || true"
  # Lutris
  run_sudo "add-apt-repository -y ppa:lutris-team/lutris || true"
  run_sudo "apt update -y || true"
  run_sudo "DEBIAN_FRONTEND=noninteractive apt install -y lutris || true"
  # Steam
  run_sudo "add-apt-repository -y multiverse || true"
  run_sudo "apt update -y || true"
  run_sudo "DEBIAN_FRONTEND=noninteractive apt install -y steam || run_sudo 'apt install -y flatpak && flatpak install flathub com.valvesoftware.Steam -y' || true"
fi

# --- Dev stack ---
if [[ " ${CHOICES[*]} " == *" dev "* ]]; then
  echo "--- Installing Dev stack: Docker, Python, Node, Java, Rust, VSCode extensions ---"
  # Docker (official)
  run_sudo "apt remove -y docker docker-engine docker.io containerd runc || true"
  run_sudo "apt update -y || true"
  run_sudo "apt install -y ca-certificates curl gnupg lsb-release || true"
  run_sudo "mkdir -p /etc/apt/keyrings || true"
  run_sudo "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg || true"
  run_sudo "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu focal stable\" > /etc/apt/sources.list.d/docker.list || true"
  run_sudo "apt update -y || true"
  run_sudo "DEBIAN_FRONTEND=noninteractive apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin || true"
  run_sudo "usermod -aG docker $(id -un) || true"

  # Python
  apt_update_install python3 python3-pip python3-venv || true

  # Node (LTS)
  curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - || true
  run_sudo "DEBIAN_FRONTEND=noninteractive apt install -y nodejs || true"

  # Java
  apt_update_install openjdk-11-jdk || true

  # Rust
  if ! command -v rustc >/dev/null 2>&1; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y || true
    export PATH="$HOME/.cargo/bin:$PATH"
  fi

  # VSCode extensions
  if command -v code >/dev/null 2>&1; then
    code --install-extension ms-python.python --force || true
    code --install-extension ms-vscode.cpptools --force || true
    code --install-extension ms-azuretools.vscode-docker --force || true
  fi
fi

# --- Office auto-install helper ---
if [[ " ${CHOICES[*]} " == *" office "* ]]; then
  echo "--- Office auto-install helper ---"
  # Look for files named office_installer.* in TMP_DIR
  OFFICE_FILE="$(ls -1 $TMP_DIR/office_installer.* 2>/dev/null | head -n1 || true)"
  if [ -n "$OFFICE_FILE" ]; then
    echo "Found Office installer: $OFFICE_FILE"
    # If ISO, try mount and find setup.exe
    if [[ "$OFFICE_FILE" == *.iso ]]; then
      echo "Mounting ISO..."
      mkdir -p "$TMP_DIR/office_iso"
      sudo mount -o loop "$OFFICE_FILE" "$TMP_DIR/office_iso" || true
      SETUP_PATH="$(find "$TMP_DIR/office_iso" -iname 'setup.exe' -print -quit || true)"
      if [ -n "$SETUP_PATH" ]; then
        echo "Running Office setup from ISO: $SETUP_PATH"
        wine "$SETUP_PATH" || echo "Office setup may require GUI/interaction."
      else
        echo "No setup.exe found in ISO. Unmounting."
      fi
      sudo umount "$TMP_DIR/office_iso" || true
      rmdir "$TMP_DIR/office_iso" || true
    else
      # Attempt to run executable (silent flags vary by Office version; safest: run normally)
      echo "Attempting to run Office installer via Wine (may require GUI & license acceptance)..."
      wine "$OFFICE_FILE" || echo "Office installer returned non-zero; may require manual interaction."
    fi
  else
    whiptail --msgbox "لو حابب السكربت يثبت Office تلقائيًا: ضع ملف التثبيت (مثلاً office_installer.exe أو office_installer.iso) داخل $TMP_DIR ومن ثم شغّل هذا السكربت واختر خيار Office." 12 80
  fi
fi

# --- Per-prefix launcher tools (CPU/RAM limits) ---
if [[ " ${CHOICES[*]} " == *" prefix-tools "* ]]; then
  echo "--- Per-prefix launcher creation ---"
  # Ask user whether to create new prefix or configure existing
  PREFIX_ACTION=$(whiptail --title "Per-Prefix Launchers" --menu "اختر إجراء:" 15 60 3 \
    "1" "Create new WinePrefix with resource-limited launcher" \
    "2" "Create launcher for existing prefix" 3>&1 1>&2 2>&3) || echo "No selection"

  if [[ "$PREFIX_ACTION" == "1" ]]; then
    PREFIX_NAME=$(whiptail --inputbox "اكتب اسم الـ WinePrefix الجديد (مثال: prefix_game1):" 8 60 "prefix1" 3>&1 1>&2 2>&3)
    PREFIX_PATH="$HOME_DIR/.wine_$PREFIX_NAME"
    echo "Creating new WINEPREFIX at $PREFIX_PATH"
    mkdir -p "$PREFIX_PATH"
    export WINEPREFIX="$PREFIX_PATH"
    wineboot --init || true
    # Ask resource limits
    CPU_CORES=$(whiptail --inputbox "كم عدد CPU cores تريد تقييد العملية بها؟ (مثال: 0-3 للـ 4 نواة، أو 1)" 8 60 "0-3" 3>&1 1>&2 2>&3)
    MEM_MB=$(whiptail --inputbox "كم ذاكرة (بالـ MB) تريد كحد أقصى للعملية؟ (مثال: 4096)" 8 60 "4096" 3>&1 1>&2 2>&3)
    LAUNCHER="$DESKTOP_DIR/launch-$PREFIX_NAME.sh"
    cat > "$LAUNCHER" <<EOF
#!/bin/bash
# Launcher for WINEPREFIX=$PREFIX_PATH
export WINEPREFIX="$PREFIX_PATH"
ulimit -v $((MEM_MB * 1024))   # limit virtual memory in KB
# CPU affinity (taskset): use provided mask or range. If user provided range like 0-3, convert to mask
# If it's already a mask, user may edit launcher.
taskset -c $CPU_CORES wine "\$@"
EOF
    chmod +x "$LAUNCHER"
    add_desktop_entry "$DESKTOP_DIR/$PREFIX_NAME-launcher.desktop" "[Desktop Entry]
Version=1.0
Name=Launcher ($PREFIX_NAME)
Comment=Run programs in WINEPREFIX $PREFIX_NAME with limits
Exec=$LAUNCHER
Terminal=false
Type=Application
Icon=wine
Categories=Utility;
StartupNotify=true
"
    whiptail --msgbox "تم إنشاء الـ prefix و launcher:\n$PREFIX_PATH\nLauncher: $LAUNCHER" 10 70
  elif [[ "$PREFIX_ACTION" == "2" ]]; then
    EXISTING=$(whiptail --inputbox "اكتب مسار الـ WINEPREFIX الموجود (مثال: /home/you/.wine_game):" 8 60 "$WINEPREFIX_BASE" 3>&1 1>&2 2>&3)
    PREFIX_PATH="$EXISTING"
    CPU_CORES=$(whiptail --inputbox "CPU cores (مثال: 0-3):" 8 60 "0-3" 3>&1 1>&2 2>&3)
    MEM_MB=$(whiptail --inputbox "Memory limit MB (مثال: 4096):" 8 60 "4096" 3>&1 1>&2 2>&3)
    NAME=$(basename "$PREFIX_PATH")
    LAUNCHER="$DESKTOP_DIR/launch-$NAME.sh"
    cat > "$LAUNCHER" <<EOF
#!/bin/bash
export WINEPREFIX="$PREFIX_PATH"
ulimit -v $((MEM_MB * 1024))
taskset -c $CPU_CORES wine "\$@"
EOF
    chmod +x "$LAUNCHER"
    add_desktop_entry "$DESKTOP_DIR/$NAME-launcher.desktop" "[Desktop Entry]
Version=1.0
Name=Launcher ($NAME)
Comment=Run programs in WINEPREFIX $NAME with limits
Exec=$LAUNCHER
Terminal=false
Type=Application
Icon=wine
Categories=Utility;
StartupNotify=true
"
    whiptail --msgbox "Launcher created: $LAUNCHER" 8 60
  else
    echo "Skipping prefix launcher creation."
  fi
fi

# Final step: run winecfg once (may open GUI)
echo "--- Finalizing: winecfg ---"
winecfg || true

echo ""
echo "===== All done. Log: $LOGFILE ====="
whiptail --msgbox "انتهى التثبيت. راجع السجل: $LOGFILE\nملاحظة: بعض مثبتات .NET أو Office قد تطلب موافقة يدوية أو واجهة GUI. إذا حدث ذلك، أعد تشغيل الخطوة المناسبة يدوياً." 12 80
