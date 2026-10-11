"""Offline regression tests; never run the installer against the host."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / f'{name}.py')
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result


policies = module('merge_firefox_policies')


class PolicyMerge(unittest.TestCase):
    def test_preserves_existing_choices_and_adds_certificates(self):
        old = {'policies': {'Homepage': {'URL': 'https://example.com'}, 'Certificates': {'Install': ['existing.der']}, 'Custom': True}}
        new = {'policies': {'Homepage': {'URL': 'about:blank'}, 'Certificates': {'Install': ['existing.der', 'burp.der']}}}
        merged = policies.merge(old, new)
        self.assertEqual(merged['policies']['Homepage']['URL'], 'https://example.com')
        self.assertTrue(merged['policies']['Custom'])
        self.assertEqual(merged['policies']['Certificates']['Install'], ['existing.der', 'burp.der'])
        self.assertEqual(policies.merge(merged, new), merged)
        self.assertEqual(policies.merge(old, new, True)['policies']['Homepage']['URL'], 'about:blank')


class Shell(unittest.TestCase):
    def run_shell(self, code, good=True):
        with tempfile.TemporaryDirectory() as tmp:
            env = dict(os.environ, HOME=tmp)
            result = subprocess.run(['bash', '-c', 'source "$1/weaponize.sh"\n' + code, 'test', str(ROOT)], env=env, capture_output=True, text=True)
        if good:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        else:
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def test_architectures(self):
        self.run_shell('[[ "$(go_arch x86_64)" == amd64 ]]; [[ "$(go_arch aarch64)" == arm64 ]]; [[ "$(go_arch i686)" == 386 ]]')
        self.run_shell('go_arch unsupported', good=False)

    def test_extra_includes_core(self):
        self.run_shell('''PROFILE=core; VIRTUALIZATION_PLATFORM=none; build_package_lists
core=("${REQUIRED_PACKAGES[@]}")
PROFILE=extra; select_options; build_package_lists
for pkg in "${core[@]}"; do
  found=0
  for extra in "${REQUIRED_PACKAGES[@]}"; do [[ "$pkg" != "$extra" ]] || found=1; done
  (( found ))
done
[[ "$EXTRAS" == wireless,editors,servers,references ]]
''')

    def test_plan_never_calls_mutating_steps(self):
        self.run_shell('''sudo() { exit 90; }; curl() { exit 91; }; git() { exit 92; }
require_kali_user() { exit 93; }
main --plan --profile extra --guest qemu
[[ ! -d "$HOME/tools" && ! -d "$HOME/.local/state" ]]
''')

    def test_candidate_query_failure(self):
        self.run_shell('apt-cache() { return 9; }; if apt_candidate nmap; then exit 10; else [[ $? == 2 ]]; fi')

    def test_missing_required_stops(self):
        self.run_shell('REQUIRED_PACKAGES=(missing); apt_candidate() { return 1; }; select_available_packages', good=False)

    def test_missing_optional_reported(self):
        self.run_shell('REQUIRED_PACKAGES=(); OPTIONAL_PACKAGES=(missing); apt_candidate() { return 1; }; select_available_packages; [[ "${SKIPPED_PACKAGES[0]}" == missing ]]')

    def test_optional_query_failure_stops(self):
        self.run_shell('REQUIRED_PACKAGES=(); OPTIONAL_PACKAGES=(broken); apt_candidate() { return 2; }; select_available_packages', good=False)

    def test_configuration_preservation_and_backup(self):
        self.run_shell('''RUN_DIR="$HOME/logs"; mkdir "$RUN_DIR"
printf 'old' > "$HOME/config"; printf 'new' > "$HOME/template"
preserve_config "$HOME/template" "$HOME/config"
[[ "$(cat "$HOME/config")" == old ]]
REPLACE_CONFIG=1; preserve_config "$HOME/template" "$HOME/config"
[[ "$(cat "$HOME/config")" == new && "$(cat "$RUN_DIR/config.before")" == old ]]
preserve_config "$HOME/template" "$HOME/config"
[[ "$(cat "$RUN_DIR/config.before")" == old ]]
''')

    def test_doctor_rejects_configuration(self):
        self.run_shell('parse_args --doctor --configure-burp', good=False)

    def test_uv_version(self):
        self.run_shell('fake_uv() { echo "uv 0.9.17"; }; uv_usable fake_uv')
        self.run_shell('fake_uv() { echo "uv 0.8.0"; }; uv_usable fake_uv', good=False)

    def test_existing_executable_is_not_overwritten(self):
        self.run_shell('''RUN_DIR="$HOME/logs"; mkdir -p "$RUN_DIR" "$HOME/tools/bin" "$HOME/tools/uv"
export UV_TOOL_DIR="$HOME/tools/uv" UV_TOOL_BIN_DIR="$HOME/tools/bin"
printf 'original' > "$HOME/tools/bin/DonPAPI"
checkout_pinned() { :; }; ensure_uv() { UV_BIN=false; }
set +e
(set -e; install_donpapi)
status=$?
set -e
[[ "$status" != 0 && "$(cat "$HOME/tools/bin/DonPAPI")" == original ]]
''')

    def test_no_migration_option(self):
        self.run_shell('parse_args --migrate-pipx', good=False)


class Burp(unittest.TestCase):
    def invoke(self, tmp, certificate, url='http://127.0.0.1:8080/cert'):
        binary = tmp / 'bin'
        binary.mkdir(exist_ok=True)
        curl = binary / 'curl'
        curl.write_text('#!/bin/bash\ncp "$MOCK_CERT" "${@: -1}"\n')
        curl.chmod(0o755)
        env = dict(os.environ, PATH=f'{binary}:' + os.environ['PATH'],
                   MOCK_CERT=str(certificate), CERT_OUT=str(tmp / 'saved.der'),
                   BURP_LOG=str(tmp / 'burp.log'), BURP_WAIT_SECONDS='1', BURP_URL=url)
        return subprocess.run(['bash', str(ROOT / 'templates/scripts/get-burp-certificate.sh')], env=env, capture_output=True, text=True)

    def test_html_does_not_replace_existing_certificate(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            (tmp / 'saved.der').write_text('existing')
            (tmp / 'html').write_text('<html>wrong application</html>')
            result = self.invoke(tmp, tmp / 'html')
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((tmp / 'saved.der').read_text(), 'existing')

    def test_credentials_cannot_redirect_to_remote_host(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            result = self.invoke(tmp, tmp / 'unused', 'http://127.0.0.1:8080@evil.example/cert')
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse((tmp / 'saved.der').exists())

    def test_valid_local_ca(self):
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                '-keyout', str(tmp / 'key.pem'), '-outform', 'DER', '-out', str(tmp / 'cert.der'),
                '-days', '1', '-subj', '/CN=PortSwigger CA', '-addext', 'basicConstraints=critical,CA:TRUE'],
                check=True, capture_output=True)
            result = self.invoke(tmp, tmp / 'cert.der')
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual((tmp / 'saved.der').read_bytes(), (tmp / 'cert.der').read_bytes())


if __name__ == '__main__':
    unittest.main()
