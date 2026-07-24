#!/bin/bash
set -e
cd ~/Desktop/Development/lightekmcg-site

echo "Writing Employee::ApplicationController..."
mkdir -p app/controllers/employee
cat > app/controllers/employee/application_controller.rb << 'EOF'
# frozen_string_literal: true
module Employee
  # Renders inside the dashboard chrome — same rule the whole ecosystem
  # follows: if you render dash's layout, you inherit dash's controller.
  # Gets layout, nav, current_user, and auth for free from DymondDash.
  class ApplicationController < ::DymondDash::ApplicationController
    before_action :require_employee!

    private

    def require_employee!
      return if current_user&.employee? || current_user&.admin?
      redirect_to main_app.root_path, alert: "Employees only."
    end
  end
end
EOF

echo "Writing Employee::DashboardController..."
cat > app/controllers/employee/dashboard_controller.rb << 'EOF'
# frozen_string_literal: true
module Employee
  class DashboardController < Employee::ApplicationController
    def index; end
  end
end
EOF

mkdir -p app/views/employee/dashboard
cat > app/views/employee/dashboard/index.html.erb << 'EOF'
<% content_for :page_title, "Employee Dashboard" %>
<div class="dd-card">
  <div class="dd-card-title">Welcome, <%= current_user.full_name %></div>
  <p style="color:var(--dd-text-secondary); font-size:13px;">
    <%= link_to "View Clients", employee_clients_path %>
  </p>
</div>
EOF

echo "Writing Employee::ClientsController..."
cat > app/controllers/employee/clients_controller.rb << 'EOF'
# frozen_string_literal: true
module Employee
  class ClientsController < Employee::ApplicationController
    def index
      authorize! :read, User
      @clients = User.where(role: "client").order(:last_name, :first_name)
    end

    def show
      @client = User.where(role: "client").find(params[:id])
      authorize! :read, @client

      @invoices         = @client.invoices.order(created_at: :desc)
      @subscription     = @client.subscription
      @linked_accounts  = @client.linked_accounts.active
      @notifications    = defined?(DymondDash::Notification) ?
                             DymondDash::Notification.for_recipient(@client).recent.limit(10) : []
    end
  end
end
EOF

echo "Writing client views..."
mkdir -p app/views/employee/clients
cat > app/views/employee/clients/index.html.erb << 'EOF'
<% content_for :page_title, "Clients" %>
<div class="dd-card">
  <% if @clients.any? %>
    <% @clients.each do |c| %>
      <div style="display:flex; align-items:center; justify-content:space-between; padding:10px 0; border-bottom:1px solid var(--dd-border);">
        <div>
          <span style="font-weight:600;"><%= c.full_name %></span>
          <span style="color:var(--dd-text-muted); font-size:12px;"> · <%= c.email_address %></span>
        </div>
        <%= link_to "View", employee_client_path(c), class: "dd-topbar-btn dd-btn-ghost" %>
      </div>
    <% end %>
  <% else %>
    <p style="color:var(--dd-text-secondary); font-size:13px;">No clients yet.</p>
  <% end %>
</div>
EOF

cat > app/views/employee/clients/show.html.erb << 'EOF'
<% content_for :page_title, @client.full_name %>
<% content_for :topbar_actions do %>
  <%= link_to "All Clients", employee_clients_path, class: "dd-topbar-btn dd-btn-ghost" %>
<% end %>

<div class="dd-card" style="margin-bottom:16px;">
  <div class="dd-card-title">Contact</div>
  <p style="font-size:13px;"><%= @client.email_address %></p>
  <p style="font-size:13px; color:var(--dd-text-secondary);">Role: <%= @client.role.capitalize %></p>
</div>

<div class="dd-card" style="margin-bottom:16px;">
  <div class="dd-card-title">Subscription</div>
  <% if @subscription %>
    <p style="font-size:13px;">
      <%= @subscription.status.capitalize %> · <%= @subscription.billing_interval %> ·
      renews <%= @subscription.current_period_end&.strftime("%B %-d, %Y") %>
    </p>
  <% else %>
    <p style="font-size:13px; color:var(--dd-text-secondary);">No active subscription.</p>
  <% end %>
</div>

<div class="dd-card" style="margin-bottom:16px;">
  <div class="dd-card-title">Invoices</div>
  <% if @invoices.any? %>
    <% @invoices.each do |inv| %>
      <div style="display:flex; justify-content:space-between; padding:6px 0; border-bottom:1px solid var(--dd-border); font-size:13px;">
        <span><%= inv.number %> · <%= inv.status.capitalize %></span>
        <span>$<%= number_with_delimiter(inv.total_cents / 100.0, precision: 2) %></span>
      </div>
    <% end %>
  <% else %>
    <p style="font-size:13px; color:var(--dd-text-secondary);">No invoices.</p>
  <% end %>
</div>

<div class="dd-card" style="margin-bottom:16px;">
  <div class="dd-card-title">Linked Bank Accounts</div>
  <% if @linked_accounts.any? %>
    <% @linked_accounts.each do |acct| %>
      <p style="font-size:13px;"><%= acct.institution_name %> · <%= acct.account_last4 %> · <%= acct.status.capitalize %></p>
    <% end %>
  <% else %>
    <p style="font-size:13px; color:var(--dd-text-secondary);">No linked accounts.</p>
  <% end %>
</div>

<div class="dd-card">
  <div class="dd-card-title">Recent Notifications</div>
  <% if @notifications.any? %>
    <% @notifications.each do |n| %>
      <p style="font-size:13px;"><%= n.title %> · <%= n.created_at.strftime("%b %-d") %></p>
    <% end %>
  <% else %>
    <p style="font-size:13px; color:var(--dd-text-secondary);">No notifications.</p>
  <% end %>
</div>
EOF

echo "Adding employee-role feature gate to User model..."
if grep -q "employee_clients" app/models/user.rb; then
  echo "  (already present, skipping)"
else
  perl -0pi -e 's/(when :lightek_studio\n        employee\? \|\| admin\?)/$1\n      when :employee_clients\n        employee? || admin?/' app/models/user.rb
  if grep -q "employee_clients" app/models/user.rb; then
    echo "  OK — patched successfully"
  else
    echo "  WARNING: automatic patch did not match. Add this manually to app/models/user.rb"
    echo "  inside can_access_feature?, right after the :lightek_studio branch:"
    echo "      when :employee_clients"
    echo "        employee? || admin?"
  fi
fi

echo "Registering Clients nav item..."
cat > config/initializers/employee_nav.rb << 'EOF'
# frozen_string_literal: true
# Registers Clients in the dashboard nav — visible to employee/admin only,
# via User#can_access_feature?(:employee_clients).
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |f|
    f.slug = :employee_clients; f.label = "Clients"; f.icon = "users"
    f.gem_source = "host"; f.nav_section = :overview; f.min_plan = :starter
    f.nav_items = [
      { label: "Clients", icon: "users", path: "employee_clients_path" }
    ]
  end
rescue StandardError => e
  Rails.logger.warn "[Employee] nav registration skipped: #{e.message}"
end
EOF

echo ""
echo "Done. All host-app files — no gem push needed. Just restart:"
echo "  rm -rf tmp/cache/bootsnap*"
echo "  bin/rails server"
echo ""
echo "Then visit /dashboard (Clients tab should appear if signed in as employee/admin)"
echo "or directly: /employee/clients"
