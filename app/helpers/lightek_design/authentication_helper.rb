# frozen_string_literal: true
module LightekDesign
  module AuthenticationHelper
    def authentication_branding
      @authentication_branding ||= AuthenticationBranding.for_host(request.host)
    end
  end
end
