#!/usr/bin/env bash
# Bootstrap the lightek_ui gem AND move the shared form primitives into it —
# by COPYING your real helper files verbatim (no retyping, no drift). Then
# rewrap their module namespace for the new gem.
#
# Run from an EMPTY lightek_ui repo, and pass the path to dymond_dash's helpers:
#   cd ~/Desktop/Development/lightek_ui
#   bash bootstrap_lightek_ui.sh
#
# It auto-locates the bundled dymond_dash helpers via `bundle show` run from the
# HOST app — so run it with the host app path available, or it'll prompt.
set -euo pipefail
echo "==> Bootstrapping lightek_ui in $(pwd)"

# --- locate the source helpers (from the host app's bundled dymond_dash) ---
HOST="${HOST_APP:-$HOME/Desktop/Development/lightekmcg-site}"
DD=$(cd "$HOST" 2>/dev/null && bundle show dymond_dash 2>/dev/null || true)
if [ -z "$DD" ] || [ ! -d "$DD/app/helpers/dymond_dash" ]; then
  echo "!! could not locate dymond_dash helpers via '$HOST'."
  echo "   Set HOST_APP=/path/to/lightekmcg-site and re-run, or copy the two"
  echo "   helper files into ./_src/ manually and re-run."
  exit 1
fi
echo "  source helpers: $DD/app/helpers/dymond_dash/"

# --- gem skeleton ---
mkdir -p lib/lightek_ui
mkdir -p app/helpers/lightek_ui

cat > lib/lightek_ui/version.rb <<'RUBY'
# frozen_string_literal: true
module LightekUi
  VERSION = "0.1.0"
end
RUBY

cat > lib/lightek_ui/engine.rb <<'RUBY'
# frozen_string_literal: true
require "rails/engine"
module LightekUi
  # Ships shared view PRIMITIVES (schema-form field renderers, attachment field)
  # to any host app's views. Theme-agnostic: primitives reference CSS variables
  # (var(--...)) so ANY theming system that defines those vars can present them.
  class Engine < ::Rails::Engine
    isolate_namespace LightekUi
    # Make our helpers available to the whole host app (not just engine views).
    initializer "lightek_ui.helpers" do
      ActiveSupport.on_load(:action_controller_base) do
        helper LightekUi::SchemaFormHelper
        helper LightekUi::AttachmentFieldHelper
      end
    end
  end
end
RUBY

cat > lib/lightek_ui.rb <<'RUBY'
# frozen_string_literal: true
require "lightek_ui/version"
require "lightek_ui/engine" if defined?(Rails::Engine)
module LightekUi; end
RUBY

# --- MOVE the helpers verbatim, only rewrapping the module namespace ---
# section_form_helper.rb  -> LightekUi::SchemaFormHelper (keeps ds_* method names)
SRC="$DD/app/helpers/dymond_dash/section_form_helper.rb"
DST="app/helpers/lightek_ui/schema_form_helper.rb"
sed -e 's/module DymondDash/module LightekUi/' \
    -e 's/module SectionFormHelper/module SchemaFormHelper/' \
    "$SRC" > "$DST"
echo "  moved: section_form_helper.rb -> $DST (LightekUi::SchemaFormHelper)"

# attachment_field_helper.rb -> LightekUi::AttachmentFieldHelper
SRC2="$DD/app/helpers/dymond_dash/attachment_field_helper.rb"
DST2="app/helpers/lightek_ui/attachment_field_helper.rb"
sed -e 's/module DymondDash/module LightekUi/' \
    "$SRC2" > "$DST2"
echo "  moved: attachment_field_helper.rb -> $DST2 (LightekUi::AttachmentFieldHelper)"

# --- gemspec ---
cat > lightek_ui.gemspec <<'RUBY'
require_relative "lib/lightek_ui/version"
Gem::Specification.new do |s|
  s.name        = "lightek_ui"
  s.version     = LightekUi::VERSION
  s.summary     = "Lightek shared UI primitives (schema-form field renderers)"
  s.authors     = ["LightekMCG"]
  s.email       = ["dev@lightekmcg.com"]
  s.homepage    = "https://lightekmcg.com"
  s.license     = "Proprietary"
  s.required_ruby_version = ">= 3.2.0"
  s.files = Dir["app/**/*.rb", "lib/**/*.rb", "README.md"]
  s.require_paths = ["lib"]
  s.add_dependency "rails", ">= 7.2"
  # No theme dependency — primitives are CSS-variable based, theme-agnostic.
end
RUBY

cat > README.md <<'MD'
# lightek_ui
Shared view PRIMITIVES for the Lightek platform: schema-form field renderers
(ds_field + field types: string/text/richtext/boolean/animation/collection/
attachment/color/select) and the attachment field.

Theme-agnostic by design: primitives reference CSS variables (var(--color-...))
so ANY theming system (dymond_theme, or a future one) can present them. The
primitive layer (mechanism) is decoupled from the presentation layer (skin) via
the CSS-variable contract.

Consumers: dymond_dash (section editor, template editor), and every future
domain the scaffold emits — all get schema-driven forms from here.
MD

cat > .gitignore <<'GI'
*.gem
.bundle/
pkg/
.DS_Store
GI

echo ""
echo "==> lightek_ui built. Structure:"
find . -type f -not -path './.git/*' | sort
echo ""
echo "==> Verify the moved helpers kept their content (should be ~same line counts):"
wc -l "$DST" "$DST2"
echo ""
echo "==> Next: commit + push lightek_ui, then repoint dymond_dash (separate script)."
