# frozen_string_literal: true

require_relative 'shared_drive_office_checks'
require 'rack/test'
require_relative '../../app/services/lightek_office/powerpoint_import'

module OfficePowerpointImportFixture
  private

  def deck(text = 'Launch &amp; review', mode: nil)
    format = LightekOffice::PowerpointImport
    content_types = %(<Types xmlns="#{format::TYPES_NS}"><Override PartName="/ppt/presentation.xml" ContentType="#{format::MAIN_TYPE}"/></Types>)
    references = %(<Relationships xmlns="#{format::PACKAGE_RELS}"><Relationship Id="second" Type="#{format::OFFICE_RELS}/slide" Target="slides/slide2.xml" #{mode}/>
      <Relationship Id="first" Type="#{format::OFFICE_RELS}/slide" Target="/ppt/slides/slide1.xml"/></Relationships>)
    list = '<p:sldIdLst><p:sldId id="258" r:id="second"/><p:sldId id="257" r:id="first"/></p:sldIdLst>'
    body = '<p:sp><p:txBody><a:p><a:r><a:t>First line</a:t></a:r><a:br/><a:r><a:t>Second line</a:t></a:r></a:p></p:txBody></p:sp>'
    title = %(<p:sp><p:nvSpPr><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:txBody><a:p><a:r><a:t>#{text}</a:t></a:r></a:p></p:txBody></p:sp>)
    Zip::OutputStream.write_buffer do |archive|
      {
        '[Content_Types].xml' => content_types,
        'ppt/presentation.xml' => xml_part('presentation', list),
        'ppt/_rels/presentation.xml.rels' => references,
        'ppt/slides/slide1.xml' => xml_part('sld', '<p:cSld><p:spTree/></p:cSld>'),
        'ppt/slides/slide2.xml' => xml_part('sld', "<p:cSld><p:spTree>#{body}#{title}</p:spTree></p:cSld>")
      }.each do |path, xml|
        archive.put_next_entry(path)
        archive.write(xml)
      end
    end.string
  end

  def xml_part(root, content)
    format = LightekOffice::PowerpointImport
    %(<p:#{root} xmlns:p="#{format::PRESENTATION_NS}" xmlns:a="#{format::DRAWING_NS}" xmlns:r="#{format::OFFICE_RELS}">#{content}</p:#{root}>)
  end

  def imported(bytes)
    LightekOffice::PowerpointImport.call(bytes, filename: 'Brief.pptx')
  end
end

class OfficePowerpointImportChecks < Minitest::Test
  include OfficePowerpointImportFixture

  def test_preserves_manifest_order_title_placeholders_text_and_empty_slides
    source = imported(deck)
    assert_equal [['Launch & review', "First line\nSecond line"], ['Slide 2', '']], LightekOffice::Content.slides(source)
  end

  def test_rejects_unsupported_slide_relationships_and_delimiters
    assert_match(/supported slide part/, assert_raises(ArgumentError) { imported(deck(mode: 'TargetMode="External"')) }.message)
    assert_match(/three dashes/, assert_raises(ArgumentError) { imported(deck('---')) }.message)
    assert_raises(ArgumentError) { imported('not a package') }
  end
end

class SharedDriveOfficeChecks
  include OfficePowerpointImportFixture

  def test_imports_into_the_selected_folder_and_edits_the_saved_presentation
    post :import_powerpoint, params: location.merge(folder: @folder.id, presentation: powerpoint_upload(deck))
    assert_response :see_other
    file = @drive.entries.find_by!(name: 'Brief').office_file
    assert_equal @folder.id, file.drive_entry.parent_id
    assert_equal 'presentation', file.kind
    assert_equal 'Launch & review', LightekOffice::Content.slides(file.content).first.first

    patch :update, params: location.merge(file_id: file.id, office_file: {
      title: file.title, lock_version: file.lock_version, content: file.content.sub('First line', 'Edited line')
    })
    assert_response :see_other
    assert_includes file.reload.content, 'Edited line'
  end

  def test_viewer_and_invalid_upload_leave_no_entry
    count = @drive.entries.count
    use_actor(@viewer)
    post :import_powerpoint, params: location.merge(folder: @folder.id, presentation: powerpoint_upload(deck))
    assert_response :forbidden

    use_actor(@editor)
    post :import_powerpoint, params: location.merge(folder: @folder.id, presentation: powerpoint_upload('invalid'))
    assert_response :see_other
    assert_match(/damaged/, flash[:alert])
    assert_equal count, @drive.entries.count
  end

  private

  def powerpoint_upload(bytes)
    Rack::Test::UploadedFile.new(StringIO.new(bytes), 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      original_filename: 'Brief.pptx')
  end
end
