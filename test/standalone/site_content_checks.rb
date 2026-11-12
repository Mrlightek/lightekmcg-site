# Real AR transactions, production services/controllers/templates; engine record
# and registry interfaces stand in for the private DymondSite/DymondDash gems.
require_relative 'pwa_http_checks'
require 'nokogiri'
def Rails.root = Pathname.new(File.expand_path('../..',__dir__))
ActiveRecord::Schema.define do
  add_column :dymond_site_sites,:active_template_id,:integer
  create_table(:lightek_reservation_peers){|t|t.references :site;t.references :merchant}
  create_table(:dymond_site_site_templates){|t|t.string :key;t.string :name;t.text :description;t.boolean :preset;t.json :settings,default:{};t.timestamps}
  create_table(:dymond_site_pages){|t|t.references :site;t.string :title;t.string :slug;t.boolean :published,default:false;t.integer :position;t.timestamps}
  add_index :dymond_site_pages,[:site_id,:slug],unique:true
  create_table(:dymond_site_sections){|t|t.references :page;t.string :kind;t.json :data,default:{};t.integer :position}
  create_table(:dymond_site_nav_menus){|t|t.references :site;t.string :name}
  create_table(:dymond_site_nav_items){|t|t.references :nav_menu;t.references :page;t.integer :parent_id;t.string :label;t.string :external_url;t.integer :position}
end
ActiveRecord::Schema.define do
  create_table(:gatekeeper_application_templates){|t|t.string :kind}
  create_table(:gatekeeper_application_launches){|t|t.string :status}
  create_table(:compute_providers){|t|t.string :slug}
  create_table(:dymond_bank_subscriptions){|t|t.string :status}
end
%w[20261028210000_expand_lightek_commerce_products 20261028220000_create_lightek_commerce_product_variants 20261112070000_connect_hosting_agencies_and_commerce 20261112080000_create_platform_shipping].each{|name|migrate_session_fixture(name)}
%w[app/models/lightek_commerce/product_variant app/models/lightek_shipping/quote app/services/lightek_shipping/quotes].each{|path|require Rails.root.join(path)}
module DymondSite
  class Site
    has_many :pages,class_name:'DymondSite::Page'
    has_one :nav_menu,class_name:'DymondSite::NavMenu'
    belongs_to :active_template,class_name:'DymondSite::SiteTemplate',optional:true
    def theme = nil
    def footer = nil
  end
  class SiteTemplate < ApplicationRecord
    self.table_name='dymond_site_site_templates'
    def tokens = settings.fetch('tokens',{})
  end
  class Page < ApplicationRecord
    self.table_name='dymond_site_pages'
    belongs_to :site,class_name:'DymondSite::Site'
    has_many :sections,class_name:'DymondSite::Section'
    def theme = nil
  end
  class Section < ApplicationRecord
    self.table_name='dymond_site_sections'
    belongs_to :page,class_name:'DymondSite::Page'
  end
  class NavMenu < ApplicationRecord
    self.table_name='dymond_site_nav_menus'
    has_many :nav_items,class_name:'DymondSite::NavItem'
    def roots = nav_items.where(parent_id:nil).order(:position)
  end
  class NavItem < ApplicationRecord
    self.table_name='dymond_site_nav_items'
    belongs_to :page,class_name:'DymondSite::Page',optional:true
    def children = self.class.where(parent_id:id)
    def children? = children.exists?
    def href = external_url.presence || (page.slug=='home' ? '/' : "/#{page.slug}")
  end
  module Sections
    class Base
      def self.key(value=nil) = value ? @key=value : @key
      def self.template(*) = nil
      def self.field(name,type,**opts) = (@schema||=[]) << {'name'=>name,'type'=>type.to_s}.merge(opts.stringify_keys)
      def self.schema = @schema || []
      def self.presenter_for(record) = Struct.new(:section,:data).new(record,record.data)
    end
  end
  module SectionRegistry
    @entries={}
    def self.register(klass) = @entries[klass.key]=klass
    def self.find(key) = @entries[key]
  end
