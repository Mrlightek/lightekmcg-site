# frozen_string_literal: true

module LightekOffice
  class ExcelImport
    SHEET_NAME = 'Sheet1'
    NUMERIC_TEXT = /\A-?\d+(?:\.\d+)?\z/
    FORBIDDEN_TEXT = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\uFFFE\uFFFF]/

    def self.call(bytes, filename:)
      raise ArgumentError, 'Choose an Excel workbook ending in .xlsx.' unless filename.to_s.downcase.end_with?('.xlsx')

      workbook = LightekAccounting::WorkbookSchema.parse(bytes, filename: filename)
      sheets = workbook.fetch('sheets')
      raise ArgumentError, 'Save one worksheet per workbook before importing.' unless sheets.one?

      new(sheets.first.fetch('cells')).content
    end

    def initialize(cells)
      @cells = cells
    end

    def content
      rows = []
      @cells.each do |address, cell|
        value = import_cell(address, cell)
        next if value.nil?

        column = LightekAccounting::WorkbookSchema.column_number(address[/[A-Z]+/])
        row = address[/\d+/].to_i
        unless row.between?(1, Content::MAX_ROWS) && column.between?(1, Content::MAX_COLUMNS)
          raise ArgumentError, "Cell #{address} is outside the 100-row, 26-column Workspace grid."
        end

        rows[row - 1] ||= []
        rows[row - 1][column - 1] = value
      end

      raise ArgumentError, 'This worksheet has no values to import.' if rows.empty?

      # Emit empty intervening rows so exported formulas still reference the same cells.
      output = CSV.generate { |csv| rows.each { |row| csv << (row || []) } }
      Content.validate!('spreadsheet', output)
      output
    end

    private

    def import_cell(address, cell)
      return formula(address, cell) if cell.key?('formula')

      value = cell.fetch('value')
      return nil if value.nil? || value == ''
      raise ArgumentError, "Cell #{address} exceeds 4,000 bytes." if value.to_s.bytesize > 4_000

      case cell.fetch('type')
      when 'boolean' then value ? '=TRUE' : '=FALSE'
      when 'number'
        if BigDecimal(value).abs > BigDecimal('1e24')
          raise ArgumentError, "Cell #{address} exceeds the Workspace numeric limit."
        end

        value
      else
        text = value.gsub(/_x([0-9a-f]{4})_/i) do
          codepoint = Regexp.last_match(1).to_i(16)
          raise ArgumentError, "Cell #{address} contains an unsupported character." if (0xD800..0xDFFF).cover?(codepoint)

          [codepoint].pack('U')
        end
        if text.match?(FORBIDDEN_TEXT)
          raise ArgumentError, "Cell #{address} contains an unsupported character."
        end

        # CSV has no cell types. An Excel string that looks numeric or begins
        # with "=" is a quoted literal so the grid retains its value and type.
        text.start_with?('=') || text.match?(NUMERIC_TEXT) ? %Q(="#{text.gsub('"', '""')}") : text
      end
    end

    def formula(address, cell)
      if cell['formula_mode'].present? && cell['formula_mode'] != 'normal'
        raise ArgumentError, "Cell #{address} uses a shared or array formula. Save it as an ordinary formula before importing."
      end

      value = cell.fetch('formula').delete_prefix('=')
      if value.match?(FORBIDDEN_TEXT)
        raise ArgumentError, "Cell #{address} contains an unsupported character."
      end
      parsed = LightekAccounting::SheetFormula::Parser.new("=#{value}", SHEET_NAME).parse
      unless supported_references?(parsed)
        raise ArgumentError, "Cell #{address} refers outside the Workspace sheet. Use local references within A1:Z100."
      end

      "=#{value}"
    rescue LightekAccounting::SheetFormula::Unsupported
      raise ArgumentError, "Cell #{address} uses a formula that Workspace cannot import."
    end

    def supported_references?(node)
      case node[0]
      when :ref, :range
        node[1] == SHEET_NAME && node.drop(2).all? { |address| address.match?(/\A[A-Z](?:[1-9]\d?|100)\z/) }
      when :call then node[2].all? { |child| supported_references?(child) }
      when :binary then supported_references?(node[2]) && supported_references?(node[3])
      when :unary then supported_references?(node[1])
      when :literal then true
      end
    end
  end
end
