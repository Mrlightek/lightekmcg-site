#!/bin/bash
set -e
cd ~/Desktop/Development/lightekmcg-site

echo "Generating dymond_booking domain gem..."
bin/rails g lightek:domain booking --mount=/booking

cd ~/Desktop/Development/dymond_booking
mkdir -p db/migrate config app/models/dymond_booking app/controllers/dymond_booking app/views/dymond_booking/booking_dashboard lib/dymond_booking

echo "Writing migrations..."
TS1=$(date -u +%Y%m%d%H%M%S)
cat > "db/migrate/${TS1}_create_dymond_booking_resources.rb" << 'EOF'
# frozen_string_literal: true
class CreateDymondBookingResources < ActiveRecord::Migration[8.0]
  def change
    create_table :dymond_booking_resources do |t|
      t.string  :name,          null: false
      t.string  :resource_type, null: false, default: "service" # dj | venue | service
      t.bigint  :owner_id
      t.text    :description
      t.bigint  :rate_cents,    default: 0
      t.boolean :active,        default: true, null: false
      t.timestamps
    end
    add_index :dymond_booking_resources, :resource_type
  end
end
EOF
sleep 1
TS2=$(date -u +%Y%m%d%H%M%S)
cat > "db/migrate/${TS2}_create_dymond_booking_bookings.rb" << 'EOF'
# frozen_string_literal: true
class CreateDymondBookingBookings < ActiveRecord::Migration[8.0]
  def change
    create_table :dymond_booking_bookings do |t|
      t.references :resource, null: false, foreign_key: { to_table: :dymond_booking_resources }
      t.bigint   :requested_by_id, null: false
      t.datetime :start_time,      null: false
      t.datetime :end_time,        null: false
      t.string   :status,          null: false, default: "pending" # pending | confirmed | declined | cancelled
      t.text     :notes
      t.bigint   :total_cents,     default: 0
      t.timestamps
    end
    add_index :dymond_booking_bookings, :status
    add_index :dymond_booking_bookings, :start_time
  end
end
EOF
sleep 1
TS3=$(date -u +%Y%m%d%H%M%S)
cat > "db/migrate/${TS3}_create_dymond_booking_events.rb" << 'EOF'
# frozen_string_literal: true
class CreateDymondBookingEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :dymond_booking_events do |t|
      t.string   :title,        null: false
      t.text     :description
      t.string   :location
      t.datetime :start_time,   null: false
      t.datetime :end_time
      t.bigint   :organizer_id
      t.integer  :capacity
      t.boolean  :public,       default: true, null: false
      t.timestamps
    end
    add_index :dymond_booking_events, :start_time
    add_index :dymond_booking_events, :public
  end
end
EOF
sleep 1
TS4=$(date -u +%Y%m%d%H%M%S)
cat > "db/migrate/${TS4}_create_dymond_booking_event_rsvps.rb" << 'EOF'
# frozen_string_literal: true
class CreateDymondBookingEventRsvps < ActiveRecord::Migration[8.0]
  def change
    create_table :dymond_booking_event_rsvps do |t|
      t.references :event, null: false, foreign_key: { to_table: :dymond_booking_events }
      t.bigint  :attendee_id, null: false
      t.string  :status,      null: false, default: "going" # going | maybe | declined
      t.timestamps
    end
    add_index :dymond_booking_event_rsvps, %i[event_id attendee_id], unique: true
  end
end
EOF

echo "Writing models..."
cat > app/models/dymond_booking/resource.rb << 'EOF'
# frozen_string_literal: true
module DymondBooking
  class Resource < ApplicationRecord
    self.table_name = "dymond_booking_resources"
    TYPES = %w[dj venue service].freeze

    belongs_to :owner, class_name: "User", optional: true
    has_many :bookings, class_name: "DymondBooking::Booking", dependent: :destroy

    validates :name, presence: true
    validates :resource_type, inclusion: { in: TYPES }

    scope :active, -> { where(active: true) }

    def rate
      rate_cents.to_i / 100.0
    end

    def rate=(dollars)
      self.rate_cents = (dollars.to_f * 100).round
    end

    # Simple overlap check — does this resource have a confirmed/pending
    # booking overlapping the given window?
    def available?(start_time, end_time, excluding: nil)
      scope = bookings.where(status: %w[pending confirmed])
                       .where("start_time < ? AND end_time > ?", end_time, start_time)
      scope = scope.where.not(id: excluding.id) if excluding
      scope.none?
    end
  end
