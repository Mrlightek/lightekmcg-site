# frozen_string_literal: true

require 'json'
require 'strscan'

module NevaehOs
  module ConsoleLanguage
    PREFIX = /\A(?:(?:can|could|would) you |please )?(?:please )?/i
    DISCOVERY = /\A(?:show|list) (?:me )?(?:the )?(?:installed |available )?(?:rails |application )?models[.!?]?\z/i
    SCHEMA = /\A(?:describe|show) (?:the )?(?:fields|schema) (?:for|of) (.+?) (?:model|records?)[.!?]?\z/i
    REQUEST = /\A(?<verb>show (?:me )?(?:the )?(?:first|last)|list distinct|list|show(?: me)?|count|how many|check for|find|get|create|add|update|change|delete|remove) (?:a |an |the |any )?(?<model>[a-z][a-z0-9_:]*(?: [a-z][a-z0-9_:]*)*?) records?\b(?<tail>.*)\z/im
    VALUE = /"(?:[^"\\\x00-\x1f]|\\.)*"|-?\d+(?:\.\d+)?(?:e[+-]?\d+)?|[a-z][a-z0-9_-]*/i

    module_function

    def request(text)
      phrase = text.sub(PREFIX, '')
      return { 'kind' => 'models' } if DISCOVERY.match?(phrase)
      if (match = SCHEMA.match(phrase))
        return { 'kind' => 'schema', 'model' => match[1], 'english_model' => true }
      end
      return unless REQUEST.match?(phrase)

      { 'kind' => 'console', 'expression' => text }
    end

    def parse(text)
      match = REQUEST.match(text.sub(PREFIX, ''))
      return unless match

      verb = match[:verb].downcase
      tail = match[:tail].strip.sub(/[.!?]\z/, '').rstrip
      scanner = StringScanner.new(tail)
      calls = case verb
              when 'find', 'get', 'delete', 'remove', 'update', 'change'
                if %w[find get].include?(verb) && scanner.check(/where\s+/i)
                  query_calls('find', scanner)
                else
                  record_calls(verb, scanner)
                end
              when 'create', 'add'
                [call('create', [write_fields(scanner)])]
              else
                query_calls(verb, scanner)
              end
      raise ArgumentError, 'Use /guide console for record command examples' unless scanner.eos?

      { 'model' => match[:model], 'english_model' => true, 'calls' => calls }
    end

    def call(method, args = [])
      { 'method' => method, 'args' => args }
    end

    def query_calls(verb, scanner)
      calls = []
      calls << call('distinct') if verb == 'list distinct'
      projection = scanner.scan(/(?:return|show)\s+(?:only\s+)?/i) && field_names(scanner)
      calculation = scanner.scan(/(?:calculate\s+)?(sum|average|minimum|maximum)\s+of\s+/i) && scanner[1].downcase
      if calculation
        calculation_field = scanner.scan(/[a-z_][a-z0-9_]*/i)&.downcase
        raise ArgumentError, 'Supply a numeric column name' unless calculation_field
        scanner.skip(/\s+/)
      end
      if scanner.scan(/where\s+/i)
        filters = fields(scanner, /\s*(?:=\s*|\s+is\s+)/i, arrays: true)
        calls << call('where', [filters]) unless verb == 'find'
      end
      if scanner.scan(/(?:ordered|sorted|order|sort) by\s+/i)
        order = {}
        loop do
          field = scanner.scan(/[a-z_][a-z0-9_]*/i)
          raise ArgumentError, 'Choose a field to order by' unless field
          direction = scanner.scan(/\s+(?:descending|ascending|desc|asc)\b/i)
          order[field.downcase] = direction.to_s.strip.downcase.start_with?('desc') ? 'desc' : 'asc'
          break unless scanner.scan(/\s*,\s*/)
        end
        calls << call('order', [order])
        scanner.skip(/\s+/)
      end
      if scanner.scan(/limit\s+/i)
        limit = scanner.scan(/\d+/)
        raise ArgumentError, 'Supply a numeric record limit' unless limit
        calls << call('limit', [Integer(limit, 10)])
        scanner.skip(/\s+/)
      end
      if scanner.scan(/(?:offset|skip)\s+/i)
        offset = scanner.scan(/\d+/)
        raise ArgumentError, 'Supply a numeric offset' unless offset
        calls << call('offset', [Integer(offset, 10)])
      end
      terminal = case verb
                 when 'count', 'how many' then call('count')
                 when 'check for' then call('exists?')
                 when 'find' then call('find_by', [filters])
                 when /(?:first|last)\z/ then call(verb.split.last)
                 else
                   if projection
                     call('pluck', projection)
                   elsif calculation
                     call(calculation, [calculation_field])
                   else
                     call('all')
                   end
                 end
      if (projection || calculation) && %w[count exists? find_by first last].include?(terminal['method'])
        raise ArgumentError, 'Use list when selecting columns or calculating a value'
      end
      calls << terminal
    end

    def field_names(scanner)
      names = []
      loop do
        name = scanner.scan(/[a-z_][a-z0-9_]*/i)
        raise ArgumentError, 'Supply a column name' unless name
        names << name.downcase
        break unless scanner.scan(/\s*,\s*/)
      end
      scanner.skip(/\s+/)
      names
    end

    def record_calls(verb, scanner)
      id = scanner.scan(/(?:#|with id\s+)?\d+/i)
      raise ArgumentError, 'Supply the record ID' unless id
      calls = [call('find', [Integer(id[/\d+\z/], 10)])]
      scanner.skip(/\s+/)
      case verb
      when 'delete', 'remove' then calls << call('destroy')
      when 'update', 'change' then calls << call('update', [write_fields(scanner)])
      end
      calls
    end

    def write_fields(scanner)
      scanner.skip(/(?:with|set|setting)\s+/i)
      if scanner.peek(1) == '{'
        attributes = JSON.parse(scanner.rest)
        scanner.terminate
        attributes
      else
        fields(scanner, /\s*(?:=\s*|\s+to\s+)/i, arrays: true)
      end
    rescue JSON::ParserError
      raise ArgumentError, 'Supply valid JSON or use field to value'
    end

    def fields(scanner, connector, arrays:)
      result = {}
      loop do
        field = scanner.scan(/[a-z_][a-z0-9_]*/i)&.downcase
        raise ArgumentError, 'Supply a field and a literal value' unless field && scanner.scan(connector)
        raise ArgumentError, "Specify #{field} once" if result.key?(field)
        result[field] = value(scanner, arrays: arrays)
        break unless scanner.scan(/\s+and\s+/i)
      end
      scanner.skip(/\s+/)
      result
    end

    def value(scanner, arrays:)
      if arrays && scanner.scan(/\[\s*/)
        return [] if scanner.scan(/\]/)
        items = [value(scanner, arrays: false)]
        items << value(scanner, arrays: false) while scanner.scan(/\s*,\s*/)
        raise ArgumentError, 'Close the literal list with ]' unless scanner.scan(/\s*\]/)
        return items
      end
      token = scanner.scan(VALUE)
      raise ArgumentError, 'Supply a literal value. Quote text that contains spaces.' unless token
      return token unless token.match?(/\A["\d-]/) || %w[true false null].include?(token)

      JSON.parse(token)
    rescue JSON::ParserError
      raise ArgumentError, 'Supply a valid JSON literal'
    end
  end
end
