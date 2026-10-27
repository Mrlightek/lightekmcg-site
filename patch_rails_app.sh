#!/usr/bin/env bash
set -euo pipefail

echo "=== Patching Rails Application for Lightek Mail Auth Endpoint ==="

# 1. Patch config/routes.rb
ROUTES_FILE="config/routes.rb"
if [ -f "$ROUTES_FILE" ]; then
    if ! grep -q "authenticate_smtp" "$ROUTES_FILE"; then
        echo "Injecting route into $ROUTES_FILE..."
        sed -i '' '/namespace :lightek_mail do/a\
      post :auth, to: "lightek_mail#authenticate_smtp"
' "$ROUTES_FILE" || sed -i '/namespace :lightek_mail do/a\      post :auth, to: "lightek_mail#authenticate_smtp"' "$ROUTES_FILE"
    else
        echo "Auth route already exists in $ROUTES_FILE."
    fi
fi

# 2. Add authenticate_smtp method to app/controllers/api/lightek_mail_controller.rb
CONTROLLER_FILE="app/controllers/api/lightek_mail_controller.rb"
if [ -f "$CONTROLLER_FILE" ]; then
    if ! grep -q "def authenticate_smtp" "$CONTROLLER_FILE"; then
        echo "Injecting authenticate_smtp action into $CONTROLLER_FILE..."
        sed -i '' '/class Api::LightekMailController/a\
  skip_before_action :authenticate_account!, only: [:auth, :inbound]\
\
  def authenticate_smtp\
    verify_ingress_secret!\
    account = LightekMail::Account.find_by(email: params[:email])\
    if account && account.sending_ready? && ActiveSupport::SecurityUtils.secure_compare(account.token_digest, params[:token_digest])\
      render json: { authenticated: true }, status: :ok\
    else\
      render json: { authenticated: false }, status: :unauthorized\
    end\
  end\
' "$CONTROLLER_FILE" || sed -i '/class Api::LightekMailController/a\  skip_before_action :authenticate_account!, only: [:auth, :inbound]\n\n  def authenticate_smtp\n    verify_ingress_secret!\n    account = LightekMail::Account.find_by(email: params[:email])\n    if account && account.sending_ready? && ActiveSupport::SecurityUtils.secure_compare(account.token_digest, params[:token_digest])\n      render json: { authenticated: true }, status: :ok\n    else\n      render json: { authenticated: false }, status: :unauthorized\n    end\n  end\n' "$CONTROLLER_FILE"
    else
        echo "authenticate_smtp method already present in $CONTROLLER_FILE."
    fi
fi

echo "=== Rails patch completed successfully! ==="
