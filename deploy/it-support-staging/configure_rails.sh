#!/usr/bin/env bash
set -euo pipefail
instance=$1
domain=$2
secret_file=$3

# The instance launcher reads only this installation's environment. Pass the
# TURN secret on stdin so it does not enter a command line or log.
sudo -u lightek -H python3 "$instance/run-app.py" bin/rails runner \
  deploy/it-support-staging/configure_credentials.rb -- "$domain" < "$secret_file"
