#!/usr/bin/env bash
# Run on an application checkout with its private gems and PostgreSQL available.
set -euo pipefail
cd "$(dirname "$0")/../.."
export RAILS_ENV=test
export PARALLEL_WORKERS=1
bundle check
bin/rails db:test:prepare
bin/rails zeitwerk:check
bin/rails test test/services/lightek_mail/mail_studio_test.rb test/services/lightek_mail/sending_controls_test.rb test/services/lightek_mail/spam_scanner_test.rb test/services/lightek_mail/reservation_concurrency_test.rb test/integration/lightek_mail_test.rb test/integration/lightek_mail_controls_test.rb
python3 -m unittest discover -s test/operations -p 'lightek_mail*_test.py'
printf 'LIGHTEK_MAIL_HOST_VERIFICATION_PASSED\n'
