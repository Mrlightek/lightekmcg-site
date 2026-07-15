# frozen_string_literal: true

namespace :marlon do
  namespace :meta do
    desc "Seed the Marlon meta-framework catalog"
    task seed: :environment do
      load Rails.root.join("db/seeds/marlon_meta_framework.rb")
    end

    desc "Validate capability-pack dependencies"
    task validate: :environment do
      Marlon::CapabilityPack.find_each do |pack|
        Marlon::Blueprint::Resolver.new([pack]).resolve
      end
      puts "Marlon capability graph is valid"
    end

    desc "Print a project blueprint; PROJECT_TYPE=managed_it_services"
    task inspect: :environment do
      key = ENV.fetch("PROJECT_TYPE", "managed_it_services")
      project_type = Marlon::ProjectType.find_by!(key: key)
      blueprint = Marlon::Blueprint::Compiler.new(project_type: project_type).call
      puts JSON.pretty_generate(blueprint)
    end
  end
end
