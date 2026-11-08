# frozen_string_literal: true
module Employee
  class SoftwareLibraryController < Employee::ApplicationController
    before_action do
      authorize! :manage, NevaehWorkflow
      response.set_header('Cache-Control', 'private, no-store')
      response.set_header('X-Robots-Tag', 'noindex, nofollow')
    end
    def index
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
  end
end
