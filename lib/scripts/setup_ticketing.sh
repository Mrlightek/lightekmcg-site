#!/bin/bash
set -e
cd ~/Desktop/Development/lightekmcg-site

echo "Writing migrations..."
TS1=$(date -u +%Y%m%d%H%M%S)
cat > "db/migrate/${TS1}_create_marlon_tickets.rb" << 'EOF'
# frozen_string_literal: true
class CreateMarlonTickets < ActiveRecord::Migration[8.0]
  def change
    create_table :marlon_tickets do |t|
      t.string   :number,          null: false
      t.string   :category,        null: false
      t.string   :title,           null: false
      t.text     :description
      t.string   :priority,        null: false, default: "medium"
      t.integer  :urgency,         null: false, default: 5
      t.string   :status,          null: false, default: "open"
      t.bigint   :submitted_by_id
      t.string   :organization_name
      t.string   :reseller_id
      t.string   :assigned_team
      t.string   :assigned_rep
      t.jsonb    :extra_fields
      # Polymorphic link to whatever this ticket is about — a Project, a
      # Purchase, a Deliverable, or nothing (a raw standalone ticket).
      # Same doctrine as WorkItem#subject: dynamic reads, one column pair
      # instead of a foreign key per possible thing a ticket could relate to.
      t.string   :related_type
      t.bigint   :related_id
      t.datetime :resolved_at
      t.timestamps
    end
    add_index :marlon_tickets, :number, unique: true
    add_index :marlon_tickets, :status
    add_index :marlon_tickets, :category
    add_index :marlon_tickets, %i[related_type related_id]
    add_index :marlon_tickets, :submitted_by_id
  end
end
EOF
sleep 1
TS2=$(date -u +%Y%m%d%H%M%S)
cat > "db/migrate/${TS2}_create_marlon_ticket_events.rb" << 'EOF'
# frozen_string_literal: true
class CreateMarlonTicketEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :marlon_ticket_events do |t|
      t.references :ticket, null: false, foreign_key: { to_table: :marlon_tickets }
      t.bigint   :actor_id
      t.string   :action,   null: false
      t.text     :detail
      t.timestamps
    end
  end
end
EOF

echo "Writing category taxonomy (fixed config, like disposition kinds)..."
mkdir -p app/models/marlon
cat > app/models/marlon/ticket_categories.rb << 'EOF'
# frozen_string_literal: true
module Marlon
  # Fixed taxonomy — these 6 categories are structural, not admin-managed
  # data, same reasoning as DymondDispatch::Dispositions' registered kinds.
  # sla_hours drives the default response-time expectation shown to the
  # submitter; team/default_rep are who a new ticket in this category
  # auto-routes to.
  module TicketCategories
    ALL = {
      "deployment" => { icon: "🚀", team: "Deployment Team",  default_rep: "@darius.m",     sla_hours: 2,  label: "Deployment" },
      "billing"    => { icon: "💳", team: "Finance Team",      default_rep: "@finance-jen",  sla_hours: 24, label: "Billing" },
      "compliance" => { icon: "⚖️", team: "Compliance Team",   default_rep: "@compliance-rox", sla_hours: 1, label: "Compliance" },
      "onboarding" => { icon: "🎯", team: "Onboarding Team",   default_rep: "@onboard-kia",  sla_hours: 4,  label: "Onboarding" },
      "training"   => { icon: "📚", team: "Training Team",     default_rep: "@training-mo",  sla_hours: 48, label: "Training" },
      "technical"  => { icon: "🔧", team: "Technical Team",    default_rep: "@tech-malik",   sla_hours: 4,  label: "Technical" }
    }.freeze

    module_function

    def ids = ALL.keys

    def for(id) = ALL[id.to_s]

    def label_for(id) = ALL.dig(id.to_s, :label) || id.to_s.humanize
  end
end
EOF

echo "Writing models..."
cat > app/models/marlon/ticket.rb << 'EOF'
# frozen_string_literal: true
module Marlon
  class Ticket < ApplicationRecord
    self.table_name = "marlon_tickets"

    PRIORITIES = %w[low medium high critical].freeze
    STATUSES   = %w[open in_progress resolved].freeze

    belongs_to :submitted_by, class_name: "User", optional: true
    belongs_to :related, polymorphic: true, optional: true

    has_many :events, class_name: "Marlon::TicketEvent", dependent: :destroy, inverse_of: :ticket

    validates :title, presence: true
    validates :category, inclusion: { in: Marlon::TicketCategories.ids }
    validates :priority, inclusion: { in: PRIORITIES }
    validates :status,   inclusion: { in: STATUSES }
    validates :urgency, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 10 }

    before_validation :assign_number, on: :create
    before_validation :apply_category_defaults, on: :create

    scope :open_first, -> { order(Arel.sql("CASE status WHEN 'open' THEN 0 WHEN 'in_progress' THEN 1 ELSE 2 END"), :created_at) }
    scope :for_related, ->(record) { where(related: record) }

    def category_meta
      Marlon::TicketCategories.for(category)
    end

    def log!(action:, detail: nil, actor: nil)
      events.create!(action: action, detail: detail, actor: actor)
    end

    def resolve!(actor: nil)
      update!(status: "resolved", resolved_at: Time.current)
      log!(action: "Ticket resolved", actor: actor)
    end

    private

    def assign_number
      self.number ||= "LT-#{SecureRandom.random_number(9000) + 1000}"
    end

    def apply_category_defaults
      meta = category_meta
      return unless meta

      self.assigned_team ||= meta[:team]
      self.assigned_rep  ||= meta[:default_rep]
    end
  end
