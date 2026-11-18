# frozen_string_literal: true

class NevaehReplyChannel < ApplicationCable::Channel
  def subscribed
    key=params[:request_key]
    return reject unless current_user && NevaehOs::ReplyStream.valid_key?(key)
    stream_from NevaehOs::ReplyStream.name(current_user.id,key)
  end
end
