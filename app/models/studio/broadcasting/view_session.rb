# frozen_string_literal: true

module Studio
  module Broadcasting
    class ViewSession < ApplicationRecord
      self.table_name = "studio_broadcast_view_sessions"
      WINDOW = 60

      # Preserve a small in-memory-sized sequence window per session/context.
      # Retries count once and near-term out-of-order HLS requests still count.
      def record(sequence, media_ms)
        with_lock do
          highest = highest_sequence
          window = sequence_window
          if sequence > highest
            distance = sequence - highest
            window = distance >= WINDOW ? 0 : (window << distance) & ((1 << WINDOW) - 1)
            highest = sequence
          end
          distance = highest - sequence
          return if distance >= WINDOW || (window & (1 << distance)).positive?

          update!(highest_sequence: highest, sequence_window: window | (1 << distance),
            segments: segments + 1, media_ms: self.media_ms + media_ms)
        end
      end
    end
  end
end
