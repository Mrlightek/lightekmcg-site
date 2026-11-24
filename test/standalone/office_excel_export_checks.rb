# frozen_string_literal: true

require_relative 'shared_drive_office_checks'
require_relative '../../app/services/lightek_accounting/sheet_formula'
require_relative '../../app/services/lightek_office/content'
require_relative '../../app/services/lightek_office/excel_export'

class OfficeExcelExportChecks < Minitest::Test
  SHEET = {'s' => LightekOffice::ExcelExport::SPREADSHEET_NS}.freeze

  def test_workbook_retains_cell_positions_numbers_text_and_formulas
    source = CSV.generate_line(['2', '3.25', '=SUM($A$1:B1)', nil, '0012', '1234567890123456']) +
      CSV.generate_line(["Quoted, \"amount\"\nTotal", nil, "='Sheet1'!A1+1", '  padded  '])
    workbook_parts(source) do |archive, worksheet|
      refute_includes archive.entries.map(&:name), 'xl/externalLinks/externalLink1.xml'
      assert_equal %w[A1 B1 C1 E1 F1 A2 C2 D2], worksheet.xpath('//s:c/@r', SHEET).map(&:value)
      assert_equal ['2', '3.25'], worksheet.xpath('//s:v', SHEET).map(&:text)
      assert_equal ['SUM($A$1:B1)', "'Sheet1'!A1+1"], worksheet.xpath('//s:f', SHEET).map(&:text)
      assert_equal ['0012', '1234567890123456', "Quoted, \"amount\"\nTotal", '  padded  '],
        worksheet.xpath('//s:is/s:t', SHEET).map(&:text)
      workbook = Nokogiri::XML(archive.read('xl/workbook.xml')) { |config| config.strict }
      assert_equal '1', workbook.at_xpath('//s:calcPr', SHEET)['fullCalcOnLoad']
    end
  end

  def test_external_or_unsupported_expressions_stay_inert
    values = ['=WEBSERVICE("https://example.test/")', '=IF(FALSE,WEBSERVICE("https://example.test/"),1)',
      "='[External.xlsx]Sheet1'!A1", '=SUM(Other!A1)', '=A101', '=AA1', '=1+', '@SUM(A1:A2)', '+123']
    workbook_parts(CSV.generate_line(values)) do |_archive, worksheet|
      assert_empty worksheet.xpath('//s:f', SHEET)
      assert_equal values, worksheet.xpath('//s:is/s:t', SHEET).map(&:text)
    end
  end

  def test_sheets_keep_the_current_grid_limits
    assert_raises(ArgumentError) { LightekOffice::ExcelExport.call("1\n" * 101) }
  end

  private

  def workbook_parts(source)
    Zip::File.open_buffer(LightekOffice::ExcelExport.call(source)) do |archive|
      sheet = Nokogiri::XML(archive.read('xl/worksheets/sheet1.xml')) { |config| config.strict }
      yield archive, sheet
    end
  end
end

class SharedDriveOfficeChecks
  def test_drive_viewer_can_download_a_spreadsheet_as_excel_or_csv
    post :create, params: location.merge(folder: @folder.id,
      office_file: {kind: 'spreadsheet', title: 'Working budget', content: "2,3,=A1+B1"})
    assert_response :see_other
    file = @drive.entries.find_by!(name: 'Working budget').office_file

    use_actor(@viewer)
    get :export, params: location.merge(file_id: file.id, download: 'xlsx')
    assert_response :success
    assert_equal LightekOffice::ExcelExport::CONTENT_TYPE, response.media_type
    assert_includes response.headers.fetch('Content-Disposition'), 'working-budget.xlsx'
    Zip::File.open_buffer(response.body) do |archive|
      assert_includes archive.read('xl/worksheets/sheet1.xml'), '<f>A1+B1</f>'
    end

    get :export, params: location.merge(file_id: file.id)
    assert_response :success
    assert_equal "2,3,5\n", response.body

    use_actor(@other)
    get :export, params: location.merge(file_id: file.id, download: 'xlsx')
    assert_response :not_found
  end
end
