# frozen_string_literal: true

module Studio
  module Animation
    class ScenesController < BaseController
      before_action :find_scene, only: %i[show update destroy]

      def index
        @documents = @scenes.order(updated_at: :desc)
        respond_to do |format|
          format.html
          format.json { render json: @documents.map { |scene| scene_data(scene) } }
        end
      end

      def show
        respond_to do |format|
          format.html
          format.json { render json: scene_data(@scene) }
        end
      end

      def create
        StudioProject.transaction do
          attributes = scene_attributes
          project = if attrs_project_id.present?
            @projects.find(attrs_project_id)
          else
            @projects.create!(name: attributes.fetch(:name), owner: current_user, site: @site)
          end
          # A new project already has an empty scene from its creation callback.
          @scene = attrs_project_id.present? ? project.studio_scenes.new : project.studio_scenes.first!
          @scene.update!(attributes)
        end
        respond_with_scene(:created)
      rescue ArgumentError, JSON::ParserError, ActiveRecord::RecordInvalid => error
        invalid(error, studio_animation_scenes_path(site_id: @site.id))
      end

      def update
        @scene.with_lock do
          version = params.dig(:scene, :lock_version)
          if version && version != @scene.lock_version
            raise ArgumentError, "This scene changed in another tab. Reload before saving again."
          end
          @scene.update!(scene_attributes)
        end
        respond_with_scene(:ok)
      rescue ArgumentError, JSON::ParserError, ActiveRecord::RecordInvalid => error
        respond_to do |format|
          format.html do
            @scene_error = error.message
            render :show, status: :unprocessable_entity
          end
          format.json { render json: { error: error.message }, status: :unprocessable_entity }
        end
      end

      def destroy
        @scene.with_lock { @scene.destroy! }
        respond_to do |format|
          format.html { redirect_to studio_animation_scenes_path(site_id: @site.id), status: :see_other }
          format.json { head :no_content }
        end
      rescue ActiveRecord::RecordNotDestroyed => error
        invalid(error, studio_animation_scene_path(@scene, site_id: @site.id))
      end

      private

      def find_scene = @scene = @scenes.find(params[:id])

      def attrs_project_id = params.dig(:scene, :studio_project_id)

      def scene_attributes
        data = params.require(:scene)
        attributes = data.permit(:name).to_h.symbolize_keys
        raise ArgumentError, "A scene name is required" if action_name == "create" && attributes[:name].blank?
        if data.key?(:scene_spec)
          raw = data[:scene_spec]
          raw = raw.to_unsafe_h if raw.is_a?(ActionController::Parameters)
          if raw.is_a?(String)
            raise ArgumentError, "Scene JSON exceeds 4 MB" if raw.bytesize > 4.megabytes
            raw = JSON.parse(raw)
          end
          attributes[:scene_spec] = SceneSpec.normalize(raw)
        elsif action_name == "create"
          attributes[:scene_spec] = SceneSpec.normalize({})
        end
        attributes
      end

      def scene_data(scene)
        scene.as_json(only: %i[id name studio_project_id scene_spec updated_at lock_version])
      end

      def respond_with_scene(status)
        respond_to do |format|
          format.html { redirect_to studio_animation_scene_path(@scene, site_id: @site.id), status: :see_other }
          format.json { render json: scene_data(@scene), status: status }
        end
      end
    end
  end
end
