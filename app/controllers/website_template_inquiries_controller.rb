class WebsiteTemplateInquiriesController < ApplicationController
  allow_unauthenticated_access only: :create
  # Public JSON submissions still require the page's CSRF token.
  protect_from_forgery with: :exception
  rate_limit to: 10, within: 10.minutes, only: :create

  def create
    site = DymondSite::Site.find_by!(host: request.host.downcase)
    key, section = params.values_at(:template_key, :section_key).map(&:to_s)
    # A known template on an unrelated host is not a public form endpoint.
    published = site.pages.where(published: true).joins(:sections).where("dymond_site_sections.data ->> 'template_key' = ? AND dymond_site_sections.data ->> 'section_key' = ?", key, section).exists?
    raise ActiveRecord::RecordNotFound unless published
    source = LightekDesign::StarterLibrary.source(key, section)
    names = Nokogiri::HTML5.fragment(source).css("form [name]").map { |node| node["name"] }.uniq
    fields = params.permit(*names).to_h.transform_values(&:to_s)
    record = WebsiteTemplateInquiry.new(site: site, template_key: key, section_key: section, fields: fields)
    if record.save
      render json: {message: "Your request was received. The team will contact you to confirm details.", reference: record.id}, status: :created
    else
      render json: {error: record.errors.full_messages.join(". ")}, status: :unprocessable_entity
    end
  rescue KeyError
    head :not_found
  end
end
