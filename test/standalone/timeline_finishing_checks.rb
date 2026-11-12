# Run directly with Ruby, Active Support, Active Model, minitest and FFmpeg.
require "active_support/all"
require "active_model"
require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "../../app/services/studio/editing/timeline"
class TimelineFinishingTest < Minitest::Test
  Asset=Struct.new(:id,:kind,:status,:metadata)
  def assets
    {1=>Asset.new(1,"video","ready",{"duration"=>2,"has_audio"=>true}),2=>Asset.new(2,"audio","ready",{"duration"=>2})}
  end
  def normalized(**values)
    Studio::Editing::Timeline.normalize({"width"=>160,"height"=>90,"clips"=>[{"asset_id"=>1,"out"=>2}]}.merge(values.stringify_keys),assets:assets)
  end
  def test_empty_edit_is_saveable_but_not_exportable
    empty={"clips"=>[]}
    normalized=Studio::Editing::Timeline.normalize(empty,assets:{},allow_empty:true)
    assert_empty normalized["clips"]
    assert_equal 0,normalized["duration"]
    assert_raises(ArgumentError){Studio::Editing::Timeline.normalize(normalized,assets:{})}
  end
  def render(timeline,dir)
    source=File.join(dir,"source.mp4")
    run!(["ffmpeg","-v","error","-y","-f","lavfi","-i","color=c=red:s=160x90:r=30:d=2","-f","lavfi","-i","sine=frequency=440:duration=2","-c:v","libx264","-threads","1","-c:a","aac","-shortest",source])
    titles=timeline["titles"].each_with_index.map{|t,i|path=File.join(dir,"title-#{i}.txt");File.write(path,t["text"]);path}
    extension=timeline["output"]=="audio" ? "wav" : timeline["export_preset"]=="master" ? "mov" : "mp4"
    out=File.join(dir,"master.#{extension}")
    run!(Studio::Editing::Timeline.command(timeline,paths:[source],output:out,title_paths:titles))
    JSON.parse(run!(["ffprobe","-v","error","-show_streams","-show_format","-of","json",out]))
  end
  def run!(command)
    out,err,status=Open3.capture3(*command);assert status.success?,err;out
  end
  def test_real_speed_color_fades_title_and_track_mix
    timeline=normalized(fps:30,clips:[{asset_id:1,out:2,speed:2,fade_in:0.1,fade_out:0.2,brightness:0.1,saturation:0.6,scale:0.8,opacity:0.8,highpass:80,denoise:true}],tracks:[{id:0,name:"Dialogue",gain:0.7,pan:-0.25}],titles:[{text:"LIGHTEK: 100% {literal}\nEpisode 1",start:0.1,end:0.9,size:12,x:4,y:4}])
    assert_equal 1,timeline["duration"]
    Dir.mktmpdir("finish-"){|dir|probe=render(timeline,dir);video=probe["streams"].find{|s|s["codec_type"]=="video"};assert_equal "h264",video["codec_name"];assert_equal "30/1",video["r_frame_rate"];assert_in_delta 1,probe["format"]["duration"].to_f,0.1}
  end
  def test_real_prores_and_24_bit_audio_masters
    Dir.mktmpdir("finish-") do |dir|
      probe=render(normalized(export_preset:"master"),dir)
      video=probe["streams"].find{|s|s["codec_type"]=="video"};assert_equal "prores",video["codec_name"];assert_equal "HQ",video["profile"]
      assert_equal "pcm_s24le",probe["streams"].find{|s|s["codec_type"]=="audio"}["codec_name"]
      probe=render(normalized(output:"audio",export_preset:"master",clips:[{asset_id:1,out:0.5,speed:0.25}]),dir)
      assert_equal "pcm_s24le",probe["streams"].first["codec_name"];assert_equal "48000",probe["streams"].first["sample_rate"]
      assert_in_delta 2,probe["format"]["duration"].to_f,0.1
    end
  end
  def test_actual_mix_pan_routes_signal_to_left_channel_only
    timeline=normalized(output:"audio",tracks:[{id:0,pan:-1,gain:0.5}])
    Dir.mktmpdir("finish-") do |dir|
      render(timeline,dir)
      samples=run!(["ffmpeg","-v","error","-i",File.join(dir,"master.wav"),"-f","f32le","-acodec","pcm_f32le","-"]).unpack("e*")
      left=samples.each_slice(2).map(&:first);right=samples.each_slice(2).map(&:last)
      assert_operator Math.sqrt(left.sum{|v|v*v}/left.length),:>,0.01
      assert_operator right.map(&:abs).max,:<,0.00001
    end
  end
  def test_solo_and_mute_remove_other_tracks_from_mix
    timeline=normalized(tracks:[{id:1,solo:true}],clips:[{asset_id:1,out:2,track:0},{asset_id:2,out:2,track:1}])
    command=Studio::Editing::Timeline.command(timeline,paths:["a.mp4","b.wav"],output:"test.mp4").join(" ")
    refute_includes command,"[0:a]";assert_includes command,"[1:a]"
    timeline=normalized(tracks:[{id:0,muted:true}]);refute_includes Studio::Editing::Timeline.command(timeline,paths:["a"],output:"b").join(" "),"[0:a]"
  end
  def test_rejects_invalid_values_foreign_assets_and_title_filter_injection
    [{fps:120},{width:4097},{export_preset:"shell"},{clips:[{asset_id:99,out:1}]},{clips:[{asset_id:1,out:2,speed:0}]},{clips:[{asset_id:1,out:2,opacity:Float::NAN}]},{titles:[{text:"test",start:1,end:0}]}].each{|values|assert_raises(ArgumentError){normalized(**values)}}
    timeline=normalized(titles:[{text:"safe",end:1}]);assert_raises(ArgumentError){Studio::Editing::Timeline.command(timeline,paths:["a"],output:"b",title_paths:["/tmp/a:movie=/etc/passwd"])}
  end
  def test_legacy_timelines_keep_defaults_and_4k_settings_are_accepted
    timeline=normalized;assert_equal 24,timeline["fps"];assert_equal "review",timeline["export_preset"];assert_equal 1,timeline["clips"].first["speed"]
    assert_equal 3840,normalized(width:3840,height:2160)["width"]
    assert_equal timeline,Studio::Editing::Timeline.normalize(timeline,assets:assets)
  end
end
