# frozen_string_literal: true
class Dashboard::SalesIntakeController < Dashboard::SalesController
  skip_before_action :set_kind
  before_action { @tab = 'intake'; @intake = LightekSales::Intake.new(actor: current_user, site: @site) }
  rescue_from ActiveRecord::RecordInvalid do |error|
    redirect_to dashboard_sales_intake_path(site_id: @site.id), alert: error.record.errors.full_messages.to_sentence
  end

  def index
    @status = params[:status].to_s.in?(%w[awaiting_review needs_review imported duplicate ignored]) ? params[:status] : 'awaiting_review'
    @entries = LightekSales::IntakeEntry.where(site: @site, status: @status).includes(:lead).order(created_at: :desc).limit(100)
    captured = LightekSales::IntakeEntry.where(site: @site).where.not(inquiry_id: nil).select(:inquiry_id)
    @inquiries = WebsiteTemplateInquiry.where(site: @site).where.not(id: captured).order(created_at: :desc).limit(50)
    return unless @manage_routing
    @rules = LightekSales::IntakeRule.where(site: @site).order(:template_key, :section_key)
    @forms = @site.pages.where(published: true).joins(:sections).pluck('dymond_site_sections.data').filter_map do |data|
      next unless data.is_a?(Hash) && data['template_key'].present? && data['section_key'].present?
      keys = data.values_at('template_key', 'section_key')
      begin
        source = LightekDesign::StarterLibrary.source(*keys)
        keys.join('::') if Nokogiri::HTML5.fragment(source).at_css('form')
      rescue KeyError
        nil
      end
    end.uniq.sort
    @rule = params[:rule_id].present? ? @rules.find(params[:rule_id]) : LightekSales::IntakeRule.new(site: @site)
    @form_key = params[:form_key].presence || (@rule.persisted? ? [@rule.template_key, @rule.section_key].join('::') : @forms.first)
    if @form_key && @forms.include?(@form_key)
      template, section = @form_key.split('::', 2)
      @rule.assign_attributes(template_key: template, section_key: section) unless @rule.persisted?
      @form_fields = LightekSales::IntakeRule.new(site: @site, template_key: template, section_key: section).form_fields
    else
      @form_fields = []
    end
  end

  def show
    @entry = LightekSales::IntakeEntry.where(site: @site).find(params[:id])
  end
  def upload
    file = params.require(:file)
    raise ArgumentError, 'Choose a CSV file smaller than 512 KB.' unless file.respond_to?(:read) && file.size <= 512_000
    entries = @intake.stage_csv!(file.read(512_001))
    redirect_to dashboard_sales_intake_path(site_id: @site.id), notice: "#{entries.size} rows staged or reused. Review them before accepting into Sales.", status: :see_other
  end
  def capture
    entry = @intake.capture!(params.require(:inquiry_id))
    redirect_to dashboard_sales_intake_entry_path(site_id: @site.id, id: entry.id), status: :see_other
  end
  def accept
    entry = @intake.process!(params[:id], lock_version: params.require(:entry)[:lock_version], values: params.require(:entry).permit(*LightekSales::IntakeRule::TARGETS))
    redirect_to dashboard_sales_intake_entry_path(site_id: @site.id, id: entry.id), notice: {'duplicate' => 'Linked to the existing lead. A new inquiry follow-up task was scheduled.', 'ignored' => 'This inquiry was already ignored; no lead was created.'}.fetch(entry.status, 'Lead accepted and a follow-up task scheduled.'), status: :see_other
  rescue ActiveRecord::RecordInvalid, ArgumentError => error
    redirect_to dashboard_sales_intake_entry_path(site_id: @site.id, id: params[:id]), alert: error.message
  end
  def ignore
    @intake.ignore!(params[:id], lock_version: params.require(:entry)[:lock_version])
    redirect_to dashboard_sales_intake_path(site_id: @site.id), notice: 'Inquiry ignored. Its original submission remains available.', status: :see_other
  end
  def configure
    attrs = params.require(:rule).permit(:source, :enabled, mapping: LightekSales::IntakeRule::TARGETS).to_h
    template, section = params.require(:form_key).to_s.split('::', 2)
    @intake.save_rule!(attrs.merge('template_key' => template, 'section_key' => section), id: params[:rule_id].presence, lock_version: params[:lock_version])
    redirect_to dashboard_sales_intake_path(site_id: @site.id), notice: 'Form intake updated. Automatic acceptance applies to new inquiries after enabling.', status: :see_other
  end
end
