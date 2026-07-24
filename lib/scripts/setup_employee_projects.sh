#!/bin/bash
set -e
cd ~/Desktop/Development/lightekmcg-site

echo "Writing migrations..."
TS1=$(date -u +%Y%m%d%H%M%S)
cat > "db/migrate/${TS1}_create_marlon_projects.rb" << 'EOF'
# frozen_string_literal: true
class CreateMarlonProjects < ActiveRecord::Migration[8.0]
  def change
    create_table :marlon_projects do |t|
      t.string   :title,       null: false
      t.text     :description
      t.bigint   :client_id
      t.bigint   :owner_id
      t.bigint   :purchase_id
      t.string   :status,      null: false, default: "planning"
      t.date     :start_date
      t.date     :due_date
      t.timestamps
    end
    add_index :marlon_projects, :client_id
    add_index :marlon_projects, :owner_id
    add_index :marlon_projects, :purchase_id
    add_index :marlon_projects, :status
  end
end
EOF
sleep 1
TS2=$(date -u +%Y%m%d%H%M%S)
cat > "db/migrate/${TS2}_create_marlon_deliverables.rb" << 'EOF'
# frozen_string_literal: true
class CreateMarlonDeliverables < ActiveRecord::Migration[8.0]
  def change
    create_table :marlon_deliverables do |t|
      t.references :project, null: false, foreign_key: { to_table: :marlon_projects }
      t.string   :name,      null: false
      t.text     :description
      t.string   :status,    null: false, default: "pending"
      t.date     :due_date
      t.datetime :completed_at
      t.timestamps
    end
    add_index :marlon_deliverables, :status
  end
end
EOF
sleep 1
TS3=$(date -u +%Y%m%d%H%M%S)
cat > "db/migrate/${TS3}_create_marlon_timesheets.rb" << 'EOF'
# frozen_string_literal: true
class CreateMarlonTimesheets < ActiveRecord::Migration[8.0]
  def change
    create_table :marlon_timesheets do |t|
      t.references :project, null: false, foreign_key: { to_table: :marlon_projects }
      t.bigint   :user_id,   null: false
      t.decimal  :hours,     null: false, precision: 6, scale: 2
      t.date     :worked_on, null: false
      t.text     :notes
      t.timestamps
    end
    add_index :marlon_timesheets, :user_id
    add_index :marlon_timesheets, :worked_on
  end
end
EOF

echo "Writing models..."
mkdir -p app/models/marlon
cat > app/models/marlon/project.rb << 'EOF'
# frozen_string_literal: true
module Marlon
  class Project < ApplicationRecord
    self.table_name = "marlon_projects"

    STATUSES = %w[planning active on_hold completed cancelled].freeze

    belongs_to :client,   class_name: "User", optional: true
    belongs_to :owner,    class_name: "User", optional: true
    belongs_to :purchase, class_name: "DymondBank::Purchase", optional: true

    has_many :deliverables, class_name: "Marlon::Deliverable", dependent: :destroy
    has_many :timesheets,   class_name: "Marlon::Timesheet",   dependent: :destroy

    validates :title, presence: true
    validates :status, inclusion: { in: STATUSES }

    scope :active_first, -> { order(Arel.sql("CASE status WHEN 'active' THEN 0 WHEN 'planning' THEN 1 ELSE 2 END"), :due_date) }

    def total_hours
      timesheets.sum(:hours)
    end
  end
end
EOF

cat > app/models/marlon/deliverable.rb << 'EOF'
# frozen_string_literal: true
module Marlon
  class Deliverable < ApplicationRecord
    self.table_name = "marlon_deliverables"

    STATUSES = %w[pending in_progress completed].freeze

    belongs_to :project, class_name: "Marlon::Project"

    validates :name, presence: true
    validates :status, inclusion: { in: STATUSES }

    def complete!
      update!(status: "completed", completed_at: Time.current)
    end
  end
end
EOF

