#!/usr/bin/env bash
set -euo pipefail
APP_NAME="${APP_NAME:-lightekmcg-site}"
ENV_FILE="${ENV_FILE:-/etc/lightek/${APP_NAME}.env}"
[[ "$EUID" -eq 0 ]] || { echo "ERROR: run as root"; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "ERROR: missing $ENV_FILE"; exit 1; }
if ! grep -q '^GATEKEEPER_DEPLOY_CALLBACK_TOKEN=' "$ENV_FILE"; then
  printf '\nGATEKEEPER_DEPLOY_CALLBACK_TOKEN="%s"\n' "$(openssl rand -hex 32)" >> "$ENV_FILE"
fi
if ! grep -q '^GATEKEEPER_GITHUB_WORKFLOW=' "$ENV_FILE"; then
  printf 'GATEKEEPER_GITHUB_WORKFLOW="deploy-production.yml"\n' >> "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"
echo "Server CI/CD environment prepared."
