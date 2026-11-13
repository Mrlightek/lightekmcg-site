require 'net/http'
require 'json'
require 'uri'
module DymondBank
  # Workforce disbursements are deliberately separate from merchant sale proceeds.
  # This adapter never falls back to the platform's shared Stripe payment balance.
  class WorkforcePayouts
    class Unavailable < StandardError; end
    class ProviderError < StandardError; end
    PURPOSE = 'workforce_payouts'.freeze
    VERSION = '2026-10-28.endive'.freeze
    ORIGIN = 'https://api.stripe.com'.freeze
    def self.slug(employer) = "workforce-payouts-#{employer.id}"
    def self.configured?(employer)
      LightekVault::Secret.find_by(slug: slug(employer))&.usable? == true
    end
    def self.store!(access:, secret_key:, financial_account_ref:)
      access.require!(:owner)
      key, account = secret_key.to_s.strip, financial_account_ref.to_s.strip
      raise Unavailable, 'Enter a restricted Stripe live key or a sandbox key' unless key.match?(/\A(?:rk_(?:live|test)|sk_test)_[A-Za-z0-9]{8,}\z/)
      raise Unavailable, 'Enter the Stripe FinancialAccount ID' unless account.match?(/\A[a-z][A-Za-z0-9_]{5,200}\z/)
      access.employer.with_lock do
        if configured?(access.employer)
          old = new(employer: access.employer).financial_account_ref
          if old != account && LightekPeople::PayoutDestination.joins(:employment).where(lightek_people_employments: {employer_id: access.employer.id}).exists?
            raise Unavailable, 'An employer with payout recipients cannot change sender accounts; rotate the key for the same sender instead'
          end
        end
        adapter = new(employer: access.employer, credentials: {'secret_key'=>key, 'financial_account_ref'=>account, 'employer_id'=>access.employer.id.to_s})
        adapter.verify_sender!
        sender = LightekPeople::PayoutSender.find_or_initialize_by(employer: access.employer)
        sender.update!(financial_account_ref: account)
        LightekVault::Service.store!(name: "Workforce payouts · employer #{access.employer.id}", slug: slug(access.employer), provider: 'stripe',
          purpose: PURPOSE, payload: {'secret_key'=>key, 'financial_account_ref'=>account, 'employer_id'=>access.employer.id.to_s},
          access_policy: {'consumers'=>[name], 'purposes'=>[PURPOSE]}, metadata: {'employer_id'=>access.employer.id.to_s}, requested_by: access.actor.email_address)
        LightekPeople::AuditEvent.record!(employer: access.employer, actor: access.actor, action: 'payout_sender_configured', record: access.employer)
      end
    ensure
      key&.clear
    end
    def initialize(employer:, credentials: nil)
      @employer, @provided_credentials = employer, credentials
    end
    def with_credentials
      payload = @provided_credentials || LightekVault::Service.checkout!(slug: self.class.slug(@employer), consumer: self.class.name,
        purpose: PURPOSE, requested_by: "employer:#{@employer.id}")
      raise Unavailable, 'Payout credentials belong to another employer' unless payload['employer_id'].to_s == @employer.id.to_s
      yield payload
    rescue ActiveRecord::RecordNotFound, LightekVault::Service::AccessDenied
      raise Unavailable, 'Configure this employer’s payout sender in Vault before onboarding or releasing payroll'
    ensure
      payload&.each_value { |value| value.clear if value.is_a?(String) && !value.frozen? } unless @provided_credentials
    end
    def financial_account_ref
      with_credentials do |c|
        reference = c.fetch('financial_account_ref')
        unless @provided_credentials || LightekPeople::PayoutSender.exists?(employer_id: @employer.id, financial_account_ref: reference)
          raise Unavailable, 'Payout sender binding does not match this employer'
        end
        reference.dup
      end
    end
    def verify_sender!
      ref = financial_account_ref
      response = request(:get, "/v2/money_management/financial_accounts/#{identifier!(ref)}")
      raise Unavailable, 'Financial account could not be verified for these credentials' unless response['id'] == ref
      response
    end
    def onboard!(destination:, return_url:, refresh_url:)
      raise Unavailable, 'Destination belongs to another employer' unless destination.employment.employer_id == @employer.id
      destination.with_lock do
        existing_recipient = destination.recipient_ref.present?
        unless destination.recipient_ref.present?
          worker = destination.employment.worker
          recipient = request(:post, '/v2/core/accounts', {
            'contact_email'=>worker.email_address, 'display_name'=>worker.full_name,
            'identity'=>{'country'=>'us', 'entity_type'=>destination.employment.worker_kind == 'agency' ? 'company' : 'individual'},
            'configuration'=>{'recipient'=>{'capabilities'=>{'bank_accounts'=>{'ach'=>{'requested'=>true}}}}},
            'include'=>['configuration.recipient']
          }, key: "workforce-recipient-#{destination.id}")
          destination.update!(recipient_ref: identifier!(recipient.fetch('id')))
        end
        refresh_destination!(destination) if existing_recipient
        use_case = destination.capability_status == 'active' ? 'account_update' : 'account_onboarding'
        link = request(:post, '/v2/core/account_links', {'account'=>destination.recipient_ref,
          'use_case'=>{'type'=>use_case, use_case=>{'configurations'=>['recipient'], 'return_url'=>return_url, 'refresh_url'=>refresh_url}}})
        uri = URI.parse(link.fetch('url'))
        raise ProviderError, 'Invalid hosted onboarding URL' unless uri.scheme == 'https' && %w[accounts.stripe.com connect.stripe.com].include?(uri.host) && !uri.userinfo
        uri.to_s
      end
    end
    def refresh_destination!(destination)
      raise Unavailable, 'Destination belongs to another employer' unless destination.employment.employer_id == @employer.id
      return unless destination.recipient_ref.present?
      response = request(:get, "/v2/core/accounts/#{identifier!(destination.recipient_ref)}?include[0]=configuration.recipient")
      destination.update!(capability_status: response.dig('configuration','recipient','capabilities','bank_accounts','ach','status').to_s.slice(0,50))
    end
    def prepare!(statement)
      run = statement.pay_run
      raise Unavailable, 'Sender account changed after approval' unless run.employer_id == @employer.id && run.financial_account_ref == financial_account_ref
      destination = statement.employment.payout_destination
      raise Unavailable, 'Worker must complete bank setup' unless destination&.recipient_ref.present?
      refresh_destination!(destination)
      raise Unavailable, 'Worker’s ACH payout capability is not active' unless destination.capability_status == 'active'
      request(:post, '/v2/money_management/payout_intents', {
        'from'=>{'financial_account'=>run.financial_account_ref, 'currency'=>run.currency.downcase},
        'to'=>{'recipient'=>destination.recipient_ref, 'payout_method_options'=>{'bank_account'=>{'preferred_networks'=>['ach']}}},
        'amount'=>{'value'=>statement.net_cents, 'currency'=>run.currency.downcase},
        'confirmation_method'=>'manual', 'description'=>"Payroll #{run.id} statement #{statement.id}"
      }, key: "workforce-statement-#{statement.id}-v1")
    end
    def retrieve!(reference)
      result = request(:get, "/v2/money_management/payout_intents/#{identifier!(reference)}")
      if result.dig('latest_payout','outbound_payment').present?
        attempt = request(:get, "/v2/money_management/outbound_payments/#{identifier!(result.dig('latest_payout','outbound_payment'))}")
        result['outbound_status'] = attempt['status']
      end
      result
    end
    def confirm!(statement)
      raise Unavailable, 'Sender account changed after approval' unless statement.pay_run.financial_account_ref == financial_account_ref
      request(:post, "/v2/money_management/payout_intents/#{identifier!(statement.provider_ref)}/confirm", {}, key: "workforce-confirm-#{statement.id}-v1")
    end
    private
    def identifier!(value)
      raise ProviderError, 'Invalid provider reference' unless value.to_s.match?(/\A[a-zA-Z0-9_]{3,200}\z/)
      value.to_s
    end
    def request(method, path, body = nil, key: nil)
      uri = URI.parse(ORIGIN + path)
      with_credentials do |credentials|
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.open_timeout = 5
        http.read_timeout = 20
        klass = method == :get ? Net::HTTP::Get : Net::HTTP::Post
        req = klass.new(uri)
        req['Authorization'] = "Bearer #{credentials.fetch('secret_key')}"
        req['Stripe-Version'] = VERSION
        req['Content-Type'] = 'application/json'
        req['Idempotency-Key'] = key if key
        req.body = JSON.generate(body) if body
        response = http.request(req)
        # Never surface provider error bodies; they can echo submitted values.
        raise ProviderError, "Stripe request failed (HTTP #{response.code})" unless response.is_a?(Net::HTTPSuccess)
        raise ProviderError, 'Stripe response was too large' if response.body.bytesize > 2_000_000
        JSON.parse(response.body)
      end
    rescue Net::OpenTimeout, Net::ReadTimeout, IOError, SystemCallError, OpenSSL::SSL::SSLError, JSON::ParserError
      raise ProviderError, 'Stripe response unavailable; reconcile before retrying'
    end
  end
end
