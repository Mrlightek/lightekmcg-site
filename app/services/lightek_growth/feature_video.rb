require 'json'
module LightekGrowth
  class FeatureVideo
    # Captioned animated overview; it does not pretend to show recorded UI use.
    def self.render!(title:, body:, directory:)
      font = '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
      raise ArgumentError, 'Install the DejaVu Sans font before rendering feature videos' unless Rails.env.production? || File.file?(font)
      wrap = ->(text, width) { text.split.flat_map { |word| word.scan(/.{1,#{width}}/) }.each_with_object(['']) { |word, lines| lines.last.length + word.length + 1 <= width ? lines[-1] = [lines.last, word].reject(&:empty?).join(' ') : lines << word }.join("\n") }
      title_file = File.join(directory, 'title.txt'); body_file = File.join(directory, 'body.txt'); output = File.join(directory, 'feature.mp4')
      File.write(title_file, wrap.call(title, 32)); File.write(body_file, wrap.call(body, 65))
      escape = ->(path) { path.gsub('\\', '\\\\').gsub(':', '\\:').gsub("'", "'\\\\''") }
      filter = "drawbox=x=0:y=0:w=16:h=ih:color=0xbca5ff:t=fill,drawtext=fontfile='#{font}':textfile='#{escape.call(title_file)}':expansion=none:fontcolor=white:fontsize=42:x=64:y=105,drawtext=fontfile='#{font}':textfile='#{escape.call(body_file)}':expansion=none:fontcolor=0xd7cfee:fontsize=24:line_spacing=12:x=64:y=270,drawtext=fontfile='#{font}':text='FEATURE OVERVIEW':fontcolor=0xbca5ff:fontsize=16:x=64:y=45,fade=t=in:st=0:d=0.5,fade=t=out:st=11.5:d=0.5"
      run!(['ffmpeg','-nostdin','-y','-v','error','-f','lavfi','-i','color=c=0x191421:s=960x540:r=24:d=12','-vf',filter,'-an','-c:v','libx264','-preset','ultrafast','-threads','1','-pix_fmt','yuv420p','-movflags','+faststart',output], directory: directory, timeout: 90)
      probe = JSON.parse(run!(['ffprobe','-v','error','-show_streams','-show_format','-of','json',output], directory: directory, timeout: 15))
      stream = probe.fetch('streams').find { |row| row['codec_type']=='video' }
      raise ArgumentError, 'Feature video acceptance failed' unless stream && stream['width']==960 && stream['height']==540 && probe.dig('format','duration').to_f.between?(11.9,12.2) && File.size(output).positive?
      output
    end
    def self.run!(command, directory:, timeout:)
      if Rails.env.production?
        mapped = command.map { |argument| argument.gsub(directory, '/work') }
        command = Studio::MediaProcess.container(mapped, root: directory, image: Studio::NativeBlender::Runtime.image(:media))
      end
      Studio::MediaProcess.run!(command, timeout: timeout)
    end
  end
end
