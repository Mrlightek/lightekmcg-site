# frozen_string_literal: true

require_relative 'shared_drive_office_checks'
require_relative '../../app/services/lightek_office/powerpoint_export'

class OfficePowerpointExportChecks < Minitest::Test
  PRESENTATION = LightekOffice::PowerpointExport::PRESENTATION_NS
  DRAWING = LightekOffice::PowerpointExport::DRAWING_NS
  NS = {'p' => PRESENTATION, 'a' => DRAWING}.freeze

  def test_export_has_ordered_slides_with_editable_textboxes
    source = "Studio & Stage\nLine 1\n\nLine <2>\n---\nPlanning\nReview draft 📝"
    Zip::File.open_buffer(LightekOffice::PowerpointExport.call(source)) do |archive|
      deck = xml(archive.read('ppt/presentation.xml'))
      assert_equal %w[256 257], deck.xpath('//p:sldId/@id', NS).map(&:value)
      assert_equal ['12192000', '6858000'], deck.at_xpath('//p:sldSz', NS).values
      first = xml(archive.read('ppt/slides/slide1.xml'))
      assert_equal [['Studio & Stage'], ['Line 1', '', 'Line <2>']], editable_text(first)
      second = xml(archive.read('ppt/slides/slide2.xml'))
      assert_equal [['Planning'], ['Review draft 📝']], editable_text(second)

      paths = archive.entries.map(&:name)
      paths.grep(/\.rels\z/).each do |path|
        directory = path.sub(%r{(?:^|/)_rels/[^/]+\z}, '')
        xml(archive.read(path)).root.element_children.each do |relationship|
          assert_nil relationship['TargetMode']
          target = File.expand_path(relationship['Target'], "/#{directory}").delete_prefix('/')
          assert_includes paths, target
        end
      end
    end
  end

  def test_empty_body_stays_editable_and_existing_slide_limit_applies
    Zip::File.open_buffer(LightekOffice::PowerpointExport.call('Title only')) do |archive|
      assert_equal [['Title only'], ['']], editable_text(xml(archive.read('ppt/slides/slide1.xml')))
    end
    assert_raises(ArgumentError) { LightekOffice::PowerpointExport.call((['Title'] * 51).join("\n---\n")) }
  end

  private

  def xml(source) = Nokogiri::XML(source) { |config| config.strict }

  def editable_text(document)
    document.xpath('//p:sp[p:nvSpPr/p:cNvSpPr[@txBox="1"]]', NS).map do |shape|
      shape.xpath('p:txBody/a:p/a:r/a:t', NS).map(&:text)
    end
  end
end

class SharedDriveOfficeChecks
  def test_drive_viewer_can_download_a_presentation_as_powerpoint_or_source
    source = "Studio launch\nWelcome\n---\nNext steps\nReview the schedule"
    post :create, params: location.merge(folder: @folder.id,
      office_file: {kind: 'presentation', title: 'Production brief', content: source})
    assert_response :see_other
    file = @drive.entries.find_by!(name: 'Production brief').office_file

    use_actor(@viewer)
    get :index, params: location.merge(file_id: file.id)
    assert_response :success
    assert_includes response.body, 'Download PowerPoint (.pptx)'
    get :export, params: location.merge(file_id: file.id, download: 'pptx')
    assert_response :success
    assert_equal LightekOffice::PowerpointExport::CONTENT_TYPE, response.media_type
    assert_includes response.headers.fetch('Content-Disposition'), 'production-brief.pptx'
    Zip::File.open_buffer(response.body) do |archive|
      assert_includes archive.read('ppt/slides/slide2.xml'), 'Review the schedule'
    end

    get :export, params: location.merge(file_id: file.id)
    assert_response :success
    assert_equal source, response.body

    use_actor(@other)
    get :export, params: location.merge(file_id: file.id, download: 'pptx')
    assert_response :not_found
  end
end
