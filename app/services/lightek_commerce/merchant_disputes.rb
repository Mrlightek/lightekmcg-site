# frozen_string_literal: true
require 'digest'
require 'tmpdir'

module LightekCommerce
  class MerchantDisputes
    class Unavailable < StandardError; end
    class Unverified < Unavailable; end
    EVIDENCE_FIELDS = {
      'receipt' => 'Receipt',
      'shipping_documentation' => 'Shipping documentation',
      'customer_communication' => 'Customer communication',
      'service_documentation' => 'Service documentation',
      'uncategorized_file' => 'Other evidence'
    }.freeze
    MAX_EVIDENCE_BYTES = 4.megabytes
    RESPONDABLE = %w[needs_response warning_needs_response].freeze

    def initialize(order:, actor:)
      @order = order
      raise ActiveRecord::RecordNotFound unless order.site.tenant == actor &&
        LightekSettings::WebsiteIdentity.sites_for(actor).exists?(id: order.site_id)

      @options = LightekPayments::PayoutAccounts.options
      @intent = MerchantLedger.dispute_payment_intent!(order, @options)
    rescue MerchantLedger::Invalid
      raise Unverified, 'This order’s provider payment could not be verified.'
    end

    def list
      disputes = []
      each_dispute { |dispute| disputes << dispute }
      disputes
    end

    def each_dispute
      after = nil
      loop do
        query = {payment_intent: @intent, limit: 100}
        query[:starting_after] = after if after
        page = ::Stripe::Dispute.list(query, @options)
        page.data.each { |dispute| yield dispute if belongs_to_order?(dispute) }
        break unless page.has_more

        after = page.data.last&.id || raise(Unavailable, 'Stripe returned an incomplete dispute page.')
      end
    end

    def respond!(id:, evidence:, confirmed:, attachments: {})
      raise ActiveRecord::RecordNotFound unless id.to_s.match?(/\Adp_[a-zA-Z0-9_]{1,150}\z/)
      message = evidence.to_s.strip
      files = attachments.stringify_keys.sort.to_h
      unless confirmed && (message.present? || files.any?) && message.length <= 20_000
        raise Unavailable, 'Enter and confirm the evidence before submitting.'
      end

      @order.with_lock do
        dispute = ::Stripe::Dispute.retrieve(id, @options)
        raise ActiveRecord::RecordNotFound unless dispute.id == id && belongs_to_order?(dispute)
        unless RESPONDABLE.include?(dispute.status) && dispute.evidence_details&.due_by.to_i > Time.current.to_i &&
            dispute.evidence_details&.submission_count.to_i.zero?
          raise Unavailable, 'This dispute is no longer open for a response.'
        end

        fields = {}
        fields[:uncategorized_text] = message if message.present?
        validate_evidence_files!(files)
        extensions = files.transform_values { |file| evidence_extension!(file) }
        files.each do |kind, file|
          fields[kind] = upload_evidence!(id, file, extensions.fetch(kind))
        end
        digest = Digest::SHA256.hexdigest(fields.to_json).first(32)
        result = ::Stripe::Dispute.update(id, {evidence: fields, submit: true},
          @options.merge(idempotency_key: PaymentIdentity.key(@order, "dispute-#{id}-response-#{digest}")))
        DisputeCase.record!(order: @order, dispute: result, alert: false)
        result
      end
    rescue ::Stripe::StripeError
      raise Unavailable, 'The response could not be confirmed. Refresh the dispute before retrying.'
    end

    private

    def validate_evidence_files!(files)
      valid = files.all? do |kind, attachment|
        EVIDENCE_FIELDS.key?(kind) && attachment.is_a?(ActionDispatch::Http::UploadedFile) && attachment.size.positive?
      end
      return if valid && files.values.sum(&:size) <= MAX_EVIDENCE_BYTES

      raise Unavailable, 'Choose PDF, PNG or JPEG evidence files totaling up to 4 MB.'
    end

    def evidence_extension!(attachment)
      attachment.tempfile.rewind
      prefix = attachment.tempfile.read(8).to_s
      attachment.tempfile.rewind
      return '.pdf' if prefix.start_with?('%PDF-')
      return '.png' if prefix.start_with?("\x89PNG\r\n\x1A\n".b)
      return '.jpg' if prefix.start_with?("\xFF\xD8\xFF".b)

      raise Unavailable, 'Evidence must be a PDF, PNG or JPEG.'
    end

    def upload_evidence!(id, attachment, extension)
      tempfile = attachment.tempfile
      digest = Digest::SHA256.file(tempfile.path).hexdigest
      Dir.mktmpdir('commerce-evidence') do |directory|
        File.open(File.join(directory, "evidence#{extension}"), 'w+b', 0o600) do |file|
          IO.copy_stream(tempfile, file)
          file.rewind
          uploaded = ::Stripe::File.create({purpose: 'dispute_evidence', file: file},
            @options.merge(idempotency_key: PaymentIdentity.key(@order, "dispute-#{id}-file-#{digest}")))
          reference = uploaded.id.to_s
          raise Unavailable, 'The evidence upload could not be verified.' unless reference.match?(/\Afile_[A-Za-z0-9]+\z/)

          reference
        end
      end
    end

    def belongs_to_order?(dispute)
      intent = dispute.payment_intent
      intent = intent.id if intent.respond_to?(:id)
      intent == @intent && dispute.currency == @order.currency && dispute.amount.to_i.between?(1, @order.total_cents)
    end
  end
end
