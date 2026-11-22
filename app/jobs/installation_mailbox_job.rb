# frozen_string_literal: true

class InstallationMailboxJob < ApplicationJob
  retry_on LightekReservations::Federation::Client::Unavailable, wait: :polynomially_longer, attempts: 8
  discard_on LightekPeople::Access::Denied, ActiveRecord::RecordNotFound

  def perform(user_id)
    user = User.find(user_id)
    return if user.password_setup_required?

    installation = LightekTeam::Installation.new(user)
    installation.request('installation/mail/provision') if installation.owner?
  end
end
