module LightekAgency
  class DemoRequestMailer < ApplicationMailer
    def confirmation(id)
      @request = DemoRequest.find(id)
      setting = DemoSetting.find_by!(agency: @request.agency, public_enabled: true)
      @brand = @request.agency.agency_profile&.brand_name.presence || 'Lightek'
      @confirmation_url = confirm_demo_request_url(@request.generate_token_for(:confirmation), host: setting.public_site.host, protocol: 'https')
      mail(to: @request.email_address, subject: "Confirm your #{@brand} demo")
    end
  end
end