end
EOF

cat > app/models/marlon/ticket_event.rb << 'EOF'
# frozen_string_literal: true
module Marlon
  class TicketEvent < ApplicationRecord
    self.table_name = "marlon_ticket_events"

    belongs_to :ticket, class_name: "Marlon::Ticket", inverse_of: :events
    belongs_to :actor,  class_name: "User", optional: true

    validates :action, presence: true

    after_create :log_submission_event, if: -> { ticket.events.count == 1 }

    private

    # No-op placeholder — the FIRST event on a fresh ticket is usually
    # "Ticket submitted" itself, created explicitly by the controller.
    # This callback intentionally does nothing extra; kept as a documented
    # hook point for later (e.g. firing a notify disposition on first event).
    def log_submission_event; end
  end
end
EOF

echo "Writing Employee::TicketsController..."
cat > app/controllers/employee/tickets_controller.rb << 'EOF'
# frozen_string_literal: true
module Employee
  class TicketsController < Employee::ApplicationController
    before_action :set_ticket, only: %i[show update reply resolve]

    def index
      authorize! :read, Marlon::Ticket
      @tickets = Marlon::Ticket.open_first
      @tickets = @tickets.where(status: params[:status]) if params[:status].present?
      @tickets = @tickets.where(category: params[:category]) if params[:category].present?
    end

    def show
      @events = @ticket.events.order(:created_at)
    end

    def new
      @ticket = Marlon::Ticket.new(category: Marlon::TicketCategories.ids.first, priority: "medium", urgency: 5)
    end

    def create
      @ticket = Marlon::Ticket.new(ticket_params)
      @ticket.submitted_by = current_user
      if @ticket.save
        @ticket.log!(action: "Ticket submitted", actor: current_user)
        redirect_to employee_ticket_path(@ticket), notice: "Ticket #{@ticket.number} created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def reply
      @ticket.log!(action: "#{current_user.full_name} replied", detail: params[:detail], actor: current_user)
      @ticket.update!(status: "in_progress") if @ticket.status == "open"
      redirect_to employee_ticket_path(@ticket), notice: "Reply logged."
    end

    def resolve
      @ticket.resolve!(actor: current_user)
      redirect_to employee_ticket_path(@ticket), notice: "Ticket resolved."
    end

    private

    def set_ticket
      @ticket = Marlon::Ticket.find(params[:id])
      authorize! :read, @ticket
    end

    def ticket_params
      params.require(:ticket).permit(:category, :title, :description, :priority, :urgency,
                                      :organization_name, :reseller_id, :related_type, :related_id)
    end
  end
end
EOF

echo "Writing views..."
mkdir -p app/views/employee/tickets

cat > app/views/employee/tickets/index.html.erb << 'EOF'
<% content_for :page_title, "Tickets" %>
<% content_for :topbar_actions do %>
  <%= link_to "New Ticket", new_employee_ticket_path, class: "dd-topbar-btn dd-btn-primary" %>
<% end %>

<div class="dd-card">
  <% if @tickets.any? %>
    <% @tickets.each do |t| %>
      <div style="display:flex; align-items:center; justify-content:space-between; padding:10px 0; border-bottom:1px solid var(--dd-border);">
        <div>
          <span style="font-family:monospace; color:var(--dd-text-muted); font-size:12px;"><%= t.number %></span>
          <span style="font-weight:600;"> <%= t.title %></span>
          <span style="color:var(--dd-text-muted); font-size:12px;">
            · <%= t.category_meta&.dig(:icon) %> <%= Marlon::TicketCategories.label_for(t.category) %>
            · <%= t.priority.upcase %>
            · <%= t.status.humanize %>
          </span>
        </div>
        <%= link_to "View", employee_ticket_path(t), class: "dd-topbar-btn dd-btn-ghost" %>
      </div>
    <% end %>
  <% else %>
    <p style="color:var(--dd-text-secondary); font-size:13px;">No tickets.</p>
  <% end %>
</div>
EOF

cat > app/views/employee/tickets/show.html.erb << 'EOF'
<% content_for :page_title, "#{@ticket.number} — #{@ticket.title}" %>
<% content_for :topbar_actions do %>
  <% if @ticket.status != "resolved" %>
    <%= button_to "Mark Resolved", resolve_employee_ticket_path(@ticket), method: :patch, class: "dd-topbar-btn dd-btn-primary" %>
  <% end %>
  <%= link_to "All Tickets", employee_tickets_path, class: "dd-topbar-btn dd-btn-ghost" %>
<% end %>

