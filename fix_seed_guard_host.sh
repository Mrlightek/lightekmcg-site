#!/usr/bin/env bash
# Repoint the DymondDash boot-seed guard at canonical themes (the old guard
# referenced dropped dymond_dash_themes / removed DymondDash::Theme). Native
# rewrite of the after_initialize block. Run from the HOST app root.
#   cd ~/Desktop/Development/lightekmcg-site && bash fix_seed_guard_host.sh
set -euo pipefail
F=config/initializers/dymond_dash.rb
[ -f "$F" ] || { echo "!! $F not found — run from host app root"; exit 1; }

# Idempotency: if already repointed, stop.
if grep -q "DymondTheme::Theme.where(scope:" "$F"; then
  echo "  already repointed at canonical — nothing to do."; exit 0
fi

# Replace everything from the "# Seed" comment to end of file with the fixed block.
# We cut at the comment marker (stable) and append the corrected trigger.
if grep -qn "# Seed DymondDash defaults" "$F"; then
  CUT=$(grep -n "# Seed DymondDash defaults" "$F" | head -1 | cut -d: -f1)
  head -n $((CUT-1)) "$F" > "${F}.tmp"
else
  # no marker — keep whole file, append fixed block after it
  cp "$F" "${F}.tmp"
fi

cat >> "${F}.tmp" <<'RUBY'
# Seed DymondDash defaults on first boot (idempotent; only when empty).
# Checks canonical admin themes — the legacy dymond_dash_themes table was
# consolidated into dymond_theme_themes.
Rails.application.config.after_initialize do
  if defined?(DymondTheme::Theme) &&
     DymondTheme::Theme.where(scope: "admin").count.zero?
    DymondDash::Seeds.run
  end
rescue StandardError => e
  Rails.logger.warn "[DymondDash] boot seed skipped: #{e.message}" if defined?(Rails) && Rails.logger
end
RUBY

mv "${F}.tmp" "$F"
echo "  seed guard repointed at canonical DymondTheme::Theme (scope: admin)."
echo "==> Result (tail):"; tail -12 "$F"
