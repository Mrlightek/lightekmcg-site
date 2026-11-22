# frozen_string_literal: true

module NevaehImprovement
  module PurchasedService
    KEY = 'purchased_service'

    module_function

    def strategies = ['direct_service_link']
    def available_for?(_operator) = defined?(NevaehCustomerService::Cases).present?
    def negative_examples
      [{}, {'case_uncontested' => true, 'owned_ready_service' => false},
        {'case_uncontested' => false, 'owned_ready_service' => true}]
    end

    def action(strategy, signals)
      'offer_owned_service' if strategy == 'direct_service_link' &&
        signals['owned_ready_service'] == true && signals['case_uncontested'] == true
    end

    def accepts?(action, signals)
      action.nil? || (action == 'offer_owned_service' && signals['order_id'].to_i.positive? &&
        signals.values_at('owned_ready_service', 'case_uncontested') == [true, true])
    end

    def action_regression?(row, _strategy) = row.outcome['regression'] == true

    def sweep!
      return unless defined?(NevaehCustomerService::Cases)

      cases.scope.where("extra_fields->'customer_service'->>'topic' = ?", 'find_services')
        .where(created_at: Cycle::WINDOW.ago..Time.current).find_each { |ticket| process_record(ticket) { start!(ticket) } }
      rows.where(measured_at: nil).where('started_at <= ?', Cycle::WINDOW.ago).find_each { |row| process_record(row) { measure!(row) } }
      User.where(id: rows.select(:operator_id).distinct).find_each { |operator| Cycle.new(operator, KEY).evaluate! }
    end

    def process_record(record)
      yield
    rescue StandardError => error
      Rails.logger.warn("[Nevaeh service improvement] #{record.class.name} ##{record.id}: #{error.class}")
    end

    def start!(ticket)
      ticket.with_lock do
        next unless ticket.extra_fields.dig('customer_service', 'state') == 'answered' &&
          ticket.extra_fields.dig('customer_service', 'topic') == 'find_services' && uncontested?(ticket)

        actor = ticket.submitted_by
        next unless LightekPeople::LifecycleAccess.active?(actor)

        paid = cases.installations(actor).where(status: %w[paid fulfilled]).where.not(paid_at: nil).limit(2).to_a
        next unless paid.one?

        order = paid.first
        next unless cases.installations(actor).exists?(order.id) && LightekCommerce::Installations.ready?(order) &&
          !LightekCommerce::Installations.member_move_pending?(order)

        operator = LightekPwa::Policy.platform_operator(order.site)
        next unless NevaehOnboarding::StandingAssignment.operator?(operator)

        cycle = Cycle.new(operator, KEY)
        signals = {'order_id' => order.id, 'owned_ready_service' => true, 'case_uncontested' => true}
        row = cycle.observe!(ticket.id, signals, comparison_key: "#{actor.id}:#{order.id}")
        next unless row && row.signals['order_id'] == order.id &&
          action(cycle.strategy(row), row.signals) && row.receipt['notification_id'].nil?

        row.with_lock do
          next if row.measured_at? || row.receipt['notification_id'] || row.receipt['opened_at']

          notification = DymondDash::Notification.find_or_create_by!(recipient: actor, subject: order,
            category: 'system', title: 'Open your purchased Lightek service') do |record|
            record.body = 'Nevaeh verified that this service is available in My Applications.'
            record.url = Rails.application.routes.url_helpers.installation_path(order)
          end
          row.update!(receipt: row.receipt.merge('notification_id' => notification.id))
        end
      end
    end

    def record_visit!(actor, order)
      return unless defined?(NevaehCustomerService::Cases) && NevaehResolutionObservation.table_exists? &&
        LightekCommerce::Installations.ready?(order) && !LightekCommerce::Installations.member_move_pending?(order) &&
        cases.installations(actor).exists?(order.id)

      owned = cases.customer_scope(actor).select(:id)
      rows.where(subject_id: owned, measured_at: nil)
        .where("CAST(signals->>'order_id' AS TEXT) = ?", order.id.to_s).find_each do |row|
          row.with_lock do
            next if row.measured_at? || row.receipt['opened_at'] || row.started_at < Cycle::WINDOW.ago

            row.update!(receipt: row.receipt.merge('opened_at' => Time.current.iso8601))
          end
        end
    end

    def measure!(row)
      ticket = cases.scope.find_by(id: row.subject_id)
      ticket&.with_lock do
        row.with_lock do
          next if row.measured_at?

          reopened = ticket.events.where(action: cases::CUSTOMER_REPLY)
            .where('created_at >= ? AND created_at <= ?', row.started_at, row.started_at + Cycle::WINDOW).exists?
          handoff = ticket.events.where(action: cases::STAFF_REPLY)
            .where('created_at >= ? AND created_at <= ?', row.started_at, row.started_at + Cycle::WINDOW).exists?
          actor = ticket.submitted_by
          order = cases.installations(actor).find_by(id: row.signals['order_id']) if LightekPeople::LifecycleAccess.active?(actor)
          verified = order && row.receipt['opened_at'] && !reopened &&
            LightekCommerce::Installations.ready?(order) && !LightekCommerce::Installations.member_move_pending?(order)
          row.update!(measured_at: Time.current, outcome: {'verified' => !!verified, 'reopened' => reopened, 'handoff' => handoff,
            'regression' => row.receipt['notification_id'].present? && order.nil?})
        end
      end
      row.update!(measured_at: Time.current, outcome: {'excluded' => true}) unless ticket
    end

    def uncontested?(ticket)
      !ticket.events.where(action: [cases::CUSTOMER_REPLY, cases::STAFF_REPLY]).exists?
    end

    def cases = NevaehCustomerService::Cases
    def rows = NevaehResolutionObservation.where(workflow: KEY)
  end
end
