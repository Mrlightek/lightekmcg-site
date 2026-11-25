# frozen_string_literal: true

environment "production"
threads 0, 3
workers 0
bind "tcp://127.0.0.1:#{Integer(ENV.fetch("LIGHTEK_SLOT_PORT"), 10)}"
