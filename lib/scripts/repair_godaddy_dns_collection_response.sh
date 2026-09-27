#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

STAMP="$(date +%Y%m%d%H%M%S)"
BACKUP="tmp/repair_godaddy_dns_collection_${STAMP}"
mkdir -p "$BACKUP"

SERVICE="app/services/godaddy/dns_service.rb"
VIEW="app/views/dashboard/network/index.html.erb"

for f in "$SERVICE" "$VIEW"; do
  if [[ -f "$f" ]]; then
    mkdir -p "$BACKUP/$(dirname "$f")"
    cp "$f" "$BACKUP/$f"
  fi
done

[[ -f "$SERVICE" ]] || { echo "ERROR: $SERVICE not found"; exit 1; }

python3 <<'PY'
from pathlib import Path
import re

path = Path("app/services/godaddy/dns_service.rb")
src = path.read_text()

replacement = """    def records
      page = 1
      items = []

      loop do
        response = request(:get, "?page=#{page}&pageSize=100&totalRequired=true")
        raise ApiError, "Unexpected GoDaddy DNS response: #{response.class}" unless response.is_a?(Hash)

        page_items = response.fetch("items", [])
        raise ApiError, "Unexpected GoDaddy DNS items payload: #{page_items.class}" unless page_items.is_a?(Array)

        items.concat(page_items)

        total_pages = response["totalPages"].to_i
        break if total_pages <= page || page_items.empty?

        page += 1
      end

      items
    end
"""

if 'def records = request(:get, "")' in src:
    src = src.replace('    def records = request(:get, "")\n', replacement, 1)
elif 'response.fetch("items", [])' in src:
    print("DnsService#records already normalized.")
else:
    m = re.search(r'(?ms)^    def records\n.*?^    end\n', src)
    if not m:
        raise SystemExit("ERROR: DnsService#records implementation not found")
    src = src[:m.start()] + replacement + src[m.end():]

path.write_text(src)
print("Patched DnsService#records.")
PY

python3 <<'PY'
from pathlib import Path

path = Path("app/views/dashboard/network/index.html.erb")
src = path.read_text()
needle = '        <% Array(@records).each do |record| %>\n'
insert = needle + '          <% next unless record.is_a?(Hash) %>\n'

if 'next unless record.is_a?(Hash)' in src:
    print("View Hash guard already present.")
elif needle in src:
    path.write_text(src.replace(needle, insert, 1))
    print("Added DNS view Hash guard.")
else:
    raise SystemExit("ERROR: DNS record loop not found")
PY

cat > lib/tasks/gatekeeper_godaddy_response_lesson.rake <<'RUBY'
namespace :gatekeeper do
  desc "Teach the GoDaddy v3 DNS collection response contract"
  task learn_godaddy_dns_collection_response: :environment do
    article = Gatekeeper::LessonService.record!(
      key: "GK-LESSON-GODADDY-DNS-COLLECTION-RESPONSE",
      title: "GoDaddy DNS list responses wrap records in items",
      capability: "dns_management",
      symptom: "The Network & Domains dashboard returns HTTP 500 with TypeError: no implicit conversion of String into Integer while rendering record[\"type\"].",
      cause: "GET /v3/domains/zones/{zone}/dns-records returns a collection object. DNS records are inside response[\"items\"]. Converting the response hash with Array(...) creates key/value pair arrays, so string-key lookup fails in the view.",
      remediation: "Normalize the provider response inside Godaddy::DnsService#records. Extract response[\"items\"], validate Array<Hash>, follow page/totalPages pagination with pageSize=100, and return only DNS record hashes.",
      verification: "Run bin/rails zeitwerk:check, confirm Godaddy::DnsService#records returns Array<Hash>, then request /dashboard/network and verify HTTP 200.",
      metadata: {
        provider: "godaddy",
        endpoint: "GET /v3/domains/zones/{zone}/dns-records",
        failure_signature: "TypeError: no implicit conversion of String into Integer",
        auto_executable: true,
        response_collection_key: "items"
      }
    )
    puts "Recorded GK-LESSON-GODADDY-DNS-COLLECTION-RESPONSE as KB article #{article.id}"
  end
end
RUBY

echo "=== RUBY SYNTAX ==="
ruby -c "$SERVICE"
ruby -c lib/tasks/gatekeeper_godaddy_response_lesson.rake

echo "=== ZEITWERK ==="
bin/rails zeitwerk:check

echo "=== RECORD KB LESSON ==="
bin/rails gatekeeper:learn_godaddy_dns_collection_response

echo "=== DIFF CHECK ==="
git diff --check

echo "=== STATUS ==="
git status --short

echo "REPAIR COMPLETE"
echo "Backup: $BACKUP"
