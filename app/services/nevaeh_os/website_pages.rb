# frozen_string_literal: true
module NevaehOs
  module WebsitePages
    module_function
    def inputs(command)
      values=command.fetch('values')
      raise ArgumentError,'Use a page title and optional slug' unless values.is_a?(Hash) && (values.keys-%w[title slug]).empty?
      title=values['title']
      raise ArgumentError,'Use a page title of 1–160 characters' unless title.is_a?(String) && title.strip.length.between?(1,160) && !title.match?(/[\x00-\x1f\x7f]/)
      slug=values['slug'] || title.tr('_','-').parameterize
      raise ArgumentError,'Use a slug of at most 160 lowercase letters, numbers and hyphens' unless slug.is_a?(String) && slug.length<=160 && slug.match?(/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/)
      {'site_id'=>command.fetch('site_id'),'title'=>title.strip,'slug'=>slug}
    end
    def authorize!(actor,command)
      raise ArgumentError,'Choose a positive website ID' unless command['site_id'].to_s.match?(/\A[1-9][0-9]{0,17}\z/)
      values=inputs(command)
      site=LightekSettings::WebsiteIdentity.sites_for(actor).find(values.fetch('site_id'))
      LightekAgency::PackagePolicy.authorize!(site.tenant,'website')
      site
    rescue LightekAgency::PackagePolicy::Denied => error
      raise ArgumentError,error.message
    end
    def create!(actor:,command:)
      site=authorize!(actor,command)
      values=inputs(command)
      site.with_lock do
        authorize!(actor.reload,command)
        raise ArgumentError,'A page already uses this slug; choose another name or open the existing page' if site.pages.exists?(slug:values.fetch('slug'))
        output=NevaehIntelligences::StructuredActions.perform('site.page.create',values,actor:actor,ticket:nil)
        NevaehIntelligences::StructuredActions.verify!('site.page.create',values,output,actor:actor)
        output.merge('status'=>'completed','success'=>true,'title'=>values['title'],'slug'=>values['slug'],'published'=>false,
          'text'=>"Created draft page #{values['title']} (##{output.fetch('page_id')}). Open website pages to add content and publish it.",
          'links'=>[{'label'=>"Open website pages · draft ##{output.fetch('page_id')}",'url'=>"/dashboard/pages?site_id=#{site.id}"}])
      end
    end
  end
end
