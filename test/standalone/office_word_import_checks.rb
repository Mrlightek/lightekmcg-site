# frozen_string_literal: true

require_relative 'shared_drive_office_checks'
require 'rack/test'
require_relative '../../app/services/lightek_office/word_import'

module OfficeWordImportFixture
  private

  def word_package(body, extra = {})
    mime = LightekOffice::WordImport::WORD_PART
    ns = LightekOffice::WordImport::WORD_NS
    rel = LightekOffice::WordImport::RELATIONSHIP_NS
    parts = {
      '[Content_Types].xml' => %(<Types><Override PartName="/word/document.xml" ContentType="#{mime}"/></Types>),
      'word/document.xml' => %(<w:document xmlns:w="#{ns}" xmlns:r="#{rel}"><w:body>#{body}</w:body></w:document>),
      'word/_rels/document.xml.rels' => %(<Relationships><Relationship Id="safe" Type="#{rel}/hyperlink" TargetMode="External" Target="https://example.test/demo?a=1&amp;b=2"/>
        <Relationship Id="blocked" Type="#{rel}/hyperlink" TargetMode="External" Target="file:///example.txt"/></Relationships>)
    }.merge(extra)
    Zip::OutputStream.write_buffer do |archive|
      parts.each do |path, xml|
        archive.put_next_entry(path)
        archive.write(xml)
      end
    end.string
  end

  def sample_doc
    word_package(<<~XML)
      <w:p><w:pPr><w:pStyle w:val="Heading2"/></w:pPr><w:r><w:t>Studio &amp; team</w:t></w:r></w:p>
      <w:p><w:r><w:rPr><w:b/><w:i w:val="0"/></w:rPr><w:t>Bold 📝</w:t><w:br/><w:t>&lt;note&gt;</w:t></w:r>
        <w:hyperlink r:id="safe"><w:r><w:t>Guide</w:t></w:r></w:hyperlink>
        <w:hyperlink r:id="blocked"><w:r><w:t>Blocked link text</w:t></w:r></w:hyperlink></w:p>
      <w:p><w:pPr><w:pStyle w:val="ListBullet"/></w:pPr><w:r><w:t>First</w:t></w:r></w:p>
      <w:p><w:pPr><w:pStyle w:val="ListBullet"/></w:pPr><w:r><w:t>Second</w:t></w:r></w:p>
      <w:tbl><w:tr><w:tc><w:p><w:r><w:t>Name</w:t></w:r></w:p></w:tc>
        <w:tc><w:p><w:r><w:t>Value</w:t></w:r></w:p></w:tc></w:tr></w:tbl>
    XML
  end

  def import_word(bytes)
    LightekOffice::WordImport.call(bytes, filename: 'Brief.docx')
  end
end

class OfficeWordImportChecks < Minitest::Test
  include OfficeWordImportFixture

  def test_import_retains_standard_formatting_safe_links_and_table_text
    output = Nokogiri::HTML5.fragment(import_word(sample_doc))
    assert_equal 'Studio & team', output.at_css('h2').text
    content = output.at_css('strong')
    assert_equal 'Bold 📝<note>', content.text
    assert content.at_css('br')
    assert_empty output.css('em')
    assert_equal ['First', 'Second'], output.css('ul > li').map(&:text)
    assert_equal 'https://example.test/demo?a=1&b=2', output.css('a').sole['href']
    assert_includes output.text, 'Blocked link text'
    assert_includes output.text, 'Name | Value'
  end

  def test_rejects_document_types_macros_and_empty_documents
    assert_match(/types and entities/, assert_raises(ArgumentError) do
      import_word(word_package('', 'word/document.xml' => '<!DOCTYPE document><document/>'))
    end.message)
    assert_match(/macros/, assert_raises(ArgumentError) { import_word(word_package('', 'word/vbaProject.bin' => 'ignored')) }.message)
    assert_match(/Write some document text/, assert_raises(ArgumentError) { import_word(word_package('')) }.message)
  end
end

class SharedDriveOfficeChecks
  include OfficeWordImportFixture

  def test_drive_editor_creates_a_rich_text_document_in_the_selected_folder
    post :import_word, params: location.merge(folder: @folder.id, document: word_upload(sample_doc))
    assert_response :see_other
    entry = @drive.entries.find_by!(name: 'Brief')
    assert_equal @folder.id, entry.parent_id
    assert_equal 'document', entry.office_file.kind
    assert entry.office_file.rich_text?
    assert_includes entry.office_file.content, '<h2>Studio &amp; team</h2>'
    assert_includes response.location, "file_id=#{entry.office_file.id}"
  end

  def test_viewer_cannot_import_and_invalid_documents_leave_no_entry
    count = @drive.entries.count
    use_actor(@viewer)
    post :import_word, params: location.merge(folder: @folder.id, document: word_upload(sample_doc))
    assert_response :forbidden

    use_actor(@editor)
    post :import_word, params: location.merge(folder: @folder.id, document: word_upload(word_package('')))
    assert_response :see_other
    assert_match(/Write some document text/, flash[:alert])
    assert_equal count, @drive.entries.count
  end

  private

  def word_upload(bytes)
    Rack::Test::UploadedFile.new(StringIO.new(bytes), 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      original_filename: 'Brief.docx')
  end
end
