#!/usr/bin/env bash
# setup-creds.sh — Create or update the MaaS credentials vault.
# Run once before the first deploy, or again whenever credentials change.
set -euo pipefail

VAULT_FILE="vars/vault.yml"
VAULT_PASS_FILE="$HOME/.satellite-demo.vaultpass"

cd "$(dirname "$0")"

# ── Vault password ────────────────────────────────────────────────────────────
if [ ! -f "$VAULT_PASS_FILE" ]; then
  echo "No vault password file found at $VAULT_PASS_FILE."
  read -s -p "Choose a vault password (stored in $VAULT_PASS_FILE): " vpass; echo
  printf '%s' "$vpass" > "$VAULT_PASS_FILE"
  chmod 600 "$VAULT_PASS_FILE"
  echo "Vault password saved."
fi

# ── Existing values (shown as defaults if vault already exists) ───────────────
existing_maas_url=""
existing_maas_key=""
if [ -f "$VAULT_FILE" ]; then
  existing_maas_url=$(ansible-vault view "$VAULT_FILE" \
    --vault-password-file "$VAULT_PASS_FILE" 2>/dev/null \
    | grep "^maas_url:" | awk '{print $2}' | tr -d '"' || true)
  existing_maas_key=$(ansible-vault view "$VAULT_FILE" \
    --vault-password-file "$VAULT_PASS_FILE" 2>/dev/null \
    | grep "^maas_key:" | awk '{print $2}' | tr -d '"' || true)
  echo "Existing credentials found. Press Enter to keep current value."
fi

# ── Prompt ────────────────────────────────────────────────────────────────────
default_url="${existing_maas_url:-https://your-litellm-endpoint/v1}"
read -p "MaaS API URL [$default_url]: " maas_url
maas_url="${maas_url:-$default_url}"

if [ -n "$existing_maas_key" ]; then
  read -s -p "MaaS API key [keep existing]: " maas_key; echo
  maas_key="${maas_key:-$existing_maas_key}"
else
  read -s -p "MaaS API key: " maas_key; echo
fi

# ── Write and encrypt ─────────────────────────────────────────────────────────
tmp=$(mktemp)
cat > "$tmp" <<EOF
maas_url: "${maas_url}"
maas_key: "${maas_key}"
EOF

ansible-vault encrypt "$tmp" \
  --vault-password-file "$VAULT_PASS_FILE" \
  --encrypt-vault-id default \
  --output "$VAULT_FILE"
rm -f "$tmp"

echo "Credentials saved to $VAULT_FILE"