end
EOF

cat > app/models/dymond_booking/booking.rb << 'EOF'
# frozen_string_literal: true
module DymondBooking
  class Booking < ApplicationRecord
    self.table_name = "dymond_booking_bookings"
    STATUSES = %w[pending confirmed declined cancelled].freeze

    belongs_to :resource, class_name: "DymondBooking::Resource"
    belongs_to :requested_by, class_name: "User"

    validates :start_time, :end_time, presence: true
    validates :status, inclusion: { in: STATUSES }
    validate :end_after_start
    validate :resource_available, on: :create

    scope :upcoming, -> { where("start_time >= ?", Time.current).order(:start_time) }
    scope :in_range, ->(range_start, range_end) { where(start_time: range_start..range_end) }

    def confirm!
      update!(status: "confirmed")
    end

    def decline!
      update!(status: "declined")
    end

    def cancel!
      update!(status: "cancelled")
    end

    private

    def end_after_start
      return unless start_time && end_time
      errors.add(:end_time, "must be after start time") if end_time <= start_time
    end

    def resource_available
      return unless resource && start_time && end_time
      unless resource.available?(start_time, end_time, excluding: self)
        errors.add(:base, "Resource is already booked for that time")
      end
    end
  end
end
EOF

cat > app/models/dymond_booking/event.rb << 'EOF'
# frozen_string_literal: true
module DymondBooking
  class Event < ApplicationRecord
    self.table_name = "dymond_booking_events"

    belongs_to :organizer, class_name: "User", optional: true
    has_many :rsvps, class_name: "DymondBooking::EventRsvp", dependent: :destroy

    validates :title, :start_time, presence: true

    scope :upcoming, -> { where("start_time >= ?", Time.current).order(:start_time) }
    scope :public_events, -> { where(public: true) }

    def going_count
      rsvps.where(status: "going").count
    end

    def full?
      capacity.present? && going_count >= capacity
    end
  end
end
EOF

cat > app/models/dymond_booking/event_rsvp.rb << 'EOF'
# frozen_string_literal: true
module DymondBooking
  class EventRsvp < ApplicationRecord
    self.table_name = "dymond_booking_event_rsvps"
    STATUSES = %w[going maybe declined].freeze

    belongs_to :event, class_name: "DymondBooking::Event"
    belongs_to :attendee, class_name: "User"

    validates :status, inclusion: { in: STATUSES }
    validates :attendee_id, uniqueness: { scope: :event_id }
  end
end
EOF

echo "Stage 1 (structure) done."
cd ~/Desktop/Development/dymond_booking

