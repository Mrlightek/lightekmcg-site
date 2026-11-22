require 'test_helper'
require 'tempfile'

class NevaehOs::DcpPackageTest < ActiveSupport::TestCase
  test 'theater package validation checks the asset map and produces a receipt checksum' do
    Tempfile.create(['theater', '.zip']) do |archive|
      Zip::OutputStream.open(archive.path) do |zip|
        {
          'ASSETMAP.xml' => '<AssetMap><Chunk><Path>picture.mxf</Path></Chunk></AssetMap>',
          'PKL.xml' => '<PackingList/>',
          'CPL.xml' => '<CompositionPlaylist/>',
          'picture.mxf' => 'test fixture'
        }.each do |name, content|
          zip.put_next_entry(name)
          zip.write(content)
        end
      end
      assert_equal Digest::SHA256.file(archive.path).hexdigest, NevaehOs::DcpPackage.inspect_file(archive.path)
      Zip::File.open(archive.path) { |zip| zip.rename('picture.mxf', 'unreferenced.mxf') }
      assert_raises(ArgumentError) { NevaehOs::DcpPackage.inspect_file(archive.path) }
    end
  end
end
