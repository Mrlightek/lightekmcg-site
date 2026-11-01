# frozen_string_literal: true
module Gatekeeper
  class CentralEscalationsController < ApplicationController
    allow_unauthenticated_access only: :create
    skip_forgery_protection only: :create

    def create
      return head :payload_too_large if request.content_length.to_i > 64000
      body = request.raw_post
      installation = NevaehIntelligences::CentralReporting.authenticate!(installation_id: request.headers["X-Lightek-Installation"],
        timestamp: request.headers["X-Lightek-Timestamp"], supplied: request.headers["X-Lightek-Signature"], body: body)
      ticket = NevaehIntelligences::CentralReporting.receive!(installation: installation, payload: JSON.parse(body))
      render json: {ticket_id: ticket.id, ticket_number: ticket.number}, status: :ok
    rescue NevaehIntelligences::CentralReporting::Invalid, ActiveRecord::RecordNotFound, JSON::ParserError
      render json: {error: "Report could not be accepted; verify this installation's enrollment and source receipt"}, status: :unauthorized
    end
  end
end
