# app/controllers/api_controller.rb
module Api
  class ApiController < ApplicationController
  include ActionController::HttpAuthentication::Token::ControllerMethods

  # Require API authentication for every action inheriting from this class
  before_action :authenticate_api_user!

  private

  def authenticate_api_user!
    authenticate_or_request_with_http_token do |token, options|
      # Find the user by token. ActiveSupport::SecurityUtils avoids timing attacks.
      @current_user = User.find_by(api_token: token)
    end
  end

  # Optional helper to access the logged-in API user
  def current_user
    @current_user
  end
end
end
