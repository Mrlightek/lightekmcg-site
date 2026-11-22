require 'digest'
module LightekGrowth
  module FeatureCatalog
    # Curated Lightek platform copy, grounded in the installed feature manual.
    # These are product overviews, never fabricated recordings or testimonials.
    ROWS = [
      ['website','Websites','Your website, managed in one place','Create and edit business pages in the native content workspace. Review changes before publishing your website.','website'],
      ['studio','Creative production','Create and finish your media','Bring campaign copy, editing, music and export workflows into Studio. Review the result before delivery.','studio'],
      ['sales','Sales & customers','Keep the next conversation moving','Manage leads, deals, quotes and follow-up tasks together, with customer activity recorded in your sales workspace.','commerce'],
      ['commerce','Sales & customers','Connect orders to delivery','Follow native orders from recorded payment through fulfillment or provisioning, with their delivery history retained.','commerce'],
      ['growth','Marketing','Connect campaigns to outcomes','Use tracked placement links to follow recorded inquiries and payments. Keep unknown campaign source visible instead of inventing attribution.','marketing'],
      ['nevaeh','Automation','Give Nevaeh work she can execute','Delegate supported work to authorized specialists and read their saved reports. Unsupported actions stay visible as capability gaps.','nevaeh']
    ].freeze
    module_function
    def snapshot
      body = Rails.root.join('FEATURES.md').read
      screenshots = DemoShowcase::DOCUMENTED_IMAGES.values.flat_map(&:keys).to_h do |path|
        [path, Digest::SHA256.file(Rails.root.join(path)).hexdigest]
      end
      {'path'=>'FEATURES.md', 'sha256'=>Digest::SHA256.hexdigest(body), 'catalog_sha256'=>Digest::SHA256.hexdigest(JSON.generate(ROWS)), 'version'=>'lightek-feature-overviews-v2', 'screenshots'=>screenshots}
    end
    def rows(site)
      ROWS.filter_map do |key, category, title, body, feature|
        begin
          LightekAgency::PackagePolicy.authorize!(site.tenant, feature)
          {'key'=>key, 'category'=>category, 'title'=>title, 'body'=>body}
        rescue LightekAgency::PackagePolicy::Denied
          nil
        end
      end
    end
  end
end
