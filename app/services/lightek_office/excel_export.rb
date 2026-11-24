# frozen_string_literal: true

require 'nokogiri'
require 'zip'

module LightekOffice
  class ExcelExport
    CONTENT_TYPE = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    SHEET_NAME = 'Sheet1'
    SPREADSHEET_NS = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
    OFFICE_RELS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
    PACKAGE_RELS = 'http://schemas.openxmlformats.org/package/2006/relationships'
    CONTENT_TYPES_NS = 'http://schemas.openxmlformats.org/package/2006/content-types'

    def self.call(content)
      new(Content.validate!('spreadsheet', content)).build
    end

    def self.filename(title)
      "#{title.to_s.parameterize.presence || 'spreadsheet'}.xlsx"
    end

    def initialize(rows)
      @rows = rows
    end

    def build
      Zip::OutputStream.write_buffer do |archive|
        {
          '[Content_Types].xml' => content_types,
          '_rels/.rels' => relationships('officeDocument', 'xl/workbook.xml'),
          'xl/workbook.xml' => workbook,
          'xl/_rels/workbook.xml.rels' => relationships('worksheet', 'worksheets/sheet1.xml'),
          'xl/worksheets/sheet1.xml' => worksheet
        }.each do |path, content|
          archive.put_next_entry(path)
          archive.write(content)
        end
      end.string
    end

    private

    def xml_document(&block)
      Nokogiri::XML::Builder.new(encoding: 'UTF-8', &block).to_xml
    end

    def content_types
      xml_document do |xml|
        xml.Types('xmlns' => CONTENT_TYPES_NS) do
          xml.Default('Extension' => 'rels', 'ContentType' => 'application/vnd.openxmlformats-package.relationships+xml')
          xml.Default('Extension' => 'xml', 'ContentType' => 'application/xml')
          xml.Override('PartName' => '/xl/workbook.xml',
            'ContentType' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml')
          xml.Override('PartName' => '/xl/worksheets/sheet1.xml',
            'ContentType' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml')
        end
      end
    end

    def relationships(type, target)
      xml_document do |xml|
        xml.Relationships('xmlns' => PACKAGE_RELS) do
          xml.Relationship('Id' => 'rId1', 'Type' => "#{OFFICE_RELS}/#{type}", 'Target' => target)
        end
      end
    end

    def workbook
      xml_document do |xml|
        xml.workbook('xmlns' => SPREADSHEET_NS, 'xmlns:r' => OFFICE_RELS) do
          xml.sheets { xml.sheet('name' => SHEET_NAME, 'sheetId' => 1, 'r:id' => 'rId1') }
          xml.calcPr('fullCalcOnLoad' => 1)
        end
      end
    end

    def worksheet
      xml_document do |xml|
        xml.worksheet('xmlns' => SPREADSHEET_NS) do
          xml.sheetData do
            @rows.each_with_index do |values, row|
              xml.row('r' => row + 1) do
                values.each_with_index do |value, column|
                  write_cell(xml, "#{('A'.ord + column).chr}#{row + 1}", value) unless value.nil?
                end
              end
            end
          end
        end
      end
    end

    def write_cell(xml, address, value)
      if value.start_with?('=') && local_formula?(value)
        xml.c('r' => address) { xml.f(value.delete_prefix('=')) }
      elsif numeric?(value)
        xml.c('r' => address) { xml.v(value) }
      else
        xml.c('r' => address, 't' => 'inlineStr') do
          xml.is do
            xml.t('xml:space' => 'preserve') do
              # A literal SpreadsheetML escape must remain literal on opening.
              text = value.gsub(/_x[0-9a-fA-F]{4}_/) { |escape| "_x005F_#{escape[1..]}" }
              text = text.gsub(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/) { |character| format('_x%04X_', character.ord) }
              xml.text(text)
            end
          end
        end
      end
    end

    def numeric?(value)
      value.match?(/\A-?(?:0|[1-9]\d*)(?:\.\d+)?\z/) && value.delete('-.').sub(/\A0+/, '').length <= 15
    end

    def local_formula?(value)
      # Parse every branch, even a branch the native calculator would never execute.
      return false if value.match?(/[\u0000-\u001F\uFFFE\uFFFF]/)

      formula = LightekAccounting::SheetFormula::Parser.new(value, SHEET_NAME).parse
      local_references?(formula)
    rescue LightekAccounting::SheetFormula::Unsupported
      false
    end

    def local_references?(node)
      case node[0]
      when :ref, :range
        node[1].casecmp?(SHEET_NAME) && node.drop(2).all? do |address|
          column, row = /\A([A-Z])([1-9]\d*)\z/.match(address)&.captures
          column && column.ord - 'A'.ord < Content::MAX_COLUMNS && row.to_i <= Content::MAX_ROWS
        end
      when :call then node[2].all? { |arg| local_references?(arg) }
      when :binary then local_references?(node[2]) && local_references?(node[3])
      when :unary then local_references?(node[1])
      when :literal then true
      end
    end
  end
end
