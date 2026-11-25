class Dashboard::FeatureFlagsController < ApplicationController
  include LightekIdentity::SensitiveSession

  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action :require_operator!
  before_action :require_sensitive_session!, except: :index
  before_action :load_flag, except: :index
  rescue_from LightekFeatureFlags::Flag::Unavailable, ActiveRecord::RecordInvalid, with: :invalid

  def index
    @flags = LightekFeatureFlags::Flag.all.index_by(&:key)
    @recent_changes = LightekFeatureFlags::Change.includes(:actor, :flag).order(id: :desc).limit(30)
  end

  def update
    fields = params.require(:feature_flag).permit(:enabled, :staff, :percentage, :account_ids, :agency_ids, :installation_ids, :lock_version)
    version = Integer(fields[:lock_version].to_s, 10, exception: false)
    raise LightekFeatureFlags::Flag::Unavailable, "Reload the flag before saving." unless version

    attributes = {
      enabled: fields[:enabled] == "1", staff: fields[:staff] == "1", percentage: fields[:percentage],
      account_ids: targets!(fields[:account_ids], User.all, "account"),
      agency_ids: targets!(fields[:agency_ids], User.where(role: "white_label"), "agency"),
      installation_ids: targets!(fields[:installation_ids], GatekeeperInstallation.all, "installation")
    }
    @flag.revise!(actor: current_user, attributes: attributes, expected_version: version)
    redirect_to dashboard_feature_flags_path, notice: "Feature rollout saved.", status: :see_other
  end

  def pause
    @flag.revise!(actor: current_user, attributes: {enabled: false})
    redirect_to dashboard_feature_flags_path, notice: "Feature rollout paused.", status: :see_other
  end

  private

  def require_operator!
    response.headers["Cache-Control"] = "private, no-store"
    head :forbidden unless Gatekeeper::Hosting::Access.super_admin?(current_user) && Current.session&.connect_delegation.blank?
  end

  def load_flag
    key = params.require(:id)
    raise ActiveRecord::RecordNotFound unless LightekFeatureFlags::Flag::REGISTRY.key?(key)

    @flag = LightekFeatureFlags::Flag.create_or_find_by!(key: key)
  end

  def targets!(value, scope, label)
    tokens = value.to_s.split(/[,\s]+/).reject(&:empty?).uniq
    if tokens.size > 250 || tokens.any? { |id| !id.match?(/\A[1-9]\d{0,18}\z/) || id.to_i > (2**63 - 1) }
      raise LightekFeatureFlags::Flag::Unavailable, "Enter up to 250 valid #{label} IDs."
    end

    ids = tokens.map(&:to_i).sort
    unless scope.where(id: ids).count == ids.size
      raise LightekFeatureFlags::Flag::Unavailable, "One or more #{label} IDs could not be found."
    end
    ids
  end

  def invalid(error)
    redirect_to dashboard_feature_flags_path, alert: error.message, status: :see_other
  end
end
