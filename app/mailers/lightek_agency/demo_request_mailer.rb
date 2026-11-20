module LightekAgency
  class DemoRequestMailer < ApplicationMailer
    def agency_trial_confirmation(id)
      @request = TrialRequest.find_by(id: id)
      return unless @request&.pending_confirmation? && @request.available?

      @brand = 'Lightek Agency'
      @confirmation_url = confirm_agency_demo_url(@request.generate_token_for(:confirmation),
        host: @request.site.host, protocol: 'https', port: nil)
      mail(to: @request.email_address, subject: "Confirm your #{@brand} demo", template_name: 'confirmation')
    end

    def confirmation(id)
      @request = DemoRequest.find(id)
      setting = DemoSetting.find_by!(agency: @request.agency, public_enabled: true)
      @brand = @request.agency.agency_profile&.brand_name.presence || 'Lightek'
      @confirmation_url = confirm_demo_request_url(@request.generate_token_for(:confirmation), host: setting.public_site.host, protocol: 'https')
      mail(to: @request.email_address, subject: "Confirm your #{@brand} demo")
    end
  end
end
