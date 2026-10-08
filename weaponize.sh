#!/usr/bin/env bash
# Kali guest provisioning. Sourcing this file only defines functions for tests.
set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODE=install
PROFILE=""
VIRTUALIZATION_PLATFORM=""
EXTRAS=""
CONFIGURE_SHELL=0
SETUP_BLOODHOUND=0
CHECK_BLOODHOUND=0
UPGRADE_SYSTEM=0
REQUIRED_PACKAGES=()
OPTIONAL_PACKAGES=()
SKIPPED_PACKAGES=()
# Fixed source revisions captured on 2026-10-08; update deliberately.
KERBRUTE_REV=9cfb81e4fab8037acb44c678773ca3f93bc2b39c
PENTESTMANAGER_REV=1b32d010e8112717a533c0f2126e36539d3c7a7b
TPM_REV=e261deb1b47614eed3400089ce7197dc68acc4eb
DONPAPI_REV=4f01e2b893d3dfbc327b68797943cc2f00c5dd94
PAYLOADS_REV=3ac27901c711bdf3f5b65a7b1d1820a1f65bd09a
SHARPCOLLECTION_REV=c53d7eb583d853de0bd693c1bb61581d59b2f44e
USERNAME_ANARCHY_REV=e0631915ee90afb7ffcabf7900043927ef2f8934

info() { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die() { warn "$*"; exit 1; }
run_sudo() { sudo "$@"; }
have_systemd() { command -v systemctl >/dev/null && [[ -d /run/systemd/system ]]; }
has_extra() { [[ ",$EXTRAS," == *",$1,"* ]]; }

usage() {
    cat <<'USAGE'
Usage: bash weaponize.sh [options]
  --profile core|extra   Prompt if omitted; profiles are additive.
  --guest qemu|vmware|virtualbox|none
                           Prompt if omitted during install/update.
  --extras LIST            Comma-separated: wireless,editors,servers,references
  --configure-shell        Install pinned PentestManager/TPM; configure zsh/tmux.
  --update                 Upgrade selected APT tools (source pins stay fixed).
  --upgrade-system         Also full-upgrade Kali; requires --update.
  --verify                 Check installed packages and local CLI smoke tests only.
  --verify-bloodhound       Verify mode plus local BloodHound HTTP readiness.
  --setup-bloodhound        Run interactive Kali BloodHound setup/start after install.
  --plan                   Print package selections without writes/sudo/network.
  -h, --help               Show this help.

Run as your normal user inside Kali, not as root or on the Arch/Windows host.
None skips guest integrations only; --plan and --verify do not download anything.
USAGE
}

parse_args() {
    while (( $# )); do
        case "$1" in
            --profile|--guest|--extras)
                (( $# >= 2 )) && [[ "$2" != --* ]] || die "Missing value for $1"
                case "$1" in
                    --profile) PROFILE="$2" ;;
                    --guest) VIRTUALIZATION_PLATFORM="$2" ;;
                    --extras) EXTRAS="$2" ;;
                esac
                shift 2 ;;
            --update|--verify|--verify-bloodhound|--plan)
                [[ "$MODE" == install ]] || die "Choose one action: update, verify, or plan."
                case "$1" in
                    --update) MODE=update ;;
                    --plan) MODE=plan ;;
                    --verify) MODE=verify ;;
                    --verify-bloodhound) MODE=verify; CHECK_BLOODHOUND=1 ;;
                esac
                shift ;;
            --upgrade-system) UPGRADE_SYSTEM=1; shift ;;
            --setup-bloodhound) SETUP_BLOODHOUND=1; shift ;;
            --configure-shell) CONFIGURE_SHELL=1; shift ;;
            -h|--help) usage; exit 0 ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    [[ -z "$PROFILE" || "$PROFILE" =~ ^(core|extra)$ ]] || die "Invalid profile: $PROFILE"
    [[ -z "$VIRTUALIZATION_PLATFORM" || "$VIRTUALIZATION_PLATFORM" =~ ^(qemu|vmware|virtualbox|none)$ ]] || die "Invalid guest platform"
    local extra
    local -a selected_extras=()
    if [[ -n "$EXTRAS" ]]; then
        [[ "$EXTRAS" != ,* && "$EXTRAS" != *, && "$EXTRAS" != *,,* ]] || die "Invalid extras list"
        IFS=',' read -r -a selected_extras <<< "$EXTRAS"
        for extra in "${selected_extras[@]}"; do
            [[ "$extra" =~ ^(wireless|editors|servers|references)$ ]] || die "Unknown extra: $extra"
        done
    fi
    (( ! UPGRADE_SYSTEM )) || [[ "$MODE" == update ]] || die "--upgrade-system requires --update"
    (( ! SETUP_BLOODHOUND )) || [[ "$MODE" == install || "$MODE" == update ]] || die "Setup cannot run in read-only modes"
}