<div class="dd-card" style="margin-bottom:16px;">
  <div class="dd-card-title">Overview</div>
  <p style="font-size:13px;"><%= @ticket.category_meta&.dig(:icon) %> <%= Marlon::TicketCategories.label_for(@ticket.category) %> · Priority: <%= @ticket.priority.upcase %> · Urgency: <%= @ticket.urgency %>/10</p>
  <p style="font-size:13px;">Status: <%= @ticket.status.humanize %> · Assigned: <%= @ticket.assigned_team %> (<%= @ticket.assigned_rep %>)</p>
  <p style="font-size:13px; color:var(--dd-text-secondary);"><%= @ticket.description %></p>
  <% if @ticket.related %>
    <p style="font-size:13px;">Related: <%= @ticket.related_type %> ##<%= @ticket.related_id %></p>
  <% end %>
</div>

<div class="dd-card" style="margin-bottom:16px;">
  <div class="dd-card-title">Timeline</div>
  <% @events.each do |e| %>
    <div style="padding:8px 0; border-bottom:1px solid var(--dd-border); font-size:13px;">
      <strong><%= e.action %></strong> · <%= e.created_at.strftime("%b %-d, %l:%M %p") %>
      <% if e.detail.present? %><div style="color:var(--dd-text-secondary); margin-top:2px;"><%= e.detail %></div><% end %>
    </div>
  <% end %>
</div>

<div class="dd-card">
  <div class="dd-card-title">Reply</div>
  <%= form_with url: reply_employee_ticket_path(@ticket), method: :patch do %>
    <textarea name="detail" rows="3" class="fg-input" placeholder="Add a reply to this ticket's timeline..." style="width:100%;"></textarea>
    <div style="margin-top:8px;">
      <%= submit_tag "Send Reply", class: "dd-topbar-btn dd-btn-primary" %>
    </div>
  <% end %>
</div>
EOF

cat > app/views/employee/tickets/new.html.erb << 'EOF'
<% content_for :page_title, "New Ticket" %>
<%= form_with model: @ticket, url: employee_tickets_path do |f| %>
  <div class="dd-card" style="display:flex; flex-direction:column; gap:12px; max-width:600px;">
    <label>Category
      <%= f.select :category, Marlon::TicketCategories.ids.map { |id| [Marlon::TicketCategories.label_for(id), id] }, {}, class: "fg-input" %>
    </label>
    <label>Title <%= f.text_field :title, class: "fg-input" %></label>
    <label>Description <%= f.text_area :description, class: "fg-input" %></label>
    <label>Priority
      <%= f.select :priority, Marlon::Ticket::PRIORITIES.map { |p| [p.humanize, p] }, {}, class: "fg-input" %>
    </label>
    <label>Urgency (1-10) <%= f.number_field :urgency, min: 1, max: 10, class: "fg-input" %></label>
    <label>Organization <%= f.text_field :organization_name, class: "fg-input" %></label>
    <%= f.submit "Create Ticket", class: "dd-topbar-btn dd-btn-primary" %>
  </div>
<% end %>
EOF

echo "Adding routes..."
if ! grep -q "resources :tickets" config/routes.rb; then
  perl -0pi -e 's/(namespace :employee do\n)/$1    resources :tickets, only: %i[index show new create] do\n      member { patch :reply; patch :resolve }\n    end\n/' config/routes.rb
fi

echo "Adding employee-role feature gate + Tickets nav..."
if ! grep -q "employee_tickets" app/models/user.rb; then
  perl -0pi -e 's/(when :employee_clients\n        employee\? \|\| admin\?)/$1\n      when :employee_tickets\n        employee? || admin?/' app/models/user.rb
fi

cat > config/initializers/ticket_nav.rb << 'EOF'
# frozen_string_literal: true
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |f|
    f.slug = :employee_tickets; f.label = "Tickets"; f.icon = "ticket"
    f.gem_source = "host"; f.nav_section = :overview; f.min_plan = :starter
    f.nav_items = [{ label: "Tickets", icon: "ticket", path: "employee_tickets_path" }]
  end
rescue StandardError => e
  Rails.logger.warn "[Tickets] nav registration skipped: #{e.message}"
end
EOF

echo ""
echo "Verifying routes.rb patch..."
if grep -q "resources :tickets" config/routes.rb; then
  echo "  OK — routes patched"
else
  echo "  WARNING: routes.rb patch did not apply. Add manually inside 'namespace :employee do':"
  echo "    resources :tickets, only: %i[index show new create] do"
  echo "      member { patch :reply; patch :resolve }"
  echo "    end"
fi

echo "Verifying user.rb patch..."
if grep -q "employee_tickets" app/models/user.rb; then
  echo "  OK — user.rb patched"
else
  echo "  WARNING: user.rb patch did not apply. Add manually inside can_access_feature?, after :employee_clients:"
  echo "      when :employee_tickets"
  echo "        employee? || admin?"
fi

echo ""
echo "Done. Run:"
echo "  bin/rails db:migrate"
echo "  rm -rf tmp/cache/bootsnap*"
echo "  bin/rails server"
echo ""
echo "Visit /employee/tickets"
