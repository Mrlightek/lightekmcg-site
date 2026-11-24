module ItServices
  class TechnicianPayout
    class Invalid < StandardError; end

    def self.requests_for(site)
      reservations = LightekReservations::Reservation.joins(:resource).where(lightek_reservation_resources: { site_id: site.id })
      ItServiceRequest.where(status: "resolved", reservation_id: reservations.select(:id)).where.not(technician_id: nil)
    end

    def initialize(access:, site:)
      @access = access
      @site = site
    end

    def prepare!(run:, request_ids:, gross_amounts:, deductions:)
      @access.require!(:prepare)
      unless @site.tenant == @access.employer && run.employer_id == @access.employer.id && run.currency == "USD"
        raise LightekPeople::Access::Denied, "Choose your organization’s payroll run."
      end
      raise Invalid, "IT Services cases are unavailable." unless Enrollment.operations_ready?

      ids = Array(request_ids).map { |id| Integer(id.to_s, 10) }.uniq.sort
      raise Invalid, "Choose between 1 and 50 completed cases." unless ids.size.between?(1, 50)

      @access.employer.with_lock do
        run.with_lock do
          @access.require!(:prepare)
          raise Invalid, "Choose a draft payroll run." unless run.draft?

          requests = self.class.requests_for(@site).where(id: ids).order(:id).lock.to_a
          raise Invalid, "A selected case is unavailable." unless requests.size == ids.size
          technician_id = requests.first.technician_id
          raise Invalid, "Prepare a separate statement for each technician." unless requests.all? { |record| record.technician_id == technician_id }

          employment = LightekPeople::Employment.find_by(employer: @access.employer, worker_id: technician_id)
          raise Invalid, "Set up this technician in People & Payroll first." unless employment
          totals = ids.index_with do |id|
            cents = Integer(gross_amounts.fetch(id.to_s, "").to_s, 10)
            raise Invalid, "Enter a positive payout amount in cents for each case." unless cents.between?(1, 100_000_000)
            cents
          end
          existing = Payout.where(service_request_id: ids).includes(pay_statement: :pay_run).index_by(&:service_request_id)
          statement = run.pay_statements.find_by(employment: employment)
          if statement
            previous = Payout.where(pay_statement: statement).pluck(:service_request_id, :gross_cents).to_h
            return statement if previous == totals && deductions.all? { |field, value| statement.public_send(field) == value }

            raise Invalid, "This technician already has a statement in this run."
          end

          requests.each do |record|
            verify_case!(record, run: run, employment: employment)
            prior = existing[record.id]
            if prior && (prior.pay_statement.pay_run.status != "canceled" || prior.pay_statement.attempted_at?)
              raise Invalid, "A selected case has already been assigned to payroll."
            end
          end
          statement = LightekPeople::Payroll.new(access: @access).add!(run: run, employment: employment,
            values: deductions.merge(gross_cents: totals.values.sum))
          requests.each do |record|
            prior = existing[record.id]
            if prior && (prior.employer_id != @access.employer.id || prior.technician_id != technician_id || prior.gross_cents != totals.fetch(record.id))
              raise Invalid, "The replacement must preserve the reviewed technician and gross amount."
            end
            payout = prior || Payout.new(service_request_id: record.id, employer: @access.employer, technician_id: technician_id,
              prepared_by: @access.actor, gross_cents: totals.fetch(record.id))
            payout.update!(pay_statement: statement)
            LightekPeople::AuditEvent.record!(employer: @access.employer, actor: @access.actor,
              action: prior ? "it_service_payout_restaged" : "it_service_payout_staged", record: payout)
          end
          statement
        end
      end
    rescue ArgumentError, TypeError
      raise Invalid, "Enter valid case IDs and amounts in whole cents."
    end

    private

    def verify_case!(record, run:, employment:)
      closed_on = record.closed_at&.to_date
      unless closed_on && closed_on.between?(run.period_start, run.period_end) && employment.worked_during?(closed_on, closed_on)
        raise Invalid, "The work acceptance date must be covered by the technician’s employment and payroll period."
      end

      reservation = record.reservation
      ticket = Marlon::Ticket.where(related: record, status: "resolved")
        .where("extra_fields->>'source' = ?", NevaehCustomerService::Cases::SOURCE).order(:id).last
      handoff = ticket&.extra_fields.to_h.fetch("it_services_handoff", {})
      clearance = handoff.fetch("payment_clearance", {})
      unless reservation.customer_id == record.user_id && reservation.resource.kind == "service" &&
          reservation.status.in?(%w[confirmed checked_in completed]) &&
          handoff.values_at("state", "request_id", "technician_id", "completed_by_id", "reservation_id") ==
            ["customer_confirmed", record.id, record.technician_id, record.technician_id, reservation.id] &&
          handoff["completion_summary"].present? && clearance["reservation_id"] == reservation.id
        raise Invalid, "Nevaeh’s ticket must contain the matched customer confirmation and payment clearance."
      end

      if reservation.order_id
        valid_payment = clearance["source"] == "lightek_reservations" && clearance["order_id"] == reservation.order_id &&
          reservation.order.site_id == @site.id && Gatekeeper::ItServiceBillingPolicy.funded_order?(reservation.order)
      else
        claim = CoverageClaim.find_by(id: clearance["coverage_claim_id"], reservation: reservation, service_request_id: record.id)
        period = claim&.period
        valid_payment = clearance["source"] == "managed_it_subscription" && period &&
          period.membership.customer_id == record.user_id && period.membership.plan.resource_id == reservation.resource_id &&
          period.invoice_id == clearance["invoice_id"] && period.invoice.settlement_order_id == clearance["order_id"] &&
          Gatekeeper::ItServiceBillingPolicy.funded_order?(period.invoice.settlement_order)
      end
      raise Invalid, "The service payment requires reconciliation." unless valid_payment
    end
  end
end