select_options() {
    local choice
    if [[ -z "$PROFILE" ]]; then
        [[ -t 0 ]] || die "Non-interactive runs require --profile"
        read -r -p 'Profile: 1) Core  2) Extra (all tools) [2]: ' choice || die "Input closed"
        case "${choice:-2}" in
            1) PROFILE=core ;;
            2) PROFILE=extra ;;
            *) die "Invalid profile selection" ;;
        esac
    fi
    if [[ -z "$VIRTUALIZATION_PLATFORM" ]]; then
        if [[ "$MODE" == plan || "$MODE" == verify ]]; then
            VIRTUALIZATION_PLATFORM=none
        else
            [[ -t 0 ]] || die "Non-interactive runs require --guest"
            read -r -p 'Guest: 1) QEMU/KVM  2) VMware  3) VirtualBox  4) None: ' choice || die "Input closed"
            case "$choice" in
                1) VIRTUALIZATION_PLATFORM=qemu ;; 2) VIRTUALIZATION_PLATFORM=vmware ;;
                3) VIRTUALIZATION_PLATFORM=virtualbox ;; 4) VIRTUALIZATION_PLATFORM=none ;;
                *) die "Invalid guest selection" ;;
            esac
        fi
    fi
    if (( SETUP_BLOODHOUND || CHECK_BLOODHOUND )); then
        [[ "$PROFILE" != core ]] || die "BloodHound requires the extra profile"
    fi

    if [[ "$PROFILE" == extra ]]; then
        EXTRAS="wireless,editors,servers,references"
        CONFIGURE_SHELL=1
    fi
}

build_package_lists() {
    REQUIRED_PACKAGES=(
        ca-certificates curl wget git unzip build-essential python3 python3-venv pipx
        nmap ncat smbclient enum4linux-ng exploitdb gobuster feroxbuster ffuf
        burpsuite firefox-esr nikto openvpn iproute2 dnsutils net-tools
        socat proxychains4 openssh-client john hydra hashcat wordlists seclists
        tmux asciinema rlwrap jq neovim xclip flameshot tcpdump wireshark
        ligolo-ng ligolo-ng-common-binaries chisel peass
    )
    OPTIONAL_PACKAGES=()
    if [[ "$PROFILE" != core ]]; then
        REQUIRED_PACKAGES+=(
            netexec python3-impacket impacket-scripts certipy-ad evil-winrm
            bloodhound bloodhound-ce-python python3-ldapdomaindump
            krb5-user freerdp3-x11 metasploit-framework postgresql postgresql-client
            mimikatz powersploit windows-binaries golang
        )
    fi
    if [[ "$PROFILE" == extra ]]; then
        REQUIRED_PACKAGES+=(coercer mitm6 responder)
        OPTIONAL_PACKAGES+=(masscan eyewitness wpscan webshells cupp bettercap)
    fi
    case "$VIRTUALIZATION_PLATFORM" in
        qemu) REQUIRED_PACKAGES+=(qemu-guest-agent spice-vdagent) ;;
        vmware) REQUIRED_PACKAGES+=(open-vm-tools open-vm-tools-desktop) ;;
        virtualbox) REQUIRED_PACKAGES+=(virtualbox-guest-x11) ;;
    esac
    if has_extra wireless; then OPTIONAL_PACKAGES+=(aircrack-ng realtek-rtl88xxau-dkms); fi
    if has_extra editors; then OPTIONAL_PACKAGES+=(code-oss); fi
    if has_extra servers; then OPTIONAL_PACKAGES+=(apache2 vsftpd docker.io docker-compose); fi
    if has_extra references; then REQUIRED_PACKAGES+=(ruby); fi
    if (( CONFIGURE_SHELL )); then REQUIRED_PACKAGES+=(zsh eza); fi
}

