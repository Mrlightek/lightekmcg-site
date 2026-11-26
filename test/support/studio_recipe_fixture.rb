require "fileutils"
require "tmpdir"
require "zlib"

module StudioRecipeFixture
  SIZE = 320

  def self.path
    @path ||= begin
      directory = Dir.mktmpdir("studio-recipe-fixture-")
      at_exit { FileUtils.remove_entry(directory) }
      File.join(directory, "studio-fixture.png").tap { |file| File.binwrite(file, png) }
    end
  end

  def self.png
    rows = Array.new(SIZE) do |y|
      "\x00".b + Array.new(SIZE) do |x|
        # Four colors and a diagonal stripe give selection and fill tests visible pixels.
        if (x - y).abs < 8
          [220, 208, 80]
        elsif x < SIZE / 2
          y < SIZE / 2 ? [32, 110, 170] : [40, 130, 90]
        else
          y < SIZE / 2 ? [110, 65, 150] : [186, 90, 48]
        end
      end.flatten.pack("C*")
    end.join
    "\x89PNG\r\n\x1a\n".b + chunk("IHDR", [SIZE, SIZE, 8, 2, 0, 0, 0].pack("N2C5")) +
      chunk("IDAT", Zlib::Deflate.deflate(rows)) + chunk("IEND", "".b)
  end

  def self.chunk(type, data)
    [data.bytesize].pack("N") + type + data + [Zlib.crc32(type + data)].pack("N")
  end
  private_class_method :chunk, :png
end
