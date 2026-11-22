# frozen_string_literal: true

class Api::ExecutivePhoneController < ActionController::Base
  skip_forgery_protection
  rescue_from NevaehOs::PhoneIntake::Denied, with: -> { head :unauthorized }
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, with: -> { head :unprocessable_entity }

  def create
    response.headers['Cache-Control'] = 'private, no-store'
    return head :upgrade_required if Rails.env.production? && !request.ssl?
    return head :payload_too_large if request.content_length.to_i > NevaehOs::PhoneIntake::MAX_BYTES

    item = NevaehOs::PhoneIntake.receive!(key: request.path_parameters.fetch(:key), timestamp: request.headers['X-Lightek-Timestamp'],
      signature: request.headers['X-Lightek-Signature'], body: request.raw_post)
    render json: {work_item_id: item.id}, status: :accepted
  end
end
