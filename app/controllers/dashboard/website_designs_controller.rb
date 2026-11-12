# frozen_string_literal: true
class Dashboard::WebsiteDesignsController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  before_action :set_design_site, except: %i[manifest starter_preview]
  before_action :set_design, only: %i[preview apply import start]
  helper DymondDash::TemplateSchemaHelper
  helper LightekDesign::StudioHelper

  def index
    @site_themes = @site ? DymondSite::SiteTemplate.where(id: @site.manifest.to_h.fetch("lightek_site_themes", {}).values).order(updated_at: :desc) : []
    @html_imports = @site ? LightekDesign::HtmlImport.records_for(user: current_user, site: @site) : []
    @template_inquiries = @site ? WebsiteTemplateInquiry.where(site: @site).order(created_at: :desc).limit(50) : []
  end

  def install_theme
    template=if params[:home_design].present?
      LightekDesign::SiteTheme.from_designs!(site:@site,user:current_user,name:params[:name],home_design:params[:home_design],page_designs:params[:page_designs],include_store:params[:include_store]=="1",include_blog:params[:include_blog]=="1",request_key:params[:request_key])
    else
      LightekDesign::SiteTheme.install!(site:@site,user:current_user,name:params[:name],files:params[:theme_files],css_file:params[:css_file],home_file:params[:home_file],product_selector:params[:product_selector],request_key:params[:request_key])
    end
    redirect_to dashboard_website_designs_path(site_id:@site.id),status: :see_other,notice:"#{template.name} prepared. New pages are drafts; existing pages keep their edits. Review Pages & Sections, publish the pages you want, then activate the shared theme."
  rescue ArgumentError, ActiveRecord::RecordInvalid => error
    redirect_to dashboard_website_designs_path(site_id:@site.id),status: :see_other,alert:error.message
  end
  def activate_theme
    LightekDesign::SiteTheme.activate!(site:@site,user:current_user,template_id:params.require(:template_id))
    redirect_to dashboard_website_designs_path(site_id:@site.id),status: :see_other,notice:"Website theme activated. Existing navigation and pages were retained; draft pages remain private."
  end

  def manifest
    key = params.require(:template_key).to_s
    payload = LightekDesign::StarterLibrary.fetch(key)
    response.set_header("Cache-Control", "private, no-store")
    send_data JSON.pretty_generate(payload), filename: "#{key}.json", type: "application/json", disposition: "attachment"
  rescue KeyError
    raise ActiveRecord::RecordNotFound
  end

  def starter_preview
    key = params.require(:template_key).to_s
    LightekDesign::StarterLibrary.fetch(key)
    @design_key = "starter_#{key.tr('-', '_')}"
    @design = LightekDesign::StarterLibrary.designs.fetch(@design_key)
    @preview = true
    @site = Struct.new(:name, :id).new(@design.fetch("name"), nil)
    @page = Struct.new(:title).new("#{@design.fetch('name')} preview")
    response.set_header("Cache-Control", "private, no-store")
    render "lightek_design/preview", layout: "lightek_design/website"
  rescue KeyError
    raise ActiveRecord::RecordNotFound
  end

  def update_branding
    LightekDesign::TemplateBranding.save!(site: @site, actor: current_user,
      values: params.require(:branding).permit(:white_label_enabled, :credit, :show_credit).to_h)
    redirect_to dashboard_website_designs_path(site_id: @site.id), notice: "Template credit saved."
  rescue ArgumentError => error
    redirect_to dashboard_website_designs_path(site_id: @site.id), alert: error.message
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

  def start
    page = @site.with_lock do
      LightekDesign::WebsiteDesigns.apply!(site: @site, design: params[:design])
      LightekDesign::WebsiteDesigns.import!(site: @site, design: params[:design])
    end
    redirect_to dymond_dash.pages_path(site_id: @site.id),
      notice: "#{page.title} is ready as a draft. Appearance applied; review the placeholder content before publishing."
  end

  def update_fonts
    LightekDesign::WebsiteDesigns.save_fonts!(site: @site,
      values: params.require(:template).permit(*LightekDesign::WebsiteDesigns::FONT_KEYS).to_h)
    redirect_to dashboard_website_designs_path(site_id: @site.id), notice: "Website fonts saved."
  rescue ArgumentError => error
    flash.now[:alert] = error.message
    index
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
    elsif session[:dymond_dash_site_id].present?
      @sites.find_by(id:session[:dymond_dash_site_id]) || (@sites.first if @sites.count==1)
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
