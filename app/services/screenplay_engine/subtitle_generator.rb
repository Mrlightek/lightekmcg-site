require 'json'
require 'time'

module ScreenplayEngine
  class SubtitleGenerator
    # Converts frame numbers to SRT timecode format (HH:MM:SS,ms)
    def self.frame_to_srt_time(frame, fps = 30)
      total_seconds = frame.to_f / fps
      hours = (total_seconds / 3600).floor
      minutes = ((total_seconds % 3600) / 60).floor
      seconds = (total_seconds % 60).floor
      milliseconds = ((total_seconds - total_seconds.floor) * 1000).round

      format("%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    end

    # Builds a standard .srt file from your script lines
    def self.export_srt(script_lines, output_file = "scene_captions.srt", fps = 30)
      srt_content = []

      script_lines.each_with_index do |line, index|
        start_frame = line[:start_frame]
        # Calculate duration based on word count (minimum 36 frames)
        word_count = line[:text].split.size
        duration_frames = [word_count * 6, 36].max 
        end_frame = start_frame + duration_frames

        start_timecode = frame_to_srt_time(start_frame, fps)
        end_timecode = frame_to_srt_time(end_frame, fps)

        srt_content << (index + 1).to_s
        srt_content << "#{start_timecode} --> #{end_timecode}"
        srt_content << "#{line[:speaker].upcase}: #{line[:text]}"
        srt_content << "" # Empty line separator required by SRT spec
      end

      File.write(output_file, srt_content.join("\n"))
      puts "Successfully generated subtitle overlay: #{output_file}"
    end
  end
end