show_plan() {
    printf 'Action: %s\nProfile: %s\nGuest: %s\nExtras: %s\n' "$MODE" "$PROFILE" "$VIRTUALIZATION_PLATFORM" "${EXTRAS:-none}"
    printf '\nRequired APT packages:\n'; printf '  %s\n' "${REQUIRED_PACKAGES[@]}"
    if (( ${#OPTIONAL_PACKAGES[@]} )); then
        printf '\nOptional APT packages (unavailable packages are reported):\n'
        printf '  %s\n' "${OPTIONAL_PACKAGES[@]}"
    fi
    [[ "$PROFILE" == core ]] || printf '\nPinned Kerbrute: %s\n' "$KERBRUTE_REV"
    [[ "$PROFILE" != extra ]] || printf 'Pinned DonPAPI: %s\n' "$DONPAPI_REV"
    if (( CONFIGURE_SHELL )); then printf 'Pinned PentestManager/TPM; zsh and tmux configuration enabled.\n'; fi
    if has_extra references; then printf 'Pinned PayloadsAllTheThings, SharpCollection and username-anarchy enabled.\n'; fi
    return 0
}

require_kali_user() {
    (( EUID != 0 )) || die "Run as your normal Kali user; the script invokes sudo when needed."
    [[ -r /etc/os-release ]] || die "Cannot identify the operating system"
    local ID=""
    # shellcheck disable=SC1091
    source /etc/os-release
    [[ "$ID" == kali ]] || die "This installer is for Kali guests only (detected: $ID)."
}

apt_candidate() {
    local output candidate
    output="$(LC_ALL=C apt-cache policy "$1")" || return 2
    candidate="$(awk '/^[[:space:]]*Candidate:/ { print $2; exit }' <<< "$output")"
    [[ -n "$candidate" && "$candidate" != '(none)' ]]
}

select_available_packages() {
    AVAILABLE_PACKAGES=()
    SKIPPED_PACKAGES=()
    local pkg status
    local -a missing=()
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if apt_candidate "$pkg"; then
            AVAILABLE_PACKAGES+=("$pkg")
        else
            status=$?
            (( status == 1 )) || die "APT query failed for $pkg"
            missing+=("$pkg")
        fi
    done
    (( ${#missing[@]} == 0 )) || die "Required packages unavailable: ${missing[*]}. Check your Kali repositories/suite; no packages were installed."
    for pkg in "${OPTIONAL_PACKAGES[@]}"; do
        if apt_candidate "$pkg"; then
            AVAILABLE_PACKAGES+=("$pkg")
        else
            status=$?
            (( status == 1 )) || die "APT query failed for optional package $pkg"
            SKIPPED_PACKAGES+=("$pkg")
            warn "Optional package unavailable: $pkg"
        fi
    done
}

install_packages() {
    # Install mode leaves already-installed selected packages alone. Dependencies
    # may still change to satisfy APT. --no-remove prevents accidental removals.
    local -a flags=(--no-remove)
    [[ "$MODE" != install ]] || flags+=(--no-upgrade)
    run_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${flags[@]}" "${AVAILABLE_PACKAGES[@]}"
}

checkout_pinned() {
    local url="$1" dest="$2" revision="$3" actual
    [[ "$revision" =~ ^[0-9a-f]{40}$ ]] || die "Source pin must be a full commit ID"
    if [[ ! -e "$dest" ]]; then
        mkdir -p "$dest"
        git -C "$dest" init -q
        git -C "$dest" remote add origin "$url"
    fi
    [[ -d "$dest/.git" ]] || die "Refusing to replace non-repository: $dest"
    [[ "$(git -C "$dest" remote get-url origin)" == "$url" ]] || die "Unexpected origin in $dest"
    [[ -z "$(git -C "$dest" status --porcelain)" ]] || die "Local changes in $dest; preserve them before installing"
    if ! git -C "$dest" cat-file -e "$revision^{commit}" 2>/dev/null; then
        git -C "$dest" fetch --depth 1 origin "$revision"
    fi
    git -C "$dest" checkout --detach "$revision"
    actual="$(git -C "$dest" rev-parse HEAD)"
    [[ "$actual" == "$revision" ]] || die "Source revision verification failed: $dest"
    printf '%s\t%s\t%s\n' "$url" "$revision" "$dest" >> "$RUN_DIR/sources.tsv"
}

go_arch() {
    case "$1" in
        x86_64|amd64) printf 'amd64\n' ;;
        aarch64|arm64) printf 'arm64\n' ;;
        i386|i686) printf '386\n' ;;
        *) die "Unsupported Kerbrute architecture: $1" ;;
    esac
}

install_kerbrute() {
    local dest="$HOME/tools/repos/kerbrute-pinned" arch
    checkout_pinned https://github.com/ropnop/kerbrute.git "$dest" "$KERBRUTE_REV"
    arch="$(go_arch "$(uname -m)")"
    # Build directly for this guest; never pick an arbitrary file from dist/.
    (cd "$dest" && CGO_ENABLED=0 GOOS=linux GOARCH="$arch" go build -mod=readonly -trimpath -o "$HOME/tools/bin/kerbrute" .)
    sha256sum "$HOME/tools/bin/kerbrute" >> "$RUN_DIR/binaries.sha256"
}

install_donpapi() {
    local dest="$HOME/tools/repos/donpapi-pinned"
    local marker="$PIPX_HOME/.weaponizer-donpapi-revision"
    checkout_pinned https://github.com/login-securite/DonPAPI.git "$dest" "$DONPAPI_REV"
    # An isolated environment; no system Python modifications.
    # --force is confined to this application's environment, never --include-deps.
    if [[ "$MODE" == install && -x "$PIPX_BIN_DIR/DonPAPI" && -f "$marker" ]] &&
        [[ "$(cat "$marker")" == "$DONPAPI_REV" ]]; then
        info "Keeping the installed DonPAPI environment; use --update to refresh it."
    else
        pipx install --force "$dest"
        printf '%s\n' "$DONPAPI_REV" > "$marker"
    fi
    pipx runpip donpapi freeze > "$RUN_DIR/donpapi-python-freeze.txt"
}

configure_shell() {
    local pm="${XDG_CONFIG_HOME:-$HOME/.config}/PentestManager"
    local tpm="$HOME/.tmux/plugins/tpm" file
    checkout_pinned https://github.com/P-ict0/PentestManager.git "$pm" "$PENTESTMANAGER_REV"
    checkout_pinned https://github.com/tmux-plugins/tpm "$tpm" "$TPM_REV"
    for file in "$HOME/.zshrc" "$HOME/.tmux.conf"; do
        if [[ -f "$file" ]]; then cp -p "$file" "$RUN_DIR/$(basename "$file").before"; fi
    done
    touch "$HOME/.zshrc"
    if ! grep -qF '# Kali Weaponizer tools path' "$HOME/.zshrc"; then
        cat >> "$HOME/.zshrc" <<'ZSH'

# Kali Weaponizer tools path
export PATH="$PATH:$HOME/tools/bin"
export PIPX_HOME="$HOME/tools/pipx"
export PIPX_BIN_DIR="$HOME/tools/bin"
export PIPX_MAN_DIR="$HOME/tools/pipx/man"
ZSH
    fi
    if ! grep -qF '# PentestManager (autoload)' "$HOME/.zshrc"; then
        cat >> "$HOME/.zshrc" <<'ZSH'

# PentestManager (autoload)
if [[ -o interactive ]]; then
    source "${XDG_CONFIG_HOME:-$HOME/.config}/PentestManager/src/init.zsh"
fi
ZSH
    fi
    cp "$SCRIPT_DIR/templates/configurations/tmux/tmux.conf" "$HOME/.tmux.conf"
}

install_references() {
    checkout_pinned https://github.com/swisskyrepo/PayloadsAllTheThings "$HOME/tools/repos/PayloadsAllTheThings" "$PAYLOADS_REV"
    checkout_pinned https://github.com/Flangvik/SharpCollection "$HOME/tools/repos/SharpCollection" "$SHARPCOLLECTION_REV"
    checkout_pinned https://github.com/urbanadventurer/username-anarchy.git "$HOME/tools/repos/username-anarchy" "$USERNAME_ANARCHY_REV"
    ln -sfn "$HOME/tools/repos/username-anarchy/username-anarchy" "$HOME/tools/bin/username-anarchy"
}

configure_guest() {
    local service=""
    case "$VIRTUALIZATION_PLATFORM" in
        qemu) service=qemu-guest-agent ;;
        vmware) service=open-vm-tools ;;
    esac
    if [[ -n "$service" ]] && have_systemd; then
        # QEMU agents can be static/device-activated; starting is sufficient.
        if ! run_sudo systemctl start "$service"; then
            warn "Guest tools installed but $service did not start; check hypervisor channels/reboot."
            printf '%s\n' "$service" >> "$RUN_DIR/service-warnings.txt"
        fi
    fi
}

