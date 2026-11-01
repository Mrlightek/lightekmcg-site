namespace :studio do
  namespace :blender do
    desc "Queue official native starter files for the platform Studio library"
    task bootstrap: :environment do
      host=ENV.fetch("LIGHTEK_STUDIO_SITE_HOST")
      site=LightekPwa::SiteContext.resolve(host)
      owner=User.where(role:"super_admin").order(:id).first
      raise "A platform administrator is required to own starter templates" unless owner
      %w[pebble_scattering cozy_kitchen].each do |key|
        result=Studio::Workers::Workspace.perform("blender_demo_import",user_id:owner.id,site_id:site.id,demo_key:key)
        puts "Studio Blender #{key}: #{result[:status]}"
      end
    end
  end
end
