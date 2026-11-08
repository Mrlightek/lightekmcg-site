#!/usr/bin/env bash
set -euo pipefail
phase=$1
source_sha=$2
run_id=$3
[[ "$phase" =~ ^(integration|payment|cloud|payment_receipt)$ && "$source_sha" =~ ^[a-f0-9]{40}$ && "$run_id" =~ ^[0-9]+$ ]] || exit 1
sudo -u lightek -H env -u GEM_HOME -u GEM_PATH bash -s -- "$phase" "$source_sha" "$run_id" <<'APPLICATION'
set -euo pipefail
phase=$1
source_sha=$2
release_run_id=$3
set -a
source /etc/lightek/lightekmcg-site.env
set +a
export RBENV_ROOT=/home/lightek/.rbenv
export PATH=/home/lightek/.rbenv/versions/3.3.6/bin:/home/lightek/.rbenv/bin:/usr/local/bin:/usr/bin:/bin
root=/var/www/lightekmcg-site
production_database_url="${DATABASE_URL-}"
restore_production() {
  if [[ -n "$production_database_url" ]]; then export DATABASE_URL="$production_database_url"; else unset DATABASE_URL; fi
  export RAILS_ENV=production BUNDLE_GEMFILE="$root/Gemfile"
}
checkout=$(mktemp -d /tmp/lightek-resort-verification.XXXXXXXX)
cleanup() {
  restore_production
  if [[ "$phase" == cloud ]]; then
    (cd "$root" && bin/rails runner "$checkout/script/lightek/resort_live_verification.rb" cleanup "$checkout" "$release_run_id") || true
  fi
  if [[ -f "$checkout/release-database.json" ]]; then
    (cd "$root" && bundle exec ruby "$checkout/script/lightek/resort_release_database.rb" cleanup "$checkout/release-database.json")
  fi
  git -C "$root" worktree remove --force "$checkout" >/dev/null
}
git -C "$root" fetch origin feat/resort-reservations
git -C "$root" worktree add --detach "$checkout" "$source_sha"
trap cleanup EXIT
if [[ -f "$root/.bundle/config" ]]; then
  mkdir -p "$checkout/.bundle"
  cp "$root/.bundle/config" "$checkout/.bundle/config"
  chmod 600 "$checkout/.bundle/config"
fi
bundle_base=$(cd "$root" && bundle exec ruby -e 'puts Bundler.settings[:path].to_s')
if [[ -n "$bundle_base" ]]; then
  [[ "$bundle_base" == /* ]] || bundle_base="$root/$bundle_base"
  export BUNDLE_PATH="$bundle_base"
fi
cd "$root"
restore_production
if [[ "$phase" == integration ]]; then
  bin/rails runner "$checkout/script/lightek/resort_release_probe.rb"
  bin/rails runner "$checkout/script/lightek/resort_release_database.rb" prepare "$checkout/release-database.json" "$release_run_id"
  export DATABASE_URL="$(bundle exec ruby "$checkout/script/lightek/resort_release_database.rb" url "$checkout/release-database.json")"
  cd "$checkout"
  export RAILS_ENV=test PARALLEL_WORKERS=1 BUNDLE_GEMFILE="$checkout/Gemfile"
  bin/rails db:prepare
  bin/rails test test/services/lightek_reservations/release_test.rb
elif [[ "$phase" == cloud ]]; then
  bin/rails runner "$checkout/script/lightek/resort_live_verification.rb" cloud "$checkout" "$release_run_id"
else
  # PR 201 has one verification payment across source revisions. Re-running a
  # check never asks the customer to pay for another source commit.
  bin/rails runner "$checkout/script/lightek/resort_live_verification.rb" "$phase" "$checkout" 201
fi
APPLICATION
