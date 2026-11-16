#!/bin/zsh
# Persistent local code-signing identity in a dedicated keychain so:
# 1) TCC / Full Disk Access survives rebuilds (same cert every time)
# 2) codesign never blocks on the login-keychain password dialog
set -euo pipefail

CERT_NAME="PCOptopus Local Signing"
KEYCHAIN_PATH="${HOME}/Library/Keychains/pcoptopus-signing.keychain-db"
KEYCHAIN_PASS="pcoptopus-signing"
P12_PASS="pcoptopus-local"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGNING_DIR="$ROOT/.signing"

ensure_keychain() {
  if [[ ! -f "$KEYCHAIN_PATH" ]]; then
    security create-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN_PATH" >/dev/null
  fi
  security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
  security unlock-keychain -p "$KEYCHAIN_PASS" "$KEYCHAIN_PATH" >/dev/null
  # Prefer our keychain first without dropping login.
  local current
  current="$(security list-keychains -d user | tr -d '"')"
  if ! print -r -- "$current" | grep -F "$KEYCHAIN_PATH" >/dev/null; then
    security list-keychains -d user -s "$KEYCHAIN_PATH" $current >/dev/null
  fi
}

identity_present() {
  security find-identity -p codesigning "$KEYCHAIN_PATH" 2>/dev/null | grep -F "$CERT_NAME" >/dev/null
}

can_codesign() {
  local probe
  probe="$(mktemp)"
  printf 'pc' > "$probe"
  if codesign --force --sign "$CERT_NAME" --keychain "$KEYCHAIN_PATH" "$probe" >/dev/null 2>&1; then
    rm -f "$probe"
    return 0
  fi
  rm -f "$probe"
  return 1
}

ensure_keychain

if identity_present && can_codesign; then
  echo "$CERT_NAME"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$SIGNING_DIR"

cat > "$TMP/codesign.cnf" <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
x509_extensions = exts
[ dn ]
CN = ${CERT_NAME}
O = PCOptopus
OU = Local
C = US
[ exts ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
subjectKeyIdentifier = hash
EOF

# Reuse existing key material if present so the cert hash stays stable across machines/sessions.
if [[ -f "$SIGNING_DIR/pc.key" && -f "$SIGNING_DIR/pc.crt" ]]; then
  cp "$SIGNING_DIR/pc.key" "$TMP/pc.key"
  cp "$SIGNING_DIR/pc.crt" "$TMP/pc.crt"
else
  openssl req -new -x509 -days 3650 -nodes \
    -config "$TMP/codesign.cnf" \
    -keyout "$TMP/pc.key" -out "$TMP/pc.crt" >/dev/null 2>&1
  cp "$TMP/pc.key" "$SIGNING_DIR/pc.key"
  cp "$TMP/pc.crt" "$SIGNING_DIR/pc.crt"
  chmod 600 "$SIGNING_DIR/pc.key" "$SIGNING_DIR/pc.crt"
fi

if ! openssl pkcs12 -export -legacy \
  -out "$TMP/pc.p12" \
  -inkey "$TMP/pc.key" \
  -in "$TMP/pc.crt" \
  -name "$CERT_NAME" \
  -passout pass:"$P12_PASS" >/dev/null 2>&1; then
  openssl pkcs12 -export \
    -out "$TMP/pc.p12" \
    -inkey "$TMP/pc.key" \
    -in "$TMP/pc.crt" \
    -name "$CERT_NAME" \
    -passout pass:"$P12_PASS" \
    -certpbe PBE-SHA1-3DES -keypbe PBE-SHA1-3DES -macalg SHA1 >/dev/null 2>&1
fi
cp "$TMP/pc.p12" "$SIGNING_DIR/pc.p12"
chmod 600 "$SIGNING_DIR/pc.p12"

# Clear prior copies of this identity in the signing keychain, then import with open ACL.
security delete-identity -c "$CERT_NAME" "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
security delete-certificate -c "$CERT_NAME" "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
security import "$TMP/pc.p12" \
  -k "$KEYCHAIN_PATH" \
  -P "$P12_PASS" \
  -A \
  -T /usr/bin/codesign \
  -T /usr/bin/security \
  -T /usr/bin/productbuild >/dev/null

security set-key-partition-list \
  -S apple-tool:,apple:,codesign: \
  -s -k "$KEYCHAIN_PASS" \
  "$KEYCHAIN_PATH" >/dev/null 2>&1 || true

if identity_present && can_codesign; then
  echo "$CERT_NAME"
  exit 0
fi

echo ""
exit 1
