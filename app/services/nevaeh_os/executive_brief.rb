# frozen_string_literal: true

module NevaehOs
  class ExecutiveBrief
    ROW_LIMIT = 5

    def self.available_to?(actor)
      actor&.role == 'super_admin' && LightekPeople::LifecycleAccess.active?(actor)
    end

    def initialize(actor)
      raise CanCan::AccessDenied unless self.class.available_to?(actor)

      @actor = actor
      @now = Time.current
      @routes = Rails.application.routes.url_helpers
    end

    def sections
      [provisioning_approvals, blocked_goals, urgent_tickets, due_follow_ups, paid_orders,
        executive_follow_through, executive_agenda, executive_mail, upcoming_bookings]
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

    def agenda_reply
      agenda = executive_agenda
      lines = agenda.fetch(:rows).map { |row| "#{row.fetch(:title)} · #{row.fetch(:detail)}" }
      lines.unshift("#{agenda.fetch(:count)} open agenda entries through the next 7 days.")
      lines << "Open your private CEO agenda for the full list and notes."
      {'text' => lines.join("\n"), 'status' => 'ready'}
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

    def executive_follow_through
      entries = NevaehExecutiveCase.where(owner: @actor).pending.where('due_at <= ?', @now)
      section('Executive follow-through due', entries.order(:due_at, :id)) do |entry|
        {title: entry.title, detail: "#{entry.kind_label} · #{entry.status.humanize}",
          path: @routes.dashboard_executive_work_path(item: entry.id)}
      end
    end

    def executive_agenda
      entries = NevaehAgendaItem.where(user: @actor).open_items.where('starts_at < ?', @now + 7.days)
      order = Arel.sql('CASE WHEN ends_at <= ? THEN 1 ELSE 0 END', @now)
      section('Open CEO agenda through the next 7 days', entries.order(order, :starts_at, :id)) do |entry|
        status = entry.ends_at <= @now ? 'Past due' : timestamp(entry.starts_at)
        {title: entry.title, detail: "#{entry.category_label} · #{status}",
          path: @routes.dashboard_nevaeh_agenda_path(edit: entry.id, anchor: 'agenda-entry')}
      end
    end

    def executive_mail
      mailboxes = LightekMail::Access.accounts(@actor).where(user: @actor)
      unread = LightekMail::MessageFolder.scope_messages(
        LightekMail::Message.where(account_id: mailboxes.select(:id)), 'unread'
      ).group(:account_id).count
      rows = mailboxes.where(id: unread.keys).order(:address).limit(ROW_LIMIT).map do |mailbox|
        amount = unread.fetch(mailbox.id)
        {title: mailbox.address, detail: "#{amount} unread",
          path: @routes.dashboard_mail_path(account_id: mailbox.id, folder: 'unread')}
      end
      {label: 'Unread messages in your mailboxes', count: unread.values.sum, rows: rows, row_count: unread.size,
        path: @routes.dashboard_mail_path}
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
