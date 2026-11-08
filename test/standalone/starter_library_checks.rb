# Controlled AR/ActionView checks, runnable without the private Rails engines.
require_relative 'html_design_checks'
require 'pathname'
require 'active_record'
require 'action_view'
require 'tmpdir'
module Rails
  def self.root = Pathname.new(File.expand_path('../..', __dir__))
end
module LightekReservations
  class Resource
    def self.available = self
    def self.where(**) = self
    def self.exists? = false
  end
end
require_relative '../../app/services/lightek_design/starter_library'
require_relative '../../app/services/lightek_design/template_branding'
require_relative '../../app/services/lightek_design/website_designs'
module LightekDesign::Catalog
  def self.builtin_designs = designs
end
ActiveRecord::Base.establish_connection(adapter:'sqlite3',database:':memory:')
ActiveRecord::Schema.define do
  create_table(:sites){|t|t.string :name;t.string :host;t.json :manifest,default:{};t.integer :active_template_id}
  create_table(:templates){|t|t.string :key;t.string :name;t.string :description;t.boolean :preset;t.json :settings,default:{}}
  create_table(:pages){|t|t.integer :site_id;t.string :title;t.string :slug;t.boolean :published;t.integer :position}
  create_table(:sections){|t|t.integer :page_id;t.string :kind;t.json :data;t.integer :position}
  create_table(:website_template_inquiries){|t|t.integer :site_id;t.string :template_key;t.string :section_key;t.json :fields;t.timestamps}
end
module DymondSite
  class Site < ActiveRecord::Base
    self.table_name='sites'
    has_many :pages
    belongs_to :active_template,class_name:'DymondSite::SiteTemplate',optional:true
    def tenant = nil
  end
  class SiteTemplate < ActiveRecord::Base
    self.table_name='templates'
  end
  class Page < ActiveRecord::Base
    self.table_name='pages'
    belongs_to :site
    has_many :sections
  end
  class Section < ActiveRecord::Base
    self.table_name='sections'
  end
