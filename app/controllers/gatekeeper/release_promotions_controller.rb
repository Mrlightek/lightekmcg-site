# frozen_string_literal: true

module Gatekeeper
  class ReleasePromotionsController < ApplicationController
    allow_unauthenticated_access only: :create
    skip_forgery_protection only: :create
    rate_limit to: 15, within: 1.minute, only: :create

    def create
      response.headers["Cache-Control"] = "private, no-store"
      revision = params[:production_sha].to_s
      ReleaseAssurance::ProductionPromotion.authenticate!(request.authorization, revision)
      candidate = ReleaseAssurance::Candidate.find(params[:candidate_id])
      render json: ReleaseAssurance::ProductionPromotion.verify!(candidate,
        revision: revision, tree: params[:tree_sha].to_s, profile: params[:profile].to_s)
    rescue ReleaseAssurance::Policy::Denied, ActiveRecord::RecordNotFound
      head :forbidden
    end
  end
end
