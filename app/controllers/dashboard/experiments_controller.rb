# frozen_string_literal: true

class Dashboard::ExperimentsController < Dashboard::SettingsHomeController
  protect_from_forgery with: :exception
  skip_before_action :require_settings_operator!
  before_action :load_workspace
  rescue_from LightekAgency::PackagePolicy::Denied do |error|
    render plain: error.message, status: :forbidden
  end
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique, with: :validation_error

  def index
    @experiments = @workspace.experiments.order(id: :desc).limit(30)
    @selected = params[:experiment_id].present? ? @workspace.experiments.find(params[:experiment_id]) : @experiments.first
    @report = @workspace.report(@selected.id) if @selected
    @walkthroughs = LightekGrowth::FeatureShowcase.where(site: @site, demo_experiment_started_at: nil)
      .where.not(approved_at: nil).includes(:page).filter_map do |showcase|
        [showcase.page.title, showcase.id] if showcase.page.published? && showcase.snapshot['demo_promotion_link_id']
      end
    @heroes = DymondSite::Section.where(page_id: @site.pages.where(published: true).select(:id)).includes(:page).order(:page_id, :position, :id).filter_map do |section|
      definition = LightekDesign::Catalog.section_definition(section.kind)
      ["#{section.page.title} · #{section.data['heading'].presence || section.data['cta_label']}", section.id] if definition&.fetch('block', nil) == 'hero'
    end
  end

  def create
    values = params.require(:experiment).permit(:name, :surface, :target, :showcase_target, :control, :challenger).to_h
    values['target'] = values.delete('showcase_target') if values['surface'] == 'demo_walkthrough'
    row = @workspace.start!(values)
    redirect_to dashboard_experiments_path(site_id: @site.id, experiment_id: row.id), notice: 'Experiment started.', status: :see_other
  end

  def finish
    row = @workspace.finish!(params[:id], winner: params[:winner])
    redirect_to dashboard_experiments_path(site_id: @site.id, experiment_id: row.id), notice: 'Experiment closed.', status: :see_other
  end

  private

  def load_workspace
    @site = LightekSales::Access.sites_for(current_user).find(params.require(:site_id))
    @workspace = LightekExperiments::Workspace.new(actor: current_user, site: @site)
  end

  def validation_error(error)
    redirect_to dashboard_experiments_path(site_id: @site.id), alert: error.message, status: :see_other
  end
end
