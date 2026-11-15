# frozen_string_literal: true
require 'zlib'
require 'stringio'
module LightekMarketing
  class CampaignComposition
    def initialize(operation, actor)
      @operation, @actor = operation, actor
      @scene = operation.studio_scene
      @plan = operation.manifest.fetch('campaign_plan')
      @access = Studio::PwaAccess.new('user_id'=>actor.id, 'site_id'=>operation.studio_project.site_id)
    end
    def build!
      images = 4.times.map { |i| asset("card-#{i}", 'image', png(i), 'image/png', {'width'=>360, 'height'=>640}) }
      score = Studio::Music::Composition.normalize(composition, access: @access)
      music = asset('score', 'audio', wav(score), 'audio/wav', {'duration'=>24, 'has_audio'=>true})
      supplied = StudioAsset.for_actor(@access).where(site_id: @access.site_id, id: @plan['image_ids'], kind: 'image', status: 'ready').index_by(&:id)
      raise ArgumentError, 'A selected image is no longer available' unless supplied.size == @plan['image_ids'].uniq.size
      visuals = images.each_with_index.map { |image,i| supplied[@plan['image_ids'][i]] || image }
      raw = Studio::Editing::Timeline.format('portrait').merge('export_preset'=>'review',
        'tracks'=>[{'id'=>0, 'name'=>'Campaign cards'}, {'id'=>1, 'name'=>'Original score', 'gain'=>0.45}],
        'clips'=>visuals.each_with_index.map { |image,i| {'asset_id'=>image.id, 'start'=>i*6, 'out'=>6, 'track'=>0, 'scale'=>1.06, 'fade_in'=>0.15, 'fade_out'=>0.15, 'keyframes'=>[{'time'=>0,'x'=>-45,'y'=>-30}, {'time'=>6,'x'=>-10,'y'=>0}]} } + [{'asset_id'=>music.id,'out'=>24,'track'=>1,'fade_in'=>0.2,'fade_out'=>1}],
        'titles'=>@plan['cards'].each_with_index.map { |text,i| {'text'=>wrap(text), 'start'=>i*6+0.2, 'end'=>(i+1)*6-0.15, 'x'=>108, 'y'=>510, 'size'=>58} } + [{'text'=>wrap(@plan['service']), 'start'=>0,'end'=>24,'x'=>108,'y'=>250,'size'=>40}])
      assets = (images + supplied.values + [music]).index_by(&:id)
      timeline = Studio::Editing::Timeline.normalize(raw, assets: assets)
      @scene.with_lock do
        @operation.reload
        raise ArgumentError, 'Production was cancelled' if @operation.status == 'cancelled'
        raise ActiveRecord::StaleObjectError.new(@scene, 'produce') unless @scene.lock_version == @operation.metadata.fetch('initial_scene_version')
        camera = @scene.scene_objects.create!(name: 'Campaign storyboard camera', object_type: 'camera', definition: {'location'=>[0,-8,2], 'rotation'=>[90,0,0], 'scale'=>[1,1,1]})
        shots = @plan['cards'].each_with_index.map { |text,i| {'id'=>"campaign-#{@operation.id}-shot-#{i}", 'name'=>%w[Hook Setup Introduction Invitation][i], 'notes'=>text, 'prompt'=>'Vertical motion graphic with readable type; editable image, music and caption layers.', 'camera_id'=>camera.id, 'frame_start'=>i*180+1, 'frame_end'=>(i+1)*180, 'cast_ids'=>[]} }
        board = Studio::Shots::Board.normalize(@scene, shots)
        settings = @scene.settings.deep_dup
        settings.delete('editor_kind') # The generated layers open in the native timeline workspace.
        settings.merge!('timeline'=>timeline, 'music'=>score, 'music_revision'=>1, 'music_mix'=>{'asset_id'=>music.id,'revision'=>1,'score_start'=>0}, 'campaign_plan'=>@plan, 'shot_board'=>{'version'=>1, 'revision'=>1, 'shots'=>board})
        settings['workspace'] ||= {}; settings['workspace']['story'] ||= {}
        settings['workspace']['story']['scriptDraft'] = @plan['cards'].each_with_index.map { |text,i| "#{i*6}–#{(i+1)*6}s · #{text}" }.join("\n\n")
        @scene.update!(settings: settings)
        preview = timeline.deep_dup
        preview.merge!('width'=>720, 'height'=>1280)
        preview['titles'].each { |title| %w[x y size].each { |key| title[key] = title[key]*2.0/3 } }
        preview['titles'] << {'text'=>'PRIVATE DRAFT · REVIEW REQUIRED', 'start'=>0, 'end'=>24, 'x'=>72, 'y'=>1120, 'size'=>22}
        @operation.update!(manifest: @operation.manifest.merge('timeline'=>preview, 'scene_version'=>@scene.lock_version, 'music_asset_id'=>music.id))
      end
    end
    def wrap(text)
      text.split("\n").flat_map { |line| line.scan(/\S.{0,23}(?=\s|$)|\S{1,24}/).map(&:strip) }.join("\n")
    end
    def asset(key, kind, bytes, type, metadata)
      @actor.with_lock do
        row = StudioAsset.find_or_initialize_by(owner_id: @actor.id, request_key: "campaign-#{@operation.id}-#{key}")
        return row if row.persisted? && row.file.attached?
        row.assign_attributes(site_id: @access.site_id, studio_project: @operation.studio_project, name: "Campaign #{@operation.id} #{key}", kind: kind, status: 'ready', metadata: metadata.merge('campaign_operation_id'=>@operation.id, 'generated'=>true))
        row.save!
        row.file.attach(io: StringIO.new(bytes), filename: "#{key}.#{kind == 'image' ? 'png' : 'wav'}", content_type: type, identify: false)
        row
      end
    end
    # Small exact graphics, with no external image service or untrusted SVG parser.
    def png(index)
      palettes = [[30,18,62], [15,43,66], [67,23,53], [22,48,39]]
      base = palettes.fetch(index)
      rows = 640.times.map do |y|
        pixels = 360.times.flat_map do |x|
          accent = ((x + y / 2 + index*47) % 160 < 12) || (x-300)**2 + (y-100)**2 < 5500
          base.map.with_index { |v,c| accent ? [v + [65,38,70][c],255].min : v + (y*12/640) }
        end
        "\0".b + pixels.pack('C*')
      end.join
      chunk = ->(kind,data) { [data.bytesize].pack('N') + kind + data + [Zlib.crc32(kind+data)].pack('N') }
      "\x89PNG\r\n\x1a\n".b + chunk.call('IHDR', [360,640,8,2,0,0,0].pack('NNCCCCC')) + chunk.call('IDAT', Zlib::Deflate.deflate(rows)) + chunk.call('IEND', ''.b)
    end
    def composition
      tracks = %w[kick hat bass].map { |instrument| {'id'=>instrument, 'name'=>instrument.capitalize, 'instrument'=>instrument, 'gain'=>0.65, 'notes'=>[]} }
      48.times do |beat|
        tracks[0]['notes'] << {'beat'=>beat, 'length'=>0.25, 'pitch'=>36, 'velocity'=>0.8} if beat.even?
        tracks[1]['notes'] << {'beat'=>beat+0.5, 'length'=>0.125, 'pitch'=>60, 'velocity'=>0.25}
        tracks[2]['notes'] << {'beat'=>beat, 'length'=>0.75, 'pitch'=>[36,39,43,46][(beat/4)%4], 'velocity'=>0.55} if beat%2 == 0
      end
      {'version'=>1,'name'=>'Campaign original groove','tempo'=>120,'bars'=>12,'swing'=>0,'tracks'=>tracks}
    end
    # Bounce the same saved MIDI-style score; deterministic noise, mono PCM, 24 seconds.
    def wav(score)
      rate = 24_000
      samples = Array.new(rate*24, 0.0)
      noise = Random.new(62)
      score['tracks'].each do |track|
        track['notes'].each do |note|
          start = (note['beat']*0.5*rate).round
          count = (note['length']*0.5*rate).round
          frequency = 440 * 2.0**((note['pitch']-69)/12.0)
          count.times do |j|
            t = j.to_f/rate
            envelope = Math.exp(-j.to_f/count*6) * [j/60.0,1].min
            wave = case track['instrument']
            when 'hat' then noise.rand*2-1
            when 'kick' then Math.sin(2*Math::PI*(55*t+6*(1-Math.exp(-30*t))))
            else Math.sin(2*Math::PI*frequency*t)
            end
            samples[start+j] += wave*envelope*note['velocity']*track['gain']*0.45 if start+j < samples.length
          end
        end
      end
      data = samples.map { |sample| (sample.clamp(-0.95,0.95)*32767).round }.pack('s<*')
      'RIFF' + [36+data.bytesize].pack('V') + 'WAVEfmt ' + [16,1,1,rate,rate*2,2,16].pack('VvvVVvv') + 'data' + [data.bytesize].pack('V') + data
    end
  end
end
