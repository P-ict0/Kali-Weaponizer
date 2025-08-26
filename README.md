<div align = center>

# ☠️ Kali Weaponizer

**Prepare your Kali Linux for HTB, CTFs, OSCP, ...**

Script to weaponize Kali Linux with tools and configurations.
</div>

# 📦 Installation

**This works on a fresh Kali Linux installation**

```bash
git clone https://github.com/P-ict0/Kali-Weaponizer
cd Kali-Weaponizer
chmod +x weaponize.sh
./weaponize.sh
```

# 📜 Features

- Update and upgrade Kali Linux
- Install tools in their own environment
- Setup system configurations (aliases, etc...)

# 🛠️ Configurations

- Adds google DNS to `/etc/resolv.conf`
- Updates `sources.list` to use last snapshot
- Updates and upgrades `apt` packages
- Installs virtualbox guest additions
- Creates folders for tools and adds it to PATH
- Adds aliases to `~/.zsh_aliases` (see below)
- Sets up locales
- Extracts `rockyou.txt`
...

# 🧰 Tools

- Bloodhound
- Burp Suite
    - Extracts CA certificate
- Firefox
    - Configures Burp certificate
    - Installs extensions (FoxyProxy, and Wappalyzer)
- Certipy
- Coercer
- Docker
- Impacket
- Kerbrute
- Ldapdomaindump
- Mitm6
- NetExec (former crackmapexec)
- Responder
    - Generates certificates
- Sublime Text
- DonPAPI
- PayloadsAllTheThings
- SecLists
- SharpCollection
- Tmux
    - Also sets up configuration to enable mouse scrolling, copy-pasting, etc...


# 📝 Aliases and useful commands

Aliases are part of another repository of mine, have a look over there for reference:
https://github.com/P-ict0/PentestManager


They include things like:
- File listing with colors
- Extract ports from nmap output
- Initialize a directory for a new target with directories for notes, exploits, loot, etc...
- Aliases to setup virtual environments for Python


# 🛠️ Quick reference

- Impacket scripts: Don't run `impacket-<tool>`, use `<tool>.py`.
- Start BloodHound CE: `cd ~/tools/repos/BloodHoundCE && docker compose up -d`.
- Wordlists location: `/usr/share/wordlists`, `/opt/seclists`, `/opt/payloadsallthethings`.
- Post‑install notes: `~/tools_to_download.txt`.
- Tool locations: Nearly all tools installed are in their `dev` versions, taken from their respective repositories.
    - Repos: By default in `~/tools/repos/`
    - Binaries: Symlinks in `~/tools/bin/` (added to PATH)


# ✏️ Customization

In `weaponize.sh`:

- Timezone: change Europe/Amsterdam to your zone in `timedatectl set-timezone`.
- Locale: adjust en_US.UTF-8 as needed (`/etc/locale.gen`, `update-locale`).
- DNS: remove/alter the two `nameserver` tee lines.
- APT sources: replace the `KALI_LINE` with your preferred sources (or skip the whole block).
- APT packages: add or remove packages as needed.
- Tools: Add or remove blocks as needed.

In the templates:
- TMUX/Firefox configuration: adjust settings in `./templates/configurations/`.
