#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
cd "$SCRIPT_DIR"

LOG_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/kali-weaponizer"
mkdir -p "$LOG_DIR"

trap 'echo "[!] Error on line ${LINENO}: ${BASH_COMMAND}" >&2' ERR

# Function to print steps
info() {
    local message="[+] $1  "
    local green='\e[32m'
    local reset='\e[0m'
    local cols=80
    if command -v tput >/dev/null 2>&1 && tput cols >/dev/null 2>&1; then
        cols="$(tput cols)"
    fi
    local message_length=${#message}
    local num_hashes=$(( cols > message_length ? cols - message_length : 0 ))

    echo -e "\n\n"
    echo -e "${green}${message}$(printf '%*s' "$num_hashes" | tr ' ' '#')${reset}"
    sleep "${SLEEP_TIME:-1}"
}

warn() {
    echo "[!] $*" >&2
}

run_sudo() {
    sudo "$@"
}

have_systemd() {
    command -v systemctl >/dev/null 2>&1 && [[ -d /run/systemd/system ]]
}

ensure_kali_sources() {
    # Defaults to kali-rolling because this script installs current packages.
    # Override with KALI_SUITE=kali-last-snapshot if you intentionally want the point-release snapshot.
    local suite="${KALI_SUITE:-kali-rolling}"
    local line="deb http://http.kali.org/kali ${suite} main contrib non-free non-free-firmware"
    local list_file="/etc/apt/sources.list.d/kali-weaponizer.list"
    local source_file
    local repo_regex="^[[:space:]]*deb[[:space:]].*http://http\.kali\.org/kali[[:space:]]+${suite}[[:space:]]"

    if [[ "${SKIP_KALI_SOURCES:-0}" == "1" ]]; then
        warn "Skipping Kali source management because SKIP_KALI_SOURCES=1."
        return 0
    fi

    # If Kali is already configured outside this script's managed file, do not add another identical repo.
    for source_file in /etc/apt/sources.list /etc/apt/sources.list.d/*.list; do
        [[ -f "$source_file" ]] || continue
        [[ "$source_file" == "$list_file" ]] && continue

        if grep -qE "$repo_regex" "$source_file"; then
            warn "Kali ${suite} repository is already configured in $source_file; not adding duplicate source."

            # Clean up the duplicate file created by earlier versions of this script.
            if [[ -f "$list_file" ]] && grep -qF "$line" "$list_file"; then
                run_sudo rm -f "$list_file"
                warn "Removed duplicate source file: $list_file"
            fi
            return 0
        fi
    done

    # If this script's managed source already exists and no duplicate was found elsewhere, keep it.
    if [[ -f "$list_file" ]] && grep -qF "$line" "$list_file"; then
        warn "Kali ${suite} repository is already configured in $list_file."
        return 0
    fi

    if [[ -f /etc/apt/sources.list && ! -f /etc/apt/sources.list.bak ]]; then
        run_sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak || true
    fi

    echo "$line" | run_sudo tee "$list_file" >/dev/null
}

apt_update() {
    run_sudo apt-get update
}

apt_available() {
    apt-cache show "$1" >/dev/null 2>&1
}

filter_available_packages() {
    local pkg
    for pkg in "$@"; do
        if apt_available "$pkg"; then
            printf '%s\n' "$pkg"
        else
            warn "APT package not available in enabled repositories, skipping: $pkg"
            printf '%s\n' "$pkg" >> "$LOG_DIR/skipped-apt-packages.log"
        fi
    done
}

apt_install_available() {
    local packages=("$@")
    local available=()
    mapfile -t available < <(filter_available_packages "${packages[@]}")
    if (( ${#available[@]} > 0 )); then
        run_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${available[@]}"
    else
        warn "No packages from this set are available."
    fi
}

apt_purge_installed_patterns() {
    local patterns=("$@")
    local installed=()
    local pattern

    for pattern in "${patterns[@]}"; do
        while IFS= read -r pkg; do
            [[ -n "$pkg" ]] && installed+=("$pkg")
        done < <(dpkg-query -W -f='${binary:Package}\n' "$pattern" 2>/dev/null || true)
    done

    if (( ${#installed[@]} > 0 )); then
        run_sudo env DEBIAN_FRONTEND=noninteractive apt-get purge -y "${installed[@]}"
    else
        warn "No matching installed packages to purge."
    fi
}

clone_or_update() {
    local repo_url="$1"
    local dest="$2"
    local owner="${3:-$USER:$(id -gn)}"

    if [[ "$dest" == /opt/* && -e "$dest" ]]; then
        run_sudo chown -R "$owner" "$dest" || true
    fi

    if [[ -d "$dest/.git" ]]; then
        git -C "$dest" pull --ff-only
    elif [[ -e "$dest" ]]; then
        warn "$dest exists and is not a git repository; leaving it untouched."
        return 0
    else
        if [[ "$dest" == /opt/* ]]; then
            run_sudo git clone "$repo_url" "$dest"
        else
            git clone "$repo_url" "$dest"
        fi
    fi

    if [[ "$dest" == /opt/* ]]; then
        run_sudo chown -R "$owner" "$dest"
    fi
}

pipx_install_force() {
    local spec="$1"
    PIPX_HOME="$HOME/tools/pipx" \
    PIPX_BIN_DIR="$HOME/tools/bin" \
    PIPX_MAN_DIR="$HOME/tools/pipx/man" \
        pipx install --force --include-deps "$spec"
}

install_docker_from_kali() {
    info "Installing Docker from Kali packages"
    apt_install_available docker.io docker-compose

    if have_systemd; then
        run_sudo systemctl enable --now docker || warn "Could not enable/start Docker."
    else
        warn "systemd is not available; Docker service was installed but not started."
    fi

    if getent group docker >/dev/null 2>&1; then
        run_sudo usermod -aG docker "$USER" || true
    fi
}

# Display ASCII art
banner="
                        ██╗  ██╗ █████╗ ██╗     ██╗                             
                        ██║ ██╔╝██╔══██╗██║     ██║                             
                        █████╔╝ ███████║██║     ██║                             
                        ██╔═██╗ ██╔══██║██║     ██║                             
                        ██║  ██╗██║  ██║███████╗██║                             
                        ╚═╝  ╚═╝╚═╝  ╚═╝╚══════╝╚═╝                             
                                                                                
██╗    ██╗███████╗ █████╗ ██████╗  ██████╗ ███╗   ██╗██╗███████╗███████╗██████╗ 
██║    ██║██╔════╝██╔══██╗██╔══██╗██╔═══██╗████╗  ██║██║╚══███╔╝██╔════╝██╔══██╗
██║ █╗ ██║█████╗  ███████║██████╔╝██║   ██║██╔██╗ ██║██║  ███╔╝ █████╗  ██████╔╝
██║███╗██║██╔══╝  ██╔══██║██╔═══╝ ██║   ██║██║╚██╗██║██║ ███╔╝  ██╔══╝  ██╔══██╗
╚███╔███╔╝███████╗██║  ██║██║     ╚██████╔╝██║ ╚████║██║███████╗███████╗██║  ██║
 ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝╚═╝      ╚═════╝ ╚═╝  ╚═══╝╚═╝╚══════╝╚══════╝╚═╝  ╚═╝
                                                                                
                           -------------
                             By P-ict0
                           -------------
"

echo -e "\n\n"
echo -e "$banner"
echo -e "\n\n"

# Prompt sudo password
info "Prompting for sudo password"
sudo -v

# Keep sudo alive while the script runs.
while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

# DNS
info "Setting up Google DNS"
if [[ -w /etc/resolv.conf || -n "$(sudo -n true 2>/dev/null && echo yes || true)" ]]; then
    if ! grep -q "nameserver 8.8.8.8" /etc/resolv.conf 2>/dev/null; then
        echo "nameserver 8.8.8.8 # Google" | run_sudo tee -a /etc/resolv.conf > /dev/null || warn "Could not update /etc/resolv.conf"
    fi
    if ! grep -q "nameserver 8.8.4.4" /etc/resolv.conf 2>/dev/null; then
        echo "nameserver 8.8.4.4 # Google" | run_sudo tee -a /etc/resolv.conf > /dev/null || warn "Could not update /etc/resolv.conf"
    fi
fi

# Setup sources.list
info "Setting up Kali apt source"
ensure_kali_sources

# Update packages
info "Updating packages"
apt_update

# Remove packages to install them later
PACKAGES_TO_REMOVE=(
    crackmapexec
    bloodhound
    python3-ldapdomaindump
    bloodhound.py
    certipy-ad
    responder
    'openjdk*'
    'oracle-java*'
    java-common
    netexec
    postgresql
)
info "Removing conflicting packages with apt"
apt_purge_installed_patterns "${PACKAGES_TO_REMOVE[@]}"

# Update packages
info "Upgrading packages"
run_sudo env DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y
info "Autoremoving packages"
run_sudo env DEBIAN_FRONTEND=noninteractive apt-get autoremove -y
info "Autocleaning packages"
run_sudo apt-get autoclean -y

# Install packages
PACKAGES_TO_INSTALL=(
    nmap
    masscan
    wfuzz
    aircrack-ng
    smbclient
    ncat
    wireshark
    wireshark-common
    asciinema
    enum4linux
    exploitdb
    tcpdump
    gobuster
    feroxbuster
    bettercap
    autoconf
    automake
    autopoint
    build-essential
    ca-certificates
    curl
    git
    gnupg
    libtool
    pkg-config
    make
    unzip
    wget
    xclip
    ruby
    realtek-rtl88xxau-dkms
    ipcalc
    eyewitness
    vsftpd
    powersploit
    libkrb5-dev
    code-oss
    jq
    evil-winrm
    htop
    default-jdk
    openjdk-21-jdk
    pipx
    python3
    python3-dev
    python3-venv
    python3-pip
    golang
    gdb
    zenity
    metasploit-framework
    eza
    postgresql
    postgresql-client
    hashcat
    wordlists
    rlwrap
    dirbuster
    wpscan
    webshells
    silversearcher-ag
    cupp
    freerdp3-x11
    apache2
    neovim
    nikto
)
PACKAGES_TO_INSTALL_NONINTERACTIVE=(
    krb5-user
)

info "Preseeding Wireshark capture setting"
echo "wireshark-common wireshark-common/install-setuid boolean true" | run_sudo debconf-set-selections || true

info "Installing needed packages"
: > "$LOG_DIR/skipped-apt-packages.log"
apt_install_available "${PACKAGES_TO_INSTALL[@]}"
apt_install_available "${PACKAGES_TO_INSTALL_NONINTERACTIVE[@]}"

# Wireshark configuration
info "Enabling Wireshark non-root capture"
if getent group wireshark >/dev/null 2>&1; then
    run_sudo usermod -aG wireshark "$USER" || true
else
    warn "wireshark group not found; skipping usermod."
fi

# Install virtualbox-guest-x11
info "Installing virtualbox-guest-x11"
apt_install_available virtualbox-guest-x11
run_sudo apt-get install -y --reinstall virtualbox-guest-x11 || warn "virtualbox-guest-x11 reinstall skipped/failed."

# Set timezone
info "Setting timezone to Amsterdam"
if have_systemd && command -v timedatectl >/dev/null 2>&1; then
    run_sudo timedatectl set-timezone Europe/Amsterdam
else
    warn "timedatectl/systemd is not available; timezone not changed."
fi

# Create folders
info "Creating needed folders"
run_sudo mkdir -p /usr/share/ca-certificates
mkdir -p "$HOME/tools/bin" "$HOME/tools/repos" "$HOME/tools/pipx/man"

# Add ~/tools/bin to PATH
info "Adding ~/tools/bin to PATH"
touch "$HOME/.zshrc"
if ! grep -qF "export PATH=\$PATH:$HOME/tools/bin" "$HOME/.zshrc"; then
    echo "export PATH=\$PATH:$HOME/tools/bin" >> "$HOME/.zshrc"
fi

# Add ~/tools/bin to secure_path in /etc/sudoers.d
info "Adding ~/tools/bin to sudo secure_path"
USER_HOME="$(getent passwd "$USER" | cut -d: -f6)"
SUDOERS_D="/etc/sudoers.d/99-tools-bin"
TMP_SUDOERS="$(mktemp)"

echo "Defaults secure_path=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${USER_HOME}/tools/bin\"" > "$TMP_SUDOERS"
if run_sudo visudo -c -f "$TMP_SUDOERS" >/dev/null 2>&1; then
    run_sudo install -m 440 "$TMP_SUDOERS" "$SUDOERS_D"
    echo "Successfully added ${USER_HOME}/tools/bin to secure_path in ${SUDOERS_D}"
else
    warn "Invalid sudoers fragment. Change not applied."
fi
rm -f "$TMP_SUDOERS"

# ZSH config
info "Setting up zsh and PentestManager"
PM_REPO_URL="https://github.com/P-ict0/PentestManager.git"
PM_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/PentestManager"
ZSHRC="$HOME/.zshrc"

mkdir -p "$(dirname "$PM_DIR")"
clone_or_update "$PM_REPO_URL" "$PM_DIR"

if [[ -f "$ZSHRC" && ! -f "$ZSHRC.bak_pentestmanager" ]]; then
    info "Backing up ~/.zshrc to ~/.zshrc.bak_pentestmanager"
    cp "$ZSHRC" "$ZSHRC.bak_pentestmanager"
fi

LOADER_MARKER="# PentestManager (autoload)"
if ! grep -qF "$LOADER_MARKER" "$ZSHRC" 2>/dev/null; then
    info "Adding PentestManager loader to ~/.zshrc"
    cat <<'EOL' >> "$ZSHRC"

# PentestManager (autoload)
[[ -o interactive ]] || return
source "${XDG_CONFIG_HOME:-$HOME/.config}/PentestManager/src/init.zsh"
EOL
else
    info "Loader already present in ~/.zshrc"
fi

info "Setting up pipx"
add_line() { grep -qxF "$1" "$HOME/.zshrc" || echo "$1" >> "$HOME/.zshrc"; }
add_line "export PIPX_HOME='$HOME/tools/pipx'"
add_line "export PIPX_BIN_DIR='$HOME/tools/bin'"
add_line "export PIPX_MAN_DIR='$HOME/tools/pipx/man'"

# Ensure a locale exists
info "Ensuring a locale exists"
if [[ -f /etc/locale.gen ]] && ! grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen; then
    echo "en_US.UTF-8 UTF-8" | run_sudo tee -a /etc/locale.gen > /dev/null
    run_sudo locale-gen
fi

# Set locale
info "Setting locale to en_US.UTF-8"
run_sudo update-locale LANG=en_US.UTF-8 || warn "Could not update locale."

# Start and enable PostgreSQL service
info "Starting and enabling PostgreSQL"
if have_systemd; then
    run_sudo systemctl enable --now postgresql || warn "Could not enable/start PostgreSQL."
else
    warn "systemd is not available; PostgreSQL service was not started."
fi
if command -v psql >/dev/null 2>&1; then
    run_sudo -u postgres psql -c "REINDEX DATABASE postgres;" || true
    run_sudo -u postgres psql -c "ALTER DATABASE postgres REFRESH COLLATION VERSION;" || true
fi

# Initialize the MSF database
info "Initializing msfdb"
if command -v msfdb >/dev/null 2>&1; then
    run_sudo msfdb init || warn "msfdb init failed or database already exists; continuing."
else
    warn "msfdb command not found; skipping."
fi

# Tools
# BloodHound.py
info "Installing BloodHound.py"
pipx_install_force git+https://github.com/fox-it/BloodHound.py

# Burp Suite
info "Installing Burp Suite"
apt_install_available burpsuite
chmod +x "./templates/scripts/get-burp-certificate.sh"
if [[ -f /usr/share/burpsuite/burpsuite.jar ]]; then
    bash "./templates/scripts/get-burp-certificate.sh" || warn "Could not auto-fetch Burp CA certificate. Start Burp once and export the CA manually if needed."
    if [[ -s /tmp/burpCA.der ]]; then
        run_sudo mv /tmp/burpCA.der /usr/share/ca-certificates/burpCA.der
    fi
else
    warn "Burp Suite jar not found; skipping CA extraction."
fi
run_sudo mkdir -p /usr/share/firefox-esr/distribution
run_sudo cp "./templates/configurations/firefox/firefox_policies.json" /usr/share/firefox-esr/distribution/policies.json

# Certipy
info "Installing Certipy"
pipx_install_force git+https://github.com/ly4k/Certipy

# Coercer
info "Installing Coercer"
pipx_install_force git+https://github.com/p0dalirius/Coercer

# Docker
install_docker_from_kali

# BloodHound CE
info "Installing BloodHound CE"
mkdir -p "$HOME/tools/repos/BloodHoundCE"
curl -fsSL https://ghst.ly/getbhce -o "$HOME/tools/repos/BloodHoundCE/docker-compose.yml"

# Impacket
info "Installing Impacket"
pipx_install_force git+https://github.com/fortra/impacket

# Kerbrute
info "Installing Kerbrute"
KERBRUTE_DIR="$HOME/tools/repos/Kerbrute"
clone_or_update https://github.com/ropnop/kerbrute "$KERBRUTE_DIR"
make -C "$KERBRUTE_DIR" linux
KERBRUTE_BIN="$(find "$KERBRUTE_DIR/dist" -type f \( -name 'kerbrute_linux_amd64' -o -name 'kerbrute_linux_x86_64' -o -name 'kerbrute_linux_386' \) | sort | head -n 1)"
if [[ -n "$KERBRUTE_BIN" ]]; then
    ln -sf "$KERBRUTE_BIN" "$HOME/tools/bin/kerbrute"
    chmod +x "$KERBRUTE_BIN"
else
    warn "Kerbrute build finished but no Linux binary was found."
fi

# ldapdomaindump
info "Installing ldapdomaindump"
pipx_install_force git+https://github.com/dirkjanm/ldapdomaindump

# Mitm6
info "Installing Mitm6"
pipx_install_force git+https://github.com/dirkjanm/mitm6

# NetExec
info "Installing NetExec"
pipx_install_force git+https://github.com/Pennyw0rth/NetExec

# Responder
info "Installing Responder"
RESPONDER_DIR="$HOME/tools/repos/Responder"
RESPONDER_VENV="$RESPONDER_DIR/.venv"
clone_or_update https://github.com/lgandx/Responder "$RESPONDER_DIR"

python3 -m venv "$RESPONDER_VENV"
# shellcheck disable=SC1091
source "$RESPONDER_VENV/bin/activate"
pip install --upgrade pip wheel
pip install -r "$RESPONDER_DIR/requirements.txt"
deactivate

cp "./templates/scripts/extract-hashes-responder.sh" "$HOME/tools/bin/extract-hashes-responder"
chmod +x "$HOME/tools/bin/extract-hashes-responder"

mkdir -p "$RESPONDER_DIR/certs"
openssl genrsa -out "$RESPONDER_DIR/certs/responder.key" 2048
openssl req -new -x509 -days 3650 -key "$RESPONDER_DIR/certs/responder.key" -out "$RESPONDER_DIR/certs/responder.crt" -subj "/"

mkdir -p "$RESPONDER_DIR/bin"
cat <<EOL > "$RESPONDER_DIR/bin/run_responder.sh"
#!/usr/bin/env bash
source "$HOME/tools/repos/Responder/.venv/bin/activate"
"$HOME/tools/repos/Responder/.venv/bin/python" "$HOME/tools/repos/Responder/Responder.py" "\${@:1}"
EOL
chmod +x "$RESPONDER_DIR/bin/run_responder.sh"
ln -sf "$RESPONDER_DIR/bin/run_responder.sh" "$HOME/tools/bin/responder"

# Sublime Text
info "Installing Sublime Text"
curl -fsSL https://download.sublimetext.com/sublimehq-pub.gpg -o /tmp/sublimehq-archive.gpg
run_sudo mkdir -p /etc/apt/keyrings
run_sudo gpg --dearmor --yes -o /etc/apt/keyrings/sublimehq-archive.gpg /tmp/sublimehq-archive.gpg
rm -f /tmp/sublimehq-archive.gpg
echo "deb [signed-by=/etc/apt/keyrings/sublimehq-archive.gpg] https://download.sublimetext.com/ apt/stable/" | run_sudo tee /etc/apt/sources.list.d/sublime-text.list > /dev/null
apt_update
apt_install_available sublime-text hunspell-en-us

# DonPAPI
info "Installing DonPAPI"
pipx_install_force git+https://github.com/login-securite/DonPAPI.git

# PayloadsAllTheThings
info "Installing PayloadsAllTheThings"
clone_or_update https://github.com/swisskyrepo/PayloadsAllTheThings /opt/payloadsallthethings

# SecLists
info "Installing SecLists"
clone_or_update https://github.com/danielmiessler/SecLists /opt/seclists

# SharpCollection
info "Installing SharpCollection"
clone_or_update https://github.com/Flangvik/SharpCollection /opt/sharpcollection

# PEASS-NG
info "Fetching PEASS-NG"
run_sudo mkdir -p /opt/PEASS-ng
run_sudo chown -R "$USER:$USER" /opt/PEASS-ng
curl -fL https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh -o /opt/PEASS-ng/linpeas.sh
curl -fL https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASany.exe -o /opt/PEASS-ng/winPEASany.exe
chmod +x /opt/PEASS-ng/linpeas.sh

# Mimikatz
info "Fetching Mimikatz"
run_sudo mkdir -p /opt/mimikatz
run_sudo chown -R "$USER:$USER" /opt/mimikatz
curl -fL https://github.com/gentilkiwi/mimikatz/releases/latest/download/mimikatz_trunk.zip -o /opt/mimikatz/mimikatz.zip
unzip -oq /opt/mimikatz/mimikatz.zip -d /opt/mimikatz

# Extracting rockyou.txt
info "Extracting rockyou.txt"
if [[ -f /usr/share/wordlists/rockyou.txt.gz && ! -f /usr/share/wordlists/rockyou.txt ]]; then
    run_sudo gzip -dk /usr/share/wordlists/rockyou.txt.gz
fi

# Install username-anarchy
info "Installing username-anarchy"
USERNAME_ANARCHY_DIR="$HOME/tools/repos/username-anarchy"
clone_or_update https://github.com/urbanadventurer/username-anarchy.git "$USERNAME_ANARCHY_DIR"
ln -sf "$USERNAME_ANARCHY_DIR/username-anarchy" "$HOME/tools/bin/username-anarchy"

# Tmux
info "Installing Tmux"
apt_update
apt_install_available tmux
if [[ ! -d "$HOME/.tmux/plugins/tpm/.git" ]]; then
    git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
else
    git -C "$HOME/.tmux/plugins/tpm" pull --ff-only
fi
cp "./templates/configurations/tmux/tmux.conf" "$HOME/.tmux.conf"

# Pipx setup path
info "Setting up pipx path"
PIPX_HOME="$HOME/tools/pipx" \
PIPX_BIN_DIR="$HOME/tools/bin" \
PIPX_MAN_DIR="$HOME/tools/pipx/man" \
    pipx ensurepath || true

# Define the output file
output_file="$HOME/tools_to_download.txt"

cat > "$output_file" <<'EOL'
Other tools you can install manually:
  Recommended:
  - Hoaxshell: https://github.com/t3l3machus/hoaxshell
  - Krbrelayx: https://github.com/dirkjanm/krbrelayx
  - Ntdsxtract: https://github.com/csababarta/ntdsxtract
  - PKINITtools https://github.com/dirkjanm/PKINITtools
  - Pretender: https://github.com/RedTeamPentesting/pretender
  - ROADtools: https://github.com/dirkjanm/ROADtools
  - ROADtools_hybrid https://github.com/dirkjanm/roadtools_hybrid
  - Adconnectdump: https://github.com/dirkjanm/adconnectdump
  - LaZagne: https://github.com/AlessandroZ/LaZagne
  - MFASweep: https://github.com/dafthack/MFASweep
EOL

echo -e "\n\n\n\n"
cat "$output_file"

echo -e "\n\n"
echo "Tool recommendations have been saved to $output_file"

if [[ -s "$LOG_DIR/skipped-apt-packages.log" ]]; then
    warn "Some APT packages were unavailable and skipped. See: $LOG_DIR/skipped-apt-packages.log"
fi

info "Shell setup"
echo "Open a new terminal or run 'exec zsh' to load updated PATH and pipx settings."
echo "If Docker/Wireshark group membership changed, log out and back in before using those features."

echo "Setup done."
echo "Happy Hacking :)"
