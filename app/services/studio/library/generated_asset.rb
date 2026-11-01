# frozen_string_literal: true
require "zlib"
require "digest"
module Studio
  module Library
    class GeneratedAsset
      FONT = {
        "A"=>%w[01110 10001 10001 11111 10001 10001 10001],"B"=>%w[11110 10001 10001 11110 10001 10001 11110],
        "C"=>%w[01111 10000 10000 10000 10000 10000 01111],"D"=>%w[11110 10001 10001 10001 10001 10001 11110],
        "E"=>%w[11111 10000 10000 11110 10000 10000 11111],"F"=>%w[11111 10000 10000 11110 10000 10000 10000],
        "G"=>%w[01111 10000 10000 10111 10001 10001 01111],"H"=>%w[10001 10001 10001 11111 10001 10001 10001],
        "I"=>%w[11111 00100 00100 00100 00100 00100 11111],"J"=>%w[00111 00010 00010 00010 10010 10010 01100],
        "K"=>%w[10001 10010 10100 11000 10100 10010 10001],"L"=>%w[10000 10000 10000 10000 10000 10000 11111],
        "M"=>%w[10001 11011 10101 10101 10001 10001 10001],"N"=>%w[10001 11001 10101 10011 10001 10001 10001],
        "O"=>%w[01110 10001 10001 10001 10001 10001 01110],"P"=>%w[11110 10001 10001 11110 10000 10000 10000],
        "Q"=>%w[01110 10001 10001 10001 10101 10010 01101],"R"=>%w[11110 10001 10001 11110 10100 10010 10001],
        "S"=>%w[01111 10000 10000 01110 00001 00001 11110],"T"=>%w[11111 00100 00100 00100 00100 00100 00100],
        "U"=>%w[10001 10001 10001 10001 10001 10001 01110],"V"=>%w[10001 10001 10001 10001 10001 01010 00100],
        "W"=>%w[10001 10001 10001 10101 10101 10101 01010],"X"=>%w[10001 10001 01010 00100 01010 10001 10001],
        "Y"=>%w[10001 10001 01010 00100 00100 00100 00100],"Z"=>%w[11111 00001 00010 00100 01000 10000 11111],
        "0"=>%w[01110 10001 10011 10101 11001 10001 01110],"1"=>%w[00100 01100 00100 00100 00100 00100 01110],
        "2"=>%w[01110 10001 00001 00010 00100 01000 11111],"3"=>%w[11110 00001 00001 01110 00001 00001 11110],
        "4"=>%w[00010 00110 01010 10010 11111 00010 00010],"5"=>%w[11111 10000 10000 11110 00001 00001 11110],
        "6"=>%w[01110 10000 10000 11110 10001 10001 01110],"7"=>%w[11111 00001 00010 00100 01000 01000 01000],
        "8"=>%w[01110 10001 10001 01110 10001 10001 01110],"9"=>%w[01110 10001 10001 01111 00001 00001 01110],
        "-"=>%w[00000 00000 00000 11111 00000 00000 00000],"."=>%w[00000 00000 00000 00000 00000 00110 00110]
      }.freeze
      def self.call(access:, key:, title: "LIGHTEK LIVE", subtitle: "GUEST NAME")
        graphic = key == "gfx_lower_thirds"
        title = title.to_s.strip.upcase.first(30).presence || "LIGHTEK LIVE"
        subtitle = subtitle.to_s.strip.upcase.first(42).presence || "GUEST NAME"
        fingerprint = Digest::SHA256.hexdigest([access.site_id,key,graphic ? [title,subtitle] : nil].to_json).first(24)
        asset = StudioAsset.find_or_initialize_by(owner_id: access.user.id, request_key: "builtin-#{fingerprint}")
        return asset if asset.persisted?
        bytes = graphic ? png(title,subtitle) : wav
        filename = graphic ? "lightek-lower-third.png" : "neural-pulse.wav"
        asset.assign_attributes(site_id: access.site_id, name: graphic ? "#{title} · lower third" : "Neural Pulse Bed", kind: graphic ? "image" : "audio", status: "ready",
          metadata: {"duration"=>4,"has_audio"=>!graphic,"generated_recipe"=>key,"width"=>graphic ? 1280 : nil,"height"=>graphic ? 720 : nil})
        asset.file.attach(io: StringIO.new(bytes), filename: filename, content_type: graphic ? "image/png" : "audio/wav", identify: false)
        asset.proxy.attach(asset.file.blob)
        asset.thumbnail.attach(asset.file.blob) if graphic
        asset.save!
        asset
      end
      def self.wav
        rate=48000
        samples=Array.new(rate*4) do |index|
          time=index.to_f/rate
          phase=time%0.5
          envelope=[phase/0.02,1].min*Math.exp(-phase*8)
          ((Math.sin(2*Math::PI*55*time)*0.22+Math.sin(2*Math::PI*110*time)*0.08)*envelope*32767).round
        end.pack("s<*")
        "RIFF"+[36+samples.bytesize].pack("V")+"WAVEfmt "+[16,1,1,rate,rate*2,2,16].pack("VvvVVvv")+"data"+[samples.bytesize].pack("V")+samples
      end
      def self.png(title,subtitle)
        rows=Array.new(720) { "\0".b*5120 }
        rect = ->(x,y,width,height,color) { height.times { |dy| rows[y+dy][x*4,width*4]=color.pack("C*")*width } }
        rect.call(64,540,1152,140,[10,20,30,238]);rect.call(64,540,12,140,[85,227,194,255])
        [[title,96,563,4],[subtitle,96,625,3]].each do |text,x,y,scale|
          text.chars.each_with_index do |char,index|
            FONT.fetch(char,Array.new(7,"00000")).each_with_index do |line,dy|
              line.chars.each_with_index { |pixel,dx| rect.call(x+(index*6+dx)*scale,y+dy*scale,scale,scale,[245,250,255,255]) if pixel=="1" }
            end
          end
        end
        chunk=->(kind,data) { [data.bytesize].pack("N")+kind+data+[Zlib.crc32(kind+data)].pack("N") }
        "\x89PNG\r\n\x1a\n".b+chunk.call("IHDR",[1280,720,8,6,0,0,0].pack("NNCCCCC"))+chunk.call("IDAT",Zlib::Deflate.deflate(rows.map { |row| "\0".b+row }.join))+chunk.call("IEND","".b)
      end
    end
  end
end
