# A local-only Action Cable backend for Apache/Passenger deployments.
directory File.expand_path("..", __dir__)
environment ENV.fetch("RAILS_ENV", "production")
bind "tcp://127.0.0.1:28080"
threads 0, 4
workers 0
pidfile File.expand_path("../tmp/pids/cable.pid", __dir__)
