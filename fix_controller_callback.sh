#!/usr/bin/env bash
set -euo pipefail

CONTROLLER_FILE="app/controllers/api/lightek_mail_controller.rb"

if [ -f "$CONTROLLER_FILE" ]; then
    echo "Correcting skip_before_action in $CONTROLLER_FILE..."
    
    # Remove the broken skip line entirely or replace it with the correct auth method if needed
    # Let's inspect what's there and clean it up safely:
    python3 -c '
path = "app/controllers/api/lightek_mail_controller.rb"
with open(path, "r") as f:
    content = f.read()

# Remove the faulty skip_before_action line causing the ArgumentError
content = content.replace("skip_before_action :authenticate_account!, only: [:auth, :inbound]", "# skipped auth check handled in endpoint")
content = content.replace("skip_before_action :authenticate_account!", "")

with open(path, "w") as f:
    f.write(content)
'
    echo "Controller file updated. Checking git diff..."
    git diff "$CONTROLLER_FILE"
fi
