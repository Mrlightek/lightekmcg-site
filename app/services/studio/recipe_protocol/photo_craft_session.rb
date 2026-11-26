module Studio
  module RecipeProtocol
    class PhotoCraftSession
      def self.arguments(source, destination)
        raise ArgumentError, "PhotoCraft requires an input image" if destination && !source

        arguments = ["serve", "--no-gpu"]
        arguments += ["--automation-read-root", File.dirname(source)] if source
        arguments += ["--automation-write-root", File.dirname(destination)] if destination
        arguments
      end

      def initialize(transport)
        @transport = transport
        @id = 0
      end

      def start(source)
        request("doc.open", {"path" => source}) if source
      end

      def execute(command, params)
        request("engine.execute", {"command" => command, "params" => params})
      rescue RecipeSession::ProtocolError => error
        # PhotoCraft's session clears the selection when it creates the layer mask.
        raise unless command == "select.deselect" &&
          error.message == "command `select.deselect` is not available right now: no selection"

        nil
      end

      def save(destination)
        request("doc.save", {"path" => destination})
      end

      def available_commands
        @transport.step(step_index: nil, command: "available_commands") do
          commands = request("engine.commands", {})
          unless commands.is_a?(Array) && commands.all? { |entry| entry.is_a?(Hash) && entry["id"].is_a?(String) }
            raise RecipeSession::ProtocolError, "Invalid PhotoCraft command registry"
          end

          commands.to_h { |entry| [entry.fetch("id"), entry.slice("params")] }
        end
      end

      private

      def request(method, params)
        @id += 1
        @transport.write_json({"id" => @id, "method" => method, "params" => params})
        reply = @transport.read_json
        unless reply.is_a?(Hash) && reply["id"] == @id && reply["ok"] == true && reply.key?("result")
          message = reply["error"] if reply.is_a?(Hash) && reply["id"] == @id && reply["ok"] == false
          raise RecipeSession::ProtocolError, message || "Invalid PhotoCraft reply for #{method}"
        end

        reply.fetch("result")
      end
    end
  end
end
