# frozen_string_literal: true
require "net/http"
require "uri"
require "json"
require "stringio"
module Studio
  module Ai
    # This adapter talks to a local engine or a site-owned managed worker. The browser
    # cannot supply URLs, graphs, model paths or output filenames.
    class Runtime
      LOCAL_WORKER_ID = "local"
      SD15_CHECKPOINT = /sd[-_. ]?1[-_. ]?5|v1[-_.]5/i
      class EngineResponseError < ArgumentError
        attr_reader :status
        def initialize(status)
          @status = Integer(status)
          super("ComfyUI returned HTTP #{@status}")
        end
      end

      def self.selection_id(identity)
        identity["installation_id"] || (LOCAL_WORKER_ID if identity["mode"] == "local")
      end

      def initialize(site:nil, identity:nil)
        identity ||= site&.manifest.to_h&.fetch("studio_ai_worker",nil)
        if identity && identity["mode"]!="local"
          url,@token=Setup.connection(site,identity)
          @origin=URI(url)
          raise ArgumentError,"Invalid managed worker origin" unless @origin.scheme=="https" && @origin.userinfo.nil? && @origin.query.nil? && @origin.fragment.nil? && @origin.path=="/lightek-ai" && @origin.hostname.to_s.match?(/\A[a-zA-Z0-9.-]+\z/)
        else
          @origin=URI(ENV.fetch("STUDIO_AI_URL","http://127.0.0.1:8188"))
          raise ArgumentError,"Studio AI must use a local engine" unless %w[http https].include?(@origin.scheme) && %w[127.0.0.1 localhost ::1].include?(@origin.hostname) && @origin.userinfo.nil? && @origin.query.nil? && @origin.fragment.nil? && ["","/"].include?(@origin.path)
        end
      end
      def request(path,payload:nil,form:nil,limit:5.megabytes)
        uri=@origin.dup;requested_path,uri.query=path.split("?",2);uri.path=@origin.path.delete_suffix("/")+requested_path
        request=payload || form ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
        request["Authorization"]="Bearer #{@token}" if @token
        if payload
          request["Content-Type"]="application/json";request.body=JSON.generate(payload)
        end
        request.set_form(form,"multipart/form-data") if form
        result="".b
        Net::HTTP.start(uri.hostname,uri.port,nil,use_ssl:uri.scheme=="https",open_timeout:3,read_timeout:20) do |http|
          http.request(request) do |response|
            raise EngineResponseError,response.code unless response.is_a?(Net::HTTPSuccess)
            response.read_body do |chunk|
              result<<chunk
              raise ArgumentError,"AI result exceeds the supported size" if result.bytesize>limit
            end
          end
        end
        result
      end
      def json(path,payload:nil)=JSON.parse(request(path,payload:payload))
      def recipes
        Dir[Rails.root.join("config/studio_ai/workflows/*.json")].sort.map do |file|
          recipe=JSON.parse(File.read(file))
          raise ArgumentError,"Invalid installed AI recipe" unless recipe["id"].to_s.match?(/\A[a-z0-9_-]+\z/) && %w[image video audio glb].include?(recipe["kind"]) && recipe["workflow"].is_a?(Hash)
          recipe
        end
      end
      def inventory(telemetry:false)
        nodes=json("/object_info")
        raise ArgumentError,"Invalid local engine inventory" unless nodes.is_a?(Hash)
        models=Array(nodes.dig("CheckpointLoaderSimple","input","required","ckpt_name",0))
        available=recipes.map do |recipe|
          missing=recipe["workflow"].values.map{|n|n.fetch("class_type")}.uniq.reject{|name|nodes.key?(name)}
          missing_inputs=Array(recipe["required_inputs"]).any?{|spec| !(nodes.dig(spec["node"],"input","required") || {}).key?(spec["field"]) && !(nodes.dig(spec["node"],"input","optional") || {}).key?(spec["field"])}
          needs_checkpoint=recipe["workflow"].values.any?{|n|n.dig("inputs","ckpt_name")=="$checkpoint"}
          missing_models=Array(recipe["required_models"]).reject do |spec|
            Array(nodes.dig(spec["node"],"input","required",spec["field"],0)).include?(spec["name"])
          end
          {id:recipe["id"],name:recipe["name"],kind:recipe["kind"],input_kind:recipe["input_kind"],steps:recipe_steps(recipe),ready:!missing_inputs && missing.empty? && missing_models.empty? && (!needs_checkpoint || models.any?),reason:missing_inputs ? "Required image-conditioning inputs are not available on this engine" : missing.any? ? "Required engine nodes are not installed" : missing_models.any? ? "Required workflow models are not installed" : needs_checkpoint && models.empty? ? "Install a local checkpoint on the generation worker" : nil}
        end
        workflow_nodes=%w[LightekStudioJob LightekBlenderRender LightekFFmpegAssembly LightekStudioResult]
        workflow_ready=workflow_nodes.all? { |name| nodes.key?(name) }
        {connected:true,engine:"Self-hosted ComfyUI",recipes:available,models:models,device:telemetry ? device_status : nil,
          workflow:{ready:workflow_ready,reason:workflow_ready ? nil : "Install the trusted Lightek workflow node package on this ComfyUI worker."}}
      rescue SystemCallError,SocketError,Timeout::Error,IOError,OpenSSL::SSL::SSLError,ArgumentError,JSON::ParserError,TypeError,KeyError => error
        code,reason=case error
        when EngineResponseError
          if [401,403].include?(error.status)
            ["engine_authentication","ComfyUI rejected Studio's authentication. An infrastructure operator must repair the saved worker credential or proxy access."]
          elsif error.status==404
            ["engine_route_missing","The configured worker responded, but its ComfyUI API route was not found. Check the worker proxy and API address."]
          else
            ["engine_http_error","The configured ComfyUI service returned HTTP #{error.status}. Check the service and its proxy."]
          end
        when Errno::ECONNREFUSED
          ["engine_connection_refused","The configured ComfyUI connection was refused. Check that ComfyUI is running and listening on the address and port used by the Rails application."]
        when Timeout::Error
          ["engine_timeout","The configured ComfyUI service timed out. Check worker health and network reachability from the Rails application."]
        when SocketError
          ["engine_dns_error","Rails could not resolve the configured ComfyUI worker. Check the worker hostname and DNS."]
        when OpenSSL::SSL::SSLError
          ["engine_tls_error","Rails could not verify the ComfyUI worker's HTTPS connection. Check its certificate and proxy."]
        when JSON::ParserError
          ["engine_invalid_json","The ComfyUI inventory response or installed workflow is not valid JSON. Check that the configured route serves the ComfyUI API."]
        when ArgumentError,TypeError,KeyError
          ["engine_inventory_invalid","Studio could not read the ComfyUI inventory or installed workflow definitions. Check the API and deployed workflow files."]
        else
          ["engine_connection_error","The ComfyUI connection was interrupted. Check worker health and the connection from Rails."]
        end
        {connected:false,engine:"Self-hosted ComfyUI",recipes:[],models:[],reason_code:code,reason:reason}
      end
      def recipe_steps(recipe)
        recipe.fetch("workflow").values.find { |node| node["class_type"]=="KSampler" }&.dig("inputs","steps")
      end

      def device_status
        stats=JSON.parse(request("/system_stats",limit:128.kilobytes))
        device=Array(stats["devices"]).find { |item| item.is_a?(Hash) && %w[cuda cpu mps xpu].include?(item["type"]) }
        return unless device
        total,free=device.values_at("vram_total","vram_free")
        memory=device["type"]!="cpu" && total.is_a?(Integer) && free.is_a?(Integer) && total.positive? && free.between?(0,total)
        {type:device["type"],vram_total:memory ? total : nil,vram_free:memory ? free : nil}
      rescue SystemCallError,SocketError,Timeout::Error,IOError,OpenSSL::SSL::SSLError,ArgumentError,JSON::ParserError,TypeError
        nil
      end

      def graph(recipe_id,prompt:,negative:,seed:,model:,steps:nil)
        recipe=recipes.find{|r|r["id"]==recipe_id} || raise(ArgumentError,"Choose an installed AI workflow")
        values={"$prompt"=>prompt,"$negative"=>negative,"$seed"=>seed,"$checkpoint"=>model}
        graph=recipe.fetch("workflow").deep_dup
        graph.each_value do |node|
          node.fetch("inputs").transform_values!{|value|values.fetch(value,value)}
        end
        if steps
          raise ArgumentError,"This workflow uses fixed sampling steps" unless recipe_steps(recipe)
          graph.each_value do |node|
            node["inputs"]["steps"]=steps if node["class_type"]=="KSampler"
          end
        end
        [recipe,graph]
      end
      def upload_image(bytes,filename:)
        raise ArgumentError,"Invalid prepared starting image" unless bytes.bytesize<=10.megabytes && bytes.start_with?("\x89PNG\r\n\x1a\n".b) && filename.match?(/\Alightek-[a-zA-Z0-9_-]+\.png\z/)
        form=[["image",StringIO.new(bytes),{filename:filename,content_type:"image/png"}],["type","input"],["subfolder","lightek"],["overwrite","false"]]
        result=JSON.parse(request("/upload/image",form:form,limit:16.kilobytes))
        raise ArgumentError,"The engine did not confirm the starting image" unless result["name"]==filename && result["subfolder"]=="lightek" && result["type"]=="input"
        "lightek/#{filename}"
      end
      def submit(graph)
        id=json("/prompt",payload:{prompt:graph}).fetch("prompt_id").to_s
        raise ArgumentError,"Local engine returned an invalid job ID" unless id.match?(/\A[a-zA-Z0-9_-]{1,100}\z/)
        id
      end
      def result(prompt_id)=json("/history/#{URI.encode_www_form_component(prompt_id)}")[prompt_id]
      def download(output)
        name=output.fetch("filename");folder=output.fetch("subfolder","")
        raise ArgumentError,"Invalid generated output path" unless name.is_a?(String) && folder.is_a?(String) && name.match?(/\A[^\\\/\x00]+\z/) && !name.include?("..") && !folder.start_with?("/","\\") && !folder.split(/[\\\/]/).include?("..") && !folder.include?("\x00")
        query=URI.encode_www_form(filename:name,subfolder:folder,type:"output")
        request("/view?#{query}",limit:250.megabytes)
      end
    end
  end
end
