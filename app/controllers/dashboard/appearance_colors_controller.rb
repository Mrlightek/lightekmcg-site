# frozen_string_literal: true
class Dashboard::AppearanceColorsController < ApplicationController
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action { head :forbidden unless current_user&.role == "super_admin" }

  def show
    @colors = LightekDashboard::AppearancePalette.values(DymondDash::AppConfig.current&.theme)
  end

  def update
    colors = LightekDashboard::AppearancePalette.validate!(params.require(:colors).permit(*LightekDashboard::AppearancePalette::COLORS.keys).to_h)
    DymondDash::AppConfig.transaction do
      config = DymondDash::AppConfig.current || DymondDash::AppConfig.new
      config.lock! if config.persisted?
      original = config.theme
      # Preserve built-in presets and website/PWA themes. Save an admin-only copy.
      theme = DymondTheme::Theme.create!(name: "Dashboard colors #{Time.current.strftime('%Y-%m-%d %H:%M:%S')}", scope: "admin", preset: false, tokens: original&.tokens.to_h.merge(colors), custom_css: original&.custom_css, templates: original&.templates || {})
      config.update!(theme: theme)
    end
    redirect_to dashboard_appearance_colors_path, notice: "Dashboard colors saved."
  rescue ArgumentError => error
    @colors = LightekDashboard::AppearancePalette.values(DymondDash::AppConfig.current&.theme)
    flash.now[:alert] = error.message
    render :show, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => error
    @colors = LightekDashboard::AppearancePalette.values(DymondDash::AppConfig.current&.theme)
    flash.now[:alert] = error.record.errors.full_messages.to_sentence
    render :show, status: :unprocessable_entity
  end
end
