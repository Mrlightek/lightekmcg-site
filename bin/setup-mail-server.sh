#!/usr/bin/env bash
set -euo pipefail

echo "=== Lightek Mail Studio: Automated Node Provisioning ==="

# 1. Install required mail packages non-interactively
echo "[1/4] Installing Postfix and Dovecot..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y postfix dovecot-core dovecot-imapd python3-requests

# 2. Deploy the checkpassword authentication bridge
echo "[2/4] Deploying authentication bridge..."
cat << 'PYEOF' > /usr/local/bin/lightek-dovecot-auth
#!/usr/bin/env python3
import sys
import os
import hashlib
import urllib.request
import json

username = os.environ.get('USER', '')
password = os.environ.get('PASSWORD', '')
if not username or not password:
    sys.exit(1)

token_digest = hashlib.sha256(password.encode('utf-8')).hexdigest()
api_url = "http://127.0.0.1:3000/api/lightek-mail/auth"
payload = json.dumps({"email": username, "token_digest": token_digest}).encode('utf-8')

ingress_secret = ""
env_file = "/etc/lightek/lightekmcg-site.env"
if os.path.exists(env_file):
    with open(env_file, 'r') as f:
        for line in f:
            if line.startswith("LIGHTEK_INGRESS_SECRET="):
                ingress_secret = line.split("=", 1)[1].strip().strip('"').strip("'")

req = urllib.request.Request(
    api_url, data=payload,
    headers={"Content-Type": "application/json", "X-Lightek-Mail-Ingress": ingress_secret},
    method="POST"
)

try:
    with urllib.request.urlopen(req, timeout=3) as response:
        if response.status == 200 and json.loads(response.read().decode()).get("authenticated") is True:
            sys.exit(0)
except Exception:
    pass
sys.exit(1)
PYEOF

chmod +x /usr/local/bin/lightek-dovecot-auth

# 3. Configure Dovecot checkpassword passdb
cat << 'DOVEEOF' > /etc/dovecot/conf.d/auth-checkpassword.conf.ext
passdb {
  driver = checkpassword
  args = /usr/local/bin/lightek-dovecot-auth
}
userdb {
  driver = static
  args = uid=vmail gid=vmail home=/var/mail/vhosts/%u
}
DOVEEOF

# Ensure Postfix auth socket is exposed
if ! grep -q "/var/spool/postfix/private/auth" /etc/dovecot/conf.d/10-master.conf; then
cat << 'DOVEMASTER' >> /etc/dovecot/conf.d/10-master.conf
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
DOVEMASTER
fi

# 4. Configure Postfix submission port 587
echo "[3/4] Configuring Postfix submission..."
if ! grep -q "^submission inet" /etc/postfix/master.cf; then
cat << 'POSTMASTER' >> /etc/postfix/master.cf

submission inet n       -       y       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_client_restrictions=permit_sasl_authenticated,reject
  -o smtpd_sender_restrictions=reject_sender_login_mismatch
  -o smtpd_recipient_restrictions=permit_sasl_authenticated,reject_unauth_destination
POSTMASTER
fi

echo "[4/4] Validating and restarting mail services..."
postfix check
systemctl restart dovecot
systemctl reload postfix

echo "=== Mail server successfully provisioned and ready for plug-and-play deployment! ==="
