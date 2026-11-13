require 'zip'
require 'nokogiri'
require 'csv'
require 'bigdecimal'
module LightekAccounting
  # OpenXML is input data, never executable code. Native sheets preserve source
  # coordinates, types, formulas and review findings for explicit conversion.
  class WorkbookSchema
    MAX_BYTES = 5_000_000
    MAX_UNPACKED = 30_000_000
    def self.xml(source)
      raise ArgumentError, 'Document types and entities are unsupported' if source.match?(/<!DOCTYPE|<!ENTITY/i)
      doc = Nokogiri::XML(source) { |config| config.strict.nonet }
      doc.remove_namespaces!
      doc
    rescue Nokogiri::XML::SyntaxError
      raise ArgumentError, 'Malformed spreadsheet XML'
    end
    def self.parse(bytes,filename:)
      raise ArgumentError, 'Workbook exceeds 5 MB' if bytes.bytesize > MAX_BYTES
      unless filename.to_s.downcase.end_with?('.xlsx')
        raise ArgumentError, 'Use XLSX, CSV, TSV or TXT; legacy XLS and macro workbooks are unsupported' unless filename.to_s.downcase.match?(/\.(csv|tsv|txt)\z/)
        table = StatementParser.table(bytes)
        cells = {}
        ([table[:headers]] + table[:rows]).each_with_index do |row,r|
          row.each_with_index do |value,c|
            text = value.to_s
            spec = {'value'=>text,'type'=>'text'}
            identifier = table[:headers][c].to_s.match?(/reference|account|routing|identifier|code|zip|phone|fitid/i)
            if r > 0 && !identifier
              if text.start_with?('=')
                spec['formula'] = text.delete_prefix('=')
              elsif text.match?(/\A-?(?:0|[1-9]\d*)(?:\.\d+)?\z/)
                spec = {'value'=>BigDecimal(text).to_s('F'),'type'=>'number'}
              elsif text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
                spec = {'value'=>Date.iso8601(text).iso8601,'type'=>'date'}
              end
            end
            cells["#{column(c + 1)}#{r + 1}"] = spec
          end
        end
        return {'version'=>1,'sheets'=>[{'name'=>'Sheet1','cells'=>cells}],'findings'=>[]}
      end
      entries = {}
      Zip::File.open_buffer(bytes) do |zip|
        raise ArgumentError, 'Too many workbook entries' if zip.entries.length > 400
        total = 0
        zip.each do |entry|
          next if entry.directory?
          raise ArgumentError, 'Unsafe workbook entry' if entry.name.start_with?('/') || entry.name.split('/').include?('..') || entries.key?(entry.name)
          raise ArgumentError, 'Macros, embedded objects and external links are unsupported' if entry.name.match?(/vbaProject|externalLinks|embeddings|activeX/i)
          total += entry.size
          raise ArgumentError, 'Expanded workbook exceeds 30 MB' if total > MAX_UNPACKED || entry.size > MAX_UNPACKED
          stream = entry.get_input_stream
          content = stream.read([entry.size + 1,MAX_UNPACKED + 1].min)
          raise ArgumentError, 'Workbook entry size mismatch' unless content.bytesize == entry.size
          entries[entry.name] = content
        end
      end
      relationships = {}
      entries.select { |path,_| path.end_with?('.rels') }.each_value do |raw|
        raise ArgumentError, 'External workbook relationships are unsupported' if xml(raw).xpath('//Relationship').any? { |n| n['TargetMode'] == 'External' }
      end
      xml(entries.fetch('xl/_rels/workbook.xml.rels')).xpath('//Relationship').each { |n| relationships[n['Id']] = n['Target'] }
      strings = entries['xl/sharedStrings.xml'] ? xml(entries['xl/sharedStrings.xml']).xpath('//si').map { |n| n.xpath('.//t').map(&:text).join } : []
      date_styles = []
      if entries['xl/styles.xml']
        styles = xml(entries['xl/styles.xml'])
        custom = styles.xpath('//numFmt').to_h { |n| [n['numFmtId'].to_i,n['formatCode'].to_s] }
        styles.xpath('//cellXfs/xf').each_with_index do |n,index|
          id = n['numFmtId'].to_i
          date_styles << index if [14,15,16,17,22].include?(id) || custom[id].to_s.gsub(/"[^"]*"|\[[^\]]*\]/,'').match?(/[yd]/i)
        end
      end
      workbook = xml(entries.fetch('xl/workbook.xml'))
      epoch1904 = workbook.at_xpath('//workbookPr')&.[]('date1904').in?(%w[1 true])
      sheets, count = [], 0
      workbook.xpath('//sheets/sheet').each do |sheet|
        target = relationships.fetch(sheet['id'])
        target = target.delete_prefix('/')
        target = "xl/#{target}" unless target.start_with?('xl/')
        raise ArgumentError, 'Unsafe worksheet relationship' if target.split('/').include?('..')
        cells = {}
        xml(entries.fetch(target)).xpath('//sheetData/row/c').each do |cell|
          count += 1
          raise ArgumentError, 'Workbook exceeds 50,000 cells' if count > 50_000
          address = cell['r'].to_s
          raise ArgumentError, 'Invalid cell address' unless address.match?(/\A[A-Z]{1,3}[1-9][0-9]{0,6}\z/)
          type, raw = cell['t'], cell.at_xpath('./v')&.text.to_s
          value = case type
          when 's' then strings.fetch(Integer(raw,10))
          when 'inlineStr' then cell.xpath('./is//t').map(&:text).join
          when 'b' then raw == '1'
          when 'str','e' then raw
          else raw.empty? ? '' : BigDecimal(raw).to_s('F')
          end
          native_type = %w[s inlineStr str e].include?(type) ? 'text' : type == 'b' ? 'boolean' : 'number'
          if date_styles.include?(cell['s'].to_i) && raw.present? && !%w[s inlineStr str e].include?(type)
            serial = BigDecimal(raw).floor
            raise ArgumentError, 'Excel fictional leap day cannot be converted' if !epoch1904 && serial == 60
            base = epoch1904 ? Date.new(1904,1,1) : Date.new(1899,12,31)
            value = (base + serial - (!epoch1904 && serial > 60 ? 1 : 0)).iso8601
            native_type = 'date'
          end
          spec = {'value'=>value,'type'=>native_type}
          if (formula = cell.at_xpath('./f'))
            spec['formula'] = formula.text
            spec['formula_mode'] = formula['t'] if formula['t']
          end
          cells[address] = spec
        end
        sheets << {'name'=>sheet['name'],'cells'=>cells}
      end
      raise ArgumentError, 'Workbook has no sheets' if sheets.empty?
      {'version'=>1,'sheets'=>sheets,'findings'=>[]}
    rescue KeyError, Zip::Error, ArgumentError => error
      raise ArgumentError, "Workbook conversion failed: #{error.is_a?(KeyError) ? 'Required workbook structure missing' : error.message}"
    end
    def self.column(index)
      value = +''
      while index > 0
        index, rem = (index - 1).divmod(26)
        value.prepend((65 + rem).chr)
      end
      value
    end
    def self.column_number(value) = value.chars.reduce(0) { |n,c| n * 26 + c.ord - 64 }
    def self.table(schema,sheet_name,header_row: 1)
      sheet = schema.fetch('sheets').find { |s| s['name'] == sheet_name } || (raise ArgumentError, 'Unknown worksheet')
      engine = SheetFormula.new(schema)
      addresses = sheet.fetch('cells').keys
      max_row = addresses.map { |a| a[/\d+/].to_i }.max || 0
      max_col = addresses.map { |a| column_number(a[/[A-Z]+/]) }.max || 0
      raise ArgumentError, 'Worksheet range is too large for a table' if max_col > 100 || max_row > 25001
      raise ArgumentError, 'Header row must be inside the worksheet' unless header_row.is_a?(Integer) && header_row >= 1 && header_row <= max_row
      rows = (header_row..max_row).map do |r|
        (1..max_col).map do |c|
          value = engine.cell(sheet_name,"#{column(c)}#{r}")
          value.is_a?(BigDecimal) ? value.to_s('F') : value.to_s
        end
      end
      {headers: rows.shift || [],rows: rows.reject { |r| r.all?(&:blank?) },format: 'workbook',default_mapping: {}}
    end
  end
end