end
%w[catalog fonts studio_blocks studio_document content_sections commerce_sections html_document html_import starter_library website_designs studio_context studio_catalog site_theme html_bindings template_branding].each{|f|require Rails.root.join("app/services/lightek_design/#{f}")}
LightekDesign::Catalog.singleton_class.alias_method(:builtin_designs,:designs)
LightekDesign::Catalog.singleton_class.prepend(LightekDesign::StudioCatalog)
LightekDesign::WebsiteDesigns.singleton_class.prepend(LightekDesign::StudioSiteCopies)
LightekDesign::Catalog.register_sections!
require Rails.root.join('app/services/lightek_settings/website_identity')
require Rails.root.join('app/models/lightek_reservations/peer')
require Rails.root.join('app/helpers/lightek_design/studio_helper')
require Rails.root.join('db/migrate/20261112170000_create_lightek_blog_entries')
CreateLightekBlogEntries.new.migrate(:up)
require Rails.root.join('app/models/lightek_blog/entry')
require Rails.root.join('app/services/lightek_blog/editor')
module DymondDash
  module TemplateSchemaHelper
    def theme_styles(*) = ''
  end
end
class ApplicationController
  def self.skip_authorization_check = nil
  helper_method :current_user
end
module Dashboard;end
require Rails.root.join('app/controllers/commerce_controller')
require Rails.root.join('app/controllers/dashboard/blog_controller')
require Rails.root.join('app/controllers/lightek_blog_controller')
Dashboard::BlogController.layout false
ApplicationController.prepend_view_path Rails.root.join('app/views')
Rails.application.routes.append do
  resources :website_blog,only:%i[index show],path:'blog',param: :slug,controller:'lightek_blog'
  get '/journal.xml',to:'lightek_blog#feed',as: :website_blog_feed
  namespace :dashboard do
    resources :blog,only:%i[index create update],controller:'blog' do
      get :preview,on: :member
    end
  end
  get '/dashboard/website/designs',to:'dashboard/blog#index',as: :dashboard_website_designs
  get '/commerce/shop',to:'commerce#index',as: :commerce_shop
  post '/commerce/cart/add',to:'commerce#add',as: :commerce_cart_add
  delete '/commerce/cart/remove',to:'commerce#remove',as: :commerce_cart_remove
  post '/commerce/checkout',to:'commerce#checkout',as: :commerce_checkout
  post '/commerce/shipping/quotes',to:'commerce#index',as: :commerce_shipping_quotes
end
module Dashboard
  class SettingsHomeController < ApplicationController
    before_action :require_settings_operator!
    def require_settings_operator!
      head(:forbidden) unless current_user&.role.in?(%w[admin super_admin])
    end
  end
end
class User
  def feature_entitlements
    Object.new.tap do |scope|
      def scope.active = self
      def scope.exists?(**) = false
    end
  end
end
ActiveRecord::Schema.define do
  create_table(:website_template_inquiries){|t|t.references :site;t.string :template_key;t.string :section_key;t.json :fields,default:{};t.timestamps}
end
require Rails.root.join('app/models/website_template_inquiry')
require Rails.root.join('app/services/lightek_commerce/industry_starters')
require Rails.root.join('app/controllers/dashboard/website_designs_controller')
require Rails.root.join('app/controllers/dashboard/design_studio_controller')
Dashboard::DesignStudioController.layout false
Dashboard::WebsiteDesignsController.layout false
Dashboard::WebsiteDesignsController.helper(Module.new{def dymond_dash = main_app})
# Use actual website controller routes; unrelated engine screens are route fixtures.
Rails.application.routes.append do
  get '/dashboard/design-studio',to:'dashboard/design_studio#index',as: :dashboard_design_studio_index
  get '/dashboard/design-studio/:id/edit',to:'dashboard/design_studio#edit',as: :edit_dashboard_design_studio
  get '/dashboard/design-content',to:'dashboard/website_designs#index'
  post '/dashboard/website/designs/themes',to:'dashboard/website_designs#install_theme',as: :dashboard_website_themes
  post '/dashboard/website/designs/themes/:template_id/activate',to:'dashboard/website_designs#activate_theme',as: :activate_dashboard_website_theme
