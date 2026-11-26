module Studio
  module RecipeProtocol
    class EffectCraftSession
      def self.arguments(source, destination)
        arguments = ["mcp"]
        arguments += ["--automation-read-root", File.dirname(source)] if source
        arguments += ["--automation-write-root", File.dirname(destination)] if destination
        arguments
      end

      def initialize(transport)
        @transport = transport
        @id = 0
      end

      def start(source)
        request("initialize", {
          "protocolVersion" => "2024-11-05", "capabilities" => {},
          "clientInfo" => {"name" => "lightek-studio", "version" => "1"}
        })
        @transport.write_json({"jsonrpc" => "2.0", "method" => "notifications/initialized"})
        tool("open_project", source ? {"path" => source} : {"new" => true})
      end

      def execute(command, params)
        tool("execute_command", {"command" => command, "params" => params})
      end

      def save(destination)
        tool("save_project", {"path" => destination})
      end

      def available_commands
        @transport.step(step_index: nil, command: "available_commands") do
          commands = tool("list_commands", {"schemas" => true})
          unless commands.is_a?(Array) && commands.all? { |entry| entry.is_a?(Hash) && entry["id"].is_a?(String) }
            raise RecipeSession::ProtocolError, "Invalid EffectCraft command registry"
          end

          commands.to_h { |entry| [entry.fetch("id"), entry.slice("params", "schema")] }
        end
      end

      private

      def tool(name, arguments)
        result = request("tools/call", {"name" => name, "arguments" => arguments})
        content = result["content"] if result.is_a?(Hash)
        if content.is_a?(Array)
          part = content.find { |item| item.is_a?(Hash) && item["type"] == "text" && item["text"].is_a?(String) }
          text = part&.fetch("text")
        end
        raise RecipeSession::ProtocolError, text || "Invalid EffectCraft result for #{name}" if !text || result["isError"]

        JSON.parse(text)
      end

      def request(method, params)
        @id += 1
        @transport.write_json({"jsonrpc" => "2.0", "id" => @id, "method" => method, "params" => params})
        loop do
          reply = @transport.read_json
          unless reply.is_a?(Hash) && reply["jsonrpc"] == "2.0"
            raise RecipeSession::ProtocolError, "Invalid EffectCraft envelope for #{method}"
          end
          next if !reply.key?("id") && reply["method"].is_a?(String)

          unless reply["id"] == @id
            raise RecipeSession::ProtocolError, "Unexpected EffectCraft reply ID for #{method}"
          end
          if reply["error"].is_a?(Hash)
            raise RecipeSession::ProtocolError, reply["error"].fetch("message", "EffectCraft rejected #{method}")
          end
          raise RecipeSession::ProtocolError, "Missing EffectCraft result for #{method}" unless reply.key?("result")

          return reply.fetch("result")
        end
      end
    end
  end
end
