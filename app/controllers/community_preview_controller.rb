# app/controllers/community_preview_controller.rb

class CommunityPreviewController < ApplicationController

  def index
    render template: "communities/index"
  end


  def topic
    render template: "communities/topic"
  end


  def discussion
    render template: "communities/discussion"
  end


  def new
    render template: "communities/new"
  end


  def profile
    render template: "communities/profile"
  end


  def admin
    render template: "communities/admin"
  end

end