cat > app/models/marlon/timesheet.rb << 'EOF'
# frozen_string_literal: true
module Marlon
  class Timesheet < ApplicationRecord
    self.table_name = "marlon_timesheets"

    belongs_to :project, class_name: "Marlon::Project"
    belongs_to :user

    validates :hours, numericality: { greater_than: 0 }
    validates :worked_on, presence: true
  end
end
EOF

echo "Writing Employee::ProjectsController..."
cat > app/controllers/employee/projects_controller.rb << 'EOF'
# frozen_string_literal: true
module Employee
  class ProjectsController < Employee::ApplicationController
    before_action :set_project, only: %i[show edit update]

    def index
      authorize! :read, Marlon::Project
      @projects = Marlon::Project.active_first
    end

    def show
      @deliverables = @project.deliverables.order(:due_date)
      @timesheets   = @project.timesheets.order(worked_on: :desc).limit(20)
    end

    def edit; end

    def update
      if @project.update(project_params)
        redirect_to employee_project_path(@project), notice: "Project updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_project
      @project = Marlon::Project.find(params[:id])
      authorize! :read, @project
    end

    def project_params
      params.require(:project).permit(:title, :description, :client_id, :owner_id,
                                       :purchase_id, :status, :start_date, :due_date)
    end
  end
end
EOF

echo "Writing Employee::TimesheetsController..."
cat > app/controllers/employee/timesheets_controller.rb << 'EOF'
# frozen_string_literal: true
module Employee
  class TimesheetsController < Employee::ApplicationController
    def index
      authorize! :read, Marlon::Timesheet
      @timesheets = Marlon::Timesheet.includes(:project, :user).order(worked_on: :desc).limit(100)
    end

    def create
      @timesheet = Marlon::Timesheet.new(timesheet_params)
      @timesheet.user = current_user
      if @timesheet.save
        redirect_to employee_timesheets_path, notice: "Time logged."
      else
        redirect_to employee_timesheets_path, alert: @timesheet.errors.full_messages.join(", ")
      end
    end

    private

    def timesheet_params
      params.require(:timesheet).permit(:project_id, :hours, :worked_on, :notes)
    end
  end
end
EOF

echo "Writing views..."
mkdir -p app/views/employee/projects app/views/employee/timesheets

cat > app/views/employee/projects/index.html.erb << 'EOF'
<% content_for :page_title, "Projects" %>
<div class="dd-card">
  <% if @projects.any? %>
    <% @projects.each do |p| %>
      <div style="display:flex; align-items:center; justify-content:space-between; padding:10px 0; border-bottom:1px solid var(--dd-border);">
        <div>
          <span style="font-weight:600;"><%= p.title %></span>
          <span style="color:var(--dd-text-muted); font-size:12px;"> · <%= p.status.humanize %><%= " · due #{p.due_date.strftime('%b %-d')}" if p.due_date %></span>
        </div>
        <%= link_to "View", employee_project_path(p), class: "dd-topbar-btn dd-btn-ghost" %>
      </div>
    <% end %>
  <% else %>
    <p style="color:var(--dd-text-secondary); font-size:13px;">No projects yet.</p>
  <% end %>
</div>
EOF

cat > app/views/employee/projects/show.html.erb << 'EOF'
<% content_for :page_title, @project.title %>
<% content_for :topbar_actions do %>
  <%= link_to "Edit", edit_employee_project_path(@project), class: "dd-topbar-btn dd-btn-ghost" %>
  <%= link_to "All Projects", employee_projects_path, class: "dd-topbar-btn dd-btn-ghost" %>
<% end %>

<div class="dd-card" style="margin-bottom:16px;">
  <div class="dd-card-title">Overview</div>
  <p style="font-size:13px;">Status: <%= @project.status.humanize %></p>
  <p style="font-size:13px; color:var(--dd-text-secondary);"><%= @project.description %></p>
  <p style="font-size:13px;">Client: <%= @project.client&.full_name || "—" %></p>
  <p style="font-size:13px;">Owner: <%= @project.owner&.full_name || "—" %></p>
  <p style="font-size:13px;">Total hours logged: <%= @project.total_hours %></p>
</div>

