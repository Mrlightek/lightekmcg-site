#!/bin/bash
set -e
cd ~/Desktop/Development/lightekmcg-site

echo "Writing Employee::UsersController..."
cat > app/controllers/employee/users_controller.rb << 'EOF'
# frozen_string_literal: true
module Employee
  # Account/role management is more sensitive than Clients/Projects/Tickets —
  # gated to admin/super_admin only, not plain employee?, and a regular admin
  # can't grant super_admin (only a super_admin can create another one).
  class UsersController < Employee::ApplicationController
    before_action :require_admin!
    before_action :set_user, only: %i[edit update destroy]

    def index
      authorize! :read, User
      @users = User.order(:role, :last_name, :first_name)
    end

    def new
      authorize! :create, User
      @user = User.new(role: "client")
    end

    def create
      authorize! :create, User
      @user = User.new(user_params)
      guard_role_escalation!(@user)
      if @user.save
        redirect_to employee_users_path, notice: "User created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize! :update, @user
    end

    def update
      authorize! :update, @user
      attrs = user_params
      attrs.delete(:password) if attrs[:password].blank?
      attrs.delete(:password_confirmation) if attrs[:password_confirmation].blank?
      @user.assign_attributes(attrs)
      guard_role_escalation!(@user)
      if @user.save
        redirect_to employee_users_path, notice: "User updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize! :destroy, @user
      if @user == current_user
        redirect_to employee_users_path, alert: "You can't delete your own account."
        return
      end
      @user.destroy
      redirect_to employee_users_path, notice: "User removed."
    end

    private

    def require_admin!
      return if current_user&.admin?
      redirect_to employee_dashboard_path, alert: "Admins only."
    end

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:email_address, :first_name, :last_name, :role,
                                    :password, :password_confirmation)
    end

    # Only a super_admin can create/promote another super_admin.
    def guard_role_escalation!(user)
      return unless user.role == "super_admin"
      return if current_user.role == "super_admin"

      user.role = user.role_was.presence || "client"
    end
  end
end
EOF

echo "Writing views..."
mkdir -p app/views/employee/users
cat > app/views/employee/users/index.html.erb << 'EOF'
<% content_for :page_title, "Users" %>
<% content_for :topbar_actions do %>
  <%= link_to "New User", new_employee_user_path, class: "dd-topbar-btn dd-btn-primary" %>
<% end %>

<div class="dd-card">
  <% @users.each do |u| %>
    <div style="display:flex; align-items:center; justify-content:space-between; padding:10px 0; border-bottom:1px solid var(--dd-border);">
      <div>
        <span style="font-weight:600;"><%= u.full_name %></span>
        <span style="color:var(--dd-text-muted); font-size:12px;"> · <%= u.email_address %> · <%= u.role.humanize %></span>
      </div>
      <div style="display:flex; gap:10px;">
        <%= link_to "Edit", edit_employee_user_path(u), class: "dd-topbar-btn dd-btn-ghost" %>
        <% unless u == current_user %>
          <%= button_to "Delete", employee_user_path(u), method: :delete,
                form: { data: { turbo_confirm: "Remove #{u.full_name}? This can't be undone." } }, class: "dd-topbar-btn dd-btn-ghost" %>
        <% end %>
      </div>
    </div>
  <% end %>
</div>
EOF

cat > app/views/employee/users/_form.html.erb << 'EOF'
<%= form_with model: @user, url: (@user.persisted? ? employee_user_path(@user) : employee_users_path) do |f| %>
  <div class="dd-card" style="display:flex; flex-direction:column; gap:12px; max-width:500px;">
    <label>First Name <%= f.text_field :first_name, class: "fg-input" %></label>
    <label>Last Name <%= f.text_field :last_name, class: "fg-input" %></label>
    <label>Email <%= f.email_field :email_address, class: "fg-input" %></label>
    <label>Role
      <%= f.select :role,
            User::ROLES.reject { |r| r == "super_admin" && current_user.role != "super_admin" }.map { |r| [r.humanize, r] },
            {}, class: "fg-input" %>
    </label>
    <label>Password <%= f.password_field :password, class: "fg-input", placeholder: (@user.persisted? ? "Leave blank to keep current password" : "") %></label>
    <label>Confirm Password <%= f.password_field :password_confirmation, class: "fg-input" %></label>
    <%= f.submit (@user.persisted? ? "Update User" : "Create User"), class: "dd-topbar-btn dd-btn-primary" %>
  </div>
<% end %>
EOF

cat > app/views/employee/users/new.html.erb << 'EOF'
<% content_for :page_title, "New User" %>
<%= render "form" %>
EOF

cat > app/views/employee/users/edit.html.erb << 'EOF'
<% content_for :page_title, "Edit #{@user.full_name}" %>
<%= render "form" %>
EOF

echo "Adding routes..."
if grep -q "resources :users" config/routes.rb; then
  echo "  (routes already present, skipping)"
else
  perl -0pi -e 's/(namespace :employee do\n)/$1    resources :users, only: %i[index new create edit update destroy]\n/' config/routes.rb
fi

echo "Adding admin-only feature gate + Users nav..."
if grep -q "employee_users" app/models/user.rb; then
  echo "  (user.rb already patched, skipping)"
else
  perl -0pi -e 's/(when :employee_tickets\n        employee\? \|\| admin\?)/$1\n      when :employee_users\n        admin?/' app/models/user.rb
fi

cat > config/initializers/employee_users_nav.rb << 'EOF'
# frozen_string_literal: true
# Users nav item — admin-only (User#can_access_feature?(:employee_users)).
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |f|
    f.slug = :employee_users; f.label = "Users"; f.icon = "users-group"
    f.gem_source = "host"; f.nav_section = :overview; f.min_plan = :starter
    f.nav_items = [{ label: "Users", icon: "users-group", path: "employee_users_path" }]
  end
rescue StandardError => e
  Rails.logger.warn "[Users] nav registration skipped: #{e.message}"
end
EOF

echo ""
echo "Verifying routes.rb patch..."
if grep -q "resources :users" config/routes.rb; then
  echo "  OK — routes patched"
else
  echo "  WARNING: routes.rb patch did not apply. Add manually inside 'namespace :employee do':"
  echo "    resources :users, only: %i[index new create edit update destroy]"
fi

echo "Verifying user.rb patch..."
if grep -q "employee_users" app/models/user.rb; then
  echo "  OK — user.rb patched"
else
  echo "  WARNING: user.rb patch did not apply. Add manually inside can_access_feature?, after :employee_tickets:"
  echo "      when :employee_users"
  echo "        admin?"
fi

echo ""
echo "Done. All host-app files — no gem push needed. Restart:"
echo "  rm -rf tmp/cache/bootsnap*"
echo "  bin/rails server"
echo ""
echo "Visit /employee/users"
