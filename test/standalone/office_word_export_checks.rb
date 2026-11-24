# frozen_string_literal: true

require 'minitest/autorun'
require 'active_support/all'
require_relative '../../app/services/lightek_office/document'
require_relative '../../app/services/lightek_office/word_export'

class OfficeWordExportChecks < Minitest::Test
  WORD = {'w' => LightekOffice::WordExport::WORD_NS}.freeze

  def test_rich_text_retains_editable_formatting_and_order
    source = <<~HTML
      <h1>Studio launch</h1><div>One <strong>bold</strong> <em>italic</em>
      <u>underlined</u> <s>revised</s><br>Line two 📝</div>
      <ol><li>First<ul><li>Nested</li></ul></li><li>Second</li></ol>
      <p><a href="https://example.com/?one=1&amp;two=2">Guide</a></p>
    HTML

    word_parts(source, rich_text: true) do |archive, document|
      paragraphs = document.xpath('/w:document/w:body/w:p', WORD)
      assert_equal 'Heading1', paragraphs.first.at_xpath('w:pPr/w:pStyle', WORD).values.first
      assert_equal %w[bold italic underlined revised],
        document.xpath('//w:r[w:rPr/w:b or w:rPr/w:i or w:rPr/w:u and not(w:rPr/w:color) or w:rPr/w:strike]/w:t', WORD).map(&:text)
      assert_includes document.xpath('//w:t', WORD).map(&:text), 'Line two 📝'
      assert_equal %w[1 2 1], document.xpath('//w:numId/@w:val', WORD).map(&:value)
      numbering = Nokogiri::XML(archive.read('word/numbering.xml')) { |config| config.strict }
      assert_equal %w[decimal bullet], numbering.xpath('//w:numFmt/@w:val', WORD).map(&:value)
      assert_equal 'https://example.com/?one=1&two=2', relationships(archive).find { |rel| rel['TargetMode'] == 'External' }['Target']
    end
  end

  def test_legacy_documents_keep_literal_text_and_line_breaks
    source = "Two & <three>\nThe next line"
    word_parts(source, rich_text: false) do |archive, document|
      assert_equal ['Two & <three>', 'The next line'], document.xpath('//w:t', WORD).map(&:text)
      assert_equal 1, document.xpath('//w:br', WORD).length
      assert_empty relationships(archive).select { |rel| rel['TargetMode'] }
    end
  end

  def test_disallowed_links_remain_text_without_external_relationships
    source = '<a href="javascript:alert(1)">Unsafe URL</a> <a href="/dashboard">Relative link</a>'
    word_parts(source, rich_text: true) do |archive, document|
      assert_empty document.xpath('//w:hyperlink', WORD)
      assert_equal ['Unsafe URL', 'Relative link'], document.xpath('//w:t', WORD).map(&:text).reject(&:blank?)
      assert_empty relationships(archive).select { |rel| rel['TargetMode'] }
    end
  end

  private

  def word_parts(source, rich_text:)
    bytes = LightekOffice::WordExport.call(source, rich_text: rich_text)
    Zip::File.open_buffer(bytes) do |archive|
      yield archive, Nokogiri::XML(archive.read('word/document.xml')) { |config| config.strict }
    end
  end

  def relationships(archive)
    Nokogiri::XML(archive.read('word/_rels/document.xml.rels')) { |config| config.strict }.root.element_children
  end
end
