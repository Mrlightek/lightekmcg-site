# frozen_string_literal: true

class BroadcastSponsorPackagesController < ApplicationController
  allow_unauthenticated_access

  def show
    response.set_header("Cache-Control", "private, no-store")
    response.set_header("Referrer-Policy", "no-referrer")
    response.set_header("X-Robots-Tag", "noindex")
    @package = Studio::Advertising::SponsorPackage.find_by!(public_key: params[:key])
    @payments = @package.report_payments.to_a
  end
end
