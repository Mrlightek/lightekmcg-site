#!/usr/bin/env python3
"""Install one isolated web image over the existing Gatekeeper SSH transport.
Input and secrets arrive on stdin; subprocess output is never returned to Rails.
"""
import fcntl
import json
import os
import pathlib
import re
import secrets
import shutil
import subprocess
import sys
import time
import urllib.request


def validate(config):
    domain = config.get("domain", "")
    if len(domain) > 253 or not re.fullmatch(r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+", domain):
        raise ValueError("Invalid hostname")
    if not re.fullmatch(r"[a-z0-9][a-z0-9.:-]*(?:/[a-z0-9][a-z0-9._-]*)+@sha256:[a-f0-9]{64}", config.get("image", "")):
        raise ValueError("Use a registry image pinned by digest")
    if type(config.get("launch_id")) is not int or config["launch_id"] <= 0:
        raise ValueError("Invalid launch")
    if type(config.get("container_port")) is not int or not 0 < config["container_port"] < 65536:
        raise ValueError("Invalid container port")
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", config.get("email", "")):
        raise ValueError("Invalid certificate email")
    if type(config.get("rails_worker", False)) is not bool:
        raise ValueError("Select worker mode")
    if config.get("rails_worker") and not config.get("rails_database"):
        raise ValueError("Sidekiq requires the Rails database stack")
    if type(config.get("rails_database")) is not bool:
        raise ValueError("Select Rails database mode")
    environment = config.get("environment", {})
    if not isinstance(environment, dict) or any(not re.fullmatch(r"[A-Z][A-Z0-9_]*", k) or not isinstance(v, str) or "\x00" in v for k, v in environment.items()):
        raise ValueError("Environment must contain named string values")
    if config.get("lightek_application") and not config["rails_database"]:
        raise ValueError("Lightek requires its database stack")
    return config


def run(args, **kwargs):
    return subprocess.run(args, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=1500, **kwargs)


def write_json(path, value):
    temp = path.with_suffix(".tmp")
    temp.write_text(json.dumps(value))
    temp.chmod(0o600)
    temp.replace(path)


def compose_config(config, state):
    environment = dict(config.get("environment", {}))
    web = {"image": config["image"], "restart": "unless-stopped",
           "ports": [f"127.0.0.1:{state['port']}:{config['container_port']}"],
           "volumes": ["storage:/rails/storage", "app-storage:/app/storage", "assets:/app/public/assets", "rails-assets:/rails/public/assets"]}
    services = {"web": web}
    volumes = {"storage": {}, "app-storage": {}, "assets": {}, "rails-assets": {}}
    if config["rails_database"]:
        environment.update(RAILS_ENV="production", RAILS_LOG_TO_STDOUT="true", RAILS_SERVE_STATIC_FILES="true",
                           SECRET_KEY_BASE=state["secret_key_base"],
                           DATABASE_URL=f"postgresql://lightek:{state['database_password']}@db:5432/application",
                           REDIS_URL="redis://redis:6379/0")
        if config.get("lightek_application"):
            environment.update(APP_HOST=config["domain"], LIGHTEK_DEPLOYED_SITE_HOST=config["domain"],
                               LIGHTEK_RELEASE=config["image"].split("@sha256:")[1])
        web["command"] = ["bin/rails", "server", "-b", "0.0.0.0", "-p", str(config["container_port"])]
        web["depends_on"] = {"db": {"condition": "service_healthy"}, "redis": {"condition": "service_started"}}
        services["db"] = {"image": "postgres:16-bookworm", "restart": "unless-stopped",
                          "environment": {"POSTGRES_USER": "lightek", "POSTGRES_PASSWORD": state["database_password"], "POSTGRES_DB": "application"},
                          "volumes": ["database:/var/lib/postgresql/data"],
                          "healthcheck": {"test": ["CMD-SHELL", "pg_isready -U lightek -d application"], "interval": "5s", "timeout": "5s", "retries": 60}}
        services["redis"] = {"image": "redis:7-bookworm", "restart": "unless-stopped", "command": ["redis-server", "--appendonly", "yes"], "volumes": ["redis:/data"]}
        volumes.update(database={}, redis={})
    # Compose interprets dollars even in JSON values. Keep supplied secrets literal.
    web["environment"] = {k: v.replace("$", "$$") for k, v in environment.items()}
    if config.get("rails_worker"):
        services["worker"] = {"image": config["image"], "restart": "unless-stopped", "environment": dict(web["environment"]),
                              "volumes": list(web["volumes"]), "depends_on": dict(web["depends_on"]),
                              "command": ["bundle", "exec", "sidekiq"]}
    return {"services": services, "volumes": volumes}


def install(config):
    validate(config)
    if os.geteuid() != 0:
        raise ValueError("Root is required")
    os.umask(0o077)
    lockpath = pathlib.Path("/run/lightek-container-install.lock")
    with lockpath.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return install_locked(config)


def install_locked(config):
    domain = config["domain"]
    root = pathlib.Path("/opt/lightek-applications") / domain
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    state_path = root / "installation.json"
    state = json.loads(state_path.read_text()) if state_path.exists() else None
    if state and state["launch_id"] != config["launch_id"]:
        raise ValueError("Hostname is owned by another installation")
    # Avoid replacing a pre-existing native Rails site's routing.
    if not state:
        for directory in (pathlib.Path("/etc/apache2/sites-available"), pathlib.Path("/etc/nginx/sites-enabled")):
            if directory.exists():
                for file in directory.iterdir():
                    if file.is_file() and re.search(r"(?:ServerName|ServerAlias|server_name)\s+[^;\n]*\b" + re.escape(domain) + r"(?:\s|;|$)", file.read_text(errors="ignore")):
                        raise ValueError("Hostname already has web server routing")
        import socket
        used = {json.loads(p.read_text())["port"] for p in root.parent.glob("*/installation.json")}
        port = None
        for candidate in range(20000, 60000):
            if candidate in used:
                continue
            with socket.socket() as sock:
                try:
                    sock.bind(("127.0.0.1", candidate))
                    port = candidate
                    break
                except OSError:
                    continue
        if port is None:
            raise ValueError("No application port available")
        state = {"launch_id": config["launch_id"], "port": port,
                 "secret_key_base": secrets.token_hex(64), "database_password": secrets.token_hex(32)}
        write_json(state_path, state)
    if config.get("lightek_application") and not state.get("owner_password"):
        state["owner_password"] = secrets.token_urlsafe(36)
        write_json(state_path, state)
    packages = []
    if not shutil.which("docker"):
        packages.extend(["docker.io", "docker-compose-v2"])
    elif subprocess.run(["docker", "compose", "version"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30).returncode:
        packages.append("docker-compose-v2")
    if not shutil.which("apache2ctl"):
        packages.append("apache2")
    if not shutil.which("certbot"):
        packages.extend(["certbot", "python3-certbot-apache"])
    if packages:
        run(["apt-get", "update", "-qq"])
        run(["apt-get", "install", "-y"] + packages,
            env={**os.environ, "DEBIAN_FRONTEND": "noninteractive"})
    run(["systemctl", "enable", "--now", "docker", "apache2"])
    run(["docker", "compose", "version"])
    project = f"lightek-app-{config['launch_id']}"
    compose = ["docker", "compose", "--project-name", project, "-f", str(root / "compose.json")]
    write_json(root / "compose.json", compose_config(config, state))
    registry = config.get("registry")
    if registry:
        docker_config = root / "registry"
        docker_config.mkdir(mode=0o700, exist_ok=True)
        os.environ["DOCKER_CONFIG"] = str(docker_config)
        run(["docker", "login", config["image"].split("/")[0], "--username", registry["username"], "--password-stdin"], input=registry["password"].encode())
    try:
        run(compose + ["pull"])
        if config["rails_database"]:
            run(compose + ["up", "-d", "--wait", "db", "redis"])
            run(compose + ["run", "--rm", "--no-deps", "web", "bin/rails", "db:prepare"])
            if config.get("lightek_application"):
                bootstrap = {"domain": domain, "owner_email": config["email"], "owner_password": state["owner_password"],
                             "owner_role": "admin", "site_name": config.get("name", domain), "headline": "Welcome",
                             "description": config.get("name", domain), "branding": config.get("branding"),
                             "reservation_federation": config.get("reservation_federation"), "demo_content": config.get("demo_content"), "managed_package": config.get("managed_package")}
                runner = ('require "json"; c=JSON.parse(STDIN.read); '
                          'raise "Rebuild this application image with demo upgrade support" if c["demo_content"] && !defined?(LightekAgency::DemoContent); '
                          'raise "Rebuild this application image with reseller package support" if c["managed_package"] && !defined?(LightekAgency::PackagePolicy); '
                          'LightekWebsite::Bootstrap.call(c); '
                          'LightekAgency::PackagePolicy.install!(user: User.find_by!(email_address: c.fetch("owner_email")), configuration: c["managed_package"]) if c["managed_package"]; '
                          'LightekAgency::DemoContent.install!(site: DymondSite::Site.find_by!(host: c.fetch("domain")), content: c["demo_content"]) if c["demo_content"]')
                run(compose + ["run", "--rm", "--no-deps", "-T", "web", "bin/rails", "runner", runner], input=json.dumps(bootstrap).encode())
            tasks = subprocess.check_output(compose + ["run", "--rm", "--no-deps", "web", "bin/rails", "-T"], stderr=subprocess.DEVNULL, timeout=180).decode()
            if "assets:precompile" in tasks:
                run(compose + ["run", "--rm", "--no-deps", "web", "bin/rails", "assets:precompile"])
        run(compose + ["up", "-d"])
    finally:
        if registry:
            shutil.rmtree(docker_config)
            os.environ.pop("DOCKER_CONFIG", None)
    health_path = "/up" if config["rails_database"] else "/"
    for attempt in range(90):
        try:
            with urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:{state['port']}{health_path}", headers={"Host": domain, "X-Forwarded-Proto": "https"}), timeout=5) as response:
                if response.status == 200:
                    break
        except Exception:
            time.sleep(2)
    else:
        raise ValueError("Container did not become healthy")
    run(["a2enmod", "proxy", "proxy_http", "headers", "ssl"])
    vhost = pathlib.Path("/etc/apache2/sites-available") / f"lightek-app-{config['launch_id']}.conf"
    vhost.write_text(f"<VirtualHost *:80>\nServerName {domain}\nProxyPreserveHost On\nRequestHeader set X-Forwarded-Proto expr=%{{REQUEST_SCHEME}}\nProxyPass / http://127.0.0.1:{state['port']}/\nProxyPassReverse / http://127.0.0.1:{state['port']}/\n</VirtualHost>\n")
    run(["a2ensite", vhost.name])
    run(["apache2ctl", "configtest"])
    run(["systemctl", "reload", "apache2"])
    run(["certbot", "--apache", "--non-interactive", "--agree-tos", "--redirect", "--keep-until-expiring", "-m", config["email"], "-d", domain])
    with urllib.request.urlopen(f"https://{domain}{health_path}", timeout=30) as response:
        if response.status != 200 or response.url.split("/")[2] != domain:
            raise ValueError("Public HTTPS verification failed")
    for service in (["web", "worker"] if config.get("rails_worker") else ["web"]):
        container = subprocess.check_output(compose + ["ps", "-q", service], timeout=30).decode().strip()
        actual = subprocess.check_output(["docker", "inspect", "--format", "{{.Config.Image}} {{.State.Running}}", container], timeout=30).decode().strip()
        if actual != config["image"] + " true":
            raise ValueError("Running image differs from template for " + service)
    health = {}
    if config.get("lightek_application"):
        verifier = globals().get("_lightek_verifier")
        if verifier is None:
            import runpy
            verifier = runpy.run_path(str(pathlib.Path(__file__).resolve().parents[3] / "script/lightek/verify_paid_instance.py"))
        health = verifier["verify_public"]({"domain": domain, "release": config["image"].split("@sha256:")[1],
                                            "owner_email": config["email"], "owner_password": state["owner_password"], "managed_package": config.get("managed_package"), "demo_content": config.get("demo_content"), "demo_content_digest": config.get("demo_content_digest")})
    fleet_config = {"compose_file": str(root / "compose.json"), "compose_project": project, "db_service": "db",
                    "health_url": f"https://{domain}/up", "revision_url": f"https://{domain}/__lightek/release"}
    return {"public_https_verified": True, "owner_login_verified": bool(health), "health": health, "release": health.get("release"), "fleet_config": fleet_config,
            "status": "succeeded", "domain": domain, "image": config["image"], "url": f"https://{domain}", "compose_project": project, "launch_id": config["launch_id"]}


if __name__ == "__main__":
    try:
        print(json.dumps(install(json.load(sys.stdin))))
    except Exception as error:
        print(json.dumps({"status": "failed", "error_class": type(error).__name__}))
        sys.exit(1)
