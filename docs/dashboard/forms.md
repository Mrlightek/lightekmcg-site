# Dashboard forms and order management

The shared dashboard form stylesheet is `public/lightek/dashboard-forms.css`. The Dymond Dash layout loads it after the existing dashboard styles. Colors come from the saved Dashboard Appearance palette, including input colors and primary-button text contrast. Light and dark themes use the same components.

## Component patterns

- Wrap a page in `dd-workspace`. Use `dd-page-header dd-page-hero` for its title, description and navigation.
- Group related inputs in `dd-form-section` with a visible heading. Use `dd-form-layout` and `dd-form-column` for a main form and settings column; the layout stacks on smaller screens.
- Wrap each label and control in `dd-field`. Use `dd-form-grid` for paired fields and `dd-form-stack` for a vertical form. Associate help text using `aria-describedby`.
- Use `dd-check` for a checkbox and its label. Checkboxes retain their own dimensions.
- Group submit and cancel actions in `dd-form-actions`. `dd-button` is the shared secondary button, `dd-button dd-btn-primary` is the primary action, and `dd-button dd-button-danger` is a destructive action. Destructive actions use the theme's danger color rather than the primary accent.
- Render validation summaries with `dd-form-errors` and `role="alert"`. Native field errors and `aria-invalid` use the existing theme error treatment.
- Specialized application workbenches retain their controls. Their custom control containers can use `data-dashboard-controls="custom"` to opt out of default field geometry.

Orders and the product editor now use these components. Existing dashboard forms inherit the shared control sizing, focus states and theme colors; existing settings tables also receive consistent cell spacing and separators. Other complex page layouts can adopt the section components incrementally.

## Orders

Go to **Commerce → Orders**. The overview shows up to 150 recent orders, payment status, customer, items and total. Summary counts apply only to the orders shown. Open **Manage order** for fulfillment, refunds, application access or unpaid cleanup.

Labels stay visible while entering tracking details or a refund. Refund amounts remain in cents, with explicit guidance. Refund submission asks for confirmation. Unpaid cleanup can be performed per order or with selection checkboxes. When JavaScript is available, **Select all unpaid**, a live selection count and selected-row highlighting are enabled. Individual selection, action forms and native expandable panels continue working without the enhancement. Payment and installation protections remain enforced on the server.

## Verification

```sh
ruby test/support/export_dashboard_forms.rb /tmp/lightek-form-fixtures
NODE_PATH=/path/to/playwright/node_modules node test/javascript/dashboard_forms_browser_test.cjs
```

The exporter renders the actual Rails Orders and Product form templates against the standalone commerce database harness. Browser checks cover desktop/mobile layouts, light/dark palettes, expandable action forms, selection state, checkbox geometry, field labels, primary-action contrast and page overflow. Dashboard Appearance CI runs the checks in Chromium and WebKit. The standalone commerce checks also cover bulk deletion, payment protections and account boundaries.

## Account verification

The MFA challenge uses a focused, single-column security card rather than the dashboard shell. It inherits the current website’s authentication branding and includes a host indicator, labeled code field, recovery help and accessible errors. See [sign-in and MFA](../security/sign-in-and-mfa.md#verify-your-sign-in-or-refresh-an-existing-session).
