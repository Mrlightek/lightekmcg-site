#!/usr/bin/env bash
# Execute against the host application, with private gems and a dedicated test DB.
set -euo pipefail
cd "$(dirname "$0")/../.."
export RAILS_ENV=test PARALLEL_WORKERS=1
bundle check
bin/rails db:test:prepare
bin/rails zeitwerk:check
bin/rails test test/integration/lightek_business_payouts_test.rb
echo LIGHTEK_BUSINESS_PAYOUTS_VERIFIED
