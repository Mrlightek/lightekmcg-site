# frozen_string_literal: true

require_relative 'shared_drive_office_checks'
require 'rack/test'
require_relative '../../app/services/lightek_accounting/workbook_schema'
require_relative '../../app/services/lightek_accounting/sheet_formula'
require_relative '../../app/services/lightek_office/excel_import'

module OfficeExcelImportFixture
  private

  def workbook(rows, sheets: 1)
    sheet_nodes = (1..sheets).map { |n| %(<sheet name="Sheet#{n}" sheetId="#{n}" r:id="rId#{n}"/>) }.join
    targets = (1..sheets).map { |n| %(<Relationship Id="rId#{n}" Target="worksheets/sheet#{n}.xml"/>) }.join
    Zip::OutputStream.write_buffer do |archive|
      files = {
        'xl/workbook.xml' => %(<workbook xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>#{sheet_nodes}</sheets></workbook>),
        'xl/_rels/workbook.xml.rels' => "<Relationships>#{targets}</Relationships>"
      }
      (1..sheets).each { |n| files["xl/worksheets/sheet#{n}.xml"] = "<worksheet><sheetData>#{rows}</sheetData></worksheet>" }
      files.each do |path, xml|
        archive.put_next_entry(path)
        archive.write(xml)
      end
    end.string
  end

  def example_workbook
    workbook(<<~XML)
      <row r="1"><c r="A1"><v>2</v></c><c r="C1" t="inlineStr"><is><t>001,002</t></is></c></row>
      <row r="3"><c r="B3"><f>SUM(A1:A2)</f><v>999</v></c><c r="C3" t="inlineStr"><is><t>0012</t></is></c>
        <c r="D3" t="inlineStr"><is><t>=external("hello")</t></is></c><c r="E3" t="b"><v>1</v></c></row>
      <row r="104"><c r="A104"/></row>
    XML
  end

  def import(bytes)
    LightekOffice::ExcelImport.call(bytes, filename: 'Budget.xlsx')
  end
end

class OfficeExcelImportChecks < Minitest::Test
  include OfficeExcelImportFixture

  def test_preserves_cells_gaps_formulas_and_numeric_looking_text
    content = import(example_workbook)
    rows = CSV.parse(content)
    assert_equal ['2.0', nil, '001,002'], rows.first
    assert_empty rows[1]
    assert_equal [nil, '=SUM(A1:A2)', '="0012"', '="=external(""hello"")"', '=TRUE'], rows[2]
    assert_equal ['2', '0012', '=external("hello")', 'true'], LightekOffice::Content.calculate(content)[2].drop(1)
  end

  def test_refuses_workbooks_that_cannot_fit_without_data_loss
    assert_match(/one worksheet/, assert_raises(ArgumentError) { import(workbook('', sheets: 2)) }.message)
    assert_match(/AA1/, assert_raises(ArgumentError) { import(workbook('<row><c r="AA1"><v>6</v></c></row>')) }.message)
    assert_match(/A1/, assert_raises(ArgumentError) { import(workbook('<row><c r="A1"><f t="shared">A2</f></c></row>')) }.message)
    assert_match(/A1/, assert_raises(ArgumentError) { import(workbook('<row><c r="A1"><f>SUM(Other!B1)</f></c></row>')) }.message)
  end

  def test_bounds_numeric_conversion_before_expanding_decimal
    bytes = workbook('<row><c r="A1"><v>1e99999999</v></c></row>')
    assert_match(/outside the supported Excel range/, assert_raises(ArgumentError) { import(bytes) }.message)
  end
end

class SharedDriveOfficeChecks
  include OfficeExcelImportFixture

  def test_drive_editor_creates_an_editable_spreadsheet_in_the_destination_folder
    post :import_excel, params: location.merge(folder: @folder.id, workbook: excel_upload(example_workbook))
    assert_response :see_other
    entry = @drive.entries.find_by!(name: 'Budget')
    assert_equal @folder.id, entry.parent_id
    assert_equal 'spreadsheet', entry.office_file.kind
    assert_equal '=SUM(A1:A2)', CSV.parse(entry.office_file.content)[2][1]
    assert_includes response.location, "file_id=#{entry.office_file.id}"
  end

  def test_viewer_and_invalid_workbook_do_not_create_a_drive_file
    entry_count = @drive.entries.count
    use_actor(@viewer)
    post :import_excel, params: location.merge(folder: @folder.id, workbook: excel_upload(example_workbook))
    assert_response :forbidden
    assert_equal entry_count, @drive.entries.count

    use_actor(@editor)
    post :import_excel, params: location.merge(folder: @folder.id, workbook: excel_upload(workbook('', sheets: 2)))
    assert_response :see_other
    assert_match(/one worksheet/, flash[:alert])
    assert_equal entry_count, @drive.entries.count
  end

  private

  def excel_upload(bytes)
    Rack::Test::UploadedFile.new(StringIO.new(bytes), 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      original_filename: 'Budget.xlsx')
  end
end
