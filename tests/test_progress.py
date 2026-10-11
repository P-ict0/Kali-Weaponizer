"""Package preflight, workflow and real PTY regressions; never install on the host."""
import errno
import fcntl
import os
import pty
import select
import struct
import subprocess
import termios
import time
import unittest
import test_installer

ROOT = test_installer.ROOT


class Workflow(unittest.TestCase):
    run_shell = test_installer.Shell.run_shell

    def test_dns_is_a_concrete_package(self):
        self.run_shell('''PROFILE=core; VIRTUALIZATION_PLATFORM=none; build_package_lists
apt-cache() {
    if [[ "$2" == dnsutils ]]; then printf '  Candidate: (none)\\n'
    else printf '  Candidate: 1.0\\n'; fi
}
select_available_packages
[[ " ${AVAILABLE_PACKAGES[*]} " == *bind9-dnsutils* ]]
''')

    def test_preflight_dependency_failure_stops_before_install(self):
        result = self.run_shell('''RUN_DIR="$HOME"; REQUIRED_PACKAGES=(test-package)
apt_candidate() { return 0; }
run_sudo() { printf 'mock dependency conflict\\n'; return 100; }
preflight_packages
echo UNEXPECTED_INSTALL
''', good=False)
        self.assertIn('APT dependency preflight failed', result.stderr)
        self.assertNotIn('UNEXPECTED_INSTALL', result.stdout)

    def test_simulation_and_install_use_same_flags(self):
        self.run_shell('''RUN_DIR="$HOME"; REQUIRED_PACKAGES=(nmap bind9-dnsutils)
apt_candidate() { return 0; }
run_sudo() { printf '%s\\n' "$*" >> "$HOME/apt-calls"; }
preflight_packages; install_packages
[[ "$(grep -c -- --no-remove "$HOME/apt-calls")" == 2 ]]
[[ "$(grep -c -- --no-upgrade "$HOME/apt-calls")" == 2 ]]
grep -q -- --simulate "$HOME/apt-calls"
MODE=update; apt_install_flags
[[ " ${APT_INSTALL_FLAGS[*]} " != *--no-upgrade* ]]
''')

    def test_virtualbox_arm64_has_clear_error(self):
        result = self.run_shell('''VIRTUALIZATION_PLATFORM=virtualbox
dpkg() { echo arm64; }
preflight_packages
''', good=False)
        self.assertIn('VirtualBox guest packages require amd64', result.stderr)

    def test_task_preserves_errexit_inside_functions(self):
        result = self.run_shell('''broken() { false; echo SHOULD_NOT_RUN; }
run_task 'Failing task' broken
echo SHOULD_NOT_RUN
''', good=False)
        self.assertNotIn('SHOULD_NOT_RUN', result.stdout)
        self.assertNotIn('Completed:', result.stdout)

    def test_plain_task_has_no_ansi_or_background_process(self):
        result = self.run_shell('''init_ui
run_task 'Example' printf 'command output\\n'
[[ -z "$SPINNER_PID" ]]
''')
        self.assertNotIn('\x1b', result.stdout + result.stderr)
        self.assertIn('Completed: Example', result.stdout)

    def test_smoke_checks_use_local_only_flags(self):
        self.run_shell('''timeout() { printf '%s\\n' "$*"; }
[[ "$(smoke_command dig)" == *$'dig\\n-v' ]]
[[ "$(smoke_command openvpn)" == *$'openvpn\\n--version' ]]
[[ "$(smoke_command socat)" == *$'socat\\n-V' ]]
[[ "$(smoke_command chisel)" == *$'chisel\\n--version' ]]
''')

    def test_mock_install_and_update_workflows(self):
        for profile in ('core', 'extra'):
            for mode in ('', '--update'):
                with self.subTest(profile=profile, mode=mode):
                    self.run_shell('''
require_kali_user() { :; }
sudo() { [[ "$1" == -v ]]; }
run_sudo() { printf '%s\\n' "$*" >> "$HOME/events"; }
apt_candidate() { return 0; }
ensure_uv() { echo uv >> "$HOME/events"; }
install_kerbrute() { echo kerbrute >> "$HOME/events"; }
install_donpapi() { echo donpapi >> "$HOME/events"; }
install_references() { echo references >> "$HOME/events"; }
configure_shell() { echo shell >> "$HOME/events"; }
configure_guest() { echo guest >> "$HOME/events"; }
write_manifest() { echo manifest >> "$HOME/events"; }
verify_installation() { echo verify >> "$HOME/events"; }
main --no-progress --profile ''' + profile + ' --guest none ' + mode + '''
[[ "$(tail -n 2 "$HOME/events")" == $'manifest\\nverify' ]]
grep -q -- --simulate "$HOME/events"
grep -q -- --no-remove "$HOME/events"
if [[ "$PROFILE" == extra ]]; then
    for event in kerbrute donpapi references shell; do grep -qx "$event" "$HOME/events"; done
else
    ! grep -qx donpapi "$HOME/events"
fi
''')


class TerminalUI(unittest.TestCase):
    def terminal_run(self, ending, env_extra=None, no_progress=False):
        master, slave = pty.openpty()
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 100, 0, 0))
        env = dict(os.environ, TERM='xterm-256color')
        env.pop('NO_COLOR', None)
        env.update(env_extra or {})
        code = '''source "$1/weaponize.sh"
NO_PROGRESS="${2:-0}"
init_ui
trap cleanup_ui EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
work() { sleep 0.4; ''' + ending + '''; }
run_task 'Terminal test' work
'''
        process = subprocess.Popen(['bash', '-c', code, 'test', str(ROOT), str(int(no_progress))],
                                   stdin=slave, stdout=slave, stderr=slave, env=env)
        os.close(slave)
        chunks = []
        deadline = time.monotonic() + 10
        try:
            while time.monotonic() < deadline:
                if not select.select([master], [], [], 0.1)[0]:
                    continue
                try:
                    data = os.read(master, 65536)
                except OSError as exc:
                    if exc.errno == errno.EIO:
                        break
                    raise
                if not data:
                    break
                chunks.append(data)
            status = process.wait(timeout=2)
        finally:
            if process.poll() is None:
                process.kill()
                process.wait()
            os.close(master)
        return status, b''.join(chunks).decode()

    def test_footer_cleanup_on_success_failure_and_interrupt(self):
        for ending, expected in [('true', 0), ('false', 1), ('kill -INT $$', 130), ('kill -TERM $$', 143)]:
            with self.subTest(ending=ending):
                status, output = self.terminal_run(ending)
                self.assertEqual(status, expected, output)
                self.assertIn('elapsed', output)
                self.assertIn('\x1b[1;23r', output)
                self.assertIn('\x1b[r', output)
                if expected:
                    self.assertNotIn('Completed:', output)

    def test_no_color_disables_colors_but_keeps_progress(self):
        status, output = self.terminal_run('true', {'NO_COLOR': '1'})
        self.assertEqual(status, 0, output)
        self.assertIn('elapsed', output)
        self.assertNotIn('\x1b[1;32m', output)

    def test_no_progress_keeps_coloured_task_messages(self):
        status, output = self.terminal_run('true', no_progress=True)
        self.assertEqual(status, 0, output)
        self.assertNotIn('elapsed', output)
        self.assertNotIn('\x1b[1;23r', output)
        self.assertIn('\x1b[1;32m', output)


if __name__ == '__main__':
    unittest.main()
