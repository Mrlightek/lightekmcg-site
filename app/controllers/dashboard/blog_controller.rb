class Dashboard::BlogController < ApplicationController
  skip_authorization_check
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action :load_site
  rescue_from ActiveRecord::RecordNotUnique,ActiveRecord::RecordInvalid,ActiveRecord::StaleObjectError,ArgumentError,KeyError,with: :invalid_article
  def index
    @editorial_schedule = LightekBlog::EditorialSchedule.find_by(site: @site, actor: current_user)
    @entries=LightekBlog::Entry.where(site:@site).includes(post: :user).order(updated_at: :desc).limit(100)
    @entry ||= params[:entry_id].present? ? @entries.find(params[:entry_id]) : LightekBlog::Entry.new(site:@site,post:Post.new(user:current_user),status:"draft")
  end
  def create = save_article
  def update = save_article
  def assign_nevaeh
    fields = params.require(:assignment).permit(:title, :category, :facts, :call_to_action, :status).to_h
    key = params[:request_key].to_s
    raise ArgumentError, 'Reload the form before assigning this article.' unless key.match?(/\A[0-9a-f-]{36}\z/)
    unless fields['title'].to_s.strip.present? && fields['facts'].to_s.strip.present?
      raise ArgumentError, 'Enter a title and the facts Nevaeh should cover.'
    end
    status = fields['status'] == 'published' ? 'published' : 'draft'
    values = fields.slice('title', 'category').merge('status' => status, 'brief' => fields.slice('facts', 'call_to_action'))
    command = { 'kind' => 'website_marketing', 'operation' => 'journal_write', 'site_id' => @site.id, 'values' => values }
    NevaehOs::WebsiteMarketing.authorize!(current_user, NevaehOs::WebsiteMarketing.bind(current_user, command))
    goal = NevaehOs::Goals.create!(actor: current_user, request_key: "journal-#{@site.id}-#{key}",
      values: { 'title' => "Write #{fields.fetch('title').first(100)}", 'steps' => [{
        'key' => 'write_article', 'label' => 'Write the Journal article', 'agent' => 'marketing_strategy',
        'command' => command, 'expectations' => [{ 'path' => 'result.article_status', 'equals' => status },
          { 'path' => 'result.published', 'equals' => status == 'published' }]
      }] })
    NevaehOs::Goals.control!(goal: goal, actor: current_user, operation: 'start') if goal.status == 'draft'
    redirect_to dashboard_blog_index_path(site_id: @site.id), status: :see_other,
      notice: "Journal goal ##{goal.id} assigned. Follow it in Nevaeh Goals."
  rescue ArgumentError, LightekAgency::PackagePolicy::Denied => error
    redirect_to dashboard_blog_index_path(site_id: @site.id), status: :see_other, alert: error.message
  end
  def configure_editorial
    editorial = NevaehOs::JournalEditorial
    if params[:operation] == 'pause'
      editorial.pause!(site: @site, actor: current_user)
      notice = 'Nevaeh editorial schedule paused.'
    else
      fields = params.require(:editorial).permit(:topics, :sources, :cadence, :article_status, :social_draft).to_h
      editorial.configure!(site: @site, actor: current_user, attributes: fields)
      notice = 'Nevaeh editorial schedule saved. The first cycle will start shortly.'
    end
    redirect_to dashboard_blog_index_path(site_id: @site.id, anchor: 'editorial-schedule'), status: :see_other, notice: notice
  rescue ArgumentError, ActiveRecord::RecordNotFound, LightekAgency::PackagePolicy::Denied => error
    redirect_to dashboard_blog_index_path(site_id: @site.id, anchor: 'editorial-schedule'), status: :see_other, alert: error.message
  end
  def preview
    @entry=LightekBlog::Entry.where(site:@site).includes(:post).find(params[:id])
    @page=Struct.new(:title,:theme,:sections).new(@entry.post.title,nil,[])
    @article_preview=true
    response.set_header("Cache-Control","private, no-store")
    response.set_header("X-Robots-Tag","noindex, nofollow")
    render "lightek_blog/show",layout:LightekDesign::Catalog.active?(@site) ? "lightek_design/website" : "lightek_blog"
  end
  def image
    LightekDesign::SiteTheme.authorize!(@site, current_user)
    entry = LightekBlog::Entry.where(site: @site).find(params[:id])
    LightekBlog::Images.deliver(self, LightekBlog::Images.blob!(entry, params[:attachment_id]))
  end
  private
  def load_site
    @sites=LightekSettings::WebsiteIdentity.sites_for(current_user).order(:name)
    @site=params[:site_id].present? ? @sites.find(params[:site_id]) : (@sites.find_by(id:session[:dymond_dash_site_id]) || @sites.first)
    session[:dymond_dash_site_id]=@site.id if @site
    render :no_application,status:(action_name=="index" ? :ok : :unprocessable_entity) unless @site
  end
  def save_article
    @entry=LightekBlog::Entry.where(site:@site).find(params[:id]) if params[:id]
    @entry=LightekBlog::Editor.save!(site:@site,user:current_user,entry:@entry,attributes:params.require(:article).permit(:title,:content,:slug,:excerpt,:category,:status,:lock_version,images: []).to_h)
    redirect_to dashboard_blog_index_path(site_id:@site.id,entry_id:@entry.id),status: :see_other,notice:"Article saved as #{@entry.status}."
  end
  def invalid_article(error)
    @article_values=params[:article]&.permit(:title,:content,:slug,:excerpt,:category,:status,:lock_version)&.to_h
    @error=case error
    when ActiveRecord::StaleObjectError then "This article changed in another window. Reload before saving."
    when ActiveRecord::RecordNotUnique then "That article URL already exists. Choose a different slug."
    else error.message
    end
    index
    render :index,status: :unprocessable_entity
  end
end
