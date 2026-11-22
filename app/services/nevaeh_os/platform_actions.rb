# frozen_string_literal: true

require_relative 'mail_actions'
require_relative 'hosting_actions'
require_relative 'room_actions'
require_relative 'agenda_actions'
require_relative 'executive_case_actions'
require_relative 'it_actions'

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
      'sales.lead.status' => {'site_id'=>:id, 'lead_id'=>:id}.freeze,
      'sales.lead.convert' => {'site_id'=>:id, 'lead_id'=>:id, 'lock_version'=>:version, 'name'=>160,
                               'amount'=>:amount, 'currency'=>3, 'close_on'=>:date}.freeze,
      'sales.quote.issue' => {'site_id'=>:id, 'quote_id'=>:id, 'lock_version'=>:version}.freeze,
      'sales.quote.draft' => {'site_id'=>:id, 'opportunity_id'=>:id, 'title'=>160, 'customer_email'=>254,
                             'expires_on'=>:date, 'quantities'=>:quote_quantities}.freeze,
      'sales.quote.accept' => {'site_id'=>:id, 'quote_id'=>:id, 'accepted_name'=>160, 'acceptance_reference'=>300,
                               'confirmed'=>:confirmation}.freeze,
      'sales.task.status' => {'site_id'=>:id, 'task_id'=>:id}.freeze,
      'sales.task.schedule' => {'site_id'=>:id, 'record_kind'=>:sales_relationship, 'record_id'=>:id,
                                'title'=>300, 'owner_id'=>:id, 'due_at'=>40}.freeze,
      'sales.task.complete' => {'site_id'=>:id, 'task_id'=>:id, 'lock_version'=>:version}.freeze,
      'sales.task.cancel' => {'site_id'=>:id, 'task_id'=>:id, 'lock_version'=>:version}.freeze,
      'sales.task.snooze' => {'site_id'=>:id, 'task_id'=>:id, 'lock_version'=>:version, 'due_at'=>40}.freeze,
      'accounting.workspace.open' => {'employer_id'=>:id}.freeze,
      'sessions.room.create' => {'site_id'=>:id, 'name'=>120, 'kind'=>10}.freeze,
      'commerce.payouts.open' => {'site_id'=>:id}.freeze,
      'commerce.order.status' => {'site_id'=>:id, 'order_id'=>:id}.freeze,
      'commerce.order.fulfill' => {'site_id'=>:id, 'order_id'=>:id, 'reference'=>300}.freeze,
      'commerce.order.provisioning.retry' => {'site_id'=>:id, 'order_id'=>:id}.freeze,
      'identity.security.status' => {}.freeze,
      'nevaeh.action.status' => {'action_id'=>:id}.freeze,
      'sales.quote.status' => {'site_id'=>:id, 'quote_id'=>:id}.freeze,
      'reservations.availability.list' => {'site_id'=>:id, 'resource_id'=>:id, 'date'=>:date}.freeze,
      'reservations.list' => {}.freeze,
      'reservations.status' => {'reservation_id'=>:id}.freeze,
      'reservations.cancel' => {'reservation_id'=>:id}.freeze,
      'reservations.reschedule' => {'reservation_id'=>:id, 'starts_at'=>40}.freeze,
      'connect.connections.list' => {}.freeze,
      'studio.broadcast.channel.status' => {'site_id'=>:id, 'channel_id'=>:id}.freeze,
      'website.design.list' => {}.freeze,
      'website.design.create' => {'name'=>120}.freeze,
      'website.design.status' => {'design_id'=>:id}.freeze,
      'website.design.publish' => {'design_id'=>:id, 'revision'=>:version}.freeze,
      'website.theme.activate' => {'site_id'=>:id, 'template_id'=>:id}.freeze,
      'marketing.publication.schedule' => {'site_id'=>:id, 'campaign_id'=>:id, 'connection_id'=>:id,
                                           'scheduled_at'=>40, 'time_zone'=>100}.freeze,
      'marketing.publication.status' => {'site_id'=>:id, 'slot_id'=>:id}.freeze,
      'marketing.publication.cancel' => {'site_id'=>:id, 'slot_id'=>:id, 'lock_version'=>:version}.freeze
    }.merge(MailActions::INPUTS, HostingActions::INPUTS, RoomActions::INPUTS, AgendaActions::INPUTS, ExecutiveCaseActions::INPUTS, ItActions::INPUTS).freeze

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
        when :amount then value.is_a?(String) && /\A\d{1,14}(?:\.\d{1,2})?\z/.match?(value)
        when :boolean then value == true || value == false
        when :mail_query then value.is_a?(String) && value.length <= 240 && !value.match?(/[\x00-\x1f\x7f]/)
        when :mail_body then value.is_a?(String) && value.strip.length.between?(1, 8000) && !value.match?(/[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/)
        when :confirmation then value == true
        when :ticket_number then value.is_a?(String) && /\ALT-[A-Z0-9-]{1,30}\z/.match?(value)
        when :quote_quantities
          value.is_a?(Hash) && value.size.between?(1, 50) && value.all? do |id, quantity|
            id.is_a?(String) && id.match?(/\A[1-9]\d{0,17}\z/) && quantity.is_a?(Integer) && quantity.between?(1, 100)
          end
        when :sales_relationship then %w[lead account contact opportunity prospect].include?(value)
        else value.is_a?(String) && value.strip.length.between?(1, type) && !value.match?(/[\x00-\x1f\x7f]/)
        end
        raise ArgumentError, "Invalid #{field} for #{key}" unless valid
      end
    end

    def authorize!(actor, command)
      key, values = command.values_at('intent', 'payload')
      validate!(key, values)
      return ItActions.authorize!(actor, key, values) if ItActions::INPUTS.key?(key)
      return MailActions.authorize!(actor, key, values) if MailActions::INPUTS.key?(key)
      return HostingActions.authorize!(actor, key, values) if HostingActions::INPUTS.key?(key)
      return ExecutiveCaseActions.authorize!(actor, values) if key == ExecutiveCaseActions::CREATE
      return AgendaActions.authorize!(actor, values) if key == AgendaActions::CREATE
      return RoomActions.authorize!(actor, values) if RoomActions::INPUTS.key?(key)

      case key
      when 'sales.lead.create', 'sales.lead.status', 'sales.lead.convert', 'sales.quote.status', 'sales.quote.draft', 'sales.quote.issue',
        'sales.quote.accept', 'sales.task.status', 'sales.task.schedule', 'sales.task.complete', 'sales.task.cancel', 'sales.task.snooze'
        raise ArgumentError, 'Sales access required' unless %w[super_admin admin white_label client employee].include?(actor.role)

        site = LightekSales::Access.sites_for(actor).find(values.fetch('site_id'))
        workspace = LightekSales::Workspace.new(actor: actor, site: site)
        workspace.revalidate!
        case key
        when 'sales.lead.create', 'sales.task.schedule' then site
        when 'sales.lead.status', 'sales.lead.convert' then workspace.find('lead', values.fetch('lead_id'))
        when 'sales.quote.draft' then workspace.find('opportunity', values.fetch('opportunity_id'))
        when /\Asales\.task\./ then LightekSales::Task.visible_in_sales(site).find(values.fetch('task_id'))
        else LightekSales::Quote.where(site: site).find(values.fetch('quote_id'))
        end
      when 'accounting.workspace.open'
        accounting_employer!(actor, values.fetch('employer_id'))
      when 'sessions.room.create'
        LightekSettings::WebsiteIdentity.sites_for(actor).find(values.fetch('site_id'))
      when 'commerce.payouts.open'
        raise ArgumentError, 'Commerce access required' unless %w[super_admin admin white_label client].include?(actor.role)

        LightekSettings::WebsiteIdentity.sites_for(actor).where(tenant: actor).find(values.fetch('site_id'))
      when 'commerce.order.status', 'commerce.order.fulfill', 'commerce.order.provisioning.retry'
        raise ArgumentError, 'Commerce access required' unless %w[super_admin admin white_label client].include?(actor.role)

        site = LightekSettings::WebsiteIdentity.sites_for(actor).find(values.fetch('site_id'))
        LightekCommerce::Order.visible.where(site: site).find(values.fetch('order_id'))
      when 'identity.security.status'
        actor
      when 'nevaeh.action.status'
        NevaehOsAction.where(user: actor).find(values.fetch('action_id'))
      when 'reservations.availability.list'
        site = LightekSettings::WebsiteIdentity.sites_for(actor).find(values.fetch('site_id'))
        LightekReservations::Resource.available.where(site: site).find(values.fetch('resource_id'))
      when 'reservations.list'
        LightekReservations::Reservation.where(customer: actor)
      when 'reservations.status', 'reservations.cancel', 'reservations.reschedule'
        LightekReservations::Reservation.where(customer: actor).find(values.fetch('reservation_id'))
      when 'connect.connections.list'
        raise ArgumentError, 'Agency access required' unless %w[white_label super_admin].include?(actor.role)

        LightekConnect::Connection.where(user: actor)
      when 'studio.broadcast.channel.status'
        site = Studio::Broadcasting::Access.sites(actor).find(values.fetch('site_id'))
        Studio::Broadcasting::Access.authorize!(actor, site)
        Studio::Broadcasting::Channel.where(site: site).find(values.fetch('channel_id'))
      when 'website.design.list', 'website.design.create', 'website.design.status', 'website.design.publish'
        unless %w[admin super_admin].include?(actor.role) || LightekSettings::WebsiteIdentity.sites_for(actor).exists?
          raise ArgumentError, 'Website design editor access required'
        end
        design_id = values['design_id']
        LightekDesign::StudioDocument.find_for!(design_id, actor) if design_id
      when 'website.theme.activate'
        LightekSettings::WebsiteIdentity.sites_for(actor).find(values.fetch('site_id'))
      when 'marketing.publication.schedule', 'marketing.publication.status', 'marketing.publication.cancel'
        site = LightekSales::Access.sites_for(actor).find(values.fetch('site_id'))
        return publication_calendar!(actor, site) if key == 'marketing.publication.schedule'

        if key == 'marketing.publication.cancel'
          publication_calendar!(actor, site)
        else
          LightekGrowth::Workspace.new(actor: actor, site: site).revalidate!
        end
        LightekMarketing::PublicationSlot.where(site: site).find(values.fetch('slot_id'))
      end
    end

    def accounting_employer!(actor, employer_id)
      employer = LightekPeople::Access.employers_for(actor).find(employer_id)
      LightekAccounting::Access.new(actor: actor, employer: employer).require!
      unless employer.can_access_feature?('commerce_workspace') || employer.can_access_feature?('bookkeeping_workspace')
        raise ArgumentError, 'This business needs an accounting workspace entitlement.'
      end

      employer
    rescue LightekAccounting::Access::Denied => error
      raise ArgumentError, error.message
    end

    def publication_calendar!(actor, site)
      calendar = LightekMarketing::PublicationCalendar.new(actor: actor, site: site)
      calendar.authorize!
      calendar
    rescue LightekAgency::PackagePolicy::Denied => error
      raise ArgumentError, error.message
    end

    def perform!(actor:, command:, action_id:)
      key, values = command.values_at('intent', 'payload')
      target = authorize!(actor, command)
      return ItActions.perform!(actor, key, target, values) if ItActions::INPUTS.key?(key)
      return MailActions.perform!(key, target, values, action_id: action_id) if MailActions::INPUTS.key?(key)
      return HostingActions.perform!(key, target, values, actor: actor) if HostingActions::INPUTS.key?(key)
      return ExecutiveCaseActions.perform!(target) if key == ExecutiveCaseActions::CREATE
      return AgendaActions.perform!(target) if key == AgendaActions::CREATE
      return RoomActions.perform!(actor, key, target, values) if RoomActions::INPUTS.key?(key)

      case key
      when 'sales.lead.create'
        lead = LightekSales::Workspace.new(actor: actor, site: target).save!('lead', values.except('site_id'))
        {'lead_id'=>lead.id, 'lead_status'=>lead.status, 'text'=>"Created lead ##{lead.id}."}
      when 'sales.lead.status'
        {'lead_id'=>target.id, 'lead_status'=>target.status, 'lock_version'=>target.lock_version, 'opportunity_id'=>target.opportunity_id}
      when 'sales.lead.convert'
        opportunity = LightekSales::Workspace.new(actor: actor, site: target.site).convert!(
          target.id, values.slice('name', 'amount', 'currency', 'close_on'), lock_version: values.fetch('lock_version'))
        {'lead_id'=>target.id, 'opportunity_id'=>opportunity.id, 'opportunity_stage'=>opportunity.stage}
      when 'sales.quote.status'
        quote_receipt(target)
      when 'sales.quote.draft'
        quote = LightekSales::Quotes.new(actor: actor, site: target.site).draft!(opportunity_id: target.id,
          values: values.slice('title', 'customer_email', 'expires_on'), quantities: values.fetch('quantities'))
        quote_receipt(quote)
      when 'sales.quote.issue'
        quote = LightekSales::Quotes.new(actor: actor, site: target.site).issue!(id: target.id, version: values.fetch('lock_version'))
        {'quote_id'=>quote.id, 'quote_status'=>quote.status, 'text'=>"Quote ##{quote.id} issued. It is ready for customer review."}
      when 'sales.quote.accept'
        quote = LightekSales::Quotes.accept!(quote: target, name: values.fetch('accepted_name'),
          reference: values.fetch('acceptance_reference'), actor: actor)
        {'quote_id'=>quote.id, 'quote_status'=>quote.status, 'order_id'=>quote.order_id, 'order_status'=>quote.order.status}
      when 'sales.task.status'
        sales_task_receipt(target)
      when 'sales.task.schedule'
        task = LightekSales::Tasks.new(actor: actor, site: target).create!(kind: values.fetch('record_kind'),
          id: values.fetch('record_id'), values: values.slice('title', 'owner_id', 'due_at'),
          source_key: "nevaeh-action:#{action_id}")
        sales_task_receipt(task)
      when 'sales.task.complete', 'sales.task.cancel', 'sales.task.snooze'
        task = LightekSales::Tasks.new(actor: actor, site: target.site).update!(target.id, action: key.delete_prefix('sales.task.'),
          lock_version: values.fetch('lock_version'), due_at: values['due_at'])
        sales_task_receipt(task)
      when 'accounting.workspace.open'
        {'employer_id'=>target.id, 'text'=>'Open Books & Accounting in your verified browser session.',
         'links'=>[{'label'=>'Open Books & Accounting', 'url'=>"/dashboard/accounting?employer_id=#{target.id}"}]}
      when 'sessions.room.create'
        room = create_room!(actor, target, values.except('site_id'))
        {'room_id'=>room.id, 'starts_at'=>room.starts_at.iso8601, 'ends_at'=>room.ends_at.iso8601,
         'links'=>[{'label'=>'Open room', 'url'=>"/sessions/#{room.key}"}]}
      when 'commerce.payouts.open'
        {'site_id'=>target.id, 'links'=>[{'label'=>'Open secure payout setup', 'url'=>"/dashboard/commerce/payouts?site_id=#{target.id}"}],
         'text'=>'Open payout setup to continue with your authenticated browser session.'}
      when 'commerce.order.status'
        commerce_receipt(target)
      when 'commerce.order.fulfill'
        order = LightekCommerce::Fulfillment.complete!(order: target, reference: values.fetch('reference'))
        commerce_receipt(order.reload)
      when 'commerce.order.provisioning.retry'
        job = LightekCommerce::PaidInstanceProvisioningJob.enqueue_recovery!(target)
        commerce_receipt(target).merge('recovery_job_id'=>job.job_id, 'recovery_status'=>'queued',
          'text'=>'Installation recovery was queued. Check the order for installation status.')
      when 'identity.security.status'
        {'mfa_enabled'=>LightekIdentity::Mfa.enabled?(target), 'mfa_required'=>LightekIdentity::Mfa.required?(target),
         'links'=>[{'label'=>'Open sign-in security', 'url'=>'/identity/security'}]}
      when 'nevaeh.action.status'
        receipt = Receipts.for(target)
        {'action_id'=>target.id, 'execution_status'=>receipt.fetch(:status), 'action_kind'=>receipt.fetch(:kind),
         'links'=>[{'label'=>'Open action receipt', 'url'=>"/dashboard/nevaeh/actions/#{target.id}"}]}
      when 'reservations.availability.list'
        reservation_slots(target, values.fetch('date'))
      when 'reservations.list'
        reservations = target.includes(:order).order(starts_at: :desc, id: :desc).limit(100)
        {'reservations'=>reservations.map { |reservation| reservation_receipt(reservation) }}
      when 'reservations.status'
        reservation_receipt(target)
      when 'reservations.cancel'
        reservation = LightekReservations::Booking.cancel!(reservation: target, actor: actor)
        reservation_receipt(reservation)
      when 'reservations.reschedule'
        reservation = LightekReservations::Booking.reschedule!(reservation: target, actor: actor, starts_at: values.fetch('starts_at'))
        reservation_receipt(reservation)
      when 'connect.connections.list'
        SpecialistTasks.summary(target, %w[id label platform revoked_at])
      when 'studio.broadcast.channel.status'
        {'channel_id'=>target.id, 'configured_status'=>target.status, 'managed_playout'=>target.managed_playout?}
      when 'website.design.list'
        {'designs'=>LightekDesign::StudioDocument.documents_for(actor).map { |design| design_receipt(design) }}
      when 'website.design.create'
        design = LightekDesign::StudioDocument.create!(user: actor, name: values.fetch('name'))
        design_receipt(design)
      when 'website.design.status'
        design_receipt(target)
      when 'website.design.publish'
        studio = LightekDesign::StudioDocument
        release = studio.publish!(record: target, document: studio.draft(target), expected_revision: values.fetch('revision'))
        design_receipt(target).merge('release_key'=>release.key, 'release_version'=>release.settings.dig('lightek_studio_release', 'version'))
      when 'website.theme.activate'
        site = LightekDesign::SiteTheme.activate!(site: target, user: actor, template_id: values.fetch('template_id'))
        {'site_id'=>site.id, 'active_template_id'=>site.active_template_id,
         'links'=>[{'label'=>'Open website designs','url'=>"/dashboard/website/designs?site_id=#{site.id}"}]}
      when 'marketing.publication.schedule'
        slot = target.schedule!(campaign_id: values.fetch('campaign_id'), connection_id: values.fetch('connection_id'),
          scheduled_at: values.fetch('scheduled_at'), time_zone: values.fetch('time_zone'), request_key: "nevaeh-action-#{action_id}")
        {'slot_id'=>slot.id, 'publication_status'=>slot.status, 'scheduled_at'=>slot.scheduled_at.iso8601,
         'text'=>"Calendar slot ##{slot.id} is #{slot.status}. Check the calendar for provider confirmation."}
      when 'marketing.publication.status'
        publication_receipt(target)
      when 'marketing.publication.cancel'
        slot = publication_calendar!(actor, target.site).cancel!(id: target.id, version: values.fetch('lock_version'))
        publication_receipt(slot).merge('text'=>'The local calendar slot is canceled.')
      end
    end

    def design_receipt(design)
      studio = LightekDesign::StudioDocument
      metadata = studio.metadata(design)
      latest = metadata.fetch('releases', []).last
      {'design_id'=>design.id, 'name'=>metadata.dig('draft', 'name'), 'revision'=>studio.revision(design),
       'release_version'=>latest&.fetch('version'),
       'links'=>[{'label'=>'Open Design Studio','url'=>"/dashboard/design-studio/#{design.id}/edit"}]}
    end

    def quote_receipt(quote)
      {'quote_id'=>quote.id, 'quote_status'=>quote.status, 'lock_version'=>quote.lock_version,
       'order_id'=>quote.order_id, 'order_status'=>quote.order&.status,
       'links'=>[{'label'=>'Open quote','url'=>"/dashboard/sales/quotes/#{quote.id}?site_id=#{quote.site_id}"}]}
    end

    def sales_task_receipt(task)
      {'task_id'=>task.id, 'task_status'=>task.status, 'due_at'=>task.due_at.iso8601, 'lock_version'=>task.lock_version,
       'links'=>[{'label'=>'Open sales tasks','url'=>"/dashboard/sales?site_id=#{task.site_id}&tab=tasks"}]}
    end

    def reservation_receipt(reservation)
      {'reservation_id'=>reservation.id, 'reservation_status'=>reservation.status,
       'experience'=>reservation.package_snapshot['name'], 'starts_at'=>reservation.starts_at.iso8601,
       'ends_at'=>reservation.ends_at.iso8601, 'order_status'=>reservation.order&.status,
       'links'=>[{'label'=>'Open reservation','url'=>"/my/reservations/#{reservation.id}"}]}
    end

    def commerce_receipt(order)
      {'order_id'=>order.id, 'order_status'=>order.status, 'paid_at'=>order.paid_at&.iso8601,
       'fulfilled_at'=>order.fulfilled_at&.iso8601, 'provisioned_at'=>order.provisioned_at&.iso8601,
       'provisioning_status'=>order.provisioning_state,
       'links'=>[{'label'=>'Open commerce orders','url'=>"/dashboard/commerce/orders?site_id=#{order.site_id}"}]}
    end

    def publication_receipt(slot)
      {'slot_id'=>slot.id, 'publication_status'=>slot.status, 'scheduled_at'=>slot.scheduled_at.iso8601,
       'lock_version'=>slot.lock_version, 'provider_status'=>slot.social_post&.status}
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
