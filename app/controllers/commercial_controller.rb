# Public commercial surfaces for the Lightek MCG operating portfolio.
# Intentionally read-only: inquiries use the existing contact flow.
class CommercialController < ApplicationController
  skip_before_action :require_authentication
  skip_authorization_check

  def index; end
  def enterprise; end
  def media; end
end
