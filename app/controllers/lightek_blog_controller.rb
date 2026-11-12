class LightekBlogController < ApplicationController
  skip_authorization_check
  allow_unauthenticated_access only:%i[index show feed]
  helper LightekDesign::StudioHelper
  helper DymondDash::TemplateSchemaHelper
  before_action :load_site
  def index
    scope=entries
    @query=params[:q].to_s.first(120).strip
    @category=params[:category].to_s.first(80).strip
    scope=scope.where("LOWER(posts.title) LIKE :q OR LOWER(posts.content) LIKE :q",q:"%#{ActiveRecord::Base.sanitize_sql_like(@query.downcase)}%") if @query.present?
    scope=scope.where(category:@category) if @category.present?
    @page_number=[params[:page].to_i,1].max.clamp(1,10000)
    @entries=scope.limit(13).offset((@page_number-1)*12).to_a
    @more=@entries.size>12;@entries=@entries.first(12)
    @categories=entries.reorder(nil).distinct.pluck(:category).reject(&:blank?).sort
    @page=Struct.new(:title,:theme,:sections).new("Journal",nil,[])
    render layout:website_layout
  end
  def show
    @entry=entries.find_by!(slug:params[:slug])
    @page=Struct.new(:title,:theme,:sections).new(@entry.post.title,nil,[])
    render layout:website_layout
  end
  def feed
    xml=Nokogiri::XML::Builder.new(encoding:"UTF-8") do |rss|
      rss.rss(version:"2.0") do
        rss.channel do
          rss.title "#{@site.name} · Journal";rss.link "#{request.base_url}/blog";rss.description "News and stories from #{@site.name}"
          entries.limit(30).each do |entry|
            rss.item do
              rss.title entry.post.title;rss.link "#{request.base_url}/blog/#{entry.slug}";rss.guid "#{request.base_url}/blog/#{entry.slug}"
              rss.description(entry.excerpt.presence || helpers.strip_tags(entry.post.content).first(600));rss.pubDate entry.published_at.rfc2822
            end
          end
        end
      end
    end
    render xml:xml.to_xml,content_type:"application/rss+xml"
  end
  private
  def entries = LightekBlog::Entry.publicly_visible.where(site:@site).includes(post: :user).order(published_at: :desc,id: :desc)
  def load_site
    @site=LightekPwa::SiteContext.resolve(request.host)
    raise ActiveRecord::RecordNotFound unless @site
  end
  def website_layout = LightekDesign::Catalog.active?(@site) ? "lightek_design/website" : "lightek_blog"
end
