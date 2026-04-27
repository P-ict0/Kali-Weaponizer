#!/usr/bin/env bash
set -Eeuo pipefail

JAVA_BIN="${JAVA_BIN:-$(command -v java || true)}"
BURP_JAR="${BURP_JAR:-/usr/share/burpsuite/burpsuite.jar}"
CERT_OUT="${CERT_OUT:-/tmp/burpCA.der}"
BURP_URL="${BURP_URL:-http://127.0.0.1:8080/cert}"

if [[ -z "$JAVA_BIN" ]]; then
  echo "java not found in PATH" >&2
  exit 1
fi

if [[ ! -f "$BURP_JAR" ]]; then
  echo "Burp Suite jar not found: $BURP_JAR" >&2
  exit 1
fi

rm -f "$CERT_OUT"

timeout 90 "$JAVA_BIN" -Djava.awt.headless=true -jar "$BURP_JAR" <<< "y" >/tmp/burp-certificate.log 2>&1 &
BURP_PID=$!

for _ in {1..60}; do
  if curl -fsS "$BURP_URL" -o "$CERT_OUT"; then
    break
  fi
  sleep 1
done

kill "$BURP_PID" >/dev/null 2>&1 || true
wait "$BURP_PID" >/dev/null 2>&1 || true

test -s "$CERT_OUT"
