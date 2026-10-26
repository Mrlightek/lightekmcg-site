#!/usr/bin/env bash
# Read-only inventory. Does not print passwords, private keys, mail bodies or env files.
set -u
printf 'LIGHTEK_MAIL_AUDIT_BEGIN\n'
for service in postfix dovecot opendkim rspamd; do
  printf '%s: ' "$service"
  systemctl is-active "$service" 2>/dev/null || true
done
ss -lntp '( sport = :25 or sport = :465 or sport = :587 or sport = :993 )' 2>/dev/null || true
if command -v postconf >/dev/null; then
  postconf mail_version myhostname mydestination inet_interfaces inet_protocols mynetworks smtpd_relay_restrictions relay_domains relay_recipient_maps transport_maps smtpd_milters non_smtpd_milters smtp_tls_security_level message_size_limit
  postconf -M smtp/inet 2>/dev/null || true
fi
if command -v dig >/dev/null; then
  dig +short A mail.lightekmcg.com
  dig +short MX lightekmcg.com
  dig +short TXT lightekmcg.com
  dig +short TXT _dmarc.lightekmcg.com
  dig +short TXT mail._domainkey.lightekmcg.com
fi
printf 'LIGHTEK_MAIL_AUDIT_END\n'