echo "Writing admin BookingDashboardController (calendar + resource/booking/event management)..."
cat > app/controllers/dymond_booking/booking_dashboard_controller.rb << 'EOF'
# frozen_string_literal: true
module DymondBooking
  class BookingDashboardController < ::DymondDash::ApplicationController
    def index
      @month = params[:month].present? ? Date.parse("#{params[:month]}-01") : Date.current.beginning_of_month
      range = @month.beginning_of_month.beginning_of_week..@month.end_of_month.end_of_week

      @bookings = DymondBooking::Booking.includes(:resource, :requested_by).in_range(range.first.beginning_of_day, range.last.end_of_day)
      @events   = DymondBooking::Event.where(start_time: range.first.beginning_of_day..range.last.end_of_day)

      @days = (range.first..range.last).map do |date|
        {
          date: date,
          bookings: @bookings.select { |b| b.start_time.to_date == date },
          events:   @events.select { |e| e.start_time.to_date == date }
        }
      end
    end

    # ── Resources ──
    def resources
      @resources = DymondBooking::Resource.order(:name)
    end

    def new_resource
      @resource = DymondBooking::Resource.new
    end

    def create_resource
      @resource = DymondBooking::Resource.new(resource_params)
      if @resource.save
        redirect_to dymond_dash.booking_resources_path, notice: "Resource created."
      else
        render :new_resource, status: :unprocessable_entity
      end
    end

    def edit_resource
      @resource = DymondBooking::Resource.find(params[:id])
    end

    def update_resource
      @resource = DymondBooking::Resource.find(params[:id])
      if @resource.update(resource_params)
        redirect_to dymond_dash.booking_resources_path, notice: "Resource updated."
      else
        render :edit_resource, status: :unprocessable_entity
      end
    end

    def destroy_resource
      DymondBooking::Resource.find(params[:id]).destroy
      redirect_to dymond_dash.booking_resources_path, notice: "Resource removed."
    end

    # ── Bookings ──
    def confirm_booking
      DymondBooking::Booking.find(params[:id]).confirm!
      redirect_back fallback_location: dymond_dash.booking_dashboard_path, notice: "Booking confirmed."
    end

    def decline_booking
      DymondBooking::Booking.find(params[:id]).decline!
      redirect_back fallback_location: dymond_dash.booking_dashboard_path, notice: "Booking declined."
    end

    # ── Events ──
    def new_event
      @event = DymondBooking::Event.new(start_time: Time.current)
    end

    def create_event
      @event = DymondBooking::Event.new(event_params)
      @event.organizer = current_user
      if @event.save
        redirect_to dymond_dash.booking_dashboard_path, notice: "Event created."
      else
        render :new_event, status: :unprocessable_entity
      end
    end

    def edit_event
      @event = DymondBooking::Event.find(params[:id])
    end

    def update_event
      @event = DymondBooking::Event.find(params[:id])
      if @event.update(event_params)
        redirect_to dymond_dash.booking_dashboard_path, notice: "Event updated."
      else
        render :edit_event, status: :unprocessable_entity
      end
    end

    def destroy_event
      DymondBooking::Event.find(params[:id]).destroy
      redirect_to dymond_dash.booking_dashboard_path, notice: "Event removed."
    end

    private

    def resource_params
      params.require(:resource).permit(:name, :resource_type, :owner_id, :description, :rate, :active)
    end

    def event_params
      params.require(:event).permit(:title, :description, :location, :start_time, :end_time, :capacity, :public)
    end
  end
end
EOF

