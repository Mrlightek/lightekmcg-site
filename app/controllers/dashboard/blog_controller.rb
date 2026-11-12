class Dashboard::BlogController < ApplicationController
  skip_authorization_check
  layout "dymond_dash/layouts/dymond_dash"
  protect_from_forgery with: :exception
  before_action :load_site
  rescue_from ActiveRecord::RecordNotUnique,ActiveRecord::RecordInvalid,ActiveRecord::StaleObjectError,ArgumentError,KeyError,with: :invalid_article
  def index
    @entries=LightekBlog::Entry.where(site:@site).includes(post: :user).order(updated_at: :desc).limit(100)
    @entry ||= params[:entry_id].present? ? @entries.find(params[:entry_id]) : LightekBlog::Entry.new(site:@site,post:Post.new(user:current_user),status:"draft")
  end
  def create = save_article
  def update = save_article
  def preview
    @entry=LightekBlog::Entry.where(site:@site).includes(:post).find(params[:id])
    @page=Struct.new(:title,:theme,:sections).new(@entry.post.title,nil,[])
    @article_preview=true
    response.set_header("Cache-Control","private, no-store")
    response.set_header("X-Robots-Tag","noindex, nofollow")
    render "lightek_blog/show",layout:LightekDesign::Catalog.active?(@site) ? "lightek_design/website" : "lightek_blog"
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
    @entry=LightekBlog::Editor.save!(site:@site,user:current_user,entry:@entry,attributes:params.require(:article).permit(:title,:content,:slug,:excerpt,:category,:status,:lock_version).to_h)
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
