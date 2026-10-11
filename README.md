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

The interactive display uses green section dividers, cyan prompts, yellow warnings
and red errors. A bottom status line shows the current task, spinner and elapsed
time while command output continues above it. There are no artificial delays or
estimated percentages. Use `--no-progress` to disable the footer, or `NO_COLOR=1`
to disable colours. Redirected output and run logs stay plain text. The footer is
restored on success, failure and Ctrl-C; small or unsupported terminals use normal
step messages instead.

## Choose a profile

| Profile | What you get |
| --- | --- |
| **`core`** | Everyday enumeration and web tools (Nmap, FFUF, Feroxbuster, Gobuster, Burp, Firefox), VPN/network utilities, password tools, wordlists, Wireshark, tmux, Ligolo-ng, Chisel, and PEASS. |
| **`extra`** | Everything in `core`, plus AD/Windows and lab tools (NetExec, Impacket, Certipy, Evil-WinRM, BloodHound CE, Kerbrute, Responder, Metasploit, DonPAPI, etc.), optional wireless/editor/server packages, reference repositories, and PentestManager/zsh/tmux configuration. |

`extra` is the full setup. **It adds the Kali user's zsh integration and installs tmux configuration only if missing.** Existing tmux settings are preserved; use `--replace-config` to back them up and replace them. On `core`, shell configuration is opt-in with `--configure-shell`.

## Useful commands

Run these from the cloned project directory. Replace `qemu` with `vmware`, `virtualbox`, or `none` to match your setup.

| Task | Command |
| --- | --- |
| Full QEMU/KVM setup | `bash weaponize.sh --profile extra --guest qemu` |
| Minimal VMware setup | `bash weaponize.sh --profile core --guest vmware` |
| Install without VM guest tools | `bash weaponize.sh --profile core --guest none` |
| Preview without installing | `bash weaponize.sh --plan --profile extra --guest qemu` |
| Diagnose an existing installation | `bash weaponize.sh --doctor --profile extra --guest qemu` |
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
| uv tool environments | `~/tools/uv` |
| uv/uvx bootstrap (when needed) | `~/tools/uv-bin` |
| Reference/source repositories | `~/tools/repos` |
| SecLists | `/usr/share/seclists` |
| PEASS | `/usr/share/peass` |
| Run logs, backups, package manifests | `~/.local/state/kali-weaponizer/run-*/` |

With `extra` or `--configure-shell`, open a new zsh terminal to pick up `~/tools/bin`, `~/tools/uv-bin` and the uv environment variables in your `PATH`. Otherwise add it yourself or use full paths.

## Troubleshooting

- **Missing required APT package:** Check your Kali repositories and run `sudo apt update`. DNS tools use the real `bind9-dnsutils` package (`dig`, `nslookup`, `nsupdate`), not the virtual `dnsutils` name. The RDP client uses `freerdp-x11` (`xfreerdp`). The script stops rather than silently omitting a required tool; unavailable *optional* packages are skipped with a warning.
- **APT dependency conflict:** Before installation, the script simulates the selected APT transaction with package removals blocked. See `apt-preflight.log` in the run directory for held packages, conflicts or missing dependencies. Repository changes between preflight and installation can still cause failures.
- **VirtualBox on ARM64:** Kali currently does not provide `virtualbox-guest-x11` for ARM64. Use an applicable guest integration option or `--guest none`; the installer reports this before installing packages.
- **VM clipboard/display not working:** Ensure you selected the correct guest platform, then check your hypervisor's guest-agent/SPICE settings and reboot Kali if needed.
- **A command or installation check fails:** See the latest `run.log` and `check-*.log` under `~/.local/state/kali-weaponizer/run-*/`.
- **Existing/customized VM:** This installer assumes a fresh Kali installation. Resolve old installations and command-path conflicts separately; it does not migrate or uninstall them.

For every flag, run `bash weaponize.sh --help`.

## Python tools and uv

