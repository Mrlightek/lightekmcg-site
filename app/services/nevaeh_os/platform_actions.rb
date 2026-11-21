# frozen_string_literal: true

module NevaehOs
  # Explicit OS bindings. These commands run through the saved-action worker
  # and reuse the same access checks as their Dashboard entry points.
  module PlatformActions
    REVIEWS = {
      'operations.finance.review' => 'finance',
      'operations.commerce.review' => 'commerce',
      'operations.hosting.review' => 'hosting',
      'operations.payroll.review' => 'payroll',
      'operations.sales.review' => 'sales'
    }.freeze

    INPUTS = {
      'sales.lead.create' => {'site_id'=>:id, 'name'=>160, 'company'=>160, 'email'=>254}.freeze,
      'sales.quote.issue' => {'site_id'=>:id, 'quote_id'=>:id, 'lock_version'=>:version}.freeze,
      'sessions.room.create' => {'site_id'=>:id, 'name'=>120, 'kind'=>10}.freeze,
      'commerce.payouts.open' => {'site_id'=>:id}.freeze,
      'identity.security.status' => {}.freeze,
      'nevaeh.action.status' => {'action_id'=>:id}.freeze,
      'sales.quote.status' => {'site_id'=>:id, 'quote_id'=>:id}.freeze,
      'reservations.availability.list' => {'site_id'=>:id, 'resource_id'=>:id, 'date'=>:date}.freeze,
      'connect.connections.list' => {}.freeze,
      'mail.mailbox.status' => {'mailbox_id'=>:id}.freeze,
      'studio.broadcast.channel.status' => {'site_id'=>:id, 'channel_id'=>:id}.freeze,
      'marketing.publication.schedule' => {'site_id'=>:id, 'campaign_id'=>:id, 'connection_id'=>:id,
                                           'scheduled_at'=>40, 'time_zone'=>100}.freeze
    }.freeze

    module_function

    def supported?(key)
      INPUTS.key?(key) || REVIEWS.key?(key) || key == 'site.page.create'
    end

    def command(key, payload)
      if (role = REVIEWS[key])
        return {'kind'=>'specialist_review', 'role'=>role, 'inputs'=>payload}
      end
      if key == 'site.page.create'
        return {'kind'=>'website_page', 'site_id'=>payload['site_id'], 'values'=>payload.except('site_id')}.compact
      end

      validate!(key, payload)
      {'kind'=>'platform_action', 'intent'=>key, 'payload'=>payload}
    end

    def validate!(key, values)
      fields = INPUTS.fetch(key) { raise ArgumentError, 'Unknown platform action' }
      raise ArgumentError, "Use exactly these inputs: #{fields.keys.join(', ')}" unless values.is_a?(Hash) && values.keys.sort == fields.keys.sort

      fields.each do |field, type|
        value = values.fetch(field)
        valid = case type
        when :id then (value.is_a?(Integer) || value.is_a?(String)) && /\A[1-9][0-9]{0,17}\z/.match?(value.to_s)
        when :version then (value.is_a?(Integer) || value.is_a?(String)) && /\A[0-9]{1,10}\z/.match?(value.to_s)
        when :date then value.is_a?(String) && /\A\d{4}-\d{2}-\d{2}\z/.match?(value)
        else value.is_a?(String) && value.strip.length.between?(1, type) && !value.match?(/[\x00-\x1f\x7f]/)
        end
        raise ArgumentError, "Invalid #{field} for #{key}" unless valid
      end
    end

    def authorize!(actor, command)
      key, values = command.values_at('intent', 'payload')
      validate!(key, values)
      case key
      when 'sales.lead.create', 'sales.quote.status', 'sales.quote.issue'
        raise ArgumentError, 'Sales access required' unless %w[super_admin admin white_label client employee].include?(actor.role)

        site = LightekSales::Access.sites_for(actor).find(values.fetch('site_id'))
        LightekSales::Workspace.new(actor: actor, site: site).revalidate!
        key == 'sales.lead.create' ? site : LightekSales::Quote.where(site: site).find(values.fetch('quote_id'))
      when 'sessions.room.create'
        LightekSettings::WebsiteIdentity.sites_for(actor).find(values.fetch('site_id'))
      when 'commerce.payouts.open'
        raise ArgumentError, 'Commerce access required' unless %w[super_admin admin white_label client].include?(actor.role)

        LightekSettings::WebsiteIdentity.sites_for(actor).where(tenant: actor).find(values.fetch('site_id'))
      when 'identity.security.status'
        actor
      when 'nevaeh.action.status'
        NevaehOsAction.where(user: actor).find(values.fetch('action_id'))
      when 'reservations.availability.list'
        site = LightekSettings::WebsiteIdentity.sites_for(actor).find(values.fetch('site_id'))
        LightekReservations::Resource.available.where(site: site).find(values.fetch('resource_id'))
      when 'connect.connections.list'
        raise ArgumentError, 'Agency access required' unless %w[white_label super_admin].include?(actor.role)

        LightekConnect::Connection.where(user: actor)
      when 'mail.mailbox.status'
        mailbox!(actor, values.fetch('mailbox_id'))
      when 'studio.broadcast.channel.status'
        site = Studio::Broadcasting::Access.sites(actor).find(values.fetch('site_id'))
        Studio::Broadcasting::Access.authorize!(actor, site)
        Studio::Broadcasting::Channel.where(site: site).find(values.fetch('channel_id'))
      when 'marketing.publication.schedule'
        site = LightekSales::Access.sites_for(actor).find(values.fetch('site_id'))
        publication_calendar!(actor, site)
      end
    end

    def publication_calendar!(actor, site)
      calendar = LightekMarketing::PublicationCalendar.new(actor: actor, site: site)
      calendar.authorize!
      calendar
    rescue LightekAgency::PackagePolicy::Denied => error
      raise ArgumentError, error.message
    end

    def mailbox!(actor, id)
      LightekMail::Access.accounts(actor).find(id)
    rescue LightekMail::Access::Denied => error
      raise ArgumentError, error.message
    end

    def perform!(actor:, command:, action_id:)
      key, values = command.values_at('intent', 'payload')
      target = authorize!(actor, command)
      case key
      when 'sales.lead.create'
        lead = LightekSales::Workspace.new(actor: actor, site: target).save!('lead', values.except('site_id'))
        {'lead_id'=>lead.id, 'lead_status'=>lead.status, 'text'=>"Created lead ##{lead.id}."}
      when 'sales.quote.status'
        {'quote_id'=>target.id, 'quote_status'=>target.status, 'lock_version'=>target.lock_version,
         'order_id'=>target.order_id, 'order_status'=>target.order&.status}
      when 'sales.quote.issue'
        quote = LightekSales::Quotes.new(actor: actor, site: target.site).issue!(id: target.id, version: values.fetch('lock_version'))
        {'quote_id'=>quote.id, 'quote_status'=>quote.status, 'text'=>"Quote ##{quote.id} issued. It is ready for customer review."}
      when 'sessions.room.create'
        room = create_room!(actor, target, values.except('site_id'))
        {'room_id'=>room.id, 'starts_at'=>room.starts_at.iso8601, 'ends_at'=>room.ends_at.iso8601,
         'links'=>[{'label'=>'Open room', 'url'=>"/sessions/#{room.key}"}]}
      when 'commerce.payouts.open'
        {'site_id'=>target.id, 'links'=>[{'label'=>'Open secure payout setup', 'url'=>"/dashboard/commerce/payouts?site_id=#{target.id}"}],
         'text'=>'Open payout setup to continue with your authenticated browser session.'}
      when 'identity.security.status'
        {'mfa_enabled'=>LightekIdentity::Mfa.enabled?(target), 'mfa_required'=>LightekIdentity::Mfa.required?(target),
         'links'=>[{'label'=>'Open sign-in security', 'url'=>'/identity/security'}]}
      when 'nevaeh.action.status'
        receipt = Receipts.for(target)
        {'action_id'=>target.id, 'execution_status'=>receipt.fetch(:status), 'action_kind'=>receipt.fetch(:kind),
         'links'=>[{'label'=>'Open action receipt', 'url'=>"/dashboard/nevaeh/actions/#{target.id}"}]}
      when 'reservations.availability.list'
        reservation_slots(target, values.fetch('date'))
      when 'connect.connections.list'
        SpecialistTasks.summary(target, %w[id label platform revoked_at])
      when 'mail.mailbox.status'
        {'mailbox_id'=>target.id, 'enabled'=>target.enabled?, 'sending_ready'=>target.sending_ready?}
      when 'studio.broadcast.channel.status'
        {'channel_id'=>target.id, 'configured_status'=>target.status, 'managed_playout'=>target.managed_playout?}
      when 'marketing.publication.schedule'
        slot = target.schedule!(campaign_id: values.fetch('campaign_id'), connection_id: values.fetch('connection_id'),
          scheduled_at: values.fetch('scheduled_at'), time_zone: values.fetch('time_zone'), request_key: "nevaeh-action-#{action_id}")
        {'slot_id'=>slot.id, 'publication_status'=>slot.status, 'scheduled_at'=>slot.scheduled_at.iso8601,
         'text'=>"Calendar slot ##{slot.id} is #{slot.status}. Check the calendar for provider confirmation."}
      end
    end

    def create_room!(actor, site, attributes)
      LightekSessions::RoomCreation.call(actor: actor, site: site, attributes: attributes)
    rescue LightekSessions::Access::Denied => error
      raise ArgumentError, error.message
    end

    def reservation_slots(resource, date)
      slots = LightekReservations::Availability.slots(resource: resource, date: date)
      {'resource_id'=>resource.id, 'time_zone'=>resource.timezone, 'slots'=>slots}
    rescue LightekReservations::Availability::Invalid => error
      raise ArgumentError, error.message
    end
  end
end
