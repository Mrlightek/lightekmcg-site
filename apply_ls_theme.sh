#!/bin/bash
set -e
cat > /tmp/apply_ls_theme.rb << 'RUBY_EOF'
# frozen_string_literal: true
theme = DymondTheme::Theme.find_or_initialize_by(slug: "ls-cinematic")
theme.assign_attributes(
  name: "LS Cinematic",
  is_preset: true,
  sidebar_bg: "#0a0d12",
  topbar_bg: "#0a0d12",
  accent_primary: "#00d4e8",
  accent_hover: "#33e0f0",
  text_primary: "#e8ecf1",
  text_secondary: "rgba(232,236,241,0.65)",
  text_muted: "rgba(232,236,241,0.40)",
  border_color: "rgba(255,255,255,0.08)",
  card_bg: "#12161d",
  danger_color: "#f0455a",
  success_color: "#2ed88a",
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
