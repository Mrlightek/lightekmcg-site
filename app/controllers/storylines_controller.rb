class StorylinesController < ApplicationController
  before_action :set_storyline, only: %i[ show edit update destroy ]

  # GET /storylines or /storylines.json
  def index
    @storylines = Storyline.all
  end

  # GET /storylines/1 or /storylines/1.json
  def show
  end

  # GET /storylines/new
  def new
    @storyline = Storyline.new
  end

  # GET /storylines/1/edit
  def edit
  end

  # POST /storylines or /storylines.json
  def create
    @storyline = Storyline.new(storyline_params)

    respond_to do |format|
      if @storyline.save
        format.html { redirect_to @storyline, notice: "Storyline was successfully created." }
        format.json { render :show, status: :created, location: @storyline }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @storyline.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /storylines/1 or /storylines/1.json
  def update
    respond_to do |format|
      if @storyline.update(storyline_params)
        format.html { redirect_to @storyline, notice: "Storyline was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @storyline }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @storyline.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /storylines/1 or /storylines/1.json
  def destroy
    @storyline.destroy!

    respond_to do |format|
      format.html { redirect_to storylines_path, notice: "Storyline was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_storyline
      @storyline = Storyline.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def storyline_params
      params.fetch(:storyline, {})
    end
end
