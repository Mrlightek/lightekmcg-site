class Dashboard::VaultController < DymondDash::ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  before_action :require_super_admin!

  def index
    @secrets = LightekVault::Secret.order(updated_at: :desc)
    @audit_events = LightekVault::AuditEvent.includes(:secret).order(created_at: :desc).limit(30)
    @active_count = LightekVault::Secret.active.count
    @expiring_count = LightekVault::Secret.expiring_soon.count
  end

  def create
    attrs = params.require(:vault_secret)

    LightekVault::Service.store!(
      name: attrs.fetch(:name),
      slug: attrs.fetch(:slug),
      payload: build_payload(attrs),
      secret_type: attrs.fetch(:secret_type, "credential"),
      provider: attrs[:provider],
      environment: attrs.fetch(:environment, "production"),
      purpose: attrs[:purpose],
      access_policy: {
        "consumers" => split_csv(attrs[:allowed_consumers]),
        "purposes" => split_csv(attrs[:allowed_purposes])
      },
      requested_by: current_user.email_address
    )

    redirect_to dashboard_vault_path,
                notice: "Secret stored in Lightek Vault."
  rescue StandardError => e
    redirect_to dashboard_vault_path, alert: e.message
  end

  def disable
    LightekVault::Service.disable!(slug: params.require(:slug), requested_by: current_user.email_address)
    redirect_to dashboard_vault_path, notice: "Secret disabled."
  rescue StandardError => e
    redirect_to dashboard_vault_path, alert: e.message
  end

  private

  def require_super_admin!
    return if current_user&.role == "super_admin"
    redirect_to dymond_dash.dashboard_path, alert: "Super administrator access is required."
  end

  def build_payload(attrs)
    keys = Array(attrs[:payload_keys])
    values = Array(attrs[:payload_values])

    structured = keys.zip(values).each_with_object({}) do |(key, value), payload|
      key = key.to_s.strip
      next if key.blank?

      raise ArgumentError, "Duplicate payload field: #{key}" if payload.key?(key)

      payload[key] = value.to_s
    end

    return structured if structured.any?

    value = attrs[:payload].to_s
    raise ArgumentError, "Secret payload cannot be blank" if value.blank?

    { "value" => value }
  end

  def split_csv(value)
    value.to_s.split(",").map(&:strip).reject(&:blank?)
  end
end
