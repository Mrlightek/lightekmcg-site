# Dashboard appearance

Go to **Dashboard → Settings → Dashboard & branding → Dashboard appearance** as a super admin. Select colors for page backgrounds, sidebar/panels, top bar, cards, primary/secondary/muted text, accent and hover, field background/text/borders, borders, and success/error statuses. **Save Dashboard colors** applies them to the shared Dashboard shell, ordinary forms, Business workspace navigation, and compatible Dashboard components.

**Theme presets** opens the existing theme picker. Saving colors creates an admin-scoped copy of the current theme; it does not overwrite a preset or change public website or PWA configuration. Existing custom tokens, CSS and templates are retained. Primary button text automatically uses black or white for contrast. Other foreground/background pairings remain the operator's choice.

The shared administration stylesheet provides compact 36px desktop fields, intrinsic-width buttons, bounded form widths, responsive grids, and a mobile navigation toggle. Studio and Nevaeh keep their own specialized workbench control geometry. Media, starter-design artwork and content previews retain their own colors.

PWA Settings currently exposes accent and background colors. A complete PWA palette editor is separate work; Dashboard colors do not supply those settings.

Validation: `ruby test/standalone/dashboard_appearance_test.rb` exercises color validation, controller authorization, admin-only persistence, preset/PWA isolation, and primary button contrast against a public Rails fixture. `ruby test/standalone/dashboard_breadcrumbs_test.rb` checks shared navigation labels. Browser review renders actual ERB views with fixture data in light and dark palettes; production/private-engine boot still needs release validation.

