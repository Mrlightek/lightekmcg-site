#!/bin/bash
set -e
cat > /tmp/apply_ls_theme.rb << 'RUBY_EOF'
theme = DymondTheme::Theme.find_or_initialize_by(name: "LS Cinematic")
theme.assign_attributes(
  preset: true,
  scope: "global",
  tokens: {
    "accent"         => "#00d4e8",
    "accent_hover"   => "#33e0f0",
    "border"         => "rgba(255,255,255,0.08)",
    "danger"         => "#f0455a",
    "success"        => "#2ed88a",
    "card_bg"        => "#12161d",
    "topbar_bg"      => "#0a0d12",
    "sidebar_bg"     => "#0a0d12",
    "text_muted"     => "rgba(232,236,241,0.40)",
    "text_primary"   => "#e8ecf1",
    "text_secondary" => "rgba(232,236,241,0.65)"
  },
  custom_css: <<~CSS
    @import url('https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@500;600;700&family=Barlow:wght@400;500&family=Space+Mono:wght@400;700&display=swap');
    body { font-family: 'Barlow', sans-serif !important; }
    .dd-brand-name, .dd-card-title, .dd-topbar-title, .dd-page-title, h1, h2 {
      font-family: 'Barlow Condensed', sans-serif !important; letter-spacing: 0.02em;
    }
    .dd-nav-label { font-family: 'Space Mono', monospace !important; letter-spacing: 0.14em; }
  CSS
)
theme.save!
puts "Theme saved: #{theme.id} — #{theme.name}"

config = DymondDash::AppConfig.current
config.update!(theme_id: theme.id)
puts "Active theme set to: #{DymondDash::AppConfig.current.theme.name}"
RUBY_EOF
cd ~/Desktop/Development/lightekmcg-site
bin/rails runner /tmp/apply_ls_theme.rb
rm /tmp/apply_ls_theme.rb
