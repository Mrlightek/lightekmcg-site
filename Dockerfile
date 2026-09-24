# syntax=docker/dockerfile:1
FROM ruby:3.3.6-slim

# Install Postfix alongside essential build tools
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    build-essential libpq-dev libyaml-dev libffi-dev pkg-config \
    git openssh-client postgresql-client curl postfix \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mkdir -p -m 0700 ~/.ssh && ssh-keyscan github.com >> ~/.ssh/known_hosts

COPY Gemfile Gemfile.lock ./
RUN --mount=type=ssh bundle install --jobs 1

COPY . .

# Copy Postfix configuration into the system folder
COPY config/postfix/master.cf /etc/postfix/master.cf

COPY bin/docker-entrypoint.sh /usr/bin/
RUN chmod +x /usr/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]

# Expose HTTP (3000) and SMTP (25)
EXPOSE 3000 25
CMD ["bin/rails", "server", "-b", "0.0.0.0"]