echo "Writing public BookingController (event listing/RSVP + booking request)..."
cat > app/controllers/dymond_booking/public_controller.rb << 'EOF'
# frozen_string_literal: true
module DymondBooking
  class PublicController < ::DymondSite::ApplicationController
    def index
      @resources = DymondBooking::Resource.active
      @events = DymondBooking::Event.public_events.upcoming
    end

    def request_booking
      booking = DymondBooking::Booking.new(booking_params)
      booking.requested_by = current_user
      if booking.save
        render json: { ok: true, id: booking.id, status: booking.status }
      else
        render json: { ok: false, error: booking.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    def rsvp
      event = DymondBooking::Event.find(params[:event_id])
      r = DymondBooking::EventRsvp.find_or_initialize_by(event: event, attendee: current_user)
      r.status = params[:status].presence || "going"
      if r.save
        render json: { ok: true, going_count: event.going_count }
      else
        render json: { ok: false, error: r.errors.full_messages.join(", ") }, status: :unprocessable_entity
      end
    end

    private

    def booking_params
      params.require(:booking).permit(:resource_id, :start_time, :end_time, :notes)
    end
  end
end
EOF

echo "Writing routes..."
cat > config/routes.rb << 'EOF'
# frozen_string_literal: true
DymondBooking::Engine.routes.draw do
  root to: "public#index"
  post "book",  to: "public#request_booking", as: :request_booking
  post "rsvp",  to: "public#rsvp",             as: :rsvp
end
EOF

echo "Writing editor_routes.rb..."
cat > lib/dymond_booking/editor_routes.rb << 'EOF'
# frozen_string_literal: true
module DymondBooking
  module EditorRoutesRegistration
    module_function
    def register!
      return unless defined?(DymondDash::EditorRoutes)
      c = "dymond_booking/booking_dashboard"
      DymondDash::EditorRoutes.register(path: "booking",                       to: "#{c}#index",           as: "booking_dashboard",   verb: :get)
      DymondDash::EditorRoutes.register(path: "booking/resources",             to: "#{c}#resources",       as: "booking_resources",   verb: :get)
      DymondDash::EditorRoutes.register(path: "booking/resources/new",        to: "#{c}#new_resource",    as: "new_booking_resource", verb: :get)
      DymondDash::EditorRoutes.register(path: "booking/resources",             to: "#{c}#create_resource", as: "booking_resources_create", verb: :post)
      DymondDash::EditorRoutes.register(path: "booking/resources/:id/edit",   to: "#{c}#edit_resource",   as: "edit_booking_resource", verb: :get)
      DymondDash::EditorRoutes.register(path: "booking/resources/:id",         to: "#{c}#update_resource", as: "booking_resource",     verb: :patch)
      DymondDash::EditorRoutes.register(path: "booking/resources/:id",         to: "#{c}#destroy_resource", as: "destroy_booking_resource", verb: :delete)
      DymondDash::EditorRoutes.register(path: "booking/bookings/:id/confirm", to: "#{c}#confirm_booking", as: "confirm_booking",      verb: :patch)
      DymondDash::EditorRoutes.register(path: "booking/bookings/:id/decline", to: "#{c}#decline_booking", as: "decline_booking",      verb: :patch)
      DymondDash::EditorRoutes.register(path: "booking/events/new",           to: "#{c}#new_event",       as: "new_booking_event",    verb: :get)
      DymondDash::EditorRoutes.register(path: "booking/events",               to: "#{c}#create_event",    as: "booking_events",       verb: :post)
      DymondDash::EditorRoutes.register(path: "booking/events/:id/edit",     to: "#{c}#edit_event",      as: "edit_booking_event",   verb: :get)
      DymondDash::EditorRoutes.register(path: "booking/events/:id",           to: "#{c}#update_event",    as: "booking_event",        verb: :patch)
      DymondDash::EditorRoutes.register(path: "booking/events/:id",           to: "#{c}#destroy_event",   as: "destroy_booking_event", verb: :delete)
    end
  end
end
EOF

echo "Stage 2 (controllers/routes) done."
cd ~/Desktop/Development/dymond_booking

echo "Writing calendar view..."
cat > app/views/dymond_booking/booking_dashboard/index.html.erb << 'EOF'
<% content_for :page_title, "Booking Calendar" %>
<% content_for :topbar_actions do %>
  <%= link_to "Resources", dymond_dash.booking_resources_path, class: "dd-topbar-btn dd-btn-ghost" %>
  <%= link_to "New Event", dymond_dash.new_booking_event_path, class: "dd-topbar-btn dd-btn-primary" %>
<% end %>

<style>
  .bk-cal-nav { display: flex; align-items: center; justify-content: space-between; margin-bottom: 16px; }
  .bk-cal-month { font-size: 16px; font-weight: 700; }
  .bk-cal-grid { display: grid; grid-template-columns: repeat(7, 1fr); gap: 1px; background: var(--dd-border); border: 1px solid var(--dd-border); border-radius: var(--dd-radius); overflow: hidden; }
  .bk-cal-dow { background: rgba(255,255,255,0.03); padding: 8px; font-size: 10px; font-weight: 600; letter-spacing: 0.08em; text-transform: uppercase; color: var(--dd-text-muted); text-align: center; }
  .bk-cal-day { background: var(--dd-sidebar-bg); min-height: 96px; padding: 6px; font-size: 11px; }
  .bk-cal-day.other-month { opacity: 0.35; }
  .bk-cal-daynum { font-weight: 600; margin-bottom: 4px; color: var(--dd-text-secondary); }
  .bk-cal-item { display: block; padding: 2px 5px; border-radius: 4px; margin-bottom: 2px; font-size: 10px;
                 white-space: nowrap; overflow: hidden; text-overflow: ellipsis; text-decoration: none; }
  .bk-cal-item.booking-pending   { background: rgba(196,149,42,0.15); color: var(--dd-accent); }
  .bk-cal-item.booking-confirmed { background: rgba(61,174,130,0.15); color: var(--dd-success); }
  .bk-cal-item.booking-declined  { background: rgba(205,77,61,0.1); color: var(--dd-danger); text-decoration: line-through; }
  .bk-cal-item.event { background: rgba(0,120,200,0.15); color: #4090e0; }
</style>

<div class="bk-cal-nav">
  <%= link_to "← Prev", dymond_dash.booking_dashboard_path(month: (@month - 1.month).strftime("%Y-%m")), class: "dd-topbar-btn dd-btn-ghost" %>
  <div class="bk-cal-month"><%= @month.strftime("%B %Y") %></div>
  <%= link_to "Next →", dymond_dash.booking_dashboard_path(month: (@month + 1.month).strftime("%Y-%m")), class: "dd-topbar-btn dd-btn-ghost" %>
</div>

<div class="bk-cal-grid">
  <% %w[Sun Mon Tue Wed Thu Fri Sat].each do |d| %>
    <div class="bk-cal-dow"><%= d %></div>
  <% end %>
  <% @days.each do |day| %>
    <div class="bk-cal-day <%= 'other-month' unless day[:date].month == @month.month %>">
      <div class="bk-cal-daynum"><%= day[:date].day %></div>
      <% day[:bookings].each do |b| %>
        <a href="#" class="bk-cal-item booking-<%= b.status %>" title="<%= b.resource.name %> — <%= b.status.humanize %>">
          🎧 <%= b.resource.name %>
        </a>
      <% end %>
      <% day[:events].each do |e| %>
        <a href="<%= dymond_dash.edit_booking_event_path(e) %>" class="bk-cal-item event" title="<%= e.title %>">
          📅 <%= e.title %>
        </a>
      <% end %>
    </div>
  <% end %>
</div>

<div class="dd-card" style="margin-top:20px;">
  <div class="dd-card-title">Pending Bookings</div>
  <% pending = @bookings.select { |b| b.status == "pending" } %>
  <% if pending.any? %>
    <% pending.each do |b| %>
      <div style="display:flex; align-items:center; justify-content:space-between; padding:8px 0; border-bottom:1px solid var(--dd-border); font-size:13px;">
        <span><%= b.resource.name %> · <%= b.requested_by.full_name %> · <%= b.start_time.strftime("%b %-d, %l:%M %p") %></span>
        <div style="display:flex; gap:8px;">
          <%= button_to "Confirm", dymond_dash.confirm_booking_path(b), method: :patch, class: "dd-topbar-btn dd-btn-primary" %>
          <%= button_to "Decline", dymond_dash.decline_booking_path(b), method: :patch, class: "dd-topbar-btn dd-btn-ghost" %>
        </div>
      </div>
    <% end %>
  <% else %>
    <p style="color:var(--dd-text-secondary); font-size:13px;">No pending bookings.</p>
  <% end %>
</div>
EOF

echo "Writing resource CRUD views..."
cat > app/views/dymond_booking/booking_dashboard/resources.html.erb << 'EOF'
<% content_for :page_title, "Resources" %>
<% content_for :topbar_actions do %>
  <%= link_to "New Resource", dymond_dash.new_booking_resource_path, class: "dd-topbar-btn dd-btn-primary" %>
<% end %>
<div class="dd-card">
  <% @resources.each do |r| %>
    <div style="display:flex; align-items:center; justify-content:space-between; padding:8px 0; border-bottom:1px solid var(--dd-border);">
      <span><%= r.name %> <span style="color:var(--dd-text-muted); font-size:12px;">· <%= r.resource_type.humanize %> · $<%= r.rate %>/hr<%= " · inactive" unless r.active %></span></span>
      <div style="display:flex; gap:8px;">
        <%= link_to "Edit", dymond_dash.edit_booking_resource_path(r), class: "dd-topbar-btn dd-btn-ghost" %>
        <%= button_to "Delete", dymond_dash.destroy_booking_resource_path(r), method: :delete,
              form: { data: { turbo_confirm: "Remove #{r.name}?" } }, class: "dd-topbar-btn dd-btn-ghost" %>
      </div>
    </div>
  <% end %>
</div>
EOF

cat > app/views/dymond_booking/booking_dashboard/_resource_form.html.erb << 'EOF'
<%= form_with model: @resource, url: (@resource.persisted? ? dymond_dash.booking_resource_path(@resource) : dymond_dash.booking_resources_create_path) do |f| %>
  <div class="dd-card" style="display:flex; flex-direction:column; gap:12px; max-width:500px;">
    <label>Name <%= f.text_field :name, class: "fg-input" %></label>
    <label>Type
      <%= f.select :resource_type, DymondBooking::Resource::TYPES.map { |t| [t.humanize, t] }, {}, class: "fg-input" %>
    </label>
    <label>Description <%= f.text_area :description, class: "fg-input" %></label>
    <label>Rate ($/hr) <%= f.text_field :rate, value: @resource.rate, class: "fg-input" %></label>
    <label><%= f.check_box :active %> Active</label>
    <%= f.submit class: "dd-topbar-btn dd-btn-primary" %>
  </div>
<% end %>
EOF

cat > app/views/dymond_booking/booking_dashboard/new_resource.html.erb << 'EOF'
<% content_for :page_title, "New Resource" %>
<%= render "resource_form" %>
EOF

cat > app/views/dymond_booking/booking_dashboard/edit_resource.html.erb << 'EOF'
<% content_for :page_title, "Edit #{@resource.name}" %>
<%= render "resource_form" %>
EOF

echo "Writing event CRUD views..."
cat > app/views/dymond_booking/booking_dashboard/_event_form.html.erb << 'EOF'
<%= form_with model: @event, url: (@event.persisted? ? dymond_dash.booking_event_path(@event) : dymond_dash.booking_events_path) do |f| %>
  <div class="dd-card" style="display:flex; flex-direction:column; gap:12px; max-width:500px;">
    <label>Title <%= f.text_field :title, class: "fg-input" %></label>
    <label>Description <%= f.text_area :description, class: "fg-input" %></label>
    <label>Location <%= f.text_field :location, class: "fg-input" %></label>
    <label>Start <%= f.datetime_field :start_time, class: "fg-input" %></label>
    <label>End <%= f.datetime_field :end_time, class: "fg-input" %></label>
    <label>Capacity (optional) <%= f.number_field :capacity, class: "fg-input" %></label>
    <label><%= f.check_box :public %> Public event</label>
    <%= f.submit class: "dd-topbar-btn dd-btn-primary" %>
  </div>
<% end %>
EOF

cat > app/views/dymond_booking/booking_dashboard/new_event.html.erb << 'EOF'
<% content_for :page_title, "New Event" %>
<%= render "event_form" %>
EOF

cat > app/views/dymond_booking/booking_dashboard/edit_event.html.erb << 'EOF'
<% content_for :page_title, "Edit #{@event.title}" %>
<%= render "event_form" %>
<div class="dd-card" style="margin-top:16px;">
  <div class="dd-card-title">RSVPs (<%= @event.going_count %> going)</div>
  <% @event.rsvps.includes(:attendee).each do |r| %>
    <p style="font-size:13px;"><%= r.attendee.full_name %> · <%= r.status.humanize %></p>
  <% end %>
</div>
EOF

echo "Registering nav item..."
cat > ~/Desktop/Development/lightekmcg-site/config/initializers/booking_nav.rb << 'EOF'
# frozen_string_literal: true
Rails.application.config.after_initialize do
  next unless defined?(DymondDash::FeatureRegistry)
  DymondDash::FeatureRegistry.register do |f|
    f.slug = :booking; f.label = "Booking"; f.icon = "calendar"
    f.gem_source = "booking"; f.nav_section = :team; f.min_plan = :starter
    f.nav_items = [{ label: "Booking Calendar", icon: "calendar", path: "dymond_dash.booking_dashboard_path" }]
  end
rescue StandardError => e
  Rails.logger.warn "[Booking] nav registration skipped: #{e.message}"
end
EOF

echo "Stage 3 (admin views) done."
cd ~/Desktop/Development/dymond_booking
mkdir -p app/views/dymond_booking/public

cat > app/views/dymond_booking/public/index.html.erb << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<%= csrf_meta_tags %>
<title>Booking & Events — Lightek MCG</title>
<style>
  :root{
    --bg:#0a0e16; --panel:#0d1220; --border:rgba(255,255,255,.08);
    --cyan:#00b4dc; --cyan2:#20d8f8; --green:#18c878; --orange:#e08020;
    --white:#e4eef8; --muted:rgba(228,238,248,.45);
    --fc:'Arial Black',sans-serif; --fb:-apple-system,sans-serif; --fm:'Courier New',monospace;
  }
  *,*::before,*::after{box-sizing:border-box;margin:0;padding:0;}
  body{background:var(--bg);color:var(--white);font-family:var(--fb);}
  .bk-topnav{display:flex;align-items:center;justify-content:space-between;padding:16px 32px;border-bottom:1px solid var(--border);background:var(--panel);}
  .bk-logo{display:flex;align-items:center;gap:10px;font-family:var(--fc);font-weight:900;letter-spacing:.05em;}
  .bk-logo-mark{width:32px;height:32px;border:2px solid var(--cyan);color:var(--cyan);display:flex;align-items:center;justify-content:center;font-size:16px;}
  .bk-eyebrow{font-family:var(--fm);font-size:9px;letter-spacing:.2em;text-transform:uppercase;color:var(--muted);margin-left:12px;padding-left:12px;border-left:1px solid var(--border);}
  .bk-nav-right{display:flex;align-items:center;gap:10px;}
  .bk-btn{font-family:var(--fc);font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;
          padding:9px 18px;border:1px solid var(--border);background:transparent;color:var(--white);cursor:pointer;transition:all .15s;}
  .bk-btn:hover{border-color:var(--cyan);color:var(--cyan);}
  .bk-btn.primary{background:var(--cyan);color:#000;border-color:var(--cyan);}
  .bk-btn.primary:hover{background:var(--cyan2);}
  .bk-hero{padding:64px 32px 40px;max-width:1100px;margin:0 auto;}
  .bk-hero-eyebrow{font-family:var(--fm);font-size:9px;letter-spacing:.2em;text-transform:uppercase;color:var(--cyan);margin-bottom:14px;}
  .bk-hero h1{font-family:var(--fc);font-size:clamp(36px,6vw,64px);font-weight:900;line-height:1.02;letter-spacing:-.02em;margin-bottom:16px;}
  .bk-hero p{font-size:16px;color:var(--muted);max-width:560px;line-height:1.6;}
  .bk-section{max-width:1100px;margin:0 auto;padding:24px 32px 48px;}
  .bk-section-title{font-family:var(--fc);font-size:22px;font-weight:900;margin-bottom:16px;letter-spacing:-.01em;}
  .bk-grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:16px;}
  .bk-card{background:var(--panel);border:1px solid var(--border);border-radius:2px;padding:20px;position:relative;overflow:hidden;}
  .bk-card::before{content:'';position:absolute;top:0;left:0;right:0;height:3px;background:var(--cyan);}
  .bk-card.event::before{background:var(--green);}
  .bk-card-date{font-family:var(--fm);font-size:11px;color:var(--cyan);letter-spacing:.08em;text-transform:uppercase;margin-bottom:8px;}
  .bk-card-title{font-family:var(--fc);font-size:17px;font-weight:900;margin-bottom:6px;}
  .bk-card-meta{font-size:12px;color:var(--muted);margin-bottom:14px;}
  .bk-card-rate{font-family:var(--fc);font-size:20px;font-weight:900;color:var(--cyan);margin-bottom:14px;}
  .bk-form-row{display:flex;flex-direction:column;gap:8px;margin-top:10px;}
  .bk-form-row input,.bk-form-row textarea{background:rgba(255,255,255,.04);border:1px solid var(--border);color:var(--white);padding:8px 10px;font-family:var(--fb);font-size:13px;}
  .bk-status{font-family:var(--fm);font-size:10px;margin-top:8px;letter-spacing:.05em;}
  .bk-status.ok{color:var(--green);}
  .bk-status.err{color:#e05050;}
  .bk-going-count{font-family:var(--fm);font-size:10px;color:var(--muted);margin-top:8px;}
</style>
</head>
<body>

<div class="bk-topnav">
  <div class="bk-logo">
    <div class="bk-logo-mark">L</div>
    LIGHTEK MCG
    <span class="bk-eyebrow">BOOKING & EVENTS</span>
  </div>
  <div class="bk-nav-right">
    <span style="font-family:var(--fm);font-size:11px;color:var(--muted);"><%= current_user&.full_name&.upcase || "GUEST" %></span>
  </div>
</div>

<div class="bk-hero">
  <div class="bk-hero-eyebrow">◆ LIGHTEK MCG · RESERVE A RESOURCE OR RSVP TO AN EVENT</div>
  <h1>BOOK IT.<br>SHOW UP.</h1>
  <p>Reserve DJs, venues, and services for your next deployment event — or RSVP to what's happening across the network.</p>
</div>

<div class="bk-section">
  <div class="bk-section-title">Upcoming Events</div>
  <div class="bk-grid">
    <% @events.each do |e| %>
      <div class="bk-card event">
        <div class="bk-card-date"><%= e.start_time.strftime("%b %-d, %Y · %-l:%M %p") %></div>
        <div class="bk-card-title"><%= e.title %></div>
        <div class="bk-card-meta"><%= e.location %><%= " · #{e.description}" if e.description.present? %></div>
        <button class="bk-btn primary" onclick="rsvp(<%= e.id %>, this)"<%= " disabled" if e.full? %>>
          <%= e.full? ? "FULL" : "RSVP — GOING" %>
        </button>
        <div class="bk-going-count" id="going-<%= e.id %>"><%= e.going_count %> going<%= " / #{e.capacity} capacity" if e.capacity %></div>
      </div>
    <% end %>
    <% if @events.empty? %>
      <p style="color:var(--muted); font-size:13px;">No upcoming public events right now.</p>
    <% end %>
  </div>
</div>

<div class="bk-section">
  <div class="bk-section-title">Available Resources</div>
  <div class="bk-grid">
    <% @resources.each do |r| %>
      <div class="bk-card">
        <div class="bk-card-date"><%= r.resource_type.upcase %></div>
        <div class="bk-card-title"><%= r.name %></div>
        <div class="bk-card-meta"><%= r.description %></div>
        <div class="bk-card-rate">$<%= r.rate.to_i %>/hr</div>
        <div class="bk-form-row">
          <input type="datetime-local" id="start-<%= r.id %>" placeholder="Start time">
          <input type="datetime-local" id="end-<%= r.id %>" placeholder="End time">
          <textarea id="notes-<%= r.id %>" rows="2" placeholder="Notes for this booking..."></textarea>
          <button class="bk-btn primary" onclick="requestBooking(<%= r.id %>, this)">REQUEST BOOKING →</button>
        </div>
        <div class="bk-status" id="status-<%= r.id %>"></div>
      </div>
    <% end %>
    <% if @resources.empty? %>
      <p style="color:var(--muted); font-size:13px;">No resources available right now.</p>
    <% end %>
  </div>
</div>

<script>
function csrf(){ return document.querySelector('meta[name="csrf-token"]')?.content; }

function rsvp(eventId, btn){
  btn.disabled = true;
  fetch('/booking/rsvp', {
    method: 'POST',
    headers: {'Content-Type':'application/json','Accept':'application/json','X-CSRF-Token':csrf()},
    body: JSON.stringify({event_id: eventId, status: 'going'})
  }).then(r => r.json()).then(data => {
    if (data.ok) {
      btn.textContent = '✓ GOING';
      document.getElementById('going-'+eventId).textContent = data.going_count + ' going';
    } else {
      btn.disabled = false;
      alert(data.error || 'Could not RSVP.');
    }
  }).catch(() => { btn.disabled = false; alert('Network error.'); });
}

function requestBooking(resourceId, btn){
  const start = document.getElementById('start-'+resourceId).value;
  const end = document.getElementById('end-'+resourceId).value;
  const notes = document.getElementById('notes-'+resourceId).value;
  const status = document.getElementById('status-'+resourceId);
  if (!start || !end) { status.textContent = 'Pick a start and end time.'; status.className = 'bk-status err'; return; }
  btn.disabled = true;
  fetch('/booking/book', {
    method: 'POST',
    headers: {'Content-Type':'application/json','Accept':'application/json','X-CSRF-Token':csrf()},
    body: JSON.stringify({booking: {resource_id: resourceId, start_time: start, end_time: end, notes: notes}})
  }).then(r => r.json()).then(data => {
    btn.disabled = false;
    if (data.ok) {
      status.textContent = '✓ Requested — status: ' + data.status;
      status.className = 'bk-status ok';
    } else {
      status.textContent = data.error || 'Could not submit request.';
      status.className = 'bk-status err';
    }
  }).catch(() => { btn.disabled = false; status.textContent = 'Network error.'; status.className = 'bk-status err'; });
}
</script>
</body>
</html>
EOF

echo "Adding current_user to PublicController for consistency with other public pages..."
python3 - << 'PYEOF'
path = "app/controllers/dymond_booking/public_controller.rb"
with open(path) as f:
    content = f.read()
print("PublicController already inherits DymondSite::ApplicationController, which has current_user from the earlier fix — no change needed.")
PYEOF

echo "Stage 4 (public view) done."
