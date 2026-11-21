# frozen_string_literal: true

require "csv"

module Studio
  module Broadcasting
    class ContractReport
      attr_reader :version, :carriage

      def initialize(version: nil, carriage: nil)
        @version = version
        @carriage = carriage || version.contract.carriage_agreement
      end

      def snapshot
        return legacy_snapshot unless version

        terms = version.terms_snapshot
        evidence_rows = BroadcastContractEvidence.where(version_id: version.evidence_version_ids)
        evidence = evidence_rows.group(:kind).sum(:quantity)
        payments = version.contract.payment_rows(terms.fetch("payment_ids"), recipient_id: terms["payout_recipient_id"]).to_a
        signed = version.executed?
        booked_delivery = terms["delivery_mode"] == "booked_spots"
        delivered = signed ? (booked_delivery ? payments.count { |payment| payment.placement.delivered_at? } : evidence.fetch("delivery", 0)) : 0
        promised = terms.fetch("delivery_target")
        agreed = terms.fetch("amount_cents")
        paid = signed ? (version.contract.kind == "sponsor" ? payments.sum { |payment| collected(payment) } : evidence.fetch("reviewed_payment", 0)) : 0
        role = version.contract.payout_role
        royalties = role && payments.flat_map(&:payouts).select { |payout| payout.role == role }
        held = payments.select { |payment| payment.state == "held" }
        outstanding = if signed
          if version.contract.kind == "sponsor"
            payments.select { |payment| payment.placement.delivered_at? && collected(payment).zero? && payment.state != "held" }.sum(&:amount_cents)
          else
            [agreed - paid, 0].max
          end
        end
        {
          "title" => terms.fetch("title"), "kind" => terms.fetch("kind"), "version" => version.number, "issuer" => terms.fetch("issuer"),
          "counterparty" => terms.fetch("counterparty"), "starts_on" => version.starts_on.iso8601, "ends_on" => version.ends_on.iso8601,
          "market" => terms["market"], "status" => version.withdrawn_at? ? "Withdrawn" : (signed ? "Executed" : "Awaiting signatures"),
          "terms" => terms.fetch("terms"), "carriage_terms" => terms.fetch("carriage_terms"), "as_of" => Time.current.utc.iso8601,
          "promised_deliveries" => promised, "delivered" => delivered, "deliveries_remaining" => signed ? [promised - delivered, 0].max : nil,
          "agreed_cents" => agreed, "confirmed_paid_cents" => paid, "outstanding_cents" => outstanding,
          "held_cents" => signed && version.contract.kind == "sponsor" ? held.sum(&:amount_cents) : nil,
          "not_yet_delivered_cents" => signed && version.contract.kind == "sponsor" ? payments.reject { |payment| payment.placement.delivered_at? }.sum(&:amount_cents) : nil,
          "royalty_role" => role, "royalty_paid_cents" => signed && royalties ? royalties.sum { |payout| transferred(payout) } : nil,
          "royalty_owed_cents" => signed && royalties ? royalties.sum { |payout| payout_due(payout) } : nil,
          "royalty_held_cents" => signed && royalties ? royalties.select { |payout| payout.payment.state == "held" }.sum(&:amount_cents) : nil,
          "currency" => "USD", "fixed_fee_due_on" => (terms["due_on"] if version.contract.kind != "sponsor"),
          "payment_basis" => version.contract.kind == "sponsor" ? "Verified ad payment captures" : "Operator-reviewed fixed-fee payment evidence",
          "delivery_basis" => booked_delivery ? "Verified public ad insertions" : "Operator-reviewed delivery evidence",
          "audience" => audience,
          "evidence" => evidence_rows.order(:occurred_on, :id).map { |row| row.slice("kind", "reference", "quantity", "occurred_on", "recorded_by_id") },
          "booked_spots" => terms.fetch("booked_spots").map { |spot| spot.merge(spot_status(payments.find { |payment| payment.id == spot.fetch("payment_id") }, beneficiary: role)) }
        }
      end

      def self.for_site(site)
        local = CarriageAgreement.where(outlet_site: site).or(CarriageAgreement.where(station_site: site, hosted_carriage_id: nil))
        contracts = BroadcastContract.where(site: site).or(BroadcastContract.where(carriage_agreement_id: local.select(:id)))
        rows = []
        contracts.includes(versions: :signatures).find_each do |contract|
          history = contract.versions.sort_by(&:number)
          version = history.reverse.find { |row| row.executed? && row.starts_on <= Date.current } || history.last
          rows << new(version: version).snapshot if version
        end
        local.where.not(id: contracts.where.not(carriage_agreement_id: nil).select(:carriage_agreement_id)).find_each do |carriage|
          rows << new(carriage: carriage).snapshot
        end
        ProgramLicense.where(licensor_site: site).or(ProgramLicense.where(licensee_site: site)).find_each do |license|
          rows << program_license(license)
        end
        rows
      end

      def self.program_license(license)
        station_channels = Channel.where(site_id: license.licensee_site_id).select(:id)
        airings = Airing.where(channel_id: station_channels, starts_at: license.starts_at..license.ends_at)
        matched = []
        airings.find_each do |airing|
          played = airing.state["public_started_at"].present? && airing.events.filter_map { |event| event["row"] if event["type"] == "row_aired" }
          indexes = airing.rundown.each_index.select { |index| airing.rundown[index]["license_id"] == license.id }
          next if indexes.empty?

          matched << { "airing_id" => airing.id, "title" => airing.title, "starts_at" => airing.starts_at.utc.iso8601,
            "status" => airing.status, "observed_rows" => played ? (indexes.map { |index| index + 1 } & played) : [] }
        end
        {
          "title" => license.title, "kind" => "program_license", "issuer" => license.source_name,
          "counterparty" => license.licensee_site.name, "starts_on" => license.starts_at.utc.iso8601, "ends_on" => license.ends_at.utc.iso8601,
          "status" => license.transferable? ? license.status.humanize : "Withdrawn upstream",
          "terms" => license.rights_label, "as_of" => Time.current.utc.iso8601,
          "delivered" => matched.count { |airing| airing["observed_rows"].present? },
          "currency" => "USD", "payment_basis" => "The rights grant has no structured fee or delivery quota.",
          "delivery_basis" => "Public playout observed for the licensed rows on this installation",
          "program_airings" => matched,
          "licensed_clips" => ProgramClip.where(license: license).with_attached_video.map do |clip|
            { "title" => clip.title, "prepared" => clip.video.attached?, "withdrawn_at" => clip.withdrawn_at&.utc&.iso8601 }
          end,
          "sublicenses" => ProgramLicense.where(parent_license: license).order(:id).pluck(:id, :status)
        }
      end

      def self.csv(rows)
        headers = %w[title kind version as_of issuer counterparty starts_on ends_on market status terms carriage_terms promised_deliveries delivered
          deliveries_remaining agreed_cents confirmed_paid_cents outstanding_cents held_cents not_yet_delivered_cents royalty_role royalty_paid_cents
          royalty_owed_cents royalty_held_cents currency fixed_fee_due_on payment_basis delivery_basis audience evidence booked_spots program_airings licensed_clips sublicenses]
        CSV.generate do |csv|
          csv << headers
          rows.each { |row| csv << headers.map { |key| csv_cell(row[key]) } }
        end
      end

      def self.csv_cell(value)
        return JSON.generate(value) if value.is_a?(Array) || value.is_a?(Hash)
        return value unless value.is_a?(String) && value.match?(/\A[[:space:]]*[=+@-]|\A[\t\r\n]/)

        "'#{value}"
      end

      private

      def collected(payment)
        payment.state == "captured" && payment.captured_at? && payment.charge_reference? ? payment.amount_cents : 0
      end

      def transferred(payout)
        payout.transfer_reference? && !payout.reversal_reference? ? payout.amount_cents : 0
      end

      def payout_due(payout)
        collected(payout.payment).positive? && payout.payment.placement.delivered_at? && !payout.transfer_reference? ? payout.amount_cents : 0
      end

      def spot_status(payment, beneficiary:)
        return { "funding_status" => "unavailable" } unless payment

        { "delivered_at" => payment.placement.delivered_at&.utc&.iso8601, "funding_status" => payment.state,
          "captured_cents" => (collected(payment) unless beneficiary) }
      end

      def legacy_snapshot
        {
          "title" => carriage.channel_name, "kind" => "carriage", "issuer" => carriage.outlet_site.name,
          "counterparty" => carriage.station_site.name, "starts_on" => carriage.starts_on.iso8601, "ends_on" => carriage.ends_on.iso8601,
          "status" => carriage.accepted_at? ? "Accepted carriage terms" : "Awaiting acceptance",
          "terms" => ("Accepted on #{carriage.accepted_at.utc.iso8601}" if carriage.accepted_at?),
          "carriage_terms" => carriage.terms, "audience" => audience, "currency" => "USD", "as_of" => Time.current.utc.iso8601,
          "payment_basis" => "Compensation is in the original text. No structured settlement amount has been recorded."
        }
      end

      def audience
        return unless carriage

        channel_id = carriage.channel_id || -carriage.hosted_carriage_id
        days = (version&.starts_on || carriage.starts_on)..(version&.ends_on || carriage.ends_on)
        sessions = ViewSession.where(channel_id: channel_id, outlet_site_id: carriage.outlet_site_id, day: days, ad_row: -1)
        { "sessions" => sessions.distinct.count(:session_key), "segments" => sessions.sum(:segments), "viewing_ms" => sessions.sum(:media_ms) }
      end
    end
  end
end
