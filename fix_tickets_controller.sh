#!/bin/bash
set -e
sed -i '' 's/before_action :set_ticket, only: %i\[show update reply resolve\]/before_action :set_ticket, only: %i[show reply resolve]/' \
  ~/Desktop/Development/lightekmcg-site/app/controllers/employee/tickets_controller.rb

echo "Fixed. Restart:"
echo "  rm -rf tmp/cache/bootsnap*"
echo "  bin/rails server"
