class Dashboard::SearchGrowthController < Dashboard::SettingsHomeController
  skip_before_action :require_settings_operator!
  protect_from_forgery with: :exception
  before_action :set_search_workspace
  rescue_from ArgumentError, ActiveRecord::RecordInvalid, ActiveRecord::StaleObjectError, LightekGrowth::SearchConsole::Unavailable do |error|
    redirect_to dashboard_search_growth_path(site_id: @site.id), alert: error.message, status: :see_other
  end

  def show
    @snapshot = LightekGrowth::SearchSnapshot.where(site: @site).order(id: :desc).first
    @candidate = @snapshot&.review_candidate
    @backlinks = LightekGrowth::Backlink.where(site: @site).order(updated_at: :desc).limit(100)
  end

  def sync
    LightekGrowth::SearchConsole.new(actor: current_user, site: @site).sync!(inspection_url: params[:inspection_url], domain: params[:property_type] == 'domain')
    back('Search Console evidence refreshed.')
  end

  def record
    backlink_work.record!(source: params[:source_url], target: params[:target_url], status: params[:link_status])
    back('Backlink record saved.')
  end

  def import
    count = backlink_work.import!(params[:backlink_csv])
    back("Processed #{count} backlink rows.")
  end

  def draft
    raise ArgumentError, 'Approve the outreach draft first.' unless params[:approved] == '1'

    link = LightekGrowth::Backlink.where(site: @site, status: 'prospect').find(params[:id])
    version = params[:record_version].to_s
    raise ActiveRecord::StaleObjectError.new(link, 'draft') unless link.updated_at.iso8601(6) == version

    LightekAgency::PackagePolicy.authorize!(@site.tenant, 'nevaeh')
    goal = NevaehOs::Goals.create!(actor: current_user, request_key: "backlink-draft-#{link.id}-#{link.updated_at.to_i}-#{link.updated_at.usec}",
      values: { 'title' => "Draft outreach for backlink prospect ##{link.id}", 'steps' => [{
        'key' => 'draft', 'label' => 'Prepare a backlink outreach draft', 'agent' => 'marketing_strategy',
        'command' => { 'kind' => 'backlink_draft', 'site_id' => @site.id, 'backlink_id' => link.id, 'record_version' => version },
        'expectations' => [{ 'path' => 'result.backlink_id', 'equals' => link.id }]
      }] })
    NevaehOs::Goals.control!(goal: goal, actor: current_user, operation: 'start') if goal.status == 'draft'
    back("Nevaeh goal ##{goal.id} saved. The outreach draft will appear here after execution.")
  end

  private

  def set_search_workspace
    @site = LightekSales::Access.sites_for(current_user).find(params.require(:site_id))
    LightekGrowth::Workspace.new(actor: current_user, site: @site)
  end

  def backlink_work = LightekGrowth::BacklinkWork.new(actor: current_user, site: @site)
  def back(notice) = redirect_to(dashboard_search_growth_path(site_id: @site.id), notice: notice, status: :see_other)
end
