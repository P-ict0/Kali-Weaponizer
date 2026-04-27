#!/usr/bin/env bash
set -Eeuo pipefail

JAVA_BIN="${JAVA_BIN:-$(command -v java || true)}"
BURP_JAR="${BURP_JAR:-/usr/share/burpsuite/burpsuite.jar}"
CERT_OUT="${CERT_OUT:-/tmp/burpCA.der}"
BURP_URL="${BURP_URL:-http://localhost:8080/cert}"
BURP_LOG="${BURP_LOG:-/tmp/burp-certificate.log}"

if [[ -z "$JAVA_BIN" ]]; then
  echo "[!] java not found in PATH" >&2
  exit 1
fi

if [[ ! -f "$BURP_JAR" ]]; then
  echo "[!] Burp Suite jar not found: $BURP_JAR" >&2
  exit 1
fi

rm -f "$CERT_OUT" "$BURP_LOG"

echo "[+] Starting Burp Suite temporarily to expose CA certificate"

timeout 90 "$JAVA_BIN" -Djava.awt.headless=true -jar "$BURP_JAR" < <(echo y) >"$BURP_LOG" 2>&1 &
BURP_PID=$!

# Burp can be slow after first install.
sleep 30

echo "[+] Downloading Burp CA certificate"

if curl -fsS "$BURP_URL" -o "$CERT_OUT"; then
  echo "[+] Burp CA downloaded to $CERT_OUT"
else
  echo "[!] Failed to download Burp CA from $BURP_URL" >&2
  echo "[!] Burp startup log:" >&2
  cat "$BURP_LOG" >&2 || true

  kill "$BURP_PID" >/dev/null 2>&1 || true
  wait "$BURP_PID" >/dev/null 2>&1 || true
  exit 1
fi

kill "$BURP_PID" >/dev/null 2>&1 || true
wait "$BURP_PID" >/dev/null 2>&1 || true

test -s "$CERT_OUT"
