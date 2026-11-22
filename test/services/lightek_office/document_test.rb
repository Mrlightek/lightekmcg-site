require 'test_helper'

class LightekOffice::DocumentTest < ActiveSupport::TestCase
  test 'legacy document text enters the editor without interpreting markup' do
    assert_equal 'Hello &lt;first&gt;<br>Second line', LightekOffice::Document.editor_html("Hello <first>\nSecond line", rich_text: false)
  end

  test 'rich documents retain supported formatting and strip executable or embedded content' do
    html = LightekOffice::Document.prepare!(<<~HTML)
      <h1>Notes</h1><strong>Yes</strong><a href="https://example.com">Source</a><a href="javascript:alert(1)">Bad URL</a>
      <img src="https://example.com/external.png"><action-text-attachment sgid="x"></action-text-attachment>
      <div onload="alert(1)">End</div>
    HTML
    assert_includes html, '<h1>Notes</h1>'
    assert_includes html, '<strong>Yes</strong>'
    assert_includes html, 'href="https://example.com"'
    refute_match(/javascript:|<img|action-text-attachment|onload|external\.png/, html)
    assert_includes LightekOffice::Document.export(html), '<strong>Yes</strong>'
  end

  test 'an empty Trix document is rejected' do
    assert_raises(ArgumentError) { LightekOffice::Document.prepare!('<div>&nbsp;<br></div>') }
  end
end
