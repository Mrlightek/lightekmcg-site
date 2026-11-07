require "tmpdir"
module Studio
  module Assets
    class BundleImport
      def self.call(asset)
        asset.update!(status:"processing",error_message:nil)
        archive=asset.file.blob
        Dir.mktmpdir("studio-upload-bundle-") do |root|
          archive.open do |file|
            folder=File.join(root,"bundle")
            paths=JSON.parse(Studio::MediaProcess.run!(["python3",Rails.root.join("blender/extract_demo.py").to_s,file.path,folder],timeout:90))
            raise ArgumentError,"Choose an archive with at most 20 Blender files" if paths.length>20
            paths.each_with_index do |path,index|
              target=index.zero? ? asset : StudioAsset.find_or_initialize_by(owner_id:asset.owner_id,request_key:"#{asset.request_key}-bundle-#{index}")
              next if index>0 && target.persisted? && target.status=="ready"
              target.assign_attributes(site_id:asset.site_id,name:index.zero? ? asset.name : File.basename(path).first(160),kind:"blend",status:"processing")
              target.metadata=target.metadata.merge("bundle_relative_source"=>Pathname(path).relative_path_from(Pathname(folder)).to_s,"uploaded_bundle"=>true)
              target.bundle.attach(archive)
              target.file.attach(io:File.open(path,"rb"),filename:File.basename(path),content_type:"application/x-blender",identify:false)
              target.save!
              Ingestor.call(target,source_path:path,source_root:folder)
            end
          end
        end
        asset
      rescue StandardError=>error
        asset.update!(status:"failed",error_message:error.message.to_s.first(1000))
        raise
      end
    end
  end
end
