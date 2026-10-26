# Production Action Cable behind Apache

Passenger 6's Apache integration cannot provide the full-duplex WebSocket transport required by Live Studio. A response can say `101 Switching Protocols` while omitting `Connection: Upgrade` and including `Transfer-Encoding: chunked`, causing Firefox to abort the handshake with 1006. Phusion documents the Apache integration limitation and recommends a separate backend behind Apache: https://www.phusionpassenger.com/docs/advanced_guides/config_and_optimization/apache/tuning_sse_and_websockets.html

The site continues to run on Apache/Passenger. Only `/cable` on the existing TLS virtual host proxies to Puma at `127.0.0.1:28080`. Rails documents this standalone Action Cable arrangement: https://guides.rubyonrails.org/action_cable_overview.html#standalone

## Install after merging and deploying

Run on the production VPS as root:

```bash
cd /var/www/lightekmcg-site
bash lib/scripts/install_lightek_cable_service.sh --check
bash lib/scripts/install_lightek_cable_service.sh
```

The installer uses the existing bundled Puma, Ruby 3.3.6 and `/etc/lightek/lightekmcg-site.env`. It requires an enabled TLS virtual host whose ServerName or ServerAlias is `lightekmcg.com`. APP_ROOT, APP_USER, APP_DOMAIN, RUBY_VERSION and ENV_FILE can override the defaults. It refuses unmanaged `/cable` mappings, customized managed blocks, unmanaged unit files and occupied backend ports. It does not print credentials or open a firewall port.

The script backs up modified unit/vhost files under `/var/backups/lightekmcg-site-cable`, enables standard Apache proxy/header modules, creates `lightekmcg-site-cable.service`, validates Apache syntax, starts Puma, verifies the backend handshake and reloads Apache. It then verifies the TLS handshake locally using the production domain for certificate verification. It checks the status, Connection, Upgrade, Sec-WebSocket-Accept, selected protocol and absence of Transfer-Encoding. If validation fails, it restores the previous unit/vhost files and service enablement state. Enabled prerequisite Apache modules are left enabled. Backups and the list of files changed are retained.

Success prints **LIGHTEK_CABLE_HANDSHAKE_PASS**. This is an anonymous wire-level test: Rails may then disconnect the probe as unauthorized, which is expected. It is not evidence of a signed-in recording. Reload Live Studio, enable the camera and microphone, and run a private test. No application origin/authentication checks or Vault policy are disabled. Apache preserves the host, TLS scheme and existing cookies to the local Cable service.

## Operation

```bash
systemctl status lightekmcg-site-cable --no-pager
journalctl -u lightekmcg-site-cable -n 80 --no-pager
```

Future standard deployments restart the Cable service if installed, and wait for its handshake before reporting success. Restarting the service ends active broadcasts, so stop a live session before deploying. The service is enabled at boot and restarts on process failure. The existing Redis/database services remain prerequisites.

Verification used a real Apache 2.4.58 TLS proxy, Puma 8.0.2 and Action Cable 8.0.4 with a fixture connection/channel. The test verified a valid handshake, welcome, subscription, bidirectional frames, invalid-cookie rejection, origin rejection and a static website response outside `/cable`. Configuration tests cover virtual-host scope, idempotence, conflicts, preservation and rollback. The actual production systemd install and signed-in media session must still be verified on the VPS.
