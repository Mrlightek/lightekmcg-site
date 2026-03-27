class StorylineWorldCommunitiesController < ApplicationController
  before_action :set_storyline_world_community, only: %i[ show edit update destroy ]

  # GET /storyline_world_communities or /storyline_world_communities.json
  def index
    @storyline_world_communities = StorylineWorldCommunity.all
  end

  # GET /storyline_world_communities/1 or /storyline_world_communities/1.json
  def show
  end

  # GET /storyline_world_communities/new
  def new
    @storyline_world_community = StorylineWorldCommunity.new
  end

  # GET /storyline_world_communities/1/edit
  def edit
  end

  # POST /storyline_world_communities or /storyline_world_communities.json
  def create
    @storyline_world_community = StorylineWorldCommunity.new(storyline_world_community_params)

    respond_to do |format|
      if @storyline_world_community.save
        format.html { redirect_to @storyline_world_community, notice: "Storyline world community was successfully created." }
        format.json { render :show, status: :created, location: @storyline_world_community }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @storyline_world_community.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /storyline_world_communities/1 or /storyline_world_communities/1.json
  def update
    respond_to do |format|
      if @storyline_world_community.update(storyline_world_community_params)
        format.html { redirect_to @storyline_world_community, notice: "Storyline world community was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @storyline_world_community }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @storyline_world_community.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /storyline_world_communities/1 or /storyline_world_communities/1.json
  def destroy
    @storyline_world_community.destroy!

    respond_to do |format|
      format.html { redirect_to storyline_world_communities_path, notice: "Storyline world community was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_storyline_world_community
      @storyline_world_community = StorylineWorldCommunity.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def storyline_world_community_params
      params.fetch(:storyline_world_community, {})
    end
end
