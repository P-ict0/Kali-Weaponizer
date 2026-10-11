#!/usr/bin/env bash
set -Eeuo pipefail

# Burp must already be running as the same user whose CA you want to trust.
# Do not launch/accept a licence for a second instance or kill an existing one.
BURP_URL="${BURP_URL:-http://127.0.0.1:8080/cert}"
CERT_OUT="${CERT_OUT:-$HOME/.local/share/kali-weaponizer/burpCA.der}"
BURP_LOG="${BURP_LOG:-$HOME/.local/state/kali-weaponizer/burp-certificate.log}"
BURP_WAIT_SECONDS="${BURP_WAIT_SECONDS:-60}"
[[ "$BURP_WAIT_SECONDS" =~ ^[1-9][0-9]*$ ]] || { echo 'Invalid BURP_WAIT_SECONDS' >&2; exit 1; }
# Only fetch from a local proxy. Certificate trust must not be sourced remotely.
if [[ ! "$BURP_URL" =~ ^http://(127\.0\.0\.1|localhost):([0-9]{1,5})/cert$ ]]; then
    echo 'BURP_URL must be a local HTTP /cert endpoint with an explicit port.' >&2
    exit 1
fi
port="${BASH_REMATCH[2]}"
(( 10#$port > 0 && 10#$port <= 65535 )) || { echo 'Invalid listener port' >&2; exit 1; }
command -v openssl >/dev/null
mkdir -p "$(dirname "$CERT_OUT")" "$(dirname "$BURP_LOG")"
temp="$(mktemp -d "$(dirname "$CERT_OUT")/.burp-cert-XXXXXX")"
trap 'rm -rf -- "$temp"' EXIT
: > "$BURP_LOG"
printf 'Waiting up to %s seconds for your running Burp instance at %s\n' "$BURP_WAIT_SECONDS" "$BURP_URL"
deadline=$((SECONDS + BURP_WAIT_SECONDS))
while (( SECONDS < deadline )); do
    remaining=$((deadline - SECONDS))
    if curl --noproxy '*' -fsS --connect-timeout 2 --max-time "$remaining" "$BURP_URL" -o "$temp/cert.der" 2>> "$BURP_LOG" &&
        openssl x509 -inform DER -in "$temp/cert.der" -noout -checkend 0 >> "$BURP_LOG" 2>&1 &&
        openssl x509 -inform DER -in "$temp/cert.der" -noout -text > "$temp/cert.txt" 2>> "$BURP_LOG" &&
        grep -q 'CA:TRUE' "$temp/cert.txt" &&
        openssl x509 -inform DER -in "$temp/cert.der" -noout -subject | grep -qi 'PortSwigger'; then
        install -m 644 "$temp/cert.der" "$temp/validated.der"
        mv -f -- "$temp/validated.der" "$CERT_OUT"
        openssl x509 -inform DER -in "$CERT_OUT" -noout -subject -fingerprint -sha256
        printf 'Validated Burp CA saved to %s\n' "$CERT_OUT"
        exit 0
    fi
    sleep 1
done
printf 'No valid Burp CA received. Start Burp, check its listener port, and retry. Log: %s\n' "$BURP_LOG" >&2
exit 1