verify_installation() {
    local pkg cmd failed=0
    local -a smoke=(nmap ffuf feroxbuster gobuster openvpn socat chisel ligolo-proxy)
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if [[ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null || true)" != 'install ok installed' ]]; then
            warn "Required package missing/unconfigured: $pkg"; failed=1
        fi
    done
    if [[ "$PROFILE" != core ]]; then
        smoke+=(nxc impacket-smbclient certipy-ad bloodhound-ce-python kerbrute)
        for cmd in bloodhound-setup bloodhound-start bloodhound-stop evil-winrm; do
            if ! command -v "$cmd" >/dev/null; then warn "Missing command: $cmd"; failed=1; fi
        done
    fi
    if [[ "$PROFILE" == extra ]]; then smoke+=(coercer mitm6 responder DonPAPI); fi
    for cmd in "${smoke[@]}"; do
        if ! command -v "$cmd" >/dev/null; then
            warn "Missing command: $cmd"; failed=1
        elif ! timeout 30 "$cmd" -h > "$RUN_DIR/check-$cmd.log" 2>&1; then
            warn "CLI smoke test failed: $cmd (see check-$cmd.log)"; failed=1
        fi
    done
    if [[ ! -s /usr/share/peass/linpeas/linpeas.sh || ! -s /usr/share/peass/winpeas/winPEASany.exe ]]; then
        warn "PEASS target files are missing"; failed=1
    fi
    if ! dpkg-query -L ligolo-ng-common-binaries > "$RUN_DIR/ligolo-agent-files.txt"; then
        warn "Cannot list Ligolo agent files"; failed=1
    elif ! grep -Eq 'windows.*amd64.*\.exe$' "$RUN_DIR/ligolo-agent-files.txt"; then
        warn "Windows amd64 Ligolo agent not found"; failed=1
    fi
    if (( CONFIGURE_SHELL )); then
        if ! zsh -n "$HOME/.zshrc"; then warn "Invalid zsh configuration"; failed=1; fi
    fi
    if (( CHECK_BLOODHOUND )); then
        # A UI check is separate from CLI installation and data-import testing.
        if ! curl --noproxy '*' -fsSL --max-time 15 http://127.0.0.1:8080/ui/login > "$RUN_DIR/bloodhound-ui.html"; then
            warn "BloodHound UI is not reachable on localhost:8080"; failed=1
        elif ! grep -qi bloodhound "$RUN_DIR/bloodhound-ui.html"; then
            warn "Port 8080 responded but does not appear to serve BloodHound"; failed=1
        fi
    fi
    (( failed == 0 ))
}

write_manifest() {
    {
        printf 'Timestamp: %s\nProfile: %s\nGuest: %s\nExtras: %s\n' "$(date -u +%FT%TZ)" "$PROFILE" "$VIRTUALIZATION_PLATFORM" "$EXTRAS"
        printf 'Installer HEAD: '; git -C "$SCRIPT_DIR" rev-parse HEAD
        printf 'Installer SHA256: '; sha256sum "$SCRIPT_DIR/weaponize.sh"
        uname -srmo
    } > "$RUN_DIR/environment.txt"
    dpkg-query -W -f='${binary:Package}\t${Version}\t${Status}\n' > "$RUN_DIR/apt-packages.tsv"
    pipx list --json > "$RUN_DIR/pipx.json"
    if (( ${#SKIPPED_PACKAGES[@]} )); then printf '%s\n' "${SKIPPED_PACKAGES[@]}" > "$RUN_DIR/skipped-apt-packages.txt"; fi
}

main() {
    parse_args "$@"
    select_options
    build_package_lists
    show_plan
    [[ "$MODE" != plan ]] || return 0
    require_kali_user
    export PATH="$PATH:$HOME/tools/bin"
    export PIPX_HOME="$HOME/tools/pipx" PIPX_BIN_DIR="$HOME/tools/bin" PIPX_MAN_DIR="$HOME/tools/pipx/man"
    local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/kali-weaponizer"
    mkdir -p "$state_dir"
    RUN_DIR="$(mktemp -d "$state_dir/run-$(date -u +%Y%m%dT%H%M%SZ)-XXXXXX")"
    export RUN_DIR
    exec > >(tee "$RUN_DIR/run.log") 2>&1
    trap 'warn "Failed on line $LINENO. Logs: $RUN_DIR"' ERR
    if [[ "$MODE" == verify ]]; then
        verify_installation
        info "Local verification passed. Logs: $RUN_DIR"
        return 0
    fi
    sudo -v
    info "Refreshing existing APT sources (DNS and repository configuration are preserved)"
    run_sudo apt-get -o APT::Update::Error-Mode=any update
    select_available_packages
    if (( UPGRADE_SYSTEM )); then
        run_sudo env DEBIAN_FRONTEND=noninteractive apt-get --no-remove full-upgrade -y
    fi
    install_packages
    mkdir -p "$HOME/tools/bin" "$HOME/tools/repos" "$HOME/tools/pipx/man"
    if [[ "$PROFILE" != core ]]; then install_kerbrute; fi
    if [[ "$PROFILE" == extra ]]; then
        install_donpapi
        install -m 755 "$SCRIPT_DIR/templates/scripts/extract-hashes-responder.sh" "$HOME/tools/bin/extract-hashes-responder"
    fi
    if has_extra references; then install_references; fi
    if (( CONFIGURE_SHELL )); then configure_shell; fi
    configure_guest
    if [[ -f /usr/share/wordlists/rockyou.txt.gz && ! -f /usr/share/wordlists/rockyou.txt ]]; then
        run_sudo gzip -dk /usr/share/wordlists/rockyou.txt.gz
    fi
    if (( SETUP_BLOODHOUND )); then
        run_sudo bloodhound-setup
        run_sudo bloodhound-start
        CHECK_BLOODHOUND=1
    fi
    write_manifest
    verify_installation
    if (( ${#SKIPPED_PACKAGES[@]} )) || [[ -s "$RUN_DIR/service-warnings.txt" ]]; then
        warn "Required tool checks passed with optional/guest-service warnings. Review $RUN_DIR"
    else
        info "Required package and CLI checks passed. Manifest/logs: $RUN_DIR"
    fi
    if [[ "$PROFILE" != core ]] && (( ! CHECK_BLOODHOUND )); then
        warn "BloodHound is installed; service readiness and data import are NOT verified. See README setup steps."
    fi
    info 'Before an exam: test VPN/DNS, BloodHound data import, screenshots and reporting; then snapshot the VM.'
    info 'Tools bin: ~/tools/bin (add to your guest shell PATH or use explicit paths).'
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
