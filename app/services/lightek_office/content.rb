# frozen_string_literal: true

require 'csv'

module LightekOffice
  module Content
    module_function

    MAX_BYTES = 64.kilobytes
    MAX_ROWS = 100
    MAX_COLUMNS = 26
    MAX_SLIDES = 50

    def validate!(kind, text)
      raise ArgumentError, 'Keep the file within 64 KB.' if text.bytesize > MAX_BYTES
      case kind
      when 'spreadsheet' then sheet_rows(text)
      when 'presentation' then slides(text)
      end
    end

    def sheet_rows(text)
      rows = CSV.parse(text)
      if rows.size > MAX_ROWS || rows.any? { |row| row.size > MAX_COLUMNS || row.any? { |cell| cell.to_s.bytesize > 4_000 } }
        raise ArgumentError, 'Use up to 100 rows, 26 columns, and 4,000 bytes per cell.'
      end

      rows
    rescue CSV::MalformedCSVError
      raise ArgumentError, 'Enter valid CSV rows. Use double quotes around values with a comma.'
    end

    def calculate(text)
      rows = sheet_rows(text)
      cells = {}
      rows.each_with_index do |row, i|
        row.each_with_index do |value, j|
          value = value.to_s
          address = "#{('A'.ord + j).chr}#{i + 1}"
          cells[address] = if value.start_with?('=')
            {'formula'=>value, 'type'=>'text', 'value'=>''}
          elsif value.match?(/\A-?\d+(?:\.\d+)?\z/)
            {'type'=>'number', 'value'=>value}
          else
            {'type'=>'text', 'value'=>value}
          end
        end
      end
      calculator = LightekAccounting::SheetFormula.new('sheets'=>[{'name'=>'Sheet1', 'cells'=>cells}])
      rows.each_with_index.map do |row, i|
        row.each_with_index.map do |_, j|
          value = calculator.cell('Sheet1', "#{('A'.ord + j).chr}#{i + 1}")
          value.is_a?(BigDecimal) ? value.to_s('F').sub(/\.0\z/, '') : value.to_s
        rescue LightekAccounting::SheetFormula::Unsupported
          '#ERROR'
        end
      end
    end

    def csv(text)
      CSV.generate do |output|
        calculate(text).each do |row|
          output << row.map do |cell|
            if cell.match?(/\A[\p{Space}\uFEFF]*[=+\-@]/) && !cell.match?(/\A-?\d+(?:\.\d+)?\z/)
              "'#{cell}"
            else
              cell
            end
          end
        end
      end
    end

    def slides(text)
      parts = text.split(/^---[ \t]*\r?$/, MAX_SLIDES + 1).map(&:strip).reject(&:blank?)
      raise ArgumentError, 'Use up to 50 slides.' if parts.size > MAX_SLIDES

      parts.map do |slide|
        title, body = slide.split(/\r?\n/, 2)
        [title, body.to_s.strip]
      end
    end
  end
end
