# frozen_string_literal: true

class SalesInquiriesController < ApplicationController
  allow_unauthenticated_access
  skip_authorization_check
  layout 'auth'
  protect_from_forgery with: :exception
  before_action :set_form_site
  rate_limit to: 10, within: 10.minutes, only: :create

  def new
    @inquiry = WebsiteTemplateInquiry.new(fields: {})
  end

  def create
    return received if params[:website_url].present?

    fields = params.permit(sales_submission: WebsiteTemplateInquiry::SALES_FIELD_LIMITS.keys)
      .fetch(:sales_submission, {}).to_h.transform_values { |value| value.to_s.strip }
    template, section = WebsiteTemplateInquiry::SALES_FORM_KEYS
    @inquiry = WebsiteTemplateInquiry.new(site: @site, template_key: template, section_key: section, fields: fields)
    @inquiry.growth_visit = LightekGrowth::Tracking.from_request(site: @site, cookies: cookies, request: request)
    return received if @inquiry.save

    render :new, status: :unprocessable_entity
  end

  private

  def set_form_site
    response.set_header('Cache-Control', 'private, no-store')
    response.set_header('Referrer-Policy', 'same-origin')
    response.set_header('X-Robots-Tag', 'noindex')
    @site = DymondSite::Site.find_by!(host: request.host.downcase)
    raise ActiveRecord::RecordNotFound unless WebsiteTemplateInquiry.sales_form_available?(@site)
  end

  def received
    flash[:sales_inquiry_received] = true
    redirect_to sales_inquiry_path, status: :see_other
  end
end