end
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class=true
end
require_relative '../../app/models/website_template_inquiry'
class StarterLibraryChecks < Minitest::Test
  def setup
    [WebsiteTemplateInquiry,DymondSite::Section,DymondSite::Page,DymondSite::Site,DymondSite::SiteTemplate].each(&:delete_all)
    @site=DymondSite::Site.create!(name:'Client site',host:'client.example.test',manifest:{})
  end
  def test_all_twelve_defaults_clone_to_valid_editable_documents
    assert_equal 12,LightekDesign::StarterLibrary.designs.size
    assert_equal 14,LightekDesign::Catalog.designs.size
    LightekDesign::StarterLibrary.designs.each do |key,definition|
      document=LightekDesign::StudioDocument.normalize(LightekDesign::StudioDocument.from_definition(definition))
      assert_equal definition['sections'].length,document['sections'].length
      assert document['sections'].all?{|section|section['block']=='starter'}
      assert definition['sections'].any?{|section|section['chrome_header']}
      assert definition['sections'].any?{|section|section['chrome_footer']}
      assert LightekDesign::Fonts.valid_stack?(definition.dig('fonts','font_heading'))
    end
  end
  def test_use_template_applies_tokens_and_imports_editable_draft_without_duplicates
    key='starter_barber_clean_cut'
    LightekDesign::WebsiteDesigns.apply!(site:@site,design:key)
    first=LightekDesign::WebsiteDesigns.import!(site:@site,design:key)
    first.sections.first.update!(data:first.sections.first.data.merge('copy'=>['Custom copy']))
    again=LightekDesign::WebsiteDesigns.import!(site:@site,design:key)
    assert_equal first.id,again.id
    assert_equal 1,@site.pages.count
    refute first.published
    assert_equal ['Custom copy'],first.sections.first.reload.data['copy']
    assert_equal '#c8102e',@site.active_template.settings.dig('tokens','color_primary')
  end
  def test_every_source_section_renders_with_markers_and_without_scripts
    LightekDesign::StarterLibrary.designs.each_value do |definition|
      definition['sections'].each do |section|
        html=LightekDesign::StarterLibrary.render_html(section['data'],site:@site,preview:true,authenticity_token:'csrf-fixture')
        assert_includes html,'data-section='
        refute_match(/<script|onclick=|data-ok=/,html)
        assert_includes html,'disabled' if html.include?('<form')
      end
    end
  end
  def test_editable_copy_is_escaped_and_unsafe_links_are_rejected
    data=LightekDesign::StarterLibrary.designs['starter_barber_clean_cut']['sections'].first['data'].deep_dup
    data['copy'][0]='<img src=x onerror=alert(1)>'
    data['links'][0]='javascript:alert(1)'
    html=LightekDesign::StarterLibrary.render_html(data,site:@site,preview:false,authenticity_token:'token')
    assert_includes html,'&lt;img'
    refute_match(/href="javascript:/,html)
  end
  def test_unknown_templates_and_path_traversal_are_rejected
    assert_raises(ArgumentError){LightekDesign::StarterLibrary.normalize_data({'template_key'=>'../../Gemfile','section_key'=>'hero'})}
    assert_raises(ArgumentError){LightekDesign::StarterLibrary.normalize_data({'template_key'=>'barber-clean-cut','section_key'=>'../../secret'})}
  end
  def test_studio_preview_without_a_persisted_site_can_render_the_footer
    data=LightekDesign::StarterLibrary.designs['starter_barber_clean_cut']['sections'].last['data']
    html=LightekDesign::StarterLibrary.render_html(data,site:Struct.new(:name,:id).new('Workspace',nil),preview:true,authenticity_token:'token')
    assert_includes html,'Template by LightekMCG'
  end
  def test_adding_an_installed_section_from_the_palette_keeps_its_native_renderer
    definition=LightekDesign::StarterLibrary.designs['starter_barber_clean_cut']
    section=LightekDesign::StudioDocument.from_definition(definition)['sections'][1]
    section['source_kind']=definition['sections'][1]['kind'];section['block']=nil
    document=LightekDesign::StudioDocument.from_definition(definition).merge('sections'=>[section])
    normalized=LightekDesign::StudioDocument.normalize(document)['sections'].first
    assert_equal 'starter',normalized['block']
    assert_nil normalized['source_kind']
  end
  def test_regular_credit_is_retained_even_if_content_or_settings_try_to_replace_it
    @site.update!(manifest:{'template_branding'=>{'credit'=>'Other brand','show_credit'=>false}})
    definition=LightekDesign::StarterLibrary.designs['starter_barber_clean_cut']
    data=definition['sections'].last['data'].deep_dup
    data['copy'].map!{|text|text.include?('Template by')?'Other brand':text}
    html=LightekDesign::StarterLibrary.render_html(data,site:@site,preview:false,authenticity_token:'token')
    assert_includes html,'Template by LightekMCG'
    assert_raises(ArgumentError){LightekDesign::TemplateBranding.save!(site:@site,actor:Struct.new(:role).new('admin'),values:{'credit'=>'Other brand'})}
  end
  def test_super_admin_can_enable_white_label_and_agency_can_customize_but_not_grant_it
    owner=Struct.new(:role).new('super_admin')
    LightekDesign::TemplateBranding.save!(site:@site,actor:owner,values:{'white_label_enabled'=>'1','show_credit'=>'1','credit'=>'Designed by Example Agency'})
    assert_equal 'Designed by Example Agency',LightekDesign::TemplateBranding.new(@site.reload).credit
    LightekDesign::TemplateBranding.save!(site:@site,actor:Struct.new(:role).new('admin'),values:{'white_label_enabled'=>'0','show_credit'=>'0','credit'=>'Agency'})
    assert LightekDesign::TemplateBranding.new(@site.reload).white_label?
    assert_equal '',LightekDesign::TemplateBranding.new(@site).credit
  end
  def test_contact_form_saves_an_inquiry_and_validates_required_answers
    request=WebsiteTemplateInquiry.new(site:@site,template_key:'barber-clean-cut',section_key:'contact',fields:{'name'=>'Client','phone'=>'555-0100'})
    assert request.save,request.errors.full_messages.join(',')
    assert_equal @site.id,request.reload.site_id
    request.fields={'name'=>''}; refute request.valid?
    request.fields={'name'=>'Client','phone'=>'555','admin'=>'true'};refute request.valid?
    request.fields={'name'=>'Client','phone'=>'x'*2001};refute request.valid?
  end
  def test_forms_post_only_to_native_endpoint_and_do_not_claim_bookings
    data=LightekDesign::StarterLibrary.designs['starter_barber_clean_cut']['sections'].find{|s|s['data']['section_key']=='contact'}['data']
    html=LightekDesign::StarterLibrary.render_html(data,site:@site,preview:false,authenticity_token:'safe-token')
    assert_includes html,'action="/website/template-inquiries"'
    assert_includes html,'value="safe-token"'
    assert_includes html,'Send request'
    refute_includes html,'You are on the book'
  end
  def test_medical_warning_is_preserved
    data=LightekDesign::StarterLibrary.designs['starter_medical_bayside_health']['sections'].find{|s|s['section_type']=='contact'}['data']
    html=LightekDesign::StarterLibrary.render_html(data,site:@site,preview:false,authenticity_token:'token')
    assert_match(/sensitive medical/i,html)
  end
  def test_library_renders_both_website_and_studio_flows
    view=ActionView::Base.with_empty_template_cache.new(ActionView::LookupContext.new([Rails.root.join('app/views')]),{},nil)
    view.instance_variable_set(:@site,@site)
    def view.protect_against_forgery? = false
    def view.url_for(value) = value.is_a?(String) ? value : '/fixture'
    def view.method_missing(name,*args,**kw)
      return '/fixture/'+name.to_s if name.to_s.end_with?('_path')
      super
    end
    def view.respond_to_missing?(name,*) = name.to_s.end_with?('_path') || super
    [false,true].each do |studio|
      html=view.render(partial:'dashboard/website_designs/template_library',locals:{designs:LightekDesign::StarterLibrary.designs,studio:studio})
      assert_equal 12,Nokogiri::HTML5.fragment(html).css('[data-template-card]').size
      assert_includes html,studio ? 'Customize in Studio' : 'Use template'
      refute_match(/claude\.ai|Free|Pro tier/,html)
      directory=ENV['TEMPLATE_PREVIEW_DIR']
      if directory
        FileUtils.mkdir_p(directory)
        File.write(File.join(directory,studio ? 'studio-library.html' : 'website-library.html'),'<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head><body><div class="dd-content">'+html+'</div></body></html>')
      end
    end
  end
end
