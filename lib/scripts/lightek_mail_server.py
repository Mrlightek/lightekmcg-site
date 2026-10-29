#!/usr/bin/env python3
"""Bootstrap a fresh Ubuntu mail node; keep SMTP private and internet delivery held."""
import argparse
import os
from pathlib import Path
import pwd
import re
import shutil
import subprocess
import sys


def hostname(value):
    if not re.fullmatch(r"(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}", value):
        raise ValueError("Use a lowercase fully qualified mail hostname")
    return value


def configuration(name):
    hostname(name)
    return {
        "postfix/main.cf": f"""# Lightek private bootstrap: do not expose SMTP until routing/DNS/TLS verification.
compatibility_level = 3.6
myhostname = {name}
myorigin = $myhostname
mydestination = localhost, localhost.localdomain
inet_interfaces = loopback-only
inet_protocols = ipv4
mynetworks = 127.0.0.1/32
smtpd_relay_restrictions = permit_mynetworks, reject_unauth_destination
smtpd_restriction_classes = lightek_sender
lightek_sender = check_sender_access hash:/etc/postfix/lightek_senders, reject
smtpd_sender_restrictions = check_client_access cidr:/etc/postfix/lightek_local_clients
smtpd_recipient_limit = 20
authorized_submit_users =
smtp_tls_security_level = may
message_size_limit = 20971520
smtp_destination_concurrency_limit = 2
smtp_destination_rate_delay = 1s
default_destination_recipient_limit = 20
defer_transports = smtp
milter_protocol = 6
milter_default_action = tempfail
smtpd_milters = inet:127.0.0.1:11332
non_smtpd_milters = inet:127.0.0.1:11332
# Virtual recipients are explicitly enumerated, so unknown recipients are refused.
virtual_mailbox_domains = hash:/etc/postfix/lightek_domains
virtual_mailbox_maps = hash:/etc/postfix/lightek_recipients
virtual_transport = lmtp:unix:private/dovecot-lmtp
smtpd_sasl_type = dovecot
smtpd_sasl_path = private/auth
smtpd_sasl_auth_enable = no
smtpd_tls_auth_only = yes
smtpd_recipient_restrictions = reject_unauth_destination, reject_unlisted_recipient
""",
        "postfix/master.cf.d/README": "# Submission services are staged separately; do not expose until a trusted TLS certificate is installed.\\n",
        "dovecot/conf.d/99-lightek.conf": """# Private mailbox service, accessible locally until TLS and external routing are approved.
protocols = imap lmtp
listen = 127.0.0.1
ssl = required
disable_plaintext_auth = yes
mail_location = maildir:/var/vmail/%d/%n/Maildir
first_valid_uid = 5000
passdb {
  driver = passwd-file
  args = scheme=SHA512-CRYPT username_format=%u /etc/dovecot/lightek-users
}
userdb {
  driver = static
  args = uid=vmail gid=vmail home=/var/vmail/%d/%n
}
service lmtp {
  unix_listener /var/spool/postfix/private/dovecot-lmtp {
    mode = 0600
    user = postfix
    group = postfix
  }
}
service auth {
  unix_listener /var/spool/postfix/private/auth {
    mode = 0660
    user = postfix
    group = postfix
  }
}
""",
        "postfix/lightek_submission.cf": """# Activate only after trusted TLS certificate configuration.
submission inet n - y - - smtpd
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o smtpd_sender_login_maps=hash:/etc/postfix/lightek_logins
  -o smtpd_sender_restrictions=reject_sender_login_mismatch
smtps inet n - y - - smtpd
  -o smtpd_tls_wrappermode=yes
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o smtpd_sender_login_maps=hash:/etc/postfix/lightek_logins
  -o smtpd_sender_restrictions=reject_sender_login_mismatch
""",
        "postfix/lightek_logins": "# Authorized SMTP login-to-sender mappings; empty until mailbox provisioning.\n",
        "postfix/lightek_domains": "# Authorized virtual domains only; populated by mailbox provisioning.\n",
        "postfix/lightek_recipients": "# Authorized mailboxes only; populated by mailbox provisioning.\n",
        "postfix/lightek_senders": "# No senders enabled during bootstrap. Exact mailbox allowlist required.\n",
        "postfix/lightek_local_clients": "127.0.0.1/32 lightek_sender\n",
        "rspamd/local.d/worker-normal.inc": 'bind_socket = "127.0.0.1:11333";\ncount = 2;\n',
        "rspamd/local.d/worker-controller.inc": "enabled = false;\n",
        "rspamd/local.d/worker-proxy.inc": """bind_socket = "127.0.0.1:11332";
milter = yes;
timeout = 120s;
upstream "local" { default = yes; self_scan = yes; }
""",
        "rspamd/local.d/redis.conf": 'servers = "127.0.0.1:16379";\n',
        "rspamd/local.d/actions.conf": 'reject = 6;\nadd_header = 4;\ngreylist = null;\n',
        "rspamd/local.d/milter_headers.conf": 'skip_local = false;\nskip_authenticated = false;\nuse = ["x-spam-status", "x-spam-flag", "authentication-results"];\n',
        "rspamd/local.d/dkim_signing.conf": """enabled = true;
path = "/var/lib/rspamd/dkim/$domain.$selector.key";
selector = "mail";
use_esld = false;
use_domain = "header";
sign_local = true;
sign_authenticated = true;
allow_hdrfrom_mismatch = false;
allow_username_mismatch = false;
""",
        "rspamd/local.d/ratelimit.conf": """# Defense at the MTA as well as the application's rolling recipient quotas.
allow_local = true;
ham_factor_rate = 1.0;
spam_factor_rate = 1.0;
ham_factor_burst = 1.0;
spam_factor_burst = 1.0;
max_rate_mult = 1.0;
max_bucket_mult = 1.0;
rates {
  lightek_sender {
    selector = "from('smtp').lower";
    bucket = [
      { burst = 5; rate = "5 / 1m"; },
      { burst = 25; rate = "25 / 1h"; },
      { burst = 100; rate = "100 / 1d"; }
    ];
  }
  lightek_node {
    selector = "ip";
    bucket = [
      { burst = 25; rate = "25 / 1m"; },
      { burst = 100; rate = "100 / 1h"; },
      { burst = 500; rate = "500 / 1d"; }
    ];
  }
}
""",
        "redis/lightek-mail.conf": """bind 127.0.0.1
port 16379
protected-mode yes
daemonize no
dir /var/lib/redis/lightek-mail
appendonly yes
appendfsync everysec
maxmemory 128mb
maxmemory-policy noeviction
""",
        "systemd/system/lightek-mail-redis.service": """[Unit]
Description=Lightek mail rate-limit Redis (separate from application Redis)
After=network.target
[Service]
User=redis
Group=redis
ExecStart=/usr/bin/redis-server /etc/redis/lightek-mail.conf
Restart=on-failure
NoNewPrivileges=true
ProtectSystem=full
ProtectHome=true
PrivateTmp=true
[Install]
WantedBy=multi-user.target
""",
    }


