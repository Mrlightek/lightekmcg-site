# frozen_string_literal: true
require 'digest'
require 'fileutils'
require 'pathname'
module NevaehOs
  module Applications
    module_function
    def recipes(package)
      case package
      when 'ffmpeg'
        {'version'=>{'argv'=>['/usr/bin/ffmpeg','-version'],'inputs'=>{}},
         'probe'=>{'argv'=>['/usr/bin/ffprobe','-v','error','-show_format','-show_streams','-of','json','{input}'],'inputs'=>{'input'=>{'type'=>'file'}}},
         'transcode'=>{'argv'=>['/usr/bin/ffmpeg','-nostdin','-n','-i','{input}','-c:v','libx264','-c:a','aac','{output}'],'inputs'=>{'input'=>{'type'=>'file'},'output'=>{'type'=>'output'}}}}
      when 'blender'
        {'version'=>{'argv'=>['/usr/bin/blender','--version'],'inputs'=>{}}}
      when 'pandoc'
        {'version'=>{'argv'=>['/usr/bin/pandoc','--version'],'inputs'=>{}},
         'convert'=>{'argv'=>['/usr/bin/pandoc','{input}','-o','{output}'],'inputs'=>{'input'=>{'type'=>'file'},'output'=>{'type'=>'output'}}}}
      else
        {} # Unknown applications get documented drafts, not guessed executable flags.
      end
    end
    def setup!(actor,package)
      UbuntuPackages.authorize!(actor)
      install=UbuntuPackages.call(operation:'install',package:package)
      existing=NevaehApplicationAdapter.find_by(user:actor,package:package,status:'active')
      return {'package'=>package,'install'=>install,'adapter_id'=>existing.id,'status'=>'active','message'=>'Package installed; the existing active adapter was preserved.'} if existing
      imported=integrate!(actor,package)
      adapter=NevaehApplicationAdapter.find(imported.fetch('adapter_id'))
      if recipes(package).present? && adapter.operations==recipes(package)
        activation=activate!(adapter,actor)
        verification=run!(adapter:adapter,actor:actor,operation:'version',inputs:{})
        raise ArgumentError,'Installed application failed its version verification' unless verification['success']
        {'package'=>package,'install'=>install,'adapter_id'=>adapter.id,'status'=>'active','operations'=>activation['operations'],'verification'=>verification,'message'=>'Installed, documentation imported, API adapter activated and application version verified.'}
      else
        imported.merge('install'=>install,'message'=>'Installed and documented. This application needs reviewed operation contracts before its API can be activated.')
      end
    end
    def integrate!(actor, package)
      UbuntuPackages.authorize!(actor)
      documents=UbuntuPackages.call(operation:'docs',package:package)
      metadata=UbuntuPackages.call(operation:'show',package:package)
      record=NevaehApplicationAdapter.find_or_initialize_by(user:actor,package:package)
      if record.persisted? && record.status == 'active'
        raise ArgumentError,'This adapter is active. Inspect it before replacing its reviewed definition.'
      end
      record.assign_attributes(name:package.humanize,operations:record.operations.presence || recipes(package),documentation:documents.merge('metadata'=>metadata),status:'draft')
      record.save!
      text=documents.fetch('documents').map { |doc| "## #{doc['path']}\n#{doc['text']}" }.join("\n\n")[0,100000]
      text=metadata['description'].to_s if text.blank?
      if text.present?
        article=Gatekeeper::LessonService.record!(key:"ubuntu-#{package}-#{metadata['installed_version']}".gsub(/[^a-zA-Z0-9_.-]/,'-'),title:"Ubuntu application: #{package}",
          capability:'nevaeh.application.reference',symptom:metadata['summary'].to_s,cause:'Installed Ubuntu package documentation',remediation:text,
          verification:"Installed package #{metadata['installed_version']}; adapter remains draft",metadata:{'package'=>package,'package_version'=>metadata['installed_version'],'auto_executable'=>false})
      end
      {'adapter_id'=>record.id,'package'=>package,'status'=>record.status,'operations'=>record.operations,'knowledge_article_id'=>article&.id,
       'message'=>record.operations.any? ? 'Installed documentation imported. Review the operations and activate the adapter to use its API.' : 'Installed documentation imported. This application needs authored operation contracts; edit application_adapters with the reviewed executable and input schema.'}
    end
    def workspace(actor)
      # Native deployments intentionally symlink Rails storage to shared storage.
      # Trust that configured base, then reject symlinks within application workspaces.
      storage=Rails.root.join('storage')
      FileUtils.mkdir_p(storage) unless storage.exist?
      storage=storage.realpath
      root=storage.join('nevaeh_applications',actor.id.to_s)
      cursor=storage
      root.relative_path_from(storage).each_filename do |part|
        cursor=cursor.join(part)
        raise ArgumentError,'Application workspace contains a symlink' if cursor.symlink?
      end
      FileUtils.mkdir_p(root,mode:0o700)
      root.realpath
    end
    def checked_path(root,name,existing:)
      raise ArgumentError,'Use a relative workspace filename' unless name.is_a?(String) && name.match?(%r{\A[a-zA-Z0-9][a-zA-Z0-9_. /-]{0,200}\z}) && name.split('/').none? { |v| %w[. ..].include?(v) }
      path=root.join(name);cursor=root
      name.split('/').each do |part|
        cursor=cursor.join(part)
        raise ArgumentError,'Symlinks are not accepted as application inputs or outputs' if cursor.symlink?
      end
      raise ArgumentError,'Input is missing from your application workspace' if existing && !path.file?
      raise ArgumentError,'Output parent directory is missing' unless path.dirname.directory?
      raise ArgumentError,'Output file already exists; choose a new name' if !existing && path.exist?
      path.to_s
    end
    def validate!(adapter)
      operations=adapter.operations
      raise ArgumentError,'Define 1–30 application operations' unless operations.is_a?(Hash) && operations.length.between?(1,30)
      binaries=Array(adapter.documentation['binaries'])
      operations.each do |name,definition|
        raise ArgumentError,'Invalid operation name' unless name.match?(/\A[a-z][a-z0-9_.-]{0,60}\z/)
        raise ArgumentError,'Operations require argv and inputs only' unless definition.is_a?(Hash) && definition.keys.sort == %w[argv inputs]
        argv=definition['argv'];inputs=definition['inputs']
        raise ArgumentError,'argv must contain 1–40 fixed arguments' unless argv.is_a?(Array) && argv.length.between?(1,40) && argv.all? { |v| v.is_a?(String) && v.bytesize <= 2000 && !v.include?("\x00") }
        binary=argv.first
        raise ArgumentError,'Executable must be owned by the installed package' unless binaries.include?(binary) && binary.start_with?('/usr/bin/','/usr/sbin/','/bin/','/sbin/')
        stat=File.stat(binary)
        raise ArgumentError,'Executable must be root-owned and not writable by the application' unless stat.uid.zero? && (stat.mode & 0o022).zero? && File.executable?(binary)
        raise ArgumentError,'Use up to 20 typed inputs' unless inputs.is_a?(Hash) && inputs.size <= 20
        inputs.each do |key,schema|
          raise ArgumentError,'Invalid input schema' unless key.match?(/\A[a-z][a-z0-9_]{0,40}\z/) && schema.is_a?(Hash) && (schema.keys - %w[type values min max]).empty? && %w[file output integer enum].include?(schema['type'])
          if schema['type']=='enum'
            raise ArgumentError,'Enum values must be explicit non-option strings' unless schema['values'].is_a?(Array) && schema['values'].length.between?(1,30) && schema['values'].all? { |v| v.is_a?(String) && v.match?(/\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,60}\z/) }
          end
        end
        placeholders=argv.drop(1).filter_map { |v| v.match(/\A\{([a-z][a-z0-9_]*)\}\z/)&.[](1) }
        raise ArgumentError,'Placeholders must match the declared inputs' unless placeholders.uniq.sort==inputs.keys.sort
        raise ArgumentError,'Inputs must be whole arguments' if argv.drop(1).any? { |v| v.include?('{') && !v.match?(/\A\{[a-z][a-z0-9_]*\}\z/) }
      end
      true
    rescue Errno::ENOENT
      raise ArgumentError,'An adapter executable is not installed'
    end
    def activate!(adapter,actor)
      UbuntuPackages.authorize!(actor)
      validate!(adapter)
      # Activation validates the contracts. It never executes arbitrary operations.
      fingerprint=Digest::SHA256.hexdigest(JSON.generate(adapter.operations))
      adapter.update!(status:'active',verification:{'sha256'=>fingerprint,'verified_at'=>Time.current.iso8601,'actor_id'=>actor.id})
      {'adapter_id'=>adapter.id,'status'=>'active','operations'=>adapter.operations.keys,'sha256'=>fingerprint}
    end
    def run!(adapter:,actor:,operation:,inputs:)
      UbuntuPackages.authorize!(actor)
      adapter.with_lock do
        raise ArgumentError,'Activate the reviewed application adapter first' unless adapter.status=='active'
        raise ArgumentError,'Application definition changed since activation' unless adapter.verification['sha256']==Digest::SHA256.hexdigest(JSON.generate(adapter.operations))
        validate!(adapter)
        definition=adapter.operations.fetch(operation) { raise ArgumentError,'Unknown application operation' }
        raise ArgumentError,'Inputs must exactly match this operation schema' unless inputs.is_a?(Hash) && inputs.keys.sort==definition['inputs'].keys.sort
        root=workspace(actor)
        values=definition['inputs'].to_h do |key,schema|
          value=inputs[key]
          parsed=case schema['type']
          when 'file','output' then checked_path(root,value,existing:schema['type']=='file')
          when 'integer'
            raise ArgumentError,'Integer input is outside its range' unless value.is_a?(Integer) && value.between?(schema.fetch('min',0),schema.fetch('max',1000000))
            value.to_s
          when 'enum'
            raise ArgumentError,'Choose one of the enumerated values' unless schema['values'].include?(value)
            value
          end
          [key,parsed]
        end
        argv=definition['argv'].map { |arg| (m=arg.match(/\A\{([a-z][a-z0-9_]*)\}\z/)) ? values.fetch(m[1]) : arg }
        result=ProcessRunner.call(argv,directory:root)
        result.merge('package'=>adapter.package,'operation'=>operation,'adapter_id'=>adapter.id,'outputs'=>definition['inputs'].select { |_,s| s['type']=='output' }.keys.map { |key| inputs[key] })
      end
    end
  end
end
