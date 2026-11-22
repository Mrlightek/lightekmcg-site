# frozen_string_literal: true

require 'digest'

module LightekExperiments
  class Experience
    WINDOW = 30.days
    VISITOR_TOKEN = /\A[0-9a-f]{48}\z/
    RECORDS = {
      'inquiry' => 'WebsiteTemplateInquiry',
      'demo_request' => 'LightekAgency::DemoRequest',
      'checkout' => 'LightekCommerce::Order',
      'reservation' => 'LightekReservations::Reservation',
      'member_signup' => 'LightekPwa::MemberSignupRequest'
    }.freeze

    def initialize(site:, request:, response:, cookies:)
      @site, @request, @response, @cookies = site, request, response, cookies
    end

    def copy(surface:, target: '', default:)
      return default unless eligible_site?

      experiment = Experiment.where(site: @site, surface: surface, target: target.to_s).order(id: :desc).first
      return default unless experiment
      return experiment.winner ? experiment.copy_for(experiment.winner) : default if experiment.finished_at

      @response.set_header('Cache-Control', 'private, no-store')
      return default if opted_out? || @request.head? || prefetch?

      existing_token = visitor_token
      token = existing_token || SecureRandom.hex(24)
      digest = Digest::SHA256.hexdigest(token)
      assignments = experiment.assignments
      assignment = assignments.find_by(visitor_digest: digest) || assignments.create_or_find_by!(visitor_digest: digest) do |row|
        row.arm = Digest::SHA256.hexdigest("#{experiment.id}:#{token}").last.to_i(16).even? ? 'control' : 'challenger'
      end
      unless existing_token
        @cookies.signed[cookie_key] = { value: token, expires: WINDOW.from_now, httponly: true, same_site: :lax, secure: @request.ssl? }
      end
      experiment.copy_for(assignment.arm)
    rescue LightekAgency::PackagePolicy::Denied
      default
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.warn("A/B test exposure unavailable: #{error.class}")
      default
    end

    def record(event, record)
      return unless eligible_site? && !opted_out? && (token = visitor_token)
      return unless record.persisted? && record.class.name == RECORDS[event] && belongs_to_site?(event, record)

      assignments = Assignment.joins(:experiment).includes(:experiment)
        .where(lightek_experiments: { site_id: @site.id }, visitor_digest: Digest::SHA256.hexdigest(token))
        .where(created_at: WINDOW.ago..Time.current).order(id: :desc)
      assignments.uniq { |row| [row.experiment.surface, row.experiment.target] }.each do |assignment|
        next unless record.created_at >= assignment.created_at && Surfaces::RULES.fetch(assignment.experiment.surface)[1].include?(event)

        assignment.outcomes.create_or_find_by!(event: event, record_id: record.id)
      end
    rescue LightekAgency::PackagePolicy::Denied
      nil
    rescue ActiveRecord::ActiveRecordError => error
      Rails.logger.warn("A/B test conversion unavailable: #{error.class}")
      nil
    end

    private

    def eligible_site?
      return false unless @site && @request && @site.host.to_s.casecmp?(@request.host.to_s)

      LightekAgency::PackagePolicy.authorize!(@site.tenant, 'marketing')
      true
    end

    def opted_out?
      @request.headers['DNT'] == '1' || @request.headers['Sec-GPC'] == '1'
    end

    def prefetch?
      [@request.headers['Purpose'], @request.headers['Sec-Purpose']].any? { |value| value.to_s.include?('prefetch') }
    end

    def visitor_token
      token = @cookies.signed[cookie_key].to_s
      token if VISITOR_TOKEN.match?(token)
    end

    def cookie_key = "lightek_experiment_#{@site.id}"

    def belongs_to_site?(event, record)
      case event
      when 'demo_request'
        LightekAgency::DemoSetting.exists?(agency_id: record.agency_id, public_site_id: @site.id, public_enabled: true)
      when 'reservation'
        record.resource.site_id == @site.id
      else
        record.site_id == @site.id
      end
    end
  end
end
