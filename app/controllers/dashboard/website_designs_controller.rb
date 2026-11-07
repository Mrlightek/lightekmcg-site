# frozen_string_literal: true
class Dashboard::WebsiteDesignsController < Dashboard::SettingsHomeController
  before_action :set_design_site
  before_action :set_design, only: %i[preview apply import]
  helper DymondDash::TemplateSchemaHelper
  helper LightekDesign::StudioHelper

  def index
    @html_imports = @site ? LightekDesign::HtmlImport.records_for(user: current_user, site: @site) : []
  end

  def upload_html
    record = LightekDesign::HtmlImport.enqueue!(user: current_user, site: @site, html_file: params[:html_file], css_file: params[:css_file], name: params[:name], create_page: params[:create_page] == "1", product_selector: params[:product_selector])
    redirect_after_html_import(record)
  rescue ArgumentError => error
    redirect_to dashboard_website_designs_path(site_id: @site.id), alert: error.message
  end

  def convert_html
    record = LightekDesign::HtmlImport.records_for(user: current_user, site: @site).find(params.require(:import_id))
    LightekDesign::HtmlImportJob.perform_now(record.id)
    redirect_after_html_import(record.reload)
  end

  def preview
    @preview = true
    @design_key = params[:design]
    @page = Struct.new(:title).new("#{@design.fetch('name')} preview")
    response.set_header("Cache-Control", "private, no-store")
    render "lightek_design/preview", layout: "lightek_design/website"
  end

  def apply
    LightekDesign::WebsiteDesigns.apply!(site: @site, design: params[:design])
    redirect_to dashboard_website_designs_path(site_id: @site.id), notice: "Design applied. Your pages and publication settings are unchanged."
  end

  def import
    page = LightekDesign::WebsiteDesigns.import!(site: @site, design: params[:design])
    redirect_to dashboard_website_designs_path(site_id: @site.id),
      notice: "Starter page ‘#{page.title}’ is available in Pages. Existing edits and publication settings were preserved."
  end

  def update_fonts
    LightekDesign::WebsiteDesigns.save_fonts!(site: @site,
      values: params.require(:template).permit(*LightekDesign::WebsiteDesigns::FONT_KEYS).to_h)
    redirect_to dashboard_website_designs_path(site_id: @site.id), notice: "Website fonts saved."
  rescue ArgumentError => error
    flash.now[:alert] = error.message
    render :index, status: :unprocessable_entity
  end

  private

  def redirect_after_html_import(record)
    meta = record.settings.fetch("html_import")
    if meta["status"] == "complete"
      redirect_to dashboard_website_designs_path(site_id: @site.id), notice: "Design converted and saved to the design library.#{' Your draft page is ready in Pages & Sections.' if meta['page_id']}"
    else
      redirect_to dashboard_website_designs_path(site_id: @site.id), alert: meta["error"].presence || "Conversion did not complete. Use Convert now to retry the saved source."
    end
  end

  def set_design_site
    @sites = LightekSettings::WebsiteIdentity.sites_for(current_user).order(:name, :id)
    @site = if params[:site_id].present?
      @sites.find(params[:site_id])
    elsif @sites.count == 1
      @sites.first
    end
    raise ActiveRecord::RecordNotFound if action_name != "index" && !@site
    session[:dymond_dash_site_id] = @site.id if @site
  end

  def set_design
    @design = LightekDesign::Catalog.selectable_designs(user: current_user, active: LightekDesign::Catalog.design_for(@site)).fetch(params[:design].to_s) { raise ActiveRecord::RecordNotFound }
  end
end
