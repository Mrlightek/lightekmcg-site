# frozen_string_literal: true

module Studio
  module Pipeline
    class Runtime
      SCRIPTS = "script/media_pipeline/scripts"

      def self.path(root, name) = Rails.env.production? ? File.join("/work", name) : File.join(root, name)

      def self.blender!(root, script, arguments, role:, timeout:)
        executable = Rails.env.production? ? "blender" : ENV.fetch("BLENDER_BIN", "blender")
        worker_scripts = Rails.env.production? ? "/pipeline" : Rails.root.join(SCRIPTS).to_s
        command = [executable, "--background", "--factory-startup", "--disable-autoexec", "--threads", "2",
          "--python-exit-code", "1", "--python", File.join(worker_scripts, script), "--", *arguments]
        run!(root, command, role: role, timeout: timeout)
      end

      def self.run!(root, command, role:, timeout:)
        if Rails.env.production?
          image = Studio::NativeBlender::Runtime.image(role)
          command = Studio::MediaProcess.container(command, root: root, image: image)
          command.insert(command.index(image), "-v", "#{Rails.root.join(SCRIPTS)}:/pipeline:ro")
        end
        Studio::MediaProcess.run!(command, timeout: timeout)
      end

      def self.copy!(attachment, target)
        FileUtils.mkdir_p(File.dirname(target))
        File.open(target, "wb") { |io| attachment.blob.download { |chunk| io.write(chunk) } }
      end
    end
  end
end
