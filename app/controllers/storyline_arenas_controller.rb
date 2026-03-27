class StorylineArenasController < ApplicationController
  before_action :set_storyline_arena, only: %i[ show edit update destroy ]

  # GET /storyline_arenas or /storyline_arenas.json
  def index
    @storyline_arenas = StorylineArena.all
  end

  # GET /storyline_arenas/1 or /storyline_arenas/1.json
  def show
  end

  # GET /storyline_arenas/new
  def new
    @storyline_arena = StorylineArena.new
  end

  # GET /storyline_arenas/1/edit
  def edit
  end

  # POST /storyline_arenas or /storyline_arenas.json
  def create
    @storyline_arena = StorylineArena.new(storyline_arena_params)

    respond_to do |format|
      if @storyline_arena.save
        format.html { redirect_to @storyline_arena, notice: "Storyline arena was successfully created." }
        format.json { render :show, status: :created, location: @storyline_arena }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @storyline_arena.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /storyline_arenas/1 or /storyline_arenas/1.json
  def update
    respond_to do |format|
      if @storyline_arena.update(storyline_arena_params)
        format.html { redirect_to @storyline_arena, notice: "Storyline arena was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @storyline_arena }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @storyline_arena.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /storyline_arenas/1 or /storyline_arenas/1.json
  def destroy
    @storyline_arena.destroy!

    respond_to do |format|
      format.html { redirect_to storyline_arenas_path, notice: "Storyline arena was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_storyline_arena
      @storyline_arena = StorylineArena.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def storyline_arena_params
      params.fetch(:storyline_arena, {})
    end
end
