#!/bin/bash

set -euo pipefail
IFS=$'\n\t'


# Function to print steps
info() {
    SLEEP_TIME=1
    local message="[+] $1  "  # Two spaces added after the message
    local green='\e[32m'
    local reset='\e[0m'
    local cols=$(tput cols)
    local message_length=${#message}
    local num_hashes=$((cols - message_length))

    # Print the message in green and fill the rest of the line with green '#'
    echo -e "\n\n"
    echo -e "${green}${message}$(printf '%*s' "$num_hashes" | tr ' ' '#')${reset}"
    sleep $SLEEP_TIME
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

# DNS
info "Setting up google DNS"
if ! grep -q "nameserver 8.8.8.8" /etc/resolv.conf; then
    echo "nameserver 8.8.8.8 # Google" | sudo tee -a /etc/resolv.conf > /dev/null
fi
if ! grep -q "nameserver 8.8.4.4" /etc/resolv.conf; then
    echo "nameserver 8.8.4.4 # Google" | sudo tee -a /etc/resolv.conf > /dev/null
fi

# Setup sources.list
info "Setting up sources.list"
if [ ! -f /etc/apt/sources.list.bak ]; then
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak || true
fi

KALI_LINE="deb http://http.kali.org/kali kali-last-snapshot main contrib non-free non-free-firmware"
if ! grep -qF "$KALI_LINE" /etc/apt/sources.list; then
    echo "$KALI_LINE" | sudo tee /etc/apt/sources.list >/dev/null
fi

# Update packages
info "Updating packages"
sudo apt update

# Remove packages to install them later
PACKAGES_TO_REMOVE=(
    crackmapexec
    bloodhound
    python3-ldapdomaindump
    bloodhound.py
    certipy-ad
    responder
    openjdk*
    oracle-java*
    java-common
    netexec
    postgresql
)
info "Removing packages with apt"
sudo apt remove --purge -y "${PACKAGES_TO_REMOVE[@]}"

# Update packages
info "Upgrading packages"
sudo apt full-upgrade -y
info "Autoremoving packages"
sudo apt autoremove -y
info "Autocleaning packages"
sudo apt autoclean -y

# Install packages

PACKAGES_TO_INSTALL=(
    nmap
    masscan
    wfuzz
    aircrack-ng
    smbclient
    ncat
    wireshark
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
    libtool
    pkg-config
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
    openjdk-25-jdk
    pipx
    python3
    python3-venv
    python3-pip
    golang
    gdb
    zenity
    metasploit-framework
    eza
    postgresql-17
    postgresql-client-17
    hashcat
    wordlists
    rlwrap
    dirbuster
    wpscan
    webshells
    silversearcher-ag
    cupp
    python2-minimal
    freerdp3-x11
    apache2
    neovim
    nikto
)
PACKAGES_TO_INSTALL_NONINTERACTIVE=(
    krb5-user
)
info "Instaling needed packages"
sudo apt install -y "${PACKAGES_TO_INSTALL[@]}"
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES_TO_INSTALL_NONINTERACTIVE[@]}"

## Wireshark configuration
info "Enabling Wireshark non-root capture"
sudo usermod -aG wireshark "$USER" || true

# Install virtualbox-guest-x11
info "Installing virtualbox-guest-x11"
sudo apt install -y --reinstall virtualbox-guest-x11


# Set timezone
info "Setting timezone to Amsterdam"
sudo timedatectl set-timezone Europe/Amsterdam

# Create folders
info "Creating needed folders"
sudo mkdir -p /usr/share/ca-certificates
mkdir -p "$HOME/tools/bin"
mkdir -p "$HOME/tools/repos"

# Add /tools/bin to PATH
info "Adding ~/tools/bin to PATH"
if ! grep -q "export PATH=\$PATH:$HOME/tools/bin" "$HOME/.zshrc"; then
    echo "export PATH=\$PATH:$HOME/tools/bin" >> "$HOME/.zshrc"
fi

# Add ~/tools/bin to secure_path in /etc/sudoers.d
info "Adding ~/tools/bin to sudo secure_path"
USER_HOME="$(getent passwd "$USER" | cut -d: -f6)"
SUDOERS_D="/etc/sudoers.d/99-tools-bin"
TMP_SUDOERS="$(mktemp)"

echo "Defaults secure_path=\"/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${USER_HOME}/tools/bin\"" > "$TMP_SUDOERS"
sudo visudo -c -f "$TMP_SUDOERS" >/dev/null 2>&1
if [ $? -eq 0 ]; then
    sudo install -m 440 "$TMP_SUDOERS" "$SUDOERS_D"
    echo "Successfully added ${USER_HOME}/tools/bin to secure_path in ${SUDOERS_D}"
else
    echo "Error: Invalid sudoers. Change not applied."
fi
rm -f "$TMP_SUDOERS"

# ZSH config
info "Setting up zsh and aliases"
ALIAS_URL="https://raw.githubusercontent.com/P-ict0/PentestManager/main/pentest_aliases.sh"
wget "$ALIAS_URL" -O "$HOME/.zsh_aliases"

if ! grep -qF '[ -f "$HOME/.zsh_aliases" ]' "$HOME/.zshrc"; then
cat <<'EOL' >> "$HOME/.zshrc"
if [ -f "$HOME/.zsh_aliases" ]; then
    . "$HOME/.zsh_aliases"
fi
EOL
fi

info "Setting up pipx"
add_line() { grep -qxF "$1" "$HOME/.zshrc" || echo "$1" >> "$HOME/.zshrc"; }
add_line "export PIPX_HOME='$HOME/tools/pipx'"
add_line "export PIPX_BIN_DIR='$HOME/tools/bin'"
add_line "export PIPX_MAN_DIR=/usr/local/share/man"

# Ensure a locale exists
info "Ensure a locale exists"
if ! grep -q "^en_US.UTF-8 UTF-8" /etc/locale.gen; then
    echo "en_US.UTF-8 UTF-8" | sudo tee -a /etc/locale.gen > /dev/null
    sudo locale-gen
fi

# Set locale
info "Setting locale to en_US.UTF-8"
sudo update-locale LANG=en_US.UTF-8

# Start and enable PostgreSQL service
info "Starting and enabling postgresql"
sudo systemctl enable --now postgresql
sudo -u postgres psql -c "REINDEX DATABASE postgres;" || true
sudo -u postgres psql -c "ALTER DATABASE postgres REFRESH COLLATION VERSION;" || true


# Initialize the MSF database
info "Initializing msfdb"
sudo /usr/bin/msfdb init

# Tools
## BloodHound.py
info "Instaling Bloodhound.py"
PIPX_HOME="$HOME/tools/pipx" PIPX_BIN_DIR="$HOME/tools/bin" PIPX_MAN_DIR=/usr/local/share/man pipx install git+https://github.com/fox-it/BloodHound.py

## Burpsuite
info "Instaling BurpSuite"
sudo apt install -y burpsuite
chmod +x "./templates/scripts/get-burp-certificate.sh"
bash "./templates/scripts/get-burp-certificate.sh"
sudo mv /tmp/burpCA.der /usr/share/ca-certificates/burpCA.der
pgrep -x java >/dev/null && sudo pkill -x java || true
sudo cp "./templates/configurations/firefox/firefox_policies.json" /usr/share/firefox-esr/distribution/policies.json

## Certipy
info "Instaling Certipy"
PIPX_HOME="$HOME/tools/pipx" PIPX_BIN_DIR="$HOME/tools/bin" PIPX_MAN_DIR=/usr/local/share/man pipx install git+https://github.com/ly4k/Certipy

## Coercer
info "Instaling Coercer"
PIPX_HOME="$HOME/tools/pipx" PIPX_BIN_DIR="$HOME/tools/bin" PIPX_MAN_DIR=/usr/local/share/man pipx install git+https://github.com/p0dalirius/Coercer

## Docker
info "Instaling Docker"
sudo apt remove -y docker.io docker-doc docker-compose podman-docker containerd runc
sudo apt update
sudo apt install -y ca-certificates curl gnupg
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg -o /tmp/docker.gpg
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg /tmp/docker.gpg
rm /tmp/docker.gpg
echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian bookworm stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

## BloodHoundCE
info "Instaling BloodHoundCE"
mkdir -p "$HOME/tools/repos/BloodHoundCE"
curl -L https://ghst.ly/getbhce -o "$HOME/tools/repos/BloodHoundCE/docker-compose.yml"

## Impacket
info "Instaling Impacket"
PIPX_HOME="$HOME/tools/pipx" PIPX_BIN_DIR="$HOME/tools/bin" PIPX_MAN_DIR=/usr/local/share/man pipx install git+https://github.com/fortra/impacket

## Kerbrute
info "Instaling Kerbrute"
git clone https://github.com/ropnop/kerbrute "$HOME/tools/repos/Kerbrute"
cd "$HOME/tools/repos/Kerbrute"
make linux
sudo ln -sf "$HOME/tools/repos/Kerbrute/dist/kerbrute_linux_386" "$HOME/tools/bin/kerbrute"
sudo chown "$USER":"$USER" "$HOME/tools/bin/kerbrute"
cd -

## ldapdomaindump
info "Instaling Ldapdomaindump"
PIPX_HOME="$HOME/tools/pipx" PIPX_BIN_DIR="$HOME/tools/bin" PIPX_MAN_DIR=/usr/local/share/man pipx install git+https://github.com/dirkjanm/ldapdomaindump

## Mitm6
info "Instaling Mitm6"
PIPX_HOME="$HOME/tools/pipx" PIPX_BIN_DIR="$HOME/tools/bin" PIPX_MAN_DIR=/usr/local/share/man pipx install git+https://github.com/dirkjanm/mitm6

## NetExec
info "Instaling NetExec"
PIPX_HOME="$HOME/tools/pipx" PIPX_BIN_DIR="$HOME/tools/bin" PIPX_MAN_DIR=/usr/local/share/man pipx install git+https://github.com/Pennyw0rth/NetExec

## Responder
info "Installing Responder"
REPO_DIR="$HOME/tools/repos/Responder"
VENV_DIR="$REPO_DIR/.venv"
if [ ! -d "$REPO_DIR/.git" ]; then
    git clone https://github.com/lgandx/Responder "$REPO_DIR"
else
    git -C "$REPO_DIR" pull --ff-only
fi

python3 -m venv "$VENV_DIR"
source "$VENV_DIR/bin/activate"
pip install --upgrade pip wheel
pip install -r "$REPO_DIR/requirements.txt"
deactivate

cp "./templates/scripts/extract-hashes-responder.sh" "$HOME/tools/bin/extract-hashes-responder"
chmod +x "$HOME/tools/bin/extract-hashes-responder"

mkdir -p "$REPO_DIR/certs"
openssl genrsa -out "$REPO_DIR/certs/responder.key" 2048
sudo openssl req -new -x509 -days 3650 -key "$REPO_DIR/certs/responder.key" -out "$REPO_DIR/certs/responder.crt" -subj "/"

mkdir -p "$REPO_DIR/bin"
cat <<EOL | tee "$REPO_DIR/bin/run_responder.sh" > /dev/null
#!/bin/bash
source "$HOME/tools/repos/Responder/.venv/bin/activate"
"$HOME/tools/repos/Responder/.venv/bin/python" "$HOME/tools/repos/Responder/Responder.py" "\${@:1}"
EOL
chmod +x "$REPO_DIR/bin/run_responder.sh"
ln -sf "$REPO_DIR/bin/run_responder.sh" "$HOME/tools/bin/responder"

## Sublime Text
info "Installing Sublime Text"
curl -fsSL https://download.sublimetext.com/sublimehq-pub.gpg -o /tmp/sublimehq-archive.gpg
sudo mkdir -p /etc/apt/keyrings
sudo gpg --dearmor -o /etc/apt/keyrings/sublimehq-archive.gpg /tmp/sublimehq-archive.gpg
rm /tmp/sublimehq-archive.gpg
echo "deb [signed-by=/etc/apt/keyrings/sublimehq-archive.gpg] https://download.sublimetext.com/ apt/stable/" | sudo tee /etc/apt/sources.list.d/sublime-text.list > /dev/null
sudo apt update
sudo apt install -y sublime-text hunspell-en-us

## DonPAPI
info "Installing DonPAPI"
PIPX_HOME="$HOME/tools/pipx" PIPX_BIN_DIR="$HOME/tools/bin" PIPX_MAN_DIR=/usr/local/share/man pipx install git+https://github.com/login-securite/DonPAPI.git

## PayloadsAllTheThings
info "Installing PayloadsAllTheThings"
sudo git clone https://github.com/swisskyrepo/PayloadsAllTheThings /opt/payloadsallthethings
sudo chown -R "$USER":"$USER" /opt/payloadsallthethings

## SecLists
info "Installing SecLists"
sudo git clone https://github.com/danielmiessler/SecLists /opt/seclists
sudo chown -R "$USER":"$USER" /opt/seclists

## SharpCollection
info "Installing SharpCollection"
sudo git clone https://github.com/Flangvik/SharpCollection /opt/sharpcollection
sudo chown -R "$USER":"$USER" /opt/sharpcollection

## PEASS-NG
info "Fetching PEASS-NG"
sudo mkdir -p /opt/PEASS-ng
sudo chown -R "$USER":"$USER" /opt/PEASS-ng
wget https://github.com/peass-ng/PEASS-ng/releases/latest/download/linpeas.sh -O /opt/PEASS-ng/linpeas.sh
wget https://github.com/peass-ng/PEASS-ng/releases/latest/download/winPEASany.exe -O /opt/PEASS-ng/winPEASany.exe

## Mimikatz
info "Fetching Mimikatz"
sudo mkdir -p /opt/mimikatz
sudo chown -R "$USER":"$USER" /opt/mimikatz
wget https://github.com/gentilkiwi/mimikatz/releases/latest/download/mimikatz_trunk.zip -O /opt/mimikatz/mimikatz.zip
unzip /opt/mimikatz/mimikatz.zip -d /opt/mimikatz

## Extracting rockyou.txt
info "Extracting rockyou.txt"
if [ -f /usr/share/wordlists/rockyou.txt.gz ]; then
    sudo gzip -d -k /usr/share/wordlists/rockyou.txt.gz
fi

## Install username-anarchy
info "Installing username-anarchy"
git clone https://github.com/urbanadventurer/username-anarchy.git "$HOME/tools/repos/username-anarchy"
ln -sf "$HOME/tools/repos/username-anarchy/username-anarchy" "$HOME/tools/bin/username-anarchy"

## Tmux
info "Installing Tmux"
sudo apt update
sudo apt install -y tmux
if [ ! -d "$HOME/.tmux/plugins/tpm/.git" ]; then
  git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
else
  git -C "$HOME/.tmux/plugins/tpm" pull --ff-only
fi
cp "./templates/configurations/tmux/tmux.conf" "$HOME/.tmux.conf"

# Pipx setup path
info "Setting up pipx path"
PIPX_HOME="$HOME/tools/pipx" PIPX_BIN_DIR="$HOME/tools/bin" PIPX_MAN_DIR=/usr/local/share/man pipx ensurepath

# Define the output file
output_file="$HOME/tools_to_download.txt"

# Write to the file
echo "Other tools you can install manually:" > "$output_file"
echo "  Recommended:" >> "$output_file"
echo "  - Hoaxshell: https://github.com/t3l3machus/hoaxshell" >> "$output_file"
echo "  - Krbrelayx: https://github.com/dirkjanm/krbrelayx" >> "$output_file"
echo "  - Ntdsxtract: https://github.com/csababarta/ntdsxtract" >> "$output_file"
echo "  - PKINITtools https://github.com/dirkjanm/PKINITtools" >> "$output_file"
echo "  - Pretender: https://github.com/RedTeamPentesting/pretender" >> "$output_file"
echo "  - ROADtools: https://github.com/dirkjanm/ROADtools" >> "$output_file"
echo "  - ROADtools_hybrid https://github.com/dirkjanm/roadtools_hybrid" >> "$output_file"
echo "  - Adconnectdump: https://github.com/dirkjanm/adconnectdump" >> "$output_file"
echo "  - LaZagne: https://github.com/AlessandroZ/LaZagne" >> "$output_file"
echo "  - MFASweep: https://github.com/dafthack/MFASweep" >> "$output_file"

# Print the list to the console
echo -e "\n\n\n\n"
cat "$output_file"

echo -e "\n\n"
echo "Tool recommendations have been saved to $output_file"

info "Shell setup"
echo "Open a new terminal or 'exec zsh' to load updated PATH and pipx settings."


echo "Setup done!!"

echo "Happy Hacking :)"
