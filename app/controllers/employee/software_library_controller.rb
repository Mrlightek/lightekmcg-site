# frozen_string_literal: true
module Employee
  class SoftwareLibraryController < Employee::ApplicationController
    before_action do
      authorize! :manage, NevaehWorkflow
      response.set_header('Cache-Control', 'private, no-store')
      response.set_header('X-Robots-Tag', 'noindex, nofollow')
    end
    def index
      return code_map if params[:view] == 'code'
      return platform_coverage if params[:view] == 'coverage'

      library = NevaehIntelligences::SoftwareLibrary.new
      @documents = library.search(query: params[:q], section: params[:section])
      @sections = library.documents.map { |entry| entry[:section] }.uniq
      @document = library.find(params[:id]) if params[:id].present?
      respond_to do |format|
        format.html
        format.json do
          render json: @document ? @document.except(:modified_at) : @documents.map { |doc| doc.except(:body, :modified_at) }
        end
      end
    rescue NevaehIntelligences::SoftwareLibrary::Missing
      head :not_found
    end

    private

    def platform_coverage
      @coverage = NevaehIntelligences::PlatformCoverage.installed(query: params[:q])
      respond_to do |format|
        format.html { render :platform_coverage }
        format.json { render json: @coverage }
      end
    end

    def code_map
      @code_map = NevaehIntelligences::CodeKnowledge.new.search(query: params[:q])
      respond_to do |format|
        format.html { render :code_map }
        format.json { render json: @code_map }
      end
    end
  end
end
