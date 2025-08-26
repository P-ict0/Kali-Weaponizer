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
