# frozen_string_literal: true
require "net/http"
require "uri"
require "tmpdir"
require "digest"
module Studio
  module NativeBlender
    class DemoImport
      MAX_BYTES=512*1024*1024
      HOSTS=%w[download.blender.org mirror.blender.org].freeze
      def self.call(asset) = new(asset).call
      def initialize(asset) = @asset=asset
      def call
        demo=DemoCatalog.fetch(@asset.metadata.fetch("demo_key"))
        @asset.update!(status:"processing",error_message:nil)
        Dir.mktmpdir("blender-demo-") do |root|
          archive=File.join(root,"download#{File.extname(URI.parse(demo.fetch('url')).path)}")
          self.class.download(demo.fetch("url"),archive)
          bundle_root=File.join(root,"bundle")
          paths=if archive.end_with?(".zip")
            JSON.parse(Studio::MediaProcess.run!(["python3",Rails.root.join("blender/extract_demo.py").to_s,archive,bundle_root],timeout:90))
          else [archive]
          end
          raise ArgumentError,"Demo archive contains too many Blender templates" if paths.length>100
          @asset.bundle.attach(io:File.open(archive,"rb"),filename:"#{demo['key']}.zip",content_type:"application/zip",identify:false) if archive.end_with?(".zip")
          # Archives may contain several independent templates. Preserve the
          # full choice in metadata, and ingest each as its own native asset.
          paths.each_with_index do |path,index|
            target=index.zero? ? @asset : sibling(demo,path,index)
            target.bundle.attach(@asset.bundle.blob) if index>0 && @asset.bundle.attached?
            target.update!(metadata:target.metadata.merge("bundle_relative_source"=>Pathname(path).relative_path_from(Pathname(bundle_root)).to_s)) if archive.end_with?(".zip")
            target.file.attach(io:File.open(path,"rb"),filename:File.basename(path),content_type:"application/x-blender",identify:false)
            target.update!(metadata:target.metadata.merge("source"=>demo,"source_sha256"=>Digest::SHA256.file(archive).hexdigest,"bundle_files"=>paths.map { |p| File.basename(p) }))
            Studio::Assets::Ingestor.call(target,source_path:path,source_root:archive.end_with?(".zip") ? bundle_root : root)
          end
        end
        @asset
      rescue StandardError => error
        @asset.update!(status:"failed",error_message:error.message.to_s.first(1000))
        raise
      end
      def sibling(demo,path,index)
        key="#{@asset.request_key}-#{index}"
        StudioAsset.find_or_create_by!(owner_id:@asset.owner_id,request_key:key) do |asset|
          asset.assign_attributes(site_id:@asset.site_id,name:"#{demo['name']} · #{File.basename(path,'.blend')}".first(160),kind:"blend",status:"processing",metadata:{"demo_key"=>demo["key"],"source"=>demo})
        end
      end
      def self.download(url,path,redirects:3)
        uri=URI.parse(url)
        raise ArgumentError,"Use an official Blender demo download" unless uri.scheme=="https" && HOSTS.include?(uri.host) && uri.userinfo.nil? && uri.port==443
        Net::HTTP.start(uri.host,uri.port,use_ssl:true,open_timeout:15,read_timeout:60) do |http|
          http.request(Net::HTTP::Get.new(uri.request_uri)) do |response|
            if response.is_a?(Net::HTTPRedirection)
              raise ArgumentError,"Too many demo download redirects" if redirects<=0
              return download(URI.join(url,response.fetch('location')).to_s,path,redirects:redirects-1)
            end
            raise "Blender download returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)
            raise "Blender demo exceeds the 512 MB download limit" if response['content-length'].to_i>MAX_BYTES
            total=0
            File.open(path,"wb") do |file|
              response.read_body do |chunk|
                total+=chunk.bytesize
                raise "Blender demo exceeds the 512 MB download limit" if total>MAX_BYTES
                file.write(chunk)
              end
            end
          end
        end
        raise "Blender demo download was empty" unless File.size?(path)
      end
    end
  end
end
