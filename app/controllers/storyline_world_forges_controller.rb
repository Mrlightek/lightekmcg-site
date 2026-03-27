class StorylineWorldForgesController < ApplicationController
  before_action :set_storyline_world_forge, only: %i[ show edit update destroy ]

  # GET /storyline_world_forges or /storyline_world_forges.json
  def index
    @storyline_world_forges = StorylineWorldForge.all
  end

  # GET /storyline_world_forges/1 or /storyline_world_forges/1.json
  def show
  end

  # GET /storyline_world_forges/new
  def new
    @storyline_world_forge = StorylineWorldForge.new
  end

  # GET /storyline_world_forges/1/edit
  def edit
  end

  # POST /storyline_world_forges or /storyline_world_forges.json
  def create
    @storyline_world_forge = StorylineWorldForge.new(storyline_world_forge_params)

    respond_to do |format|
      if @storyline_world_forge.save
        format.html { redirect_to @storyline_world_forge, notice: "Storyline world forge was successfully created." }
        format.json { render :show, status: :created, location: @storyline_world_forge }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @storyline_world_forge.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /storyline_world_forges/1 or /storyline_world_forges/1.json
  def update
    respond_to do |format|
      if @storyline_world_forge.update(storyline_world_forge_params)
        format.html { redirect_to @storyline_world_forge, notice: "Storyline world forge was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @storyline_world_forge }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @storyline_world_forge.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /storyline_world_forges/1 or /storyline_world_forges/1.json
  def destroy
    @storyline_world_forge.destroy!

    respond_to do |format|
      format.html { redirect_to storyline_world_forges_path, notice: "Storyline world forge was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_storyline_world_forge
      @storyline_world_forge = StorylineWorldForge.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def storyline_world_forge_params
      params.fetch(:storyline_world_forge, {})
    end
end
