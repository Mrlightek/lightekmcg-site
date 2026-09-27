#!/usr/bin/env bash
set -euo pipefail
[[ "$(id -u)" -eq 0 ]] || { echo "Run as root on production."; exit 1; }

apt-get update
apt-get install -y ufw

cat > /usr/local/sbin/lightek-firewall-control <<'HELPER'
#!/usr/bin/env bash
set -euo pipefail
ACTION="${1:-}"
PORT="${2:-}"
PROTO="${3:-tcp}"
case "$ACTION" in
  status) exec /usr/sbin/ufw status numbered ;;
  open|close)
    [[ "$PORT" =~ ^[0-9]+$ ]] || { echo "invalid port" >&2; exit 2; }
    (( PORT >= 1 && PORT <= 65535 )) || { echo "port out of range" >&2; exit 2; }
    [[ "$PROTO" == "tcp" || "$PROTO" == "udp" ]] || { echo "invalid protocol" >&2; exit 2; }
    if [[ "$ACTION" == "close" && "$PORT" =~ ^(22|80|443)$ ]]; then
      echo "refusing to close protected control-plane port $PORT" >&2
      exit 3
    fi
    if [[ "$ACTION" == "open" ]]; then
      exec /usr/sbin/ufw allow "${PORT}/${PROTO}"
    else
      exec /usr/sbin/ufw --force delete allow "${PORT}/${PROTO}"
    fi
    ;;
  *) echo "usage: $0 status | open PORT tcp|udp | close PORT tcp|udp" >&2; exit 2 ;;
esac
HELPER

chown root:root /usr/local/sbin/lightek-firewall-control
chmod 0755 /usr/local/sbin/lightek-firewall-control
cat > /etc/sudoers.d/lightek-firewall-control <<'SUDOERS'
lightek ALL=(root) NOPASSWD: /usr/local/sbin/lightek-firewall-control *
SUDOERS
chmod 0440 /etc/sudoers.d/lightek-firewall-control
visudo -cf /etc/sudoers.d/lightek-firewall-control

ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
/usr/local/sbin/lightek-firewall-control status