end
paths=(Dir[Rails.root.join('app/views/dashboard/website_designs/*.erb')]+Dir[Rails.root.join('app/views/dashboard/shared/_business_workspace.html.erb')]+Dir[Rails.root.join('app/views/dashboard/design_studio/*.erb')]).flat_map{|p|File.read(p).scan(/\b([a-z_]+)_path\b/).flatten}.uniq
Rails.application.routes.append do
  paths.each do |name|
    next if Rails.application.routes.named_routes.names.include?(name.to_sym)
    get "/test/workspace/#{name}",to:'dashboard/blog#index',as:name.to_sym
  end
end
Rails.application.reload_routes!
class SiteContentChecks < ActionDispatch::IntegrationTest
  def setup
    ActiveRecord::Base.connection.begin_transaction(joinable:false)
    LightekBlog::Entry.delete_all
    [DymondSite::NavItem,DymondSite::NavMenu,DymondSite::Section,DymondSite::Page,DymondSite::SiteTemplate].each(&:delete_all)
    LightekDesign::StudioContext.reset
    @user=User.create!(role:'admin',email_address:"site-#{SecureRandom.hex(6)}@example.test")
    @other=User.create!(role:'admin',email_address:"other-#{SecureRandom.hex(6)}@example.test")
    Profile.create!(user:@user,display_name:'Writer',handle:"writer-#{@user.id}")
    @site=DymondSite::Site.create!(name:'Lightek business',host:"site-#{SecureRandom.hex(6)}.test",tenant:@user)
    @foreign=DymondSite::Site.create!(name:'Other business',host:"foreign-#{SecureRandom.hex(6)}.test",tenant:@other)
    host! @site.host
    get "/test/csrf",headers:{"X-Pwa-Test-User"=>@user.id.to_s}
    @csrf=response.parsed_body.fetch("csrf_token")
  end
  def teardown
    ActiveRecord::Base.connection.rollback_transaction
  end
  def headers(user=@user) = {'X-Pwa-Test-User'=>user.id.to_s,'X-CSRF-Token'=>@csrf}
  def file(name,html)
    value=StringIO.new(html)
    value.define_singleton_method(:original_filename){name}
    value
  end
  def home_html = '<style>:root{--bg:#05060a;--cy:#00ffff}nav{display:flex}</style><header><a data-l="site">LIGHTEK</a><nav><a href="store.html">Store</a><a href="blog.html">Journal</a></nav></header><main><section><h1>Own every layer.</h1><a data-l="store">Shop</a><a data-l="careers">Careers</a></section></main><footer><a data-l="blog">Journal</a></footer>'
  def install(site:@site,user:@user,key:SecureRandom.uuid,files:nil)
    files||=[file('index.html',home_html),file('store.html','<header><nav>Mock navigation</nav></header><main><h1>Hardware.</h1><div id="grid"></div></main>'),file('blog.html','<header><nav>Mock journal</nav></header><main id="app"></main><script>app.innerHTML="Sample posts";</script>')]
    LightekDesign::SiteTheme.install!(site:site,user:user,name:'Lightek full website',files:files,request_key:key)
  end
  def article(**values)
    LightekBlog::Editor.save!(site:@site,user:@user,attributes:{title:'Own every layer',content:'<p>A connected business platform.</p>',slug:'own-every-layer',excerpt:'One platform.',category:'Ideas',status:'draft'}.merge(values))
  end
  def test_site_theme_install_is_draft_atomic_idempotent_and_retains_existing_work
    old=@site.pages.create!(title:'Existing home',slug:'home',published:true)
    key=SecureRandom.uuid;theme=install(key:key)
    assert_nil @site.reload.active_template_id
    assert_equal 4,@site.pages.count
    assert @site.pages.where.not(id:old.id).all?{|p|!p.published?}
    assert_equal 'Existing home',old.reload.title
    assert_equal theme.id,install(key:key).id
    assert_equal 4,@site.pages.count
    assert_equal 3,theme.settings.dig('lightek_site_theme','pages').size
    source=DymondSite::SiteTemplate.find(theme.settings.dig('lightek_site_theme','source_record_id'))
    assert_includes source.settings.dig('lightek_theme_source','files','blog.html'),'<script>'
    refute theme.settings.dig('lightek_site_theme').key?('source_files')
    assert_equal 'home-2',theme.settings.dig('lightek_site_theme','pages').first['slug']
    kinds=@site.pages.where.not(id:old.id).flat_map{|p|p.sections.map{|s|LightekDesign::Catalog.section_definition(s.kind)['render_kind']}}
    assert_includes kinds,'lightek_product_grid';assert_includes kinds,'lightek_blog_index'
  end
  def test_site_theme_activation_preserves_menu_and_binds_actual_app_routes_without_draft_links
    menu=@site.create_nav_menu!(name:'Existing navigation');menu.nav_items.create!(label:'Support',external_url:'/help',position:0)
    theme=install;LightekDesign::SiteTheme.activate!(site:@site,user:@user,template_id:theme.id)
    assert_equal theme.id,@site.reload.active_template_id
    assert_equal 'Support',menu.nav_items.order(:position).first.label
    assert_equal 4,menu.nav_items.count
    LightekDesign::SiteTheme.activate!(site:@site,user:@user,template_id:theme.id)
    assert_equal 4,menu.nav_items.count
    assert_equal theme.settings.dig('lightek_site_theme','pages').find{|p|p['role']=='store'}['page_id'],@site.manifest['lightek_commerce_starter_page_id']
    source=theme.settings.dig('lightek_site_theme','chrome').find{|s|s['chrome_header']}['data']
    html=LightekDesign::HtmlBindings.render(source,site:@site,navigation_html:'<ul><li><a href="/help">Support</a></li></ul>')
    assert_includes html,'Support';refute_includes html,'href="store.html"'
    body=LightekDesign::HtmlDocument.normalize_data('html'=>'<a data-l="store">Shop</a><a data-l="blog">Journal</a><a href="javascript:alert(1)">Bad</a>')
    rendered=LightekDesign::HtmlBindings.render(body,site:@site)
    assert_includes rendered,"/commerce/shop?site_id=#{@site.id}";assert_includes rendered,'href="/blog"';refute_includes rendered,'javascript:'
  end
  def test_site_theme_cannot_cross_accounts_or_partially_install_invalid_sources
    assert_raises(ActiveRecord::RecordNotFound){install(user:@other)}
    theme=install(site:@foreign,user:@other)
    assert_raises(ActiveRecord::RecordNotFound){LightekDesign::SiteTheme.activate!(site:@site,user:@user,template_id:theme.id)}
    count=DymondSite::SiteTemplate.count
    assert_raises(ArgumentError){install(files:[file('index.html',home_html),file('store.html','<main><p>No product container</p></main>')])}
    assert_equal count,DymondSite::SiteTemplate.count
    assert_empty @site.pages
  end
  def test_site_article_draft_preview_publish_archive_and_public_host_isolation
    entry=article
    get "/blog/#{entry.slug}";assert_response :not_found
    get "/dashboard/blog/#{entry.id}/preview",params:{site_id:@site.id},headers:headers;assert_response :success;assert_includes response.body,'Private preview';assert_equal 'private, no-store',response.headers['Cache-Control']
    assert_empty LightekBlog::Entry.publicly_visible.where(site:@site)
    entry=LightekBlog::Editor.save!(site:@site,user:@user,entry:entry,attributes:{title:entry.post.title,content:entry.post.content,slug:entry.slug,category:'Ideas',status:'published',lock_version:entry.lock_version})
    get "/blog/#{entry.slug}";assert_response :success;assert_includes response.body,'connected business platform'
    assert_equal 'published',entry.post.reload.moderation_state
    row=LightekCommunity::Presenter.new(LightekCommunity::Access.new(user:@user,site_id:@site.id)).post(entry.post)
    assert_equal "/blog/#{entry.slug}",row[:website_article_url]
    refute_match(/<p>/,row[:website_article_excerpt])
    refute row[:can_edit]
    refute row[:can_delete]
    assert_includes row[:website_article_edit_url],"entry_id=#{entry.id}"
    assert_raises(LightekCommunity::AccessDenied){LightekCommunity::Workers::Pwa.perform('post_update',user_id:@user.id,site_id:@site.id,post_id:entry.post_id,content:'Bypassed native editor')}
    assert_includes entry.post.reload.content,'connected business platform'
    assert_raises(LightekCommunity::AccessDenied){LightekCommunity::Workers::Pwa.perform('post_delete',user_id:@user.id,site_id:@site.id,post_id:entry.post_id)}
    get '/journal.xml';assert_response :success;assert_includes response.body,'Own every layer'
    host! @foreign.host;get "/blog/#{entry.slug}",params:{site_id:@site.id};assert_response :not_found
    host! 'unknown.test';get '/blog',params:{site_id:@site.id};assert_response :not_found
    host! @site.host
    LightekBlog::Editor.save!(site:@site,user:@user,entry:entry,attributes:{title:entry.post.title,content:entry.post.content,slug:entry.slug,status:'archived',lock_version:entry.lock_version})
    get "/blog/#{entry.slug}";assert_response :not_found
    assert_equal 'hidden',entry.post.reload.moderation_state
  end
  def test_site_article_edit_conflicts_roll_back_the_shared_post_and_bad_html_is_not_executable
    entry=article(status:'published',content:'<h2>Hello</h2><script>alert(1)</script><a href="javascript:alert(2)">Bad</a>')
    get "/blog/#{entry.slug}";assert_response :success;refute_includes response.body,'<script>';refute_includes response.body,'javascript:'
    before=entry.post.content
    assert_raises(ActiveRecord::StaleObjectError){LightekBlog::Editor.save!(site:@site,user:@user,entry:entry,attributes:{title:'Overwritten',content:'Lost?',slug:entry.slug,status:'draft',lock_version:-1})}
    assert_equal before,entry.post.reload.content
    assert_equal 'published',entry.reload.status
    assert_raises(ActiveRecord::RecordNotFound){LightekBlog::Editor.save!(site:@site,user:@other,entry:entry,attributes:{})}
  end
  def test_site_owner_client_can_install_and_theme_chrome_wraps_public_articles_once
    @user.update!(role:'client')
    theme=install
    LightekDesign::SiteTheme.activate!(site:@site,user:@user,template_id:theme.id)
    @site.pages.update_all(published:true)
    entry=article(status:'published')
    get "/blog/#{entry.slug}"
    assert_response :success
    html=Nokogiri::HTML5(response.body)
    assert_equal 2,html.css('lightek-html').size
    assert_includes response.body,'/commerce/shop?site_id='
    assert_includes response.body,'href="/blog"'
    assert_includes response.body,'connected business platform'
    assert_equal 1,LightekBlog::Entry.where(post_id:entry.post_id).count
    if ENV['SITE_CONTENT_PREVIEW_DIR']
      FileUtils.mkdir_p(ENV['SITE_CONTENT_PREVIEW_DIR'])
      File.write(File.join(ENV['SITE_CONTENT_PREVIEW_DIR'],'article.html'),response.body)
      get '/dashboard/blog',params:{site_id:@site.id,entry_id:entry.id},headers:headers
      assert_response :success
      File.write(File.join(ENV['SITE_CONTENT_PREVIEW_DIR'],'editor.html'),response.body)
      get '/dashboard/blog',params:{site_id:@site.id},headers:headers
      File.write(File.join(ENV['SITE_CONTENT_PREVIEW_DIR'],'editor-new.html'),response.body)
      get '/blog';assert_response :success
      File.write(File.join(ENV['SITE_CONTENT_PREVIEW_DIR'],'journal.html'),response.body)
    end
  end
  def test_site_article_mutations_require_csrf_and_invalid_slug_does_not_create_a_post
    before=Post.count
    post '/dashboard/blog',params:{site_id:@site.id,article:{title:'Bad',slug:'bad',content:'No CSRF',status:'published'}},headers:{'X-Pwa-Test-User'=>@user.id.to_s}
    assert_response :unprocessable_entity
    assert_equal before,Post.count
    assert_raises(ActiveRecord::RecordInvalid){article(slug:'bad / slug')}
    assert_equal before,Post.count
  end
  def test_site_design_actions_precede_collapsed_design_library
    get '/dashboard/design-content',params:{site_id:@site.id},headers:headers
    assert_response :success
    doc=Nokogiri::HTML5(response.body)
    actions=doc.at_css('[aria-label="Website editing"]')
    assert_includes actions.text,'Open Pages & Sections'
    assert_operator response.body.index('Open Pages &amp; Sections'),:<,response.body.index('data-template-library')
    refute doc.at_css('details.content-library').key?('open')
    assert_equal 'Open Pages & Sections',actions.at_css('a').text
    if ENV['SITE_CONTENT_PREVIEW_DIR']
      FileUtils.mkdir_p(ENV['SITE_CONTENT_PREVIEW_DIR'])
      File.write(File.join(ENV['SITE_CONTENT_PREVIEW_DIR'],'design.html'),response.body)
    end
  end
  def test_site_article_slug_is_unique_per_website_and_public_search_is_case_insensitive
    entry=article(status:'published');count=Post.count
    assert_raises(ActiveRecord::RecordInvalid){article}
    assert_equal count,Post.count
    foreign=LightekBlog::Editor.save!(site:@foreign,user:@other,attributes:{title:'Other version',content:'Different',slug:entry.slug,status:'published'})
    assert_equal entry.slug,foreign.slug
    get '/blog',params:{q:'OWN EVERY'};assert_response :success;assert_includes response.body,'Own every layer';refute_includes response.body,'Other version'
    get '/blog',params:{q:'%'};assert_response :success;refute_includes response.body,'href="/blog/own-every-layer"'
  end
  def test_site_theme_builds_from_installed_designs_and_font_edits_keep_the_bundle
    key=SecureRandom.uuid
    theme=LightekDesign::SiteTheme.from_designs!(site:@site,user:@user,name:'My business',home_design:'vinylctrl',page_designs:['ybnc'],include_store:true,include_blog:true,request_key:key)
    pages=theme.settings.dig('lightek_site_theme','pages')
    assert_equal %w[home page store blog],pages.map{|p|p['role']}
    assert_equal 4,@site.pages.count
    assert_nil @site.reload.active_template
    same=LightekDesign::SiteTheme.from_designs!(site:@site,user:@user,name:'Retry',home_design:'vinylctrl',request_key:key)
    assert_equal theme.id,same.id
    LightekDesign::SiteTheme.activate!(site:@site,user:@user,template_id:theme.id)
    LightekDesign::WebsiteDesigns.save_fonts!(site:@site,values:{'font_heading'=>'Inter'})
    assert_equal theme.id,@site.reload.active_template_id
    assert_equal 'Inter',@site.active_template.settings.dig('tokens','font_heading')
    assert_equal 4,@site.active_template.settings.dig('lightek_site_theme','pages').size
    second=LightekDesign::SiteTheme.from_designs!(site:@site,user:@user,name:'Another theme',home_design:'vinylctrl',request_key:SecureRandom.uuid)
    refute_equal theme.id,second.id
    assert_equal theme.id,@site.reload.active_template_id
    assert_equal 4,theme.reload.settings.dig('lightek_site_theme','pages').size
  end
  def test_site_theme_shared_chrome_uses_current_page_edits
    theme=install;LightekDesign::SiteTheme.activate!(site:@site,user:@user,template_id:theme.id)
    entry=article(status:'published')
    source=theme.settings.dig('lightek_site_theme','chrome').find{|s|s['chrome_footer']}
    record=@site.pages.find(theme.settings.dig('lightek_site_theme','chrome_page_id')).sections.find_by!(kind:source['kind'])
    record.update!(data:record.data.merge('html'=>'<footer>Updated global footer</footer>','copy'=>['Updated global footer'],'links'=>[]))
    get "/blog/#{entry.slug}";assert_response :success;assert_includes response.body,'Updated global footer'
  end
  def test_site_client_design_studio_is_owned_and_unmanaged_accounts_stay_out
    @user.update!(role:'client')
    record=LightekDesign::StudioDocument.create!(user:@user,name:'My design')
    get '/dashboard/design-studio',headers:headers;assert_response :success;assert_includes response.body,'My design'
    foreign=LightekDesign::StudioDocument.create!(user:@other,name:'Private design')
    get "/dashboard/design-studio/#{foreign.id}/edit",headers:headers;assert_response :not_found
    stranger=User.create!(role:'client',email_address:'no-site@example.test')
    get '/dashboard/design-studio',headers:headers(stranger);assert_response :forbidden
  end
  def test_site_uploaded_store_uses_actual_products_cart_and_checkout_in_the_shared_theme
    theme=install
    LightekDesign::SiteTheme.activate!(site:@site,user:@user,template_id:theme.id)
    @site.pages.update_all(published:true)
    product=LightekCommerce::Product.create!(site:@site,name:'A real business download',slug:'real-download',price_cents:1500,inventory_quantity:10,published:true,product_type:'digital')
    foreign=LightekCommerce::Product.create!(site:@foreign,name:'Private foreign inventory',slug:'other',price_cents:100,inventory_quantity:10,published:true,product_type:'digital')
    get '/commerce/shop',params:{site_id:@site.id}
    assert_response :success
    assert_includes response.body,product.name
    refute_includes response.body,foreign.name
    assert_includes response.body,'Add to cart'
    assert_includes response.body,'id="lightek-cart"'
    post '/commerce/cart/add',params:{site_id:@site.id,product_id:product.id,quantity:2},headers:{'X-CSRF-Token'=>@csrf}
    assert_response :redirect
    follow_redirect!;assert_response :success
    assert_includes response.body,'Secure checkout'
    assert_includes response.body,'Continue to secure payment'
    assert_equal 10,product.reload.inventory_quantity # cart addition does not fake payment or reserve stock
  end
  def test_site_theme_http_build_and_activate_are_scoped_and_do_not_publish_pages
    key=SecureRandom.uuid
    post '/dashboard/website/designs/themes',params:{site_id:@site.id,name:'Complete website',home_design:'vinylctrl',include_store:'1',include_blog:'1',request_key:key},headers:headers
    assert_response :see_other
    id=@site.reload.manifest.fetch('lightek_site_themes').fetch(key)
    assert_nil @site.active_template_id
    post "/dashboard/website/designs/themes/#{id}/activate",params:{site_id:@site.id},headers:headers
    assert_response :see_other
    assert_equal id,@site.reload.active_template_id
    assert @site.pages.all?{|page|!page.published?}
    post "/dashboard/website/designs/themes/#{id}/activate",params:{site_id:@foreign.id},headers:headers
    assert_response :not_found
  end
  def test_site_theme_source_record_is_not_an_applicable_public_template
    theme=install;source_id=theme.settings.dig('lightek_site_theme','source_record_id')
    source=DymondSite::SiteTemplate.find(source_id)
    refute LightekDesign::Catalog.selectable_designs(user:@user).key?(source.key)
    controller=Class.new do
      attr_accessor :params
      def apply = raise('Source reached template activation')
      prepend LightekDesign::StudioTemplateGuard
    end.new
    controller.params={id:source_id}
    assert_raises(ActiveRecord::RecordNotFound){controller.apply}
  end
  def test_site_article_dashboard_crud_keeps_bad_input_and_prevents_foreign_edits
    post '/dashboard/blog',params:{site_id:@site.id,article:{title:'First story',slug:'first-story',content:'A real draft',status:'draft'}},headers:headers
    assert_response :see_other
    entry=LightekBlog::Entry.find_by!(site:@site,slug:'first-story')
    patch "/dashboard/blog/#{entry.id}",params:{site_id:@site.id,article:{title:'Keep this title',slug:'BAD SPACE',content:'Keep my body',status:'draft',lock_version:entry.lock_version}},headers:headers
    assert_response :unprocessable_entity;assert_includes response.body,'Keep this title';assert_includes response.body,'Keep my body'
    patch "/dashboard/blog/#{entry.id}",params:{site_id:@foreign.id,article:{title:'Bad'}},headers:headers
    assert_response :not_found
    assert_equal 'First story',entry.post.reload.title
  end
end