<div class="dd-card" style="margin-bottom:16px;">
  <div class="dd-card-title">Deliverables</div>
  <% if @deliverables.any? %>
    <% @deliverables.each do |d| %>
      <p style="font-size:13px;"><%= d.name %> · <%= d.status.humanize %><%= " · due #{d.due_date.strftime('%b %-d')}" if d.due_date %></p>
    <% end %>
  <% else %>
    <p style="font-size:13px; color:var(--dd-text-secondary);">No deliverables yet.</p>
  <% end %>
</div>

<div class="dd-card">
  <div class="dd-card-title">Recent Time Entries</div>
  <% if @timesheets.any? %>
    <% @timesheets.each do |t| %>
      <p style="font-size:13px;"><%= t.worked_on.strftime("%b %-d") %> · <%= t.user.full_name %> · <%= t.hours %>h<%= " — #{t.notes}" if t.notes.present? %></p>
    <% end %>
  <% else %>
    <p style="font-size:13px; color:var(--dd-text-secondary);">No time logged yet.</p>
  <% end %>
</div>
EOF

cat > app/views/employee/projects/edit.html.erb << 'EOF'
<% content_for :page_title, "Edit #{@project.title}" %>
<%= form_with model: @project, url: employee_project_path(@project) do |f| %>
  <div class="dd-card" style="display:flex; flex-direction:column; gap:12px; max-width:600px;">
    <label>Title <%= f.text_field :title, class: "fg-input" %></label>
    <label>Description <%= f.text_area :description, class: "fg-input" %></label>
    <label>Status
      <%= f.select :status, Marlon::Project::STATUSES.map { |s| [s.humanize, s] }, {}, class: "fg-input" %>
    </label>
    <label>Start Date <%= f.date_field :start_date, class: "fg-input" %></label>
    <label>Due Date <%= f.date_field :due_date, class: "fg-input" %></label>
    <%= f.submit class: "dd-topbar-btn dd-btn-primary" %>
  </div>
<% end %>
EOF

cat > app/views/employee/timesheets/index.html.erb << 'EOF'
<% content_for :page_title, "Timesheets" %>

<div class="dd-card" style="margin-bottom:16px;">
  <div class="dd-card-title">Log Time</div>
  <%= form_with url: employee_timesheets_path, method: :post do |f| %>
    <div style="display:flex; gap:10px; flex-wrap:wrap; align-items:flex-end;">
      <label>Project
        <%= f.select :project_id, options_for_select(Marlon::Project.active_first.map { |p| [p.title, p.id] }), {}, name: "timesheet[project_id]", class: "fg-input" %>
      </label>
      <label>Hours <%= text_field_tag "timesheet[hours]", nil, class: "fg-input", style: "width:80px;" %></label>
      <label>Date <%= date_field_tag "timesheet[worked_on]", Date.current, class: "fg-input" %></label>
      <label>Notes <%= text_field_tag "timesheet[notes]", nil, class: "fg-input" %></label>
      <%= f.submit "Log", class: "dd-topbar-btn dd-btn-primary" %>
    </div>
  <% end %>
</div>

<div class="dd-card">
  <% if @timesheets.any? %>
    <% @timesheets.each do |t| %>
      <div style="padding:8px 0; border-bottom:1px solid var(--dd-border); font-size:13px;">
        <%= t.worked_on.strftime("%b %-d, %Y") %> · <%= t.project.title %> · <%= t.user.full_name %> · <%= t.hours %>h
        <% if t.notes.present? %><span style="color:var(--dd-text-secondary);"> — <%= t.notes %></span><% end %>
      </div>
    <% end %>
  <% else %>
    <p style="color:var(--dd-text-secondary); font-size:13px;">No time entries yet.</p>
  <% end %>
</div>
EOF

echo ""
echo "Done. Run the migration:"
echo "  bin/rails db:migrate"
echo ""
echo "Then restart:"
echo "  rm -rf tmp/cache/bootsnap*"
echo "  bin/rails server"
echo ""
echo "Visit /employee/projects and /employee/timesheets"
