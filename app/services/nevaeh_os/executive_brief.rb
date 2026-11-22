# frozen_string_literal: true

module NevaehOs
  class ExecutiveBrief
    ROW_LIMIT = 5

    def self.available_to?(actor)
      actor&.role == 'super_admin'
    end

    def initialize(actor)
      raise CanCan::AccessDenied unless self.class.available_to?(actor)

      @actor = actor
      @now = Time.current
      @routes = Rails.application.routes.url_helpers
    end

    def sections
      [provisioning_approvals, blocked_goals, urgent_tickets, due_follow_ups, paid_orders, upcoming_bookings]
    end

    def reply
      current = sections
      priority = current.find { |section| section[:count].positive? }
      lines = current.map { |section| "#{section[:label]}: #{section[:count]}" }
      if (item = priority&.fetch(:rows)&.first)
        lines.unshift("Start with #{item.fetch(:title)}.")
      else
        lines.unshift("Your executive queue is clear.")
      end
      lines << "Open CEO Desk in the Dashboard for the records and links."
      {'text' => lines.join("\n"), 'status' => 'ready', 'executive_brief' => current}
    end

    private

    def provisioning_approvals
      requests = ProvisioningRequest.needs_approval.order(:created_at, :id)
      section('Provisioning decisions pending', requests) do |request|
        {title: "Provisioning request ##{request.id}", detail: request.node_label.presence || 'Review proposed server capacity.',
          path: @routes.dashboard_provisioning_request_path(request)}
      end
    end

    def blocked_goals
      goals = NevaehGoal.where(user: @actor, status: 'blocked')
      section('Blocked Nevaeh goals', goals.order(updated_at: :desc, id: :desc)) do |goal|
        {title: "Goal ##{goal.id}: #{goal.title}", detail: goal.error.presence&.truncate(180) || 'Review the goal in Nevaeh.',
          path: @routes.dashboard_nevaeh_os_path(command: "/goal show #{goal.id}")}
      end
    end

    def urgent_tickets
      tickets = Marlon::Ticket.where(status: %w[open in_progress], priority: %w[critical high])
      tickets = tickets.order(Arel.sql("CASE priority WHEN 'critical' THEN 0 ELSE 1 END"), urgency: :desc, created_at: :asc, id: :asc)
      section('High-priority support tickets', tickets) do |ticket|
        {title: "#{ticket.number}: #{ticket.title}", detail: [ticket.priority.humanize, ticket.status.humanize].join(' · '),
          path: @routes.employee_ticket_path(ticket)}
      end
    end

    def due_follow_ups
      tasks = LightekSales::Task.open_tasks.where(site: owned_sites).where('due_at <= ?', @now)
      # Prospect tasks are visible only on sites with prospecting access.
      prospect_type = 'LightekSales::SocialProspect'
      prospect_site_ids = tasks.where(record_type: prospect_type).distinct.pluck(:site_id)
      permitted_ids = owned_sites.where(id: prospect_site_ids).select { |site| LightekSales::Access.prospecting_allowed?(site) }.map(&:id)
      tasks = tasks.where.not(record_type: prospect_type).or(tasks.where(site_id: permitted_ids))
      section('Sales follow-ups due', tasks.order(:due_at, :id).includes(:site)) do |task|
        {title: task.title, detail: "#{task.site.name} · due #{timestamp(task.due_at)}",
          path: @routes.dashboard_sales_path(site_id: task.site_id, tab: 'tasks')}
      end
    end

    def paid_orders
      orders = LightekCommerce::Order.visible.where(site: owned_sites, status: 'paid').where.not(paid_at: nil)
      section('Paid orders awaiting fulfillment', orders.order(:paid_at, :id).includes(:site)) do |order|
        {title: "Order ##{order.id}", detail: "#{order.site.name} · paid #{timestamp(order.paid_at)}",
          path: @routes.dashboard_commerce_orders_path(site_id: order.site_id)}
      end
    end

    def upcoming_bookings
      bookings = LightekReservations::Reservation.where(customer: @actor, status: %w[confirmed checked_in],
        starts_at: @now...(@now + 7.days))
      section('Your bookings in the next 7 days', bookings.order(:starts_at, :id).includes(:resource)) do |booking|
        {title: booking.resource.name, detail: "#{booking.reference} · #{timestamp(booking.starts_at)}",
          path: @routes.my_reservation_path(booking)}
      end
    end

    def owned_sites
      @owned_sites ||= LightekSettings::WebsiteIdentity.sites_for(@actor).where(tenant: @actor)
    end

    def section(label, scope)
      {label: label, count: scope.count, rows: scope.limit(ROW_LIMIT).map { |record| yield record }}
    end

    def timestamp(value)
      value.in_time_zone.strftime('%b %-d, %-I:%M %p %Z')
    end
  end
end