Kali-packaged tools (NetExec, Impacket, Certipy, Responder, Coercer, mitm6 and the
BloodHound CE collector) remain under **APT**. DonPAPI is the source-installed
Python application in this version and uses **`uv tool install`**, isolated from
system Python. There is no shared environment or blanket dependency executable exposure.

Both profiles provision uv. An existing uv >= 0.9.17 is reused; otherwise the
installer downloads **uv 0.9.17**, checks its embedded SHA-256 release digest and
installs it into `~/tools/uv-bin`. Bootstrap supports x86_64 and aarch64; other
architectures need a compatible uv already installed. No remote shell script is
executed. Updating the bootstrap version requires updating both embedded hashes.

DonPAPI defaults to a uv-managed Python **3.12** (downloaded when needed), independent
of Kali's system interpreter. `DONPAPI_PYTHON=3.11 bash weaponize.sh ...` selects a
different interpreter if you need one. Compatibility still needs validation on
your VM; choosing an interpreter does not guarantee every dependency works.

For manual management outside configured zsh, use:

```bash
export UV_TOOL_DIR="$HOME/tools/uv"
export UV_TOOL_BIN_DIR="$HOME/tools/bin"
export PATH="$PATH:$HOME/tools/uv-bin:$HOME/tools/bin"
uv tool list
```

Use `--update` to refresh selected tools. A source revision change triggers a
DonPAPI reinstall; ordinary reruns keep the existing matching environment. Source
commits and bootstrap digests are pinned, but APT and transitive Python dependencies
are **not fully locked**. Each run records versions, command paths and DonPAPI's
resolved dependency list. Keep a tested VM snapshot for exact recovery.

## Fresh installations

This installer targets a fresh Kali VM. It does not migrate existing pipx tools,
remove previous installations, edit APT sources or change sudo policy. Existing
command collisions fail with a clear message rather than being overwritten.
The `core` and `extra` profiles can be rerun; use `--update` for explicit updates.

Your existing Kali repository configuration is reused, including Deb822
`kali.sources`. No additional `.list` file is created, so a fresh run does not
introduce the duplicate-source problem from older installers. Existing duplicate
entries need to be resolved separately before installation.

DNS, timezone and locale remain unchanged. The installer performs no broad Java,
PostgreSQL or other package purge and no automatic `autoremove`. `--doctor` checks
the installed tools without changing system configuration (it writes local logs).

## Optional Burp and Firefox configuration

Start Burp yourself, accept its licence and enable the local proxy listener. Then:

```bash
bash weaponize.sh --profile core --guest none --configure-burp
# If BloodHound occupies 8080, configure Burp on 8081 first:
BURP_URL=http://127.0.0.1:8081/cert bash weaponize.sh --profile extra --guest qemu --configure-burp
```

This waits up to 60 seconds for a local `/cert` endpoint, requires a parseable,
unexpired DER CA certificate with a PortSwigger subject, and displays its SHA-256
fingerprint. It never starts or kills Burp. It merges the Firefox template into
existing ESR policies, retaining unrelated policies and existing scalar settings;
certificate/extension lists are deduplicated. `--replace-config` explicitly
replaces conflicting scalar settings after backup. The certificate is trusted by
Firefox through its policy, not installed into the system-wide CA trust store.
Restart Firefox and check `about:policies`. Use this only in your dedicated lab VM.

## Developer checks

These checks do not install tools or modify the host:

```bash
bash -n weaponize.sh
for script in templates/scripts/*.sh; do bash -n "$script"; done
shellcheck weaponize.sh templates/scripts/*.sh
python3 -m unittest discover -s tests -v
bash weaponize.sh --plan --profile extra --guest qemu
```

GitHub Actions runs syntax, ShellCheck, offline workflow/terminal regressions, and
APT dependency simulations for both profiles and all four guest options in a fresh
amd64 Kali rolling container. The container check refreshes indexes but does not
install the selected tools. This catches renamed or unavailable packages and
dependency conflicts before release. Full package
installation, VM integrations, VPN connectivity and BloodHound import still need
testing in a disposable Kali VM before relying on a new release.
