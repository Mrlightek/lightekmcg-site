# frozen_string_literal: true

module Studio
  module Pipeline
    class CharacterAnimation
      CAPABILITY = "studio.pipeline.character_animation"
      QUEUE_RETRY_AFTER = 2.minutes
      MAX_FRAMES = 900
      RESOLUTIONS = {"640x360" => "640 × 360", "1280x720" => "1280 × 720", "720x720" => "720 × 720"}.freeze
      DEFAULTS = {
        "gender" => 0.5, "height" => 0.5, "muscle" => 0.5, "animation" => "Walking",
        "animation_id" => "", "frames" => 30, "resolution" => "640x360"
      }.freeze
      LOGIN_COMMAND = "cd ~/mixamo-mcp && python main.py"

      def initialize(access)
        @access = access
      end

      def operations
        StudioOperation.where(capability: CAPABILITY,
          studio_project_id: StudioProject.where(owner: @access.user, site: @access.site))
      end

      def launch(inputs)
        settings = validate(inputs)
        operation = @access.user.with_lock do
          project = StudioProject.find_or_create_by!(owner: @access.user, site: @access.site, name: "Pipeline Hub")
          project.studio_operations.create!(capability: CAPABILITY, operation_type: "character_animation",
            provider: "blender", intent: {"user_id" => @access.user.id}, manifest: settings,
            metadata: {"attempt" => 1, "mode" => "full"})
        end
        enqueue(operation, 1)
      end

      def self.queue_retry_available?(operation)
        operation.status == "pending" && operation.updated_at <= QUEUE_RETRY_AFTER.ago
      end

      def retry_queued(operation, expected_attempt)
        attempt = operation.with_lock do
          unless self.class.queue_retry_available?(operation) && operation.metadata["attempt"].to_s == expected_attempt
            raise ArgumentError, "This queued attempt has changed. Check the current job status."
          end
          operation.update!(error_message: nil, updated_at: Time.current)
          operation.metadata.fetch("attempt")
        end
        enqueue(operation, attempt, queued_retry: true)
      end

      def retry_login(operation)
        resubmit(operation, "full") do
          raise ArgumentError, "The job is not waiting for a Mixamo login" unless operation.status == "awaiting_manual_login"
          operation.manifest
        end
      end

      def render_only(operation, inputs)
        resubmit(operation, "render-only") do
          unless operation.status.in?(%w[completed failed]) && self.class.file(operation, "package")
            raise ArgumentError, "Render-only requires a finished attempt and a downloaded animated FBX"
          end
          validate(operation.manifest.merge(inputs.slice("frames", "resolution")))
        end
      end

      def self.status_label(operation)
        case operation.status
        when "pending" then "Queued"
        when "awaiting_manual_login" then "Waiting for studio operator"
        else operation.status.humanize
        end
      end

      def self.file(operation, kind)
        artifact = operation.artifacts.where(kind: kind).order(id: :desc).first
        artifact.file if artifact&.file&.attached?
      end

      private

      def resubmit(operation, mode)
        attempt = operation.with_lock do
          settings = yield
          next_attempt = operation.metadata.fetch("attempt") + 1
          operation.update!(status: "pending", started_at: nil, completed_at: nil, error_message: nil,
            manifest: settings, metadata: operation.metadata.merge("attempt" => next_attempt, "mode" => mode))
          next_attempt
        end
        enqueue(operation, attempt)
      end

      def enqueue(operation, attempt, queued_retry: false)
        return operation if AnimationPipelineJob.perform_later(operation.id, attempt)

        mark_queue_failure(operation, attempt, queued_retry: queued_retry)
      rescue ActiveJob::EnqueueError, RedisClient::Error
        mark_queue_failure(operation, attempt, queued_retry: queued_retry)
      end

      def mark_queue_failure(operation, attempt, queued_retry:)
        operation.with_lock do
          if operation.status == "pending" && operation.metadata["attempt"] == attempt
            mode = operation.metadata["mode"]
            state = if queued_retry
              "pending"
            elsif mode == "full" && attempt > 1
              "awaiting_manual_login"
            else
              "failed"
            end
            operation.update!(status: state, error_message: "The Studio worker queue could not accept this attempt.")
          end
        end
        operation
      end

      def validate(inputs)
        settings = DEFAULTS.merge(inputs)
        %w[gender height muscle].each do |name|
          number = Float(settings.fetch(name), exception: false)
          unless number && number.finite? && number.between?(0, 1)
            raise ArgumentError, "#{name.humanize} must be between 0 and 1"
          end
          settings[name] = number
        end
        title = settings.fetch("animation").to_s.strip
        if title.empty? || title.length > 120 || title.match?(/[[:cntrl:]]/)
          raise ArgumentError, "Enter an animation name of 1 to 120 characters"
        end
        id = settings.fetch("animation_id").to_s.strip
        raise ArgumentError, "Enter an animation ID of 1 to 20 digits" unless id.empty? || id.match?(/\A[0-9]{1,20}\z/)

        count = Integer(settings.fetch("frames").to_s, 10, exception: false)
        unless count&.between?(1, MAX_FRAMES)
          raise ArgumentError, "Enter a frame count between 1 and #{MAX_FRAMES}"
        end
        raise ArgumentError, "Select a supported resolution" unless RESOLUTIONS.key?(settings["resolution"])

        settings.merge("animation" => title, "animation_id" => id, "frames" => count)
      end
    end
  end
end