def write_plan(directory, name):
    for relative, content in configuration(name).items():
        target = directory / relative
        if target.is_symlink():
            raise ValueError("Refusing a symlink configuration target")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)


def run(*args, **kwargs):
    return subprocess.run(args, check=True, **kwargs)


def install(name):
    hostname(name)
    if os.geteuid() != 0:
        raise ValueError("Run install as root on the mail VPS")
    release = dict(line.split("=", 1) for line in Path("/etc/os-release").read_text().splitlines() if "=" in line)
    if release.get("ID", "").strip('"') != "ubuntu" or release.get("VERSION_ID", "").strip('"') != "24.04":
        raise ValueError("This installer targets Ubuntu 24.04 only")
    if Path("/etc/lightek/mail-bootstrap-complete").exists():
        raise ValueError("Mail bootstrap already completed; use --mailbox-only instead")
    if shutil.which("postconf") or shutil.which("rspamadm") or Path("/etc/postfix/main.cf").exists() or Path("/etc/rspamd/local.d").exists():
        raise ValueError("Existing mail configuration found; refusing to overwrite it. Use the audit and integrate it separately")
    state = run("ss", "-H", "-lnt", "( sport = :25 or sport = :465 or sport = :587 or sport = :993 or sport = :16379 or sport = :11332 or sport = :11333 )", capture_output=True, text=True)
    if state.stdout.strip():
        raise ValueError("A required mail/Redis/scanner port is already in use")
    run("debconf-set-selections", input=f"postfix postfix/mailname string {name}\npostfix postfix/main_mailer_type select Local only\n", text=True)
    env = dict(os.environ, DEBIAN_FRONTEND="noninteractive")
    run("apt-get", "update", env=env)
    run("apt-get", "install", "-y", "--no-install-recommends", "postfix", "dovecot-core", "dovecot-imapd", "rspamd", "redis-server", "dnsutils", "openssl", env=env)
    run("systemctl", "stop", "postfix", "rspamd")
    try:
        write_plan(Path("/etc"), name)
        if not shutil.which("useradd"):
            raise ValueError("Missing useradd")
        try:
            pwd.getpwnam("vmail")
        except KeyError:
            run("useradd", "--system", "--uid", "5000", "--home-dir", "/var/vmail", "--shell", "/usr/sbin/nologin", "vmail")
        mailbox_owner = pwd.getpwnam("vmail")
        mailroot = Path("/var/vmail")
        mailroot.mkdir(parents=True, exist_ok=True, mode=0o750)
        os.chown(mailroot, mailbox_owner.pw_uid, mailbox_owner.pw_gid)
        credentials = Path("/etc/dovecot/lightek-users")
        if not credentials.exists():
            fd = os.open(credentials, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
            os.close(fd)
        credentials.chmod(0o600)
        redis = pwd.getpwnam("redis")
        redis_dir = Path("/var/lib/redis/lightek-mail")
        redis_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chown(redis_dir, redis.pw_uid, redis.pw_gid)
        redis_config = Path("/etc/redis/lightek-mail.conf")
        os.chown(redis_config, 0, redis.pw_gid)
        redis_config.chmod(0o640)
        for mapping in ("lightek_senders", "lightek_logins", "lightek_domains", "lightek_recipients"):
            run("postmap", "/etc/postfix/" + mapping)
        run("postfix", "check")
        run("rspamadm", "configtest")
        run("systemctl", "daemon-reload")
        run("systemctl", "enable", "--now", "lightek-mail-redis")
        run("systemctl", "enable", "--now", "rspamd")
        run("systemctl", "enable", "--now", "postfix")
    except Exception:
        subprocess.run(["systemctl", "stop", "postfix"], check=False)
        raise
    run("dovecot", "-n", capture_output=True, text=True)
    run("systemctl", "enable", "--now", "dovecot")
    run("systemctl", "is-active", "--quiet", "dovecot")
    print("LIGHTEK_MAIL_PRIVATE_BOOTSTRAP_COMPLETE")
    print("SMTP and IMAP are private; no senders are allowed; internet SMTP transport is deferred.")
    print("Do not enable customer sending yet. Complete routing, DKIM/DNS, TLS and end-to-end verification first.")


def dkim(domain):
    hostname(domain)
    if os.geteuid() != 0:
        raise ValueError("Run DKIM key preparation as root on the mail VPS")
    owner = pwd.getpwnam("_rspamd")
    directory = Path("/var/lib/rspamd/dkim")
    directory.mkdir(mode=0o750, parents=True, exist_ok=True)
    os.chown(directory, 0, owner.pw_gid)
    key = directory / f"{domain}.mail.key"
    public = directory / f"{domain}.mail.txt"
    if key.is_symlink() or public.is_symlink():
        raise ValueError("Refusing symlink DKIM material")
    if key.exists() and public.exists():
        print("LIGHTEK_MAIL_DKIM_ALREADY_PRESENT")
        return
    if key.exists() or public.exists():
        raise ValueError("Incomplete DKIM material found; refusing to overwrite it")
    old_umask = os.umask(0o077)
    try:
        result = run("rspamadm", "dkim_keygen", "-s", "mail", "-b", "2048", "-d", domain, "-k", str(key), capture_output=True, text=True)
        public.write_text(result.stdout)
        os.chown(key, 0, owner.pw_gid)
        key.chmod(0o640)
    finally:
        os.umask(old_umask)
    print(f"Publish the following public TXT record at mail._domainkey.{domain}:")
    print(public.read_text())


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["plan", "install", "dkim"])
    parser.add_argument("--hostname", default="mail.lightekmcg.com")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--domain")
    args = parser.parse_args()
    if args.action == "plan":
        if not args.output:
            parser.error("plan requires --output DIRECTORY")
        write_plan(args.output, args.hostname)
        print("Private mail configuration written for inspection; no services changed")
    elif args.action == "install":
        install(args.hostname)
    elif args.action == "dkim":
        if not args.domain:
            parser.error("dkim requires --domain DOMAIN")
        dkim(args.domain)


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Lightek mail setup stopped: {error}", file=sys.stderr)
        sys.exit(1)
