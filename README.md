# Kali Weaponizer

Set up a **Kali Linux VM** for Hack The Box, CTFs, and OSCP-style labs with a single script. Choose a tool profile and your VM platform; the script installs the matching packages and checks the result.

## Quick start

Run **inside Kali**, as your regular user (not root). You need a working internet connection, `sudo`, and Kali APT repositories.

```bash
git clone https://github.com/P-ict0/Kali-Weaponizer.git
cd Kali-Weaponizer
bash weaponize.sh
```

The menu asks you to choose:

1. **Profile:** `core` or `extra` (default: `extra`).
2. **VM platform:** QEMU/KVM, VMware, VirtualBox, or None.

Only the selected platform's **guest integration packages** are added. **None does not mean “install nothing”**—it skips guest tools only.

Want to see what would be installed first? Run:

```bash
bash weaponize.sh --plan --profile extra --guest qemu
```

`--plan` makes no changes and downloads nothing.

## Choose a profile

| Profile | What you get |
| --- | --- |
| **`core`** | Everyday enumeration and web tools (Nmap, FFUF, Feroxbuster, Gobuster, Burp, Firefox), VPN/network utilities, password tools, wordlists, Wireshark, tmux, Ligolo-ng, Chisel, and PEASS. |
| **`extra`** | Everything in `core`, plus AD/Windows and lab tools (NetExec, Impacket, Certipy, Evil-WinRM, BloodHound CE, Kerbrute, Responder, Metasploit, DonPAPI, etc.), optional wireless/editor/server packages, reference repositories, and PentestManager/zsh/tmux configuration. |

`extra` is the full setup. **It automatically configures the Kali user's zsh and replaces `~/.tmux.conf`** (backing up the existing file in the run logs). On `core`, shell configuration is opt-in with `--configure-shell`.

## Useful commands

Run these from the cloned project directory. Replace `qemu` with `vmware`, `virtualbox`, or `none` to match your setup.

| Task | Command |
| --- | --- |
| Full QEMU/KVM setup | `bash weaponize.sh --profile extra --guest qemu` |
| Minimal VMware setup | `bash weaponize.sh --profile core --guest vmware` |
| Install without VM guest tools | `bash weaponize.sh --profile core --guest none` |
| Preview without installing | `bash weaponize.sh --plan --profile extra --guest qemu` |
| Verify existing installation | `bash weaponize.sh --verify --profile extra --guest qemu` |
| Update selected tools | `bash weaponize.sh --update --profile extra --guest qemu` |
| Update tools **and Kali itself** | `bash weaponize.sh --update --upgrade-system --profile extra --guest qemu` |

For a smaller `core` setup with selected additions:

```bash
bash weaponize.sh --profile core --guest qemu --extras wireless,editors
```

Available extras: `wireless`, `editors`, `servers`, `references`. The `extra` profile enables all four automatically.

**Tip:** Take a VM snapshot before installing or upgrading, especially before a course, CTF, or exam. Standard installs don't explicitly upgrade packages already installed; `--update` does. Package removals are blocked by the installer.

## After installation

**1. Check the tools** (the installer also runs local checks when it finishes):

```bash
bash weaponize.sh --verify --profile extra --guest qemu
```

Use `core` instead if you installed `core`. Verification checks packages and local commands; it does **not** test connectivity to HTB or run scans against targets.

**2. Test your lab VPN and network:**

```bash
sudo openvpn /path/to/lab.ovpn
ip addr
ip route
```

Check that lab hosts and, for AD labs, domain DNS resolve correctly. Also test Burp, screenshots, and VM clipboard integration before you need them.

**3. Set up BloodHound CE** (only for `extra`, if you plan to use it):

```bash
sudo bloodhound-setup
sudo bloodhound-start
bash weaponize.sh --verify-bloodhound --profile extra --guest qemu
```

Follow any setup instructions about the Neo4j password. Open **http://127.0.0.1:8080/ui/login** and test an import from an authorized lab. BloodHound CE uses Kali's native installation—not Docker. If Burp also uses port 8080, move its proxy listener to another port (such as 8081). Stop BloodHound with `sudo bloodhound-stop`.

**4. Take a working VM snapshot** and keep notes/reports backed up outside the VM.

## Where things go

| Item | Location |
| --- | --- |
| Standalone tools (e.g. Kerbrute, DonPAPI) | `~/tools/bin` |
| Reference/source repositories | `~/tools/repos` |
| SecLists | `/usr/share/seclists` |
| PEASS | `/usr/share/peass` |
| Run logs, backups, package manifests | `~/.local/state/kali-weaponizer/run-*/` |

With `extra` or `--configure-shell`, open a new zsh terminal to pick up `~/tools/bin` in your `PATH`. Otherwise add it yourself or use full paths.

## Troubleshooting

- **Missing required APT package:** Check your Kali repositories and run `sudo apt update`. The script stops rather than silently omitting a required tool; unavailable *optional* packages are skipped with a warning.
- **VM clipboard/display not working:** Ensure you selected the correct guest platform, then check your hypervisor's guest-agent/SPICE settings and reboot Kali if needed.
- **A command or installation check fails:** See the latest `run.log` and `check-*.log` under `~/.local/state/kali-weaponizer/run-*/`.
- **Upgrading a previously customized VM:** Existing tools and old configurations are not automatically removed. Review potential conflicts before changing an established setup.

For every flag, run `bash weaponize.sh --help`.
