# frozen_string_literal: true
class Api::Lightek::Pwa::StudioWorkflowsController < ActionController::API
  # Stateless MCP Streamable HTTP, protocol 2025-06-18. The Bearer token is
  # restricted to one existing operation; it grants no general Studio access.
  def mcp
    raise ActiveRecord::RecordNotFound unless request.authorization.to_s.start_with?("Bearer ")
    operation=Studio::Workflows::Production.authorize!(params[:id],request.authorization.to_s.delete_prefix("Bearer "))
    origin=request.headers["Origin"]
    return head :forbidden if origin.present? && origin!="https://#{operation.studio_project.site.host}"
    return head :payload_too_large if request.raw_post.bytesize>16_384
    rpc=JSON.parse(request.raw_post)
    return render(json:{jsonrpc:"2.0",id:nil,error:{code:-32600,message:"Invalid request"}},status: :bad_request) unless rpc.is_a?(Hash) && rpc["jsonrpc"]=="2.0"
    return head :accepted if rpc["method"]=="notifications/initialized" && !rpc.key?("id")
    return head :accepted unless rpc.key?("id")
    data=case rpc["method"]
    when "initialize"
      {protocolVersion:"2025-06-18",capabilities:{tools:{listChanged:false}},serverInfo:{name:"lightek-studio-workflow",version:"1.0.0"}}
    when "tools/list"
      {tools:Studio::Workflows::Production::TOOLS.map { |name,description| {name:name,description:description,inputSchema:{type:"object",properties:{},additionalProperties:false}} }}
    when "tools/call"
      input=rpc.fetch("params")
      raise TypeError,"Invalid params" unless input.is_a?(Hash)
      begin
        result=Studio::Workflows::Production.tool(operation,input.fetch("name"),input.fetch("arguments",{}))
        {content:[{type:"text",text:JSON.generate(result)}],structuredContent:result,isError:false}
      rescue StandardError=>error
        message=if error.is_a?(ArgumentError)
          error.message.first(300)

        else
          "This job's workflow step failed. Check the CPU worker and its operation status."
        end
        operation.with_lock { operation.update!(status:"failed",error_message:message) unless operation.terminal? }
        {content:[{type:"text",text:message}],isError:true}
      end
    else
      return render json:{jsonrpc:"2.0",id:rpc["id"],error:{code:-32601,message:"Method not found"}}
    end
    render json:{jsonrpc:"2.0",id:rpc["id"],result:data}
  rescue JSON::ParserError
    render json:{jsonrpc:"2.0",id:nil,error:{code:-32700,message:"Parse error"}},status: :bad_request
  rescue KeyError,TypeError
    render json:{jsonrpc:"2.0",id:nil,error:{code:-32602,message:"Invalid params"}},status: :bad_request
  rescue ActiveRecord::RecordNotFound, LightekPwa::Policy::Denied
    head :forbidden
  end
end
