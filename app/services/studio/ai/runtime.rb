# frozen_string_literal: true
require "net/http"
require "uri"
require "json"
module Studio
  module Ai
    # This adapter talks to a local engine or a site-owned managed worker. The browser
    # cannot supply URLs, graphs, model paths or output filenames.
    class Runtime
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
      def request(path,payload:nil,limit:5.megabytes)
        uri=@origin.dup;requested_path,uri.query=path.split("?",2);uri.path=@origin.path.delete_suffix("/")+requested_path
        request=payload ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
        request["Authorization"]="Bearer #{@token}" if @token
        if payload
          request["Content-Type"]="application/json";request.body=JSON.generate(payload)
        end
        result="".b
        Net::HTTP.start(uri.hostname,uri.port,nil,use_ssl:uri.scheme=="https",open_timeout:3,read_timeout:20) do |http|
          http.request(request) do |response|
            raise ArgumentError,"The local AI engine rejected this operation (#{response.code})" unless response.is_a?(Net::HTTPSuccess)
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
      def inventory
        nodes=json("/object_info")
        raise ArgumentError,"Invalid local engine inventory" unless nodes.is_a?(Hash)
        models=Array(nodes.dig("CheckpointLoaderSimple","input","required","ckpt_name",0))
        available=recipes.map do |recipe|
          missing=recipe["workflow"].values.map{|n|n.fetch("class_type")}.uniq.reject{|name|nodes.key?(name)}
          needs_checkpoint=recipe["workflow"].values.any?{|n|n.dig("inputs","ckpt_name")=="$checkpoint"}
          missing_models=Array(recipe["required_models"]).reject do |spec|
            Array(nodes.dig(spec["node"],"input","required",spec["field"],0)).include?(spec["name"])
          end
          {id:recipe["id"],name:recipe["name"],kind:recipe["kind"],ready:missing.empty? && missing_models.empty? && (!needs_checkpoint || models.any?),reason:missing.any? ? "Required engine nodes are not installed" : missing_models.any? ? "Required workflow models are not installed" : needs_checkpoint && models.empty? ? "Install a local checkpoint on the generation worker" : nil}
        end
        {connected:true,engine:"Self-hosted ComfyUI",recipes:available,models:models}
      rescue SystemCallError,SocketError,Timeout::Error,IOError,OpenSSL::SSL::SSLError,ArgumentError,JSON::ParserError
        {connected:false,engine:"Self-hosted ComfyUI",recipes:[],models:[],reason:"No ready local generation worker. Engine and model installation must be completed before generation is available."}
      end
      def graph(recipe_id,prompt:,negative:,seed:,model:)
        recipe=recipes.find{|r|r["id"]==recipe_id} || raise(ArgumentError,"Choose an installed AI workflow")
        values={"$prompt"=>prompt,"$negative"=>negative,"$seed"=>seed,"$checkpoint"=>model}
        graph=recipe.fetch("workflow").deep_dup
        graph.each_value do |node|
          node.fetch("inputs").transform_values!{|value|values.fetch(value,value)}
        end
        [recipe,graph]
